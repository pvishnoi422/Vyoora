"""Cloud Tasks delivery for Cloud Run; durable admission still fences paid calls.

Tasks contain only an opaque job key. Photos and Firebase sessions never leave
the existing private storage/authentication boundary in a task payload.
"""
import hashlib
import json
import re
from urllib.parse import urlparse

from flask import request
from google.api_core.exceptions import AlreadyExists
from google.auth.transport.requests import Request
from google.oauth2 import id_token

from media_security import AccessDenied
from safety import ServiceError
from tryon import TryOnService


class TaskDispatcher:
    def __init__(self, client, queue, audience, service_account):
        uri = urlparse(audience)
        if (uri.scheme != 'https' or not uri.hostname or uri.username or uri.password or
                uri.path not in ('', '/') or uri.query or uri.fragment or uri.port not in (None, 443)):
            raise RuntimeError('A separate HTTPS V2 task audience is required')
        if not re.fullmatch(r'projects/[a-z0-9-]+/locations/[a-z0-9-]+/queues/[a-zA-Z0-9_-]+', queue):
            raise RuntimeError('A dedicated Cloud Tasks queue is required')
        if not re.fullmatch(r'[a-z0-9-]+@[a-z0-9-]+\.iam\.gserviceaccount\.com', service_account):
            raise RuntimeError('A dedicated task delivery identity is required')
        self.client, self.queue = client, queue
        self.audience, self.service_account = audience.rstrip('/'), service_account

    def __call__(self, key):
        # Identical client/network retries use the same task, never another paid
        # attempt. Cloud Tasks retains task names after successful delivery.
        name = self.queue + '/tasks/' + hashlib.sha256(key.encode()).hexdigest()
        try:
            self.client.create_task(request={'parent': self.queue, 'task': {
                'name': name,
                'dispatch_deadline': {'seconds': 240},
                'http_request': {
                    'http_method': 'POST',
                    'url': self.audience + '/internal/try-on',
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'jobKey': key}).encode(),
                    'oidc_token': {'service_account_email': self.service_account,
                                   'audience': self.audience},
                },
            }}, retry=None, timeout=20)
        except AlreadyExists:
            pass
        except Exception:
            # Never retry an ambiguous network write automatically.
            raise ServiceError('dispatch_unavailable', 'Generation delivery is temporarily unavailable.') from None


class QueuedTryOnService(TryOnService):
    def __init__(self, *args, dispatcher, **kwargs):
        super().__init__(*args, **kwargs)
        self.dispatcher = dispatcher

    def create(self, uid, job_id, garment_id, ref_id):
        job = super().create(uid, job_id, garment_id, ref_id)
        if job['status'] == 'queued':
            try:
                self.dispatcher(self.guard.job_ref(uid, job_id).id)
            except ServiceError:
                # Retain the reservation, but release the active-job fence.
                # If an ambiguous enqueue did arrive, the terminal job prevents
                # its later delivery from making a provider call/publishing.
                self.guard.finish(uid, job_id, 'failed', 'dispatch_unavailable')
                raise
        return job


def register_task_route(app, service, dispatcher, *, verify=id_token.verify_oauth2_token):
    @app.post('/internal/try-on')
    def process_task():
        header = request.headers.get('Authorization', '')
        try:
            if not header.startswith('Bearer '):
                raise ValueError()
            claims = verify(header[7:], Request(), audience=dispatcher.audience)
            if (claims.get('email') != dispatcher.service_account or
                    claims.get('email_verified') is not True):
                raise ValueError()
        except Exception:
            raise AccessDenied('task_authentication_required', 401) from None
        data = request.get_json(silent=True)
        if (not isinstance(data, dict) or set(data) != {'jobKey'} or
                not isinstance(data['jobKey'], str) or
                not re.fullmatch(r'[0-9a-f]{64}_[A-Za-z0-9_-]{1,128}', data['jobKey'])):
            raise AccessDenied('invalid_request', 400)
        # Request-scoped processing keeps Cloud Run CPU allocated until the
        # bounded generation/review completes. No daemon or minimum idle instance.
        service.guard.recover_stale()
        service.process_one(data['jobKey'])
        job = service.guard.jobs.document(data['jobKey']).get().to_dict() or {}
        if job.get('status') == 'running':
            # Another delivery is still active. Keep the task outstanding until
            # it completes or stale recovery fails it; never dispatch it again.
            raise ServiceError('generation_in_progress', 'Generation is still processing.')
        return '', 204
