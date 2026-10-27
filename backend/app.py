# backend/app.py
import os, re, tempfile, json, hashlib, time
from typing import List, Dict, Any
from urllib.parse import quote_plus
from collections import OrderedDict

from flask import Flask, request, jsonify, make_response
from flask_cors import CORS
from dotenv import load_dotenv

print("🔧 Starting Vyoora backend...")

# ---------- OpenAI ----------
from openai import OpenAI

# ---------- Optional OCR import ----------
try:
    import easyocr
    OCR_IMPORT_OK = True
    OCR_IMPORT_ERR = ""
except Exception as e:
    OCR_IMPORT_OK = False
    OCR_IMPORT_ERR = str(e)

# ---------- Env / OpenAI ----------
load_dotenv()
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
print("🔑 OPENAI_API_KEY present?", bool(OPENAI_API_KEY))
oai_client = OpenAI(api_key=OPENAI_API_KEY, timeout=20.0) if OPENAI_API_KEY else None

# ---------- Flask ----------
app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 10 * 1024 * 1024  # 10 MB uploads
CORS(
    app,
    resources={r"/*": {"origins": "*"}},
    supports_credentials=False,
    methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)

# ---------- Lazy EasyOCR (preload once) ----------
_reader = None
_READER_ERR = None
def get_reader():
    global _reader, _READER_ERR
    if _reader is None and OCR_IMPORT_OK:
        try:
            _reader = easyocr.Reader(["en"], gpu=False)
            print("✅ EasyOCR ready")
        except Exception as e:
            _READER_ERR = f"EasyOCR init failed: {e}"
            print("❌", _READER_ERR)
    return _reader

try:
    get_reader()
except Exception:
    pass

# ---------- Cache for AI summaries ----------
AI_SUMMARY_CACHE_MAX = 300
AI_SUMMARY_CACHE: "OrderedDict[str, dict]" = OrderedDict()

def _cache_key(ingredients: List[str]) -> str:
    norm = ",".join(sorted(x.strip().lower() for x in ingredients if x))
    return hashlib.sha1(norm.encode("utf-8")).hexdigest()

def _cache_get(k: str):
    v = AI_SUMMARY_CACHE.get(k)
    if v is not None:
        AI_SUMMARY_CACHE.move_to_end(k)
    return v

def _cache_put(k: str, v: dict):
    AI_SUMMARY_CACHE[k] = v
    AI_SUMMARY_CACHE.move_to_end(k)
    if len(AI_SUMMARY_CACHE) > AI_SUMMARY_CACHE_MAX:
        AI_SUMMARY_CACHE.popitem(last=False)

# ---------- OCR helpers ----------
IRRELEVANT_HEADINGS = [
    "directions","usage","how to use","warnings","caution","attention",
    "store in a cool","external use only","keep out of reach","stop use",
    "if irritation occurs","discontinue use","not intended","consult a physician",
    "avoid contact with eyes","manufactured by","distributed by"
]

def slice_after_ingredients(text: str) -> str:
    m = re.search(r"\bingredients?\b\s*[:\-]?", text, flags=re.IGNORECASE)
    return text[m.end():] if m else text

def normalize_token(tok: str) -> str:
    tok = tok.strip(" .:;-_")
    tok = re.sub(r"[^A-Za-z0-9 ,()\-\u2013\u2014/]", "", tok)
    tok = re.sub(r"\s+", " ", tok).strip()
    if not tok or len(tok) < 2:
        return ""
    words = []
    for w in tok.split():
        words.append(w if re.fullmatch(r"[A-Z0-9\-(),/]+", w) else w.capitalize())
    return " ".join(words).strip(", ")

def extract_ingredients_from_text(text: str) -> List[str]:
    if not text:
        return []
    text = slice_after_ingredients(text)
    low = text.lower()
    for phrase in IRRELEVANT_HEADINGS:
        p = low.find(phrase)
        if p != -1:
            text = text[:p]
            break
    parts = re.split(r"[;,•·\u2022\u00B7]|\s-\s|\n|\band\b", text, flags=re.IGNORECASE)
    parts = [normalize_token(p) for p in parts]
    parts = [p for p in parts if p and len(p.split()) <= 12]
    seen, out = set(), []
    for p in parts:
        if p not in seen:
            out.append(p); seen.add(p)
    return out

# ---------- Reference link building ----------
ALLOWED_SOURCES = {
    "EU CosIng", "CIR", "PubChem", "IFRA", "Peer-reviewed literature"
}

def _link_cosing(term: str) -> str:
    # CosIng doesn't expose stable IDs reliably; use site search.
    return f"https://www.google.com/search?q=site%3Aec.europa.eu+CosIng+{quote_plus(term)}"

def _link_cir(term: str) -> str:
    # CIR slugs aren't consistent; site search is most reliable.
    return f"https://www.google.com/search?q=site%3Acir-safety.org+{quote_plus(term)}"

def _link_pubchem(term: str) -> str:
    return f"https://pubchem.ncbi.nlm.nih.gov/#query={quote_plus(term)}"

def _link_ifra(term: str) -> str:
    return f"https://www.google.com/search?q=site%3Aifrafragrance.org+{quote_plus(term)}"

def _link_pubmed(term: str) -> str:
    return f"https://pubmed.ncbi.nlm.nih.gov/?term={quote_plus(term)}+cosmetic"

REFERENCE_LINKS = {
    "EU CosIng": _link_cosing,
    "CIR": _link_cir,
    "PubChem": _link_pubchem,
    "IFRA": _link_ifra,
    "Peer-reviewed literature": _link_pubmed,
}

def build_links_for(ingredient: str, refs: List[str]) -> List[Dict[str, str]]:
    out: List[Dict[str, str]] = []
    for r in refs:
        fn = REFERENCE_LINKS.get(r)
        if fn:
            out.append({"source": r, "url": fn(ingredient)})
    return out

# ---------- AI: summarize + flag + references ----------
def ai_summarize_and_flag(ingredients: List[str]) -> Dict[str, Any]:
    """
    Fast + robust:
      - Caps to 80 ingredients for latency
      - Caches identical sets (order-insensitive)
      - Sanitizes refs to ALLOWED_SOURCES
      - Ensures EVERY concern has at least ["CIR", "Peer-reviewed literature"]
      - Adds per-ingredient 'links' for each reference
    Returns: {"summary": str, "concerns": [...], "sources": [...]}
    """
    if not ingredients:
        return {"summary": "No ingredients detected.", "concerns": [], "sources": []}

    ingredients = ingredients[:80]

    ck = _cache_key(ingredients)
    cached = _cache_get(ck)
    if cached:
        return cached

    if not (oai_client and OPENAI_API_KEY):
        result = {"summary": "AI unavailable. Could not analyze ingredients.", "concerns": [], "sources": []}
        _cache_put(ck, result)
        return result

    sys = (
        "You are Vyoora, a skincare ingredient expert. "
        "User provides a list of cosmetic ingredients. "
        "Respond in JSON with keys: 'summary' (2–3 neutral sentences) and "
        "'concerns' (array of objects with 'ingredient', 'reason', 'references'). "
        "For 'references', ONLY include exact names from this whitelist: "
        "EU CosIng, CIR, PubChem, IFRA, Peer-reviewed literature. "
        "Do not invent study titles or URLs. If evidence is mixed, use 'Peer-reviewed literature'. "
        "Keep tone factual and practical; avoid medical claims."
    )
    user = "Ingredient list:\n" + "\n".join(f"- {x}" for x in ingredients)

    try:
        resp = oai_client.chat.completions.create(
            model="gpt-4o-mini",
            temperature=0.25,
            messages=[{"role": "system", "content": sys}, {"role": "user", "content": user}],
            response_format={"type": "json_object"},
        )
        raw = resp.choices[0].message.content
        data = json.loads(raw) if isinstance(raw, str) else raw

        summary = (data.get("summary") or "").strip() or "No summary available."
        concerns_in = data.get("concerns") or []
        concerns_out: List[Dict[str, Any]] = []
        refs_union: set = set()

        for c in concerns_in:
            if not isinstance(c, dict):
                continue
            ing = str(c.get("ingredient") or "").strip()
            rsn = str(c.get("reason") or "").strip()

            # Keep only whitelisted refs
            refs = [str(x).strip() for x in (c.get("references") or []) if str(x).strip() in ALLOWED_SOURCES]

            # ✅ Fallback: ensure every concern has at least one trusted source
            if not refs:
                refs = ["CIR", "Peer-reviewed literature"]

            if ing and rsn:
                refs_union.update(refs)
                links = build_links_for(ing, refs)
                concerns_out.append({
                    "ingredient": ing,
                    "reason": rsn,
                    "references": refs,
                    "links": links,
                })

        result = {
            "summary": summary,
            "concerns": concerns_out,
            "sources": sorted(refs_union),
        }
        _cache_put(ck, result)
        return result

    except Exception as e:
        print("AI error:", e)
        result = {"summary": "Error analyzing ingredients.", "concerns": [], "sources": []}
        _cache_put(ck, result)
        return result


# ---------- Routes ----------
@app.get("/")
def root():
    return jsonify({"ok": True, "service": "vyoora-backend"})

@app.get("/health")
def health():
    return jsonify({"status": "ok"}), 200

@app.get("/warmup")
def warmup():
    try:
        get_reader()
    except Exception:
        pass
    if oai_client and OPENAI_API_KEY:
        try:
            oai_client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[{"role": "system", "content": "ping"}, {"role": "user", "content": "ok"}],
                temperature=0.0,
                max_tokens=1,
            )
        except Exception:
            pass
    return jsonify({"ok": True})

@app.route("/upload", methods=["OPTIONS"])
def upload_options():
    return make_response(("", 204))

@app.route("/upload", methods=["POST"])
def upload():
    r = get_reader()
    if not OCR_IMPORT_OK or r is None:
        return jsonify({"error": f"OCR unavailable: {_READER_ERR or OCR_IMPORT_ERR}"}), 500

    f = request.files.get("image") or request.files.get("file")
    if not f:
        return jsonify({"error": "No image provided (expected field 'image' or 'file')"}), 400

    with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(f.filename or '')[-1] or ".jpg") as tmp:
        f.save(tmp.name)
        tmp_path = tmp.name

    try:
        start = time.time()

        # ===== OCR =====
        t1 = time.time()
        lines = r.readtext(tmp_path, detail=0, paragraph=True)
        raw_text = " ".join(lines or []).strip()
        print("⏱ OCR time:", time.time() - t1)

        # ===== CLEANING =====
        t2 = time.time()
        dedup = extract_ingredients_from_text(raw_text)
        print("⏱ Cleaning time:", time.time() - t2)

        # ===== AI =====
        t3 = time.time()
        results = ai_summarize_and_flag(dedup)
        print("⏱ AI time:", time.time() - t3)

        print("⏱ TOTAL time:", time.time() - start)

        return jsonify(results), 200

    except Exception as e:
        return jsonify({"error": f"OCR failed: {e}"}), 500
    finally:
        try:
            os.remove(tmp_path)
        except Exception:
            pass

@app.route("/chat", methods=["OPTIONS", "POST"])
def chat():
    if request.method == "OPTIONS":
        return make_response(("", 204))

    data = request.get_json(force=True, silent=True) or {}
    user_message = (data.get("message") or "").strip()
    if not user_message:
        return jsonify({"error": "Missing 'message'"}), 400

    if not (oai_client and OPENAI_API_KEY):
        return jsonify({"reply": "Server is missing OPENAI_API_KEY. Add it to .env and restart."}), 200

    try:
        completion = oai_client.chat.completions.create(
            model="gpt-4o-mini",
            temperature=0.5,
            messages=[
                {"role": "system", "content": "You are Vyoora, a concise skincare assistant. Be practical, avoid medical claims, and suggest patch testing."},
                {"role": "user", "content": user_message},
            ],
        )
        reply_text = completion.choices[0].message.content.strip()
        return jsonify({"reply": reply_text}), 200
    except Exception as e:
        print("Chat error:", e)
        return jsonify({"reply": "Sorry, I couldn’t process that just now. Try again in a moment."}), 200

# ---------- Main ----------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5001)))
