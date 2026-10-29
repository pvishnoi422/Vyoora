"""Shared V2 identity/media boundary. Not registered in the V11 application.

Firebase validates identity. Native GCS objects remain private. No download-token
or signed public URL is returned; reads require an authenticated owner each time.
"""
from datetime import datetime, timezone, timedelta
import io
import os
import re
import uuid
import warnings

import firebase_admin
from firebase_admin import auth, credentials
from google.auth.credentials import AnonymousCredentials
from flask import Flask, jsonify, request, Response
from PIL import Image, ImageOps, UnidentifiedImageError


class AccessDenied(Exception):
    def __init__(self, code, status):
        self.code, self.status = code, status


class FirebaseIdentity:
    def __init__(self, project, *, allow_emulator=False):
        host = os.environ.get('FIREBASE_AUTH_EMULATOR_HOST')
        if host:
            if (not allow_emulator or os.environ.get('K_SERVICE') or not project.startswith('demo-')
                or host.split(':')[0] not in {'localhost', '127.0.0.1'}):
                raise RuntimeError('Unsigned emulator credentials must never be accepted in production')
        class DemoCredential(credentials.Base):
            def get_credential(self): return AnonymousCredentials()
        self.app = firebase_admin.initialize_app(credential=DemoCredential() if host else None,
            options={'projectId': project}, name='verify-'+uuid.uuid4().hex)

    def verify(self, token):
        try:
            claims = auth.verify_id_token(token, app=self.app, check_revoked=True)
            uid = claims.get('uid')
            if not isinstance(uid, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', uid):
                raise ValueError('Invalid UID')
            now = datetime.now(timezone.utc).timestamp()
            if claims.get('exp', 0) <= now or claims.get('iat', now+1) > now+60:
                raise ValueError('Invalid session lifetime')
            if claims.get('email_verified') is not True:
                raise AccessDenied('verified_account_required', 403)
            if claims.get('firebase', {}).get('sign_in_provider') == 'anonymous':
                raise AccessDenied('verified_account_required', 403)
            return uid
        except AccessDenied:
            raise
        except Exception:
            raise AccessDenied('authentication_required', 401) from None

    def close(self):
        firebase_admin.delete_app(self.app)

    def require_recent(self, token):
        claims = auth.verify_id_token(token, app=self.app, check_revoked=True)
        if datetime.now(timezone.utc).timestamp()-claims.get('auth_time', 0) > 300:
            raise AccessDenied('recent_signin_required', 403)

    def delete_user(self, uid):
        auth.delete_user(uid, app=self.app)


class MemoryObjects:
    """Test double with the same immutable-create and delete contract as GCS."""
    def __init__(self): self.objects = {}
    def put(self, key, data, metadata, expires):
        if key in self.objects: raise AccessDenied('already_exists', 409)
        self.objects[key] = (data, metadata.copy())
    def get(self, key):
        if key not in self.objects: raise AccessDenied('not_found', 404)
        return self.objects[key]
    def delete(self, key):
        if key not in self.objects: raise AccessDenied('not_found', 404)
        del self.objects[key]


class PrivateGCSObjects:
    def __init__(self, bucket): self.bucket = bucket
    def put(self, key, data, metadata, expires):
        from google.api_core.exceptions import PreconditionFailed
        blob = self.bucket.blob(key)
        blob.metadata = metadata
        blob.cache_control = 'private, no-store, max-age=0'
        if expires: blob.custom_time = expires
        try: blob.upload_from_string(data, content_type='image/jpeg', if_generation_match=0)
        except PreconditionFailed: raise AccessDenied('already_exists', 409) from None
    def get(self, key):
        from google.api_core.exceptions import NotFound
        try:
            blob = self.bucket.get_blob(key)
            if blob is None: raise AccessDenied('not_found', 404)
            return blob.download_as_bytes(if_generation_match=blob.generation), blob.metadata or {}
        except NotFound: raise AccessDenied('not_found', 404) from None
    def delete(self, key):
        from google.api_core.exceptions import NotFound
        try: self.bucket.blob(key).delete()
        except NotFound: raise AccessDenied('not_found', 404) from None


def create_verification_app(identity, objects, *, clock=None):
    """Separate verification app: no provider key, paid AI route, or V11 import."""
    clock = clock or (lambda: datetime.now(timezone.utc))
    app = Flask(__name__)
    app.config['MAX_CONTENT_LENGTH'] = 5*1024*1024

    @app.errorhandler(AccessDenied)
    def denied(error):
        return jsonify({'status':'error','code':error.code}), error.status

    @app.errorhandler(413)
    def oversized(error):
        return jsonify({'status':'error','code':'image_too_large'}), 413

    @app.route('/v2/images/<owner>/<kind>/<image_id>', methods=['GET','POST','DELETE'])
    def media(owner, kind, image_id):
        header = request.headers.get('Authorization', '')
        if not header.startswith('Bearer ') or not header[7:].strip():
            raise AccessDenied('authentication_required', 401)
        uid = identity.verify(header[7:])
        if owner != uid: raise AccessDenied('owner_mismatch', 403)
        if kind not in {'wardrobe','reference-photos','saved-looks'} or not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', image_id):
            raise AccessDenied('invalid_object', 400)
        key = f'{kind}/{uid}/{image_id}.jpg'
        now = clock()
        if request.method == 'POST':
            if request.form.get('consent') != 'granted':
                raise AccessDenied('consent_required', 400)
            photo = request.files.get('image')
            if photo is None: raise AccessDenied('invalid_image', 400)
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter('error', Image.DecompressionBombWarning)
                    with Image.open(photo.stream) as image:
                        if image.width*image.height > 20_000_000 or image.format not in {'PNG','JPEG','WEBP'} or getattr(image,'n_frames',1)!=1:
                            raise ValueError('Invalid photo')
                        image.load()
                        clean = ImageOps.exif_transpose(image).convert('RGB')
                        clean.thumbnail((1600,1600))
                        buffer = io.BytesIO();clean.save(buffer, format='JPEG', quality=85)
            except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
                raise AccessDenied('invalid_image', 400) from None
            expires = now+timedelta(days=7 if kind=='reference-photos' else 30) if kind!='wardrobe' else None
            metadata = {'ownerId':uid,'consentedAt':now.isoformat().replace('+00:00', 'Z'), 'createdAt':now.isoformat().replace('+00:00', 'Z')}
            if expires: metadata['expiresAt'] = expires.isoformat().replace('+00:00', 'Z')
            objects.put(key, buffer.getvalue(), metadata, expires)
            return jsonify({'status':'created','objectKey':key,'expiresAt':expires.isoformat().replace('+00:00', 'Z') if expires else None}),201
        data, metadata = objects.get(key)
        if metadata.get('ownerId') != uid: raise AccessDenied('owner_mismatch', 403)
        if request.method == 'DELETE':
            objects.delete(key)
            return '',204
        if metadata.get('expiresAt') and now >= datetime.fromisoformat(metadata['expiresAt']):
            raise AccessDenied('expired',410)
        return Response(data, mimetype='image/jpeg', headers={'Cache-Control':'private, no-store, max-age=0'})
    return app
