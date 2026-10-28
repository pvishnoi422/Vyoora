"""Local demo Auth emulator + real isolated private bucket. Never a cloud entrypoint.

Start Auth first: npm run start --prefix verification/auth_storage
Run with the verification Python environment and gcloud signed in. Serves loopback
only, creates two synthetic verified accounts, and never imports the AI service.
"""
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timedelta, timezone

if os.environ.get('K_SERVICE'):
    raise RuntimeError('Local development only')
os.environ['FIREBASE_AUTH_EMULATOR_HOST'] = '127.0.0.1:9099'
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from firebase_admin import auth
from google.auth.credentials import Credentials
from google.cloud import storage
from media_security import FirebaseIdentity
from wardrobe import GCSWardrobe, create_wardrobe_app


class LocalGcloudCredentials(Credentials):
    def refresh(self, request):
        self.token = subprocess.check_output(['gcloud', 'auth', 'print-access-token'], text=True).strip()
        self.expiry = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(minutes=45)


identity = FirebaseIdentity('demo-vyoora-v2', allow_emulator=True)
for name in ('alice', 'bob'):
    uid = 'local-' + name
    try:
        auth.get_user(uid, app=identity.app)
    except auth.UserNotFoundError:
        auth.create_user(uid=uid, email=f'{name}@vyoora.example.invalid',
                         password='Vyoora-local-only-2026!', email_verified=True, app=identity.app)

bucket_name = 'vyoora-backend-v2-private-20261027'
bucket = storage.Client(project='vyoora-backend', credentials=LocalGcloudCredentials()).bucket(bucket_name)
bucket.reload()
if (not bucket.iam_configuration.uniform_bucket_level_access_enabled or
    bucket.iam_configuration.public_access_prevention != 'enforced' or bucket.versioning_enabled or
    bucket.soft_delete_policy.retention_duration_seconds):
    raise RuntimeError('Test bucket must be private and allow complete deletion')
app = create_wardrobe_app(identity, GCSWardrobe(bucket), origins=['http://127.0.0.1:7357', 'http://localhost:7357'])
app.run(host='127.0.0.1', port=7359, debug=False, use_reloader=False)
