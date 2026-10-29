"""Durable, authenticated private-test jobs with explicit photo/provider consent."""
from datetime import datetime, timezone
import threading
from flask import jsonify, request, Response
from media_security import AccessDenied
from safety import ServiceError
from tryon_media import CONSENT_VERSION
from provider import virtual_tryon

SUPPORTED_CATEGORIES = {'top', 'bottom', 'dress', 'outerwear'}


class TryOnService:
    def __init__(self, guard, media, wardrobe, credentials, project, provider=virtual_tryon, looks=None):
        self.guard, self.media, self.wardrobe = guard, media, wardrobe
        self.credentials, self.project, self.provider = credentials, project, provider
        self.looks = looks
        self.stop = threading.Event()

    @staticmethod
    def public(job):
        return {k: job.get(k) for k in ('id', 'ownerId', 'garmentId', 'referenceId', 'status',
            'createdAt', 'expiresAt', 'errorCode')} | {'aiGenerated': job.get('status') == 'succeeded'}

    def reference(self, uid, ref_id, *, data=False):
        self.guard.check_account_access(uid)
        self.guard.check_reference(uid, ref_id)
        return self.media.reference(uid, ref_id, data=data)

    def upload_reference(self, uid, stream):
        self.guard.check_account_access(uid)
        record = self.media.upload_reference(uid, stream)
        try:
            self.guard.grant_reference(uid, record)
            self.guard.check_account_access(uid)
        except Exception:
            self.media.delete_reference(uid, record['id'])
            self.guard.reference_ref(uid, record['id']).delete()
            raise
        return record

    def delete_reference(self, uid, ref_id):
        # Revoke FIRST. Even if file deletion fails, all subsequent reads,
        # admission, provider dispatch and result publication fail closed.
        self.guard.revoke_reference(uid, ref_id)
        if self.looks is not None: self.looks.delete_reference(uid, ref_id)
        for job in self.guard.for_reference(uid, ref_id):
            self.cancel(uid, job['id'])
        self.media.delete_reference(uid, ref_id)

    def create(self, uid, job_id, garment_id, ref_id):
        # Idempotent network retries must not depend on the photo still existing.
        try:
            old = self.guard.get(uid, job_id)
        except ServiceError as error:
            if error.http_status != 404: raise
        else:
            if old['garmentId'] != garment_id or old['referenceId'] != ref_id:
                raise ServiceError('idempotency_conflict', 'This request ID belongs to a different selection.', 409)
            return old
        # Both IDs resolve under the verified owner; clients cannot supply URLs.
        item = self.wardrobe.item(uid, garment_id)
        if item['category'] not in SUPPORTED_CATEGORIES:
            raise ServiceError('unsupported_garment', 'Choose a top, bottom, dress or outerwear item.', 400)
        self.reference(uid, ref_id)
        return self.guard.admit(uid, job_id, garment_id, ref_id)

    def cancel(self, uid, job_id):
        self.guard.cancel(uid, job_id)
        self.media.delete_preview(uid, job_id)
        return self.guard.get(uid, job_id)

    def preview(self, uid, job_id):
        job = self.guard.get(uid, job_id)
        if job['status'] != 'succeeded': raise ServiceError('preview_unavailable', 'This preview is not available.', 409)
        self.reference(uid, job['referenceId'])
        return self.media.preview(uid, job_id)

    def saved_look(self, uid, item_id, *, image=False):
        record = self.looks.get(uid, item_id, image=image)
        self.guard.check_saved_reference(uid, (record[0] if image else record)['referencePhoto']['id'])
        return record

    def save_look(self, uid, job_id, title):
        job = self.guard.get(uid, job_id)
        data, mime = self.preview(uid, job_id)
        record = self.looks.save(uid, job, title, data, mime)
        try:
            self.guard.check_account_access(uid)
            self.reference(uid, job['referenceId'])
            if self.guard.get(uid, job_id)['status'] != 'succeeded':
                raise ServiceError('preview_unavailable', 'This preview is not available.', 409)
        except Exception:
            self.looks.delete(uid, job_id)
            raise
        return record

    def delete_account(self, uid, identity):
        # First block new requests and provider dispatch. Cleanup is retryable;
        # keep the identity until every Vyoora object has been removed.
        self.guard.begin_account_deletion(uid)
        if self.looks is not None: self.looks.delete_all(uid)
        self.media.delete_all(uid)
        self.wardrobe.delete_all(uid)
        self.guard.delete_account_records(uid)
        identity.delete_user(uid)

    def process_one(self, key):
        job = self.guard.claim(key)
        if not job: return
        uid, job_id = job['ownerId'], job['id']
        try:
            reference, person = self.reference(uid, job['referenceId'], data=True)
            garment = self.wardrobe.read(uid, job['garmentId'])
            data, mime = self.provider(person, garment, credentials=self.credentials, guard=self.guard,
                job_key=key, project=self.project)
            # Cancel/revocation may race a completed external call. The durable
            # status always wins; do not publish that image or refund the attempt.
            self.reference(uid, job['referenceId'])
            if self.guard.get(uid, job_id)['status'] != 'running': return
            self.media.put_preview(uid, job_id, job['referenceId'], data, mime, reference['expiresAt'])
            if not self.guard.finish(uid, job_id, 'succeeded'):
                self.media.delete_preview(uid, job_id)
        except Exception as error:
            code = error.code if isinstance(error, (ServiceError, AccessDenied)) else 'generation_failed'
            try:
                self.media.delete_preview(uid, job_id)
            finally:
                self.guard.finish(uid, job_id, 'failed', code)

    def run_worker(self):
        while not self.stop.is_set():
            try:
                self.guard.recover_stale()
                for snapshot in self.guard.pending():
                    if self.stop.is_set(): return
                    self.process_one(snapshot.id)
            except Exception:
                # A database/storage outage does not trigger a paid retry.
                pass
            self.stop.wait(1)


def register_tryon_routes(app, user, service, *, identity=None):
    @app.errorhandler(ServiceError)
    def controlled(error):
        return jsonify(status='error', code=error.code), error.http_status

    def safe_id(value):
        import re
        if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', value):
            raise AccessDenied('invalid_request', 400)
        return value

    @app.get('/v2/try-on/availability')
    def availability():
        return jsonify(service.guard.availability(user()))

    @app.route('/v2/reference-photos', methods=['GET', 'POST'])
    def references():
        uid = user()
        if request.method == 'GET':
            records = []
            for record in service.media.references(uid):
                try: service.guard.check_reference(uid, record['id'])
                except ServiceError as error:
                    if error.code == 'reference_expired': continue
                    raise
                records.append(record)
            return jsonify(items=records)
        if (set(request.form) != {'consent', 'consentVersion', 'adultPermission'} or
            set(request.files) != {'image'} or request.form.get('consent') != 'granted' or
            request.form.get('consentVersion') != CONSENT_VERSION or
            request.form.get('adultPermission') != 'confirmed'):
            raise AccessDenied('reference_consent_required', 400)
        return jsonify(item=service.upload_reference(uid, request.files['image'].stream)), 201

    @app.get('/v2/reference-photos/<ref_id>/image')
    def reference_image(ref_id):
        _, data = service.reference(user(), safe_id(ref_id), data=True)
        return Response(data, mimetype='image/jpeg')

    @app.delete('/v2/reference-photos/<ref_id>')
    def reference_delete(ref_id):
        service.delete_reference(user(), safe_id(ref_id))
        return '', 204

    @app.route('/v2/try-on/jobs', methods=['GET', 'POST'])
    def jobs():
        uid = user()
        if request.method == 'GET':
            now = datetime.now(timezone.utc)
            return jsonify(items=[service.public(j) for j in service.guard.list(uid)
                if now < datetime.fromisoformat(j['expiresAt'])])
        data = request.get_json(silent=True)
        if (not isinstance(data, dict) or set(data) != {'jobId', 'garmentId', 'referenceId', 'consentVersion'} or
            data.get('consentVersion') != CONSENT_VERSION):
            raise AccessDenied('generation_consent_required', 400)
        job = service.create(uid, safe_id(data['jobId']), safe_id(data['garmentId']), safe_id(data['referenceId']))
        return jsonify(job=service.public(job)), 202

    @app.get('/v2/try-on/jobs/<job_id>')
    def job_status(job_id):
        return jsonify(job=service.public(service.guard.get(user(), safe_id(job_id))))

    @app.delete('/v2/try-on/jobs/<job_id>')
    def cancel_job(job_id):
        return jsonify(job=service.public(service.cancel(user(), safe_id(job_id))))

    @app.get('/v2/try-on/jobs/<job_id>/image')
    def preview(job_id):
        data, mime = service.preview(user(), safe_id(job_id))
        return Response(data, mimetype=mime)

    if service.looks is not None:
        @app.delete('/v2/account')
        def delete_account():
            uid = user(allow_deleting=True)
            if request.get_json(silent=True) != {'confirmation': 'delete-my-account'}:
                raise AccessDenied('deletion_confirmation_required', 400)
            identity.require_recent(request.headers['Authorization'][7:])
            service.delete_account(uid, identity)
            return '', 204

        @app.route('/v2/saved-looks', methods=['GET', 'POST'])
        def saved_looks():
            uid = user()
            if request.method == 'GET':
                page = request.args.get('pageToken')
                if page and len(page) > 4096: raise AccessDenied('invalid_page', 400)
                records, next_page = service.looks.list(uid, page)
                visible = []
                for record in records:
                    try: service.guard.check_saved_reference(uid, record['referencePhoto']['id'])
                    except ServiceError as error:
                        if error.code == 'reference_revoked': continue
                        raise
                    visible.append(record)
                return jsonify(items=visible, nextPageToken=next_page)
            data = request.get_json(silent=True)
            if (not isinstance(data, dict) or set(data) != {'jobId', 'title', 'consentVersion'} or
                data.get('consentVersion') != 'saved-looks-v1' or not isinstance(data.get('title'), str) or
                not 1 <= len(data['title'].strip()) <= 100):
                raise AccessDenied('saved_look_consent_required', 400)
            return jsonify(item=service.save_look(uid, safe_id(data['jobId']), data['title'].strip())), 201

        @app.route('/v2/saved-looks/<item_id>', methods=['GET', 'DELETE'])
        def saved_look(item_id):
            uid = user(); item_id = safe_id(item_id)
            if request.method == 'DELETE':
                service.looks.delete(uid, item_id)
                return '', 204
            return jsonify(item=service.saved_look(uid, item_id))

        @app.get('/v2/saved-looks/<item_id>/image')
        def saved_look_image(item_id):
            _, data, mime = service.saved_look(user(), safe_id(item_id), image=True)
            return Response(data, mimetype=mime)
