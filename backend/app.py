# Maintained Vyoora backend. See docs/SECURITY.md for the result contract.
import os, json, base64, io, warnings, ipaddress
from typing import List, Dict, Any
from urllib.parse import quote_plus
from PIL import Image, ImageOps, UnidentifiedImageError

from flask import Flask, request, jsonify
from flask_cors import CORS
from provider import complete
from safety import ServiceError
from contracts import validate_model_result

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 5 * 1024 * 1024
origins = [x.strip() for x in os.environ.get("CORS_ORIGINS", "").split(",") if x.strip()]
if origins:
    CORS(app, resources={r"/*": {"origins": origins}}, supports_credentials=False,
         methods=["GET", "POST", "OPTIONS"], allow_headers=["Content-Type", "Authorization"])
Image.MAX_IMAGE_PIXELS = 20_000_000

# ── EU Restricted / Banned ingredients (partial list of highest-risk) ─────────
EU_RESTRICTED = {
    "butylphenyl methylpropional": "Banned in EU leave-on products (IFRA/EU Regulation)",
    "lilial": "Banned in EU (reproductive toxicant)",
    "lyral": "Banned in EU (allergen)",
    "hydroxyisohexyl 3-cyclohexene carboxaldehyde": "Banned in EU (allergen)",
    "eugenol": "Restricted in EU (fragrance allergen, must be declared)",
    "isoeugenol": "Restricted in EU (fragrance allergen)",
    "cinnamyl alcohol": "Restricted in EU (fragrance allergen)",
    "cinnamal": "Restricted in EU (fragrance allergen)",
    "limonene": "Must be declared in EU (fragrance allergen above 0.001% leave-on)",
    "linalool": "Must be declared in EU (fragrance allergen above 0.001% leave-on)",
    "citronellol": "Must be declared in EU (fragrance allergen)",
    "geraniol": "Must be declared in EU (fragrance allergen)",
    "benzyl alcohol": "Restricted in EU (preservative and fragrance allergen)",
    "benzyl benzoate": "Must be declared in EU (fragrance allergen)",
    "coumarin": "Restricted in EU (fragrance allergen)",
    "formaldehyde": "Banned in EU cosmetics above 0.001%",
    "mercury": "Banned in EU cosmetics",
    "lead": "Banned in EU cosmetics",
}

# ── Severity weights for scoring ──────────────────────────────────────────────
SEVERITY_WEIGHTS = {
    "eu_banned":      25,   # EU banned ingredient
    "eu_restricted":  15,   # EU restricted/must declare
    "fragrance":      12,   # General fragrance concern
    "essential_oil":  10,   # Essential oil irritation risk
    "drying_alcohol": 10,   # Denat alcohol / drying alcohol
    "harsh_surfactant": 9,  # SLS, SLES, harsh cleansing agents
    "preservative":   8,    # Preservative concern
    "high_position":  5,    # In top 5 ingredients (high concentration)
    "general":        5,    # General concern
}

def compute_smart_score(concerns: List[Dict], ingredient_count: int, product_type: str) -> int:
    """
    Severity-weighted scoring. Each concern deducts based on severity.
    Leave-on products penalized more than rinse-off for fragrance/allergens.
    """
    if ingredient_count == 0:
        return 50

    rinse_off_types = ["cleanser", "shampoo", "conditioner", "body wash", "face wash"]
    is_rinse_off = any(t in product_type.lower() for t in rinse_off_types)

    base_score = 100
    total_deduction = 0

    for c in concerns:
        ing_lower = (c.get("ingredient") or "").lower()
        reason    = (c.get("reason") or "").lower()
        position  = c.get("ingredient_position", 99)
        eu_flag   = c.get("eu_restricted", False)
        eu_banned = c.get("eu_banned", False)

        # Base severity — default assumes sensitive, acne-prone skin
        if eu_banned:
            deduction = SEVERITY_WEIGHTS["eu_banned"]
        elif eu_flag or eu_restricted:
            deduction = SEVERITY_WEIGHTS["eu_restricted"]
        elif "fragrance" in ing_lower or "parfum" in ing_lower:
            deduction = SEVERITY_WEIGHTS["fragrance"]
            if is_rinse_off:
                deduction = max(4, deduction - 3)  # Still penalize in rinse-off
        elif any(oil in ing_lower for oil in ["tea tree", "lavender", "eucalyptus", "peppermint", "citrus", "lemon", "bergamot", "ylang", "rosemary oil", "cinnamon"]):
            deduction = SEVERITY_WEIGHTS["essential_oil"]
        elif "alcohol denat" in ing_lower or "sd alcohol" in ing_lower or "isopropyl alcohol" in ing_lower:
            deduction = SEVERITY_WEIGHTS["drying_alcohol"]
        elif "sodium lauryl sulfate" in ing_lower or ("sls" in ing_lower and len(ing_lower) < 10):
            deduction = SEVERITY_WEIGHTS["harsh_surfactant"]
        elif "paraben" in ing_lower or "preservative" in reason:
            deduction = SEVERITY_WEIGHTS["preservative"]
        else:
            deduction = SEVERITY_WEIGHTS["general"]

        # High concentration bonus penalty
        if position <= 5:
            deduction += SEVERITY_WEIGHTS["high_position"]

        total_deduction += deduction

    # Cap deduction
    total_deduction = min(total_deduction, 70)
    score = max(10, base_score - total_deduction)
    return score

def eu_restricted(ingredient: str) -> tuple[bool, bool, str]:
    """Returns (is_restricted, is_banned, reason)"""
    ing_lower = ingredient.lower().strip()
    for key, reason in EU_RESTRICTED.items():
        if key in ing_lower:
            is_banned = "banned" in reason.lower()
            return True, is_banned, reason
    return False, False, ""

# ── Reference links ───────────────────────────────────────────────────────────
ALLOWED_SOURCES = {"EU CosIng", "CIR", "PubChem", "IFRA", "Peer-reviewed literature"}
REFERENCE_LINKS = {
    "EU CosIng":                lambda t: f"https://www.google.com/search?q=site%3Aec.europa.eu+CosIng+{quote_plus(t)}",
    "CIR":                      lambda t: f"https://www.google.com/search?q=site%3Acir-safety.org+{quote_plus(t)}",
    "PubChem":                  lambda t: f"https://pubchem.ncbi.nlm.nih.gov/#query={quote_plus(t)}",
    "IFRA":                     lambda t: f"https://www.google.com/search?q=site%3Aifrafragrance.org+{quote_plus(t)}",
    "Peer-reviewed literature": lambda t: f"https://pubmed.ncbi.nlm.nih.gov/?term={quote_plus(t)}+cosmetic",
}

def build_links_for(ingredient: str, refs: List[str]) -> List[Dict[str, str]]:
    return [{"source": r, "url": REFERENCE_LINKS[r](ingredient)} for r in refs if r in REFERENCE_LINKS]

# ── Core Vision Analysis ──────────────────────────────────────────────────────
def analyse_image(image_b64: str, media_type: str = "image/jpeg", product_type: str = "unknown", actor: str = "unknown") -> Dict[str, Any]:
    product_context = f"The user has indicated this is a {product_type}. " if product_type and product_type != "unknown" else ""
    is_rinse_off_hint = ""
    rinse_off_types = ["cleanser", "shampoo", "conditioner", "body wash", "face wash"]
    if any(t in product_type.lower() for t in rinse_off_types):
        is_rinse_off_hint = "This is a RINSE-OFF product — adjust sensitization risk accordingly (fragrance less concerning than in leave-on products). "

    system_prompt = f"""You are Vyoora, a cosmetic formulation safety expert with deep dermatology and regulatory knowledge.

{product_context}{is_rinse_off_hint}

The user has sent a photo of a skincare or cosmetic product label.

Your tasks:
1. Read the INGREDIENTS list from the image, even if blurry, angled, or small text.
2. Identify what type of product this is from the label (moisturizer, serum, cleanser, sunscreen, toner, body lotion, hair product, etc.)
3. Note the position of each ingredient in the list (position 1 = highest concentration).
4. Analyse the formula for safety concerns with evidence-based reasoning.
5. Respond ONLY with a valid complete JSON object — no preamble, no markdown, no truncation.

JSON format:
{{
  "brand": "Detected brand name from label, or empty string if not visible",
  "product_name": "Detected product name from label, or empty string if not visible",
  "ingredients": ["ingredient1", "ingredient2"],
  "all_ingredients": ["every single ingredient detected from the label in order"],
  "product_type": "Moisturizer",
  "product_type_detail": "Leave-on hydrating moisturizer",
  "formula_type": "Hydrating barrier cream",
  "summary": "2-3 sentences on formula type, key actives, overall safety. Only mention ingredients that are actually in the list. Do not invent ingredient categories.",
  "score_rationale": {{
    "positives": ["Barrier-safe ceramide complex: +15", "Strong humectant profile: +10"],
    "negatives": ["EU-restricted fragrance allergen present: -12", "Preservative with sensitization potential: -5"],
    "evidence_confidence": "High"
  }},
  "score_label": "Barrier-supportive formula",
  "skin_compatibility": {{
    "best_for": ["normal", "dry"],
    "use_caution": ["sensitive"],
    "less_ideal_for": ["fungal acne-prone"]
  }},
  "who_should_avoid": ["fragrance allergy", "rosacea"],
  "concerns": [
    {{
      "ingredient": "exact ingredient name from label",
      "ingredient_position": 5,
      "category": "Fragrance",
      "reason": "Evidence-based concern using precise language: irritation potential, sensitization risk, concentration-dependent effects. Never use: toxic, harmful, unsafe, clean.",
      "eu_restricted": false,
      "eu_banned": false,
      "eu_note": "",
      "references": ["CIR"]
    }}
  ]
}}

Critical rules:
- references must ONLY use: EU CosIng, CIR, PubChem, IFRA, Peer-reviewed literature
- Only flag ingredients with genuine evidence-backed concerns
- ingredient_position = position in the INCI list (1 = first ingredient = highest concentration)
- Set eu_restricted: true if ingredient appears on EU allergen declaration list
- Set eu_banned: true if ingredient is banned in EU cosmetics
- eu_note should contain the specific EU regulation note if applicable
- score_label options: "Barrier-supportive formula" / "Balanced for most skin types" / "Hydration-focused formula" / "Acne-safe for most users" / "Sensitive-skin friendly" / "Use with awareness" / "High sensitization potential" / "Approach carefully"
- evidence_confidence: "High" / "Moderate" / "Limited"
- Do NOT mention ingredients not present in the image
- Do NOT invent ingredient categories
- If no ingredients list found: set ingredients to [], summary to "No ingredients list found in this image.", product_type to "Unknown"
- Ensure JSON is complete and valid — do not truncate
- All analysis is informed by: EU CosIng (https://ec.europa.eu/growth/tools-databases/cosing), CIR (https://cir-safety.org), PubMed (https://pubmed.ncbi.nlm.nih.gov), EWG Skin Deep (https://www.ewg.org/skindeep)"""

    try:
        raw = complete("upload", actor, [
                {"role": "system", "content": system_prompt},
                {
                    "role": "user",
                    "content": [
                        {"type": "image_url", "image_url": {"url": f"data:{media_type};base64,{image_b64}", "detail": "high"}},
                        {"type": "text", "text": "Please read and analyse the ingredients list from this cosmetic product label."}
                    ]
                }
            ])
        data = validate_model_result(json.loads(raw))

        ingredients       = [str(x).strip() for x in (data.get("ingredients") or []) if str(x).strip()]
        all_ingredients   = [str(x).strip() for x in (data.get("all_ingredients") or data.get("ingredients") or []) if str(x).strip()]
        brand             = (data.get("brand") or "").strip()
        product_name_out  = (data.get("product_name") or "").strip()
        product_type_out  = (data.get("product_type") or "Unknown").strip()
        product_detail    = (data.get("product_type_detail") or "").strip()
        formula_type      = (data.get("formula_type") or "").strip()
        summary           = (data.get("summary") or "").strip() or "Analysis complete."
        score_rationale   = data.get("score_rationale") or {}
        score_label       = (data.get("score_label") or "Balanced for most skin types").strip()
        skin_compat       = data.get("skin_compatibility") or {}
        who_avoid         = data.get("who_should_avoid") or []
        concerns_in       = data.get("concerns") or []

        concerns_out: List[Dict[str, Any]] = []
        refs_union: set = set()

        for c in concerns_in:
            if not isinstance(c, dict): continue
            ing      = str(c.get("ingredient") or "").strip()
            rsn      = str(c.get("reason") or "").strip()
            category = str(c.get("category") or "").strip()
            position = int(c.get("ingredient_position") or 99)
            refs     = [str(x).strip() for x in (c.get("references") or []) if str(x).strip() in ALLOWED_SOURCES]
            if not refs: refs = ["CIR", "Peer-reviewed literature"]

            # Check EU status
            is_restr, is_banned, eu_note_gpt = eu_restricted(ing)
            eu_flag  = bool(c.get("eu_restricted")) or is_restr
            eu_ban   = bool(c.get("eu_banned")) or is_banned
            eu_note  = (c.get("eu_note") or eu_note_gpt or "").strip()

            if eu_flag or eu_ban:
                if "EU CosIng" not in refs: refs.append("EU CosIng")
                if "IFRA" not in refs and "fragrance" in category.lower(): refs.append("IFRA")

            if ing and rsn:
                refs_union.update(refs)
                concerns_out.append({
                    "ingredient":          ing,
                    "ingredient_position": position,
                    "category":            category,
                    "reason":              rsn,
                    "eu_restricted":       eu_flag,
                    "eu_banned":           eu_ban,
                    "eu_note":             eu_note,
                    "references":          refs,
                    "links":               build_links_for(ing, refs),
                })

        # Smart severity-weighted score
        smart_score = compute_smart_score(concerns_out, len(all_ingredients), product_type_out)

        # Rebuild score rationale negatives with EU flags
        if score_rationale.get("negatives"):
            for c in concerns_out:
                if c.get("eu_banned"):
                    score_rationale["negatives"].insert(0, f"EU-banned ingredient ({c['ingredient']}): -25")
                    break
                elif c.get("eu_restricted"):
                    score_rationale["negatives"].insert(0, f"EU-restricted allergen present: -12")
                    break

        result = {
            "status": "success",
            "analysis_complete": True,
            "summary":           summary,
            "brand":             brand,
            "product_name":      product_name_out,
            "all_ingredients":   all_ingredients,
            "product_type":      product_type_out,
            "product_type_detail": product_detail,
            "formula_type":      formula_type,
            "score_rationale":   score_rationale,
            "score_label":       score_label,
            "skin_compatibility": skin_compat,
            "who_should_avoid":  who_avoid,
            "concerns":          concerns_out,
            "sources":           sorted(refs_union),
            "ingredient_count":  len(all_ingredients),
            "smart_score":       smart_score,
        }
        return result

    except ServiceError:
        raise
    except Exception:
        raise ServiceError("analysis_failed", "Analysis couldn't be completed. Please try again.", 502) from None

@app.errorhandler(ServiceError)
def service_error(error):
    response = jsonify({"status": "error", "analysis_complete": False,
                        "code": error.code, "error": error.message})
    if error.retry_after:
        response.headers["Retry-After"] = str(error.retry_after)
    return response, error.http_status


@app.errorhandler(413)
def too_large(error):
    return service_error(ServiceError("image_too_large", "Choose an image smaller than 5 MB.", 413))


@app.errorhandler(500)
def internal_error(error):
    return service_error(ServiceError("internal_error", "The request couldn't be completed.", 500))


def actor_id():
    # Ignore user-supplied forwarding headers by default. Set to 1 ONLY for
    # direct Cloud Run ingress, which appends the client it observed. An extra
    # load balancer needs a separately verified proxy configuration.
    value = request.remote_addr or "unknown"
    if os.environ.get("K_SERVICE") and os.environ.get("TRUSTED_PROXY_HOPS") == "1":
        chain = request.headers.get("X-Forwarded-For", "").split(",")
        if chain[-1].strip():
            value = chain[-1].strip()
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        return "unknown"


@app.get("/")
def root():
    return jsonify({"ok": True, "service": "vyoora-backend", "version": "11",
                    "analysis_contract": 1})


@app.get("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/upload", methods=["OPTIONS", "POST"])
def upload():
    if request.method == "OPTIONS":
        return "", 204
    f = request.files.get("image") or request.files.get("file")
    if not f:
        raise ServiceError("invalid_image", "Choose an ingredient label photo.", 400)
    product_type = request.form.get("product_type", "unknown")
    allowed = {"unknown", "Moisturizer", "Serum", "Cleanser", "Sunscreen", "Toner",
               "Eye cream", "Body lotion", "Hair product", "Other"}
    if product_type not in allowed:
        raise ServiceError("invalid_request", "Choose a valid product type.", 400)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(f.stream) as image:
                if image.format not in {"JPEG", "PNG", "WEBP"} or getattr(image, "n_frames", 1) != 1:
                    raise ValueError("Unsupported image")
                image.load()
                normalized = ImageOps.exif_transpose(image).convert("RGB")
                normalized.thumbnail((1600, 1600))
                buffer = io.BytesIO()
                normalized.save(buffer, format="JPEG", quality=85)
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise ServiceError("invalid_image", "Choose a valid JPEG, PNG, or WebP label photo.", 400) from None
    encoded = base64.b64encode(buffer.getvalue()).decode("ascii")
    return jsonify(analyse_image(encoded, "image/jpeg", product_type, actor=actor_id()))


@app.route("/chat", methods=["OPTIONS", "POST"])
def chat():
    if request.method == "OPTIONS":
        return "", 204
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ServiceError("invalid_request", "Send a message to continue.", 400)
    message = data.get("message")
    if not isinstance(message, str) or not message.strip() or len(message) > 2000:
        raise ServiceError("invalid_request", "Send a message of 1 to 2000 characters.", 400)
    history_in = data.get("history", [])
    if not isinstance(history_in, list) or len(history_in) > 20:
        raise ServiceError("invalid_request", "This conversation is too long.", 400)
    history = []
    for turn in history_in:
        if (not isinstance(turn, dict) or turn.get("role") not in {"user", "assistant"}
            or not isinstance(turn.get("content"), str) or len(turn["content"]) > 2000):
            raise ServiceError("invalid_request", "This conversation couldn't be read.", 400)
        history.append({"role": turn["role"], "content": turn["content"]})
    messages = [{"role": "system", "content": (
        "You are Lumi, Vyoora's skincare ingredient assistant. Explain uncertainty, "
        "concentration-dependent irritation, and evidence limits. Avoid diagnoses, "
        "guarantees of safety, invented sources, and invented regulatory claims. "
        "Keep replies under 130 words. If asked about analysis errors, ask the user "
        "to retry; never interpret a failed analysis as a clear result.")},
        *history, {"role": "user", "content": message.strip()}]
    reply = complete("chat", actor_id(), messages)
    return jsonify({"status": "success", "reply": reply})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.environ.get("PORT", 5001)))
