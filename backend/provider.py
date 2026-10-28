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


# Google lists retirement on 2027-03-15. Review the model and bounded price
# before production launch or replacement; never silently fall back.
TRYON_MODEL = 'virtual-try-on-001'
TRYON_REGION = 'us-central1'


def virtual_tryon(person, garment, *, credentials, guard, job_key, project, session=None):
    """One bounded Google VTO attempt, linked to its durable reservation.

    REST schema: https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/virtual-try-on-api
    No redirects, output URLs, auth retry, provider retry or fallback model.
    """
    import base64
    import io
    import re
    import requests
    from google.auth.transport.requests import Request
    from PIL import Image
    if (os.environ.get('TRYON_ENABLED', 'false').lower() != 'true' or
        os.environ.get('FIRESTORE_EMULATOR_HOST')):
        raise ServiceError('tryon_disabled', 'Try-on testing is paused.')
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,62}', project) or not all(0 < len(x) <= 5*1024*1024 for x in (person, garment)):
        raise ServiceError('invalid_request', 'The selected photos are invalid.', 400)
    url = f'https://{TRYON_REGION}-aiplatform.googleapis.com/v1/projects/{project}/locations/{TRYON_REGION}/publishers/google/models/{TRYON_MODEL}:predict'
    payload = {'instances': [{'personImage': {'image': {'bytesBase64Encoded': base64.b64encode(person).decode()}},
        'productImages': [{'image': {'bytesBase64Encoded': base64.b64encode(garment).decode()}}]}],
        'parameters': {'sampleCount': 1, 'personGeneration': 'allow-adult',
                       'safetySetting': 'block-medium-and-above', 'addWatermark': True,
                       'outputOptions': {'mimeType': 'image/png'}}}
    headers = {'Content-Type': 'application/json', 'X-Goog-User-Project': project}
    credentials.before_request(Request(), 'POST', url, headers)
    client = session or requests.Session()
    try:
        # This transaction checks consent/entitlement/kill-switch again and
        # permanently records the only attempt BEFORE transmitting any photos.
        guard.start_attempt(job_key)
        response = client.post(url, json=payload, headers=headers, timeout=(10, 120),
                               allow_redirects=False, stream=True)
        try:
            if response.status_code != 200:
                code = 'provider_access_denied' if response.status_code in (401, 403) else 'generation_failed'
                raise ServiceError(code, 'The try-on provider could not complete this preview.', 502)
            body = bytearray()
            for chunk in response.iter_content(64*1024):
                body.extend(chunk)
                if len(body) > 12*1024*1024: raise ValueError('Oversized provider output')
            import json
            predictions = json.loads(body)['predictions']
            if not isinstance(predictions, list) or len(predictions) != 1: raise ValueError('Wrong output count')
            output = predictions[0]
            if 'images' in output:
                if not isinstance(output['images'], list) or len(output['images']) != 1: raise ValueError('Wrong output count')
                output = output['images'][0]
            if output.get('raiFilteredReason'):
                raise ServiceError('generation_blocked', 'These photos could not be used for a preview. Try different photos.', 422)
            mime = output.get('mimeType')
            if mime not in {'image/png', 'image/jpeg'} or output.get('gcsUri'): raise ValueError('Unexpected output type')
            data = base64.b64decode(output['bytesBase64Encoded'], validate=True)
            if not 0 < len(data) <= 7*1024*1024: raise ValueError('Invalid output size')
            with Image.open(io.BytesIO(data)) as image:
                if image.width*image.height > 20_000_000 or image.format != {'image/png': 'PNG', 'image/jpeg': 'JPEG'}[mime]:
                    raise ValueError('Invalid output image')
                image.verify()
            with Image.open(io.BytesIO(data)) as decoded:
                decoded.load()
            return data, mime
        finally:
            response.close()
    except ServiceError:
        raise
    except Exception:
        raise ServiceError('generation_failed', 'The preview could not be completed. Your request will not be retried automatically.', 502) from None
    finally:
        if session is None: client.close()
