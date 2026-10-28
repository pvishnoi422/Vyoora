"""The only provider entry point: bounded requests and an atomic reservation."""
import os
from pathlib import Path
try:
    from openai import OpenAI
except ImportError:
    # The isolated try-on runtime uses cloud identity, without an OpenAI SDK/key.
    OpenAI = None
from safety import FirestoreGuard, ServiceError

VISION_MODEL = "gpt-4o-2024-08-06"
CHAT_MODEL = "gpt-4o-mini-2024-07-18"
OUTPUT_LIMITS = {"upload": 2200, "chat": 350}
INPUT_BYTE_LIMITS = {"upload": 24_000, "chat": 16_000}
guard = FirestoreGuard()
_client = None


def api_key():
    # Production must mount a Secret Manager secret; never load a source .env.
    secret_file = os.environ.get("OPENAI_API_KEY_FILE")
    if secret_file:
        try:
            return Path(secret_file).read_text().strip()
        except OSError:
            return None
    if not os.environ.get("K_SERVICE"):
        return os.environ.get("OPENAI_API_KEY")
    return None


def complete(endpoint, actor, messages):
    global _client
    key = api_key()
    if not key or OpenAI is None:
        raise ServiceError("ai_unavailable", "Analysis is temporarily unavailable.")
    text_bytes = 0
    for message in messages:
        content = message["content"]
        if isinstance(content, str):
            text_bytes += len(content.encode("utf-8"))
        else:
            text_bytes += sum(len(part.get("text", "").encode("utf-8")) for part in content)
    if text_bytes > INPUT_BYTE_LIMITS[endpoint]:
        raise ServiceError("invalid_request", "This request is too long.", 400)
    if _client is None:
        _client = OpenAI(api_key=key, timeout=40.0, max_retries=0)
    # This is deliberately immediately before the one provider attempt. Failure
    # or ambiguous timeouts retain the entire reservation; never refund/retry.
    guard.reserve(actor, endpoint)
    kwargs = {"model": VISION_MODEL if endpoint == "upload" else CHAT_MODEL,
              "messages": messages, "max_tokens": OUTPUT_LIMITS[endpoint],
              "temperature": 0 if endpoint == "upload" else 0.4,
              "store": False}
    if endpoint == "upload":
        kwargs["response_format"] = {"type": "json_object"}
    try:
        response = _client.chat.completions.create(**kwargs)
        choice = response.choices[0]
        if choice.finish_reason != "stop" or not choice.message.content:
            raise ValueError("Incomplete or refused response")
        return choice.message.content
    except Exception:
        # No raw provider messages, keys, images, or upstream response bodies.
        raise ServiceError("analysis_failed", "Analysis couldn't be completed. Please try again.", 502) from None


# Deliberate provider upgrade: instruction-capable editing preserves garment
# proportions instead of inheriting the reference outfit's cropped hem.
# https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-1-flash-image
TRYON_MODEL = 'gemini-3.1-flash-image'
TRYON_REGION = 'us'
TRYON_OUTPUT_TOKENS = 2048
TRYON_PROMPT_BYTE_LIMIT = 2048
GARMENT_PRESERVATION_PROMPT = (
    "Edit the adult person in image 1 to wear the exact garment from image 2. "
    "Image 2 is the product, not a style inspiration. Use its original silhouette and proportions, "
    "including torso length, hem position relative to garment width, sleeve length, neckline, texture and details. "
    "Replace the existing garment completely; do not inherit a cropped hem or tucked-in styling from image 1. "
    "Do not shorten, crop, roll up, tuck in, stretch or redesign the product. "
    "A full-length sweater must remain full-length and cover the waist; never turn it into a crop top. "
    "Preserve the person's identity, body shape, pose, original camera framing and background. "
    "Keep the complete garment visible. Output one edited photograph only."
)


def virtual_tryon(person, garment, *, credentials, guard, job_key, project, session=None):
    """One bounded, instruction-guided Google image edit; no hidden fallbacks.

    Reviewed 2026-10-28, US standard pricing: input $0.55/M tokens, image
    output $66/M (text/thinking is cheaper). Exactly two images at 1120
    input tokens each + <=2048 prompt bytes/tokens, <=2048 total output
    tokens: ceiling $0.137527 < the $0.15 reservation. No tools,
    search, multiple candidates, auto retry, or output resolutions above 1K.
    https://cloud.google.com/gemini-enterprise-agent-platform/generative-ai/pricing
    """
    import base64
    import io
    import json
    import re
    import requests
    from google.auth.transport.requests import Request
    from PIL import Image
    if (os.environ.get('TRYON_ENABLED', 'false').lower() != 'true' or
        os.environ.get('FIRESTORE_EMULATOR_HOST')):
        raise ServiceError('tryon_disabled', 'Try-on testing is paused.')
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,62}', project) or not all(0 < len(x) <= 5*1024*1024 for x in (person, garment)):
        raise ServiceError('invalid_request', 'The selected photos are invalid.', 400)
    try:
        parts = [{'text': GARMENT_PRESERVATION_PROMPT}]
        ratio = None
        for label, data in [('Image 1: adult person', person), ('Image 2: complete original product', garment)]:
            with Image.open(io.BytesIO(data)) as image:
                if image.format not in {'JPEG', 'PNG'} or max(image.size) > 1600:
                    raise ValueError('Unbounded input')
                if ratio is None: ratio = image.width / image.height
                mime = {'JPEG': 'image/jpeg', 'PNG': 'image/png'}[image.format]
            parts.extend([{'text': label}, {'inlineData': {'mimeType': mime, 'data': base64.b64encode(data).decode()}}])
        if sum(len(p.get('text', '').encode()) for p in parts) > TRYON_PROMPT_BYTE_LIMIT:
            raise ValueError('Unbounded prompt')
        ratios = {'1:1':1, '2:3':2/3, '3:2':3/2, '3:4':3/4, '4:3':4/3, '4:5':4/5, '5:4':5/4, '9:16':9/16, '16:9':16/9}
        aspect = min(ratios, key=lambda value: abs(ratios[value]-ratio))
    except Exception:
        raise ServiceError('invalid_request', 'Use a complete, supported garment and reference photo.', 400) from None
    payload = {'contents': [{'role': 'user', 'parts': parts}], 'generationConfig': {
        'candidateCount': 1, 'maxOutputTokens': TRYON_OUTPUT_TOKENS, 'responseModalities': ['IMAGE'],
        'thinkingConfig': {'thinkingLevel': 'MINIMAL', 'includeThoughts': False},
        'imageConfig': {'imageSize': '1K', 'aspectRatio': aspect}},
        'safetySettings': [{'category': c, 'threshold': 'BLOCK_MEDIUM_AND_ABOVE'} for c in (
            'HARM_CATEGORY_HATE_SPEECH', 'HARM_CATEGORY_HARASSMENT', 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'HARM_CATEGORY_DANGEROUS_CONTENT')]}
    url = f'https://aiplatform.{TRYON_REGION}.rep.googleapis.com/v1/projects/{project}/locations/{TRYON_REGION}/publishers/google/models/{TRYON_MODEL}:generateContent'
    headers = {'Content-Type': 'application/json', 'X-Goog-User-Project': project}
    credentials.before_request(Request(), 'POST', url, headers)
    client = session or requests.Session()
    try:
        guard.start_attempt(job_key)
        response = client.post(url, json=payload, headers=headers, timeout=(10, 120), allow_redirects=False, stream=True)
        try:
            if response.status_code != 200:
                code = 'provider_access_denied' if response.status_code in (401, 403) else 'generation_failed'
                raise ServiceError(code, 'The try-on provider could not complete this preview.', 502)
            body = bytearray()
            for chunk in response.iter_content(64*1024):
                body.extend(chunk)
                if len(body) > 12*1024*1024: raise ValueError('Oversized provider output')
            result = json.loads(body)
            if result.get('promptFeedback', {}).get('blockReason'):
                raise ServiceError('generation_blocked', 'These photos could not be used for a preview. Try different photos.', 422)
            candidates = result.get('candidates', [])
            if len(candidates) != 1 or candidates[0].get('finishReason') != 'STOP':
                raise ValueError('Incomplete, blocked, or multiple candidates')
            images = [p['inlineData'] for p in candidates[0].get('content', {}).get('parts', []) if 'inlineData' in p and not p.get('thought')]
            if len(images) != 1: raise ValueError('Wrong output count')
            output = images[0]; mime = output.get('mimeType')
            if mime not in {'image/png', 'image/jpeg'}: raise ValueError('Unexpected output type')
            data = base64.b64decode(output['data'], validate=True)
            if not 0 < len(data) <= 7*1024*1024: raise ValueError('Invalid output size')
            with Image.open(io.BytesIO(data)) as image:
                if image.width*image.height > 20_000_000 or image.format != {'image/png': 'PNG', 'image/jpeg': 'JPEG'}[mime]:
                    raise ValueError('Invalid output image')
                image.verify()
            with Image.open(io.BytesIO(data)) as decoded: decoded.load()
            return data, mime
        finally:
            response.close()
    except ServiceError:
        raise
    except Exception:
        raise ServiceError('generation_failed', 'The preview could not be completed. Your request will not be retried automatically.', 502) from None
    finally:
        if session is None: client.close()
