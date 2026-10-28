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
    def __init__(self, guard, media, wardrobe, credentials, project, provider=virtual_tryon):
        self.guard, self.media, self.wardrobe = guard, media, wardrobe
        self.credentials, self.project, self.provider = credentials, project, provider
        self.stop = threading.Event()

    @staticmethod
    def public(job):
        return {k: job.get(k) for k in ('id', 'ownerId', 'garmentId', 'referenceId', 'status',
            'createdAt', 'expiresAt', 'errorCode')} | {'aiGenerated': job.get('status') == 'succeeded'}

    def reference(self, uid, ref_id, *, data=False):
        self.guard.check_reference(uid, ref_id)
        return self.media.reference(uid, ref_id, data=data)

    def upload_reference(self, uid, stream):
        record = self.media.upload_reference(uid, stream)
        try: self.guard.grant_reference(uid, record)
        except Exception:
            self.media.delete_reference(uid, record['id'])
            raise
        return record

    def delete_reference(self, uid, ref_id):
        # Revoke FIRST. Even if file deletion fails, all subsequent reads,
        # admission, provider dispatch and result publication fail closed.
        self.guard.revoke_reference(uid, ref_id)
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


def register_tryon_routes(app, user, service):
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
