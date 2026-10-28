"""Authenticated wardrobe API, deployed separately from the V11 AI service.

One immutable private object holds both the normalized image and garment record
in its metadata. Creating/deleting one object atomically persists/removes both.
"""
from datetime import datetime, timezone
import io
import json
import re
import uuid
import warnings

from flask import Flask, Response, jsonify, request
from PIL import Image, ImageOps, UnidentifiedImageError
from google.api_core.exceptions import NotFound, PreconditionFailed
from werkzeug.exceptions import HTTPException
from media_security import AccessDenied

CATEGORIES = {'top', 'bottom', 'dress', 'outerwear', 'shoes', 'accessory', 'other'}


def normalize_image(stream):
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(stream) as image:
                if (image.width * image.height > 20_000_000 or
                    image.format not in {'PNG', 'JPEG', 'WEBP'} or getattr(image, 'n_frames', 1) != 1):
                    raise ValueError()
                image.load()
                clean = ImageOps.exif_transpose(image).convert('RGB')
                clean.thumbnail((1600, 1600))
                output = io.BytesIO()
                clean.save(output, format='JPEG', quality=85)
                return output.getvalue()
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError,
            Image.DecompressionBombWarning):
        raise AccessDenied('invalid_image', 400) from None


class GCSWardrobe:
    def __init__(self, bucket):
        self.bucket = bucket

    @staticmethod
    def prefix(uid):
        return f'wardrobe/{uid}/'

    def blob(self, uid, item_id):
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', item_id):
            raise AccessDenied('not_found', 404)
        return self.bucket.blob(f'{self.prefix(uid)}{item_id}.jpg')

    @staticmethod
    def record(blob, uid):
        metadata = blob.metadata or {}
        if metadata.get('ownerId') != uid:
            raise AccessDenied('not_found', 404)
        item = json.loads(metadata['wardrobeRecord'])
        expected = f'wardrobe/{uid}/{item["id"]}.jpg'
        if item.get('ownerId') != uid or blob.name != expected:
            raise AccessDenied('not_found', 404)
        return item

    def create(self, uid, item, data):
        blob = self.blob(uid, item['id'])
        blob.metadata = {'ownerId': uid, 'wardrobeRecord': json.dumps(item, separators=(',', ':'))}
        blob.cache_control = 'private, no-store, max-age=0'
        try:
            blob.upload_from_string(data, content_type='image/jpeg', if_generation_match=0, timeout=30)
        except PreconditionFailed:
            raise AccessDenied('already_exists', 409) from None
        return item

    def list(self, uid, page_token=None):
        iterator = self.bucket.list_blobs(prefix=self.prefix(uid), page_token=page_token,
                                          max_results=40, page_size=40, timeout=30)
        page = next(iterator.pages)
        items = []
        for blob in page:
            # Historical verification images have no wardrobe record.
            if not (blob.metadata or {}).get('wardrobeRecord'):
                continue
            items.append(self.record(blob, uid))
        return items, iterator.next_page_token

    def read(self, uid, item_id):
        blob = self.blob(uid, item_id)
        try:
            blob.reload(timeout=30)
            self.record(blob, uid)
            return blob.download_as_bytes(if_generation_match=blob.generation, timeout=30)
        except NotFound:
            raise AccessDenied('not_found', 404) from None

    def delete(self, uid, item_id):
        blob = self.blob(uid, item_id)
        try:
            blob.reload(timeout=30)
            self.record(blob, uid)
            blob.delete(if_generation_match=blob.generation,
                        if_metageneration_match=blob.metageneration, timeout=30)
        except NotFound:
            # Idempotent retry after a lost successful delete response.
            return
        except PreconditionFailed:
            raise AccessDenied('item_changed_retry', 409) from None


def create_wardrobe_app(identity, store, *, origins=()):
    app = Flask(__name__)
    app.config['MAX_CONTENT_LENGTH'] = 5 * 1024 * 1024
    allowed_origins = set(origins)

    @app.before_request
    def check_origin():
        origin = request.headers.get('Origin')
        if origin and origin not in allowed_origins:
            raise AccessDenied('origin_denied', 403)

    @app.after_request
    def private_response(response):
        response.headers['Cache-Control'] = 'private, no-store, max-age=0'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        origin = request.headers.get('Origin')
        if origin in allowed_origins:
            response.headers['Access-Control-Allow-Origin'] = origin
            response.headers['Vary'] = 'Origin'
            response.headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type'
            response.headers['Access-Control-Allow-Methods'] = 'GET, POST, DELETE, OPTIONS'
        return response

    @app.errorhandler(AccessDenied)
    def denied(error):
        return jsonify(status='error', code=error.code), error.status

    @app.errorhandler(HTTPException)
    def http_error(error):
        return jsonify(status='error', code='image_too_large' if error.code == 413 else 'invalid_request'), error.code

    @app.errorhandler(Exception)
    def unavailable(error):
        # Never expose bearer tokens, provider bodies, object data, or credentials.
        return jsonify(status='error', code='storage_unavailable'), 503

    def user():
        header = request.headers.get('Authorization', '')
        if not header.startswith('Bearer ') or not header[7:].strip():
            raise AccessDenied('authentication_required', 401)
        return identity.verify(header[7:])

    @app.get('/healthz')
    def health():
        return jsonify(status='ok', service='vyoora-wardrobe')

    @app.route('/v2/wardrobe', methods=['GET', 'POST'])
    def collection():
        uid = user()
        if request.method == 'GET':
            page = request.args.get('pageToken')
            if page and len(page) > 4096:
                raise AccessDenied('invalid_page', 400)
            items, next_page = store.list(uid, page)
            return jsonify(items=items, nextPageToken=next_page)
        if set(request.form) - {'name', 'category', 'color', 'consent'} or set(request.files) != {'image'}:
            raise AccessDenied('invalid_garment', 400)
        name, color = request.form.get('name', '').strip(), request.form.get('color', '').strip()
        category = request.form.get('category', '')
        if not name or len(name) > 100 or len(color) > 50 or category not in CATEGORIES:
            raise AccessDenied('invalid_garment', 400)
        if request.form.get('consent') != 'granted':
            raise AccessDenied('consent_required', 400)
        data = normalize_image(request.files['image'].stream)
        item_id = uuid.uuid4().hex
        now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        item = dict(schemaVersion=1, id=item_id, ownerId=uid, name=name, category=category,
                    image=dict(ownerId=uid, imageId=item_id, kind='wardrobe'), createdAt=now, updatedAt=now)
        if color:
            item['color'] = color
        return jsonify(item=store.create(uid, item, data)), 201

    @app.get('/v2/wardrobe/<item_id>/image')
    def image(item_id):
        return Response(store.read(user(), item_id), mimetype='image/jpeg')

    @app.delete('/v2/wardrobe/<item_id>')
    def delete(item_id):
        store.delete(user(), item_id)
        return '', 204

    return app
