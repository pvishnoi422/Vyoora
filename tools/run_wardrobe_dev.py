"""Local demo Auth emulator + real isolated private bucket. Never a cloud entrypoint.

Start Auth first: npm run start --prefix verification/auth_storage
Run with the verification Python environment and gcloud signed in. Serves loopback
only, creates two synthetic verified accounts, and never imports the AI service.
"""
import os
from pathlib import Path
import subprocess
import sys
import argparse
import threading
from datetime import datetime, timedelta, timezone

if os.environ.get('K_SERVICE'):
    raise RuntimeError('Local development only')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--try-on', action='store_true', help='Enable the approved private try-on test and durable worker')
args = parser.parse_args()
if args.try_on and os.environ.get('FIRESTORE_EMULATOR_HOST'):
    raise RuntimeError('Paid testing requires the real shared budget ledger')
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
cloud_credentials = LocalGcloudCredentials()
bucket = storage.Client(project='vyoora-backend', credentials=cloud_credentials).bucket(bucket_name)
bucket.reload()
if (not bucket.iam_configuration.uniform_bucket_level_access_enabled or
    bucket.iam_configuration.public_access_prevention != 'enforced' or bucket.versioning_enabled or
    bucket.soft_delete_policy.retention_duration_seconds):
    raise RuntimeError('Test bucket must be private and allow complete deletion')
wardrobe = GCSWardrobe(bucket)
tryon = None
if args.try_on:
    from google.cloud import firestore
    from google.api_core.exceptions import AlreadyExists
    from safety import TryOnGuard, TRYON_DAY_CAP, TRYON_MONTH_CAP, TRYON_PER_USER_DAY
    from tryon_media import TryOnMedia
    from tryon import TryOnService
    from saved_looks import SavedLooks
    os.environ['TRYON_ENABLED'] = 'true'
    guard = TryOnGuard(firestore.Client(project='vyoora-backend', credentials=cloud_credentials))
    # Create once; never reset existing budgets, quotas, membership or kill switch.
    try:
        guard.controls.document('policy').create({'enabled': True, 'daily_budget_micro_usd': TRYON_DAY_CAP,
            'monthly_budget_micro_usd': TRYON_MONTH_CAP, 'per_user_day': TRYON_PER_USER_DAY})
    except AlreadyExists: pass
    for name in ('alice', 'bob'):
        try: guard.controls.document('member_'+guard.actor('local-'+name)).create({'enabled': True})
        except AlreadyExists: pass
    tryon = TryOnService(guard, TryOnMedia(bucket), wardrobe, cloud_credentials, 'vyoora-backend', looks=SavedLooks(bucket))
    threading.Thread(target=tryon.run_worker, daemon=True, name='private-tryon-worker').start()
app = create_wardrobe_app(identity, wardrobe, tryon=tryon,
    origins=['http://127.0.0.1:7357', 'http://localhost:7357'])
try:
    app.run(host='127.0.0.1', port=7359, debug=False, use_reloader=False)
finally:
    if tryon: tryon.stop.set()
