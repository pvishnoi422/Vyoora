"""Separate V2 entrypoint. No AI key or V11 application import."""
import os
import google.auth
from google.cloud import firestore, tasks_v2
from google.cloud import storage
from media_security import FirebaseIdentity
from wardrobe import GCSWardrobe, create_wardrobe_app
from safety import TryOnGuard, ServiceError, TRYON_PER_USER_DAY
from tryon_media import TryOnMedia
from saved_looks import SavedLooks
from tryon_dispatch import TaskDispatcher, QueuedTryOnService, register_task_route


class ProductionTryOnGuard(TryOnGuard):
    def admit(self, *args, **kwargs):
        if os.environ.get('TRYON_ENABLED', 'false').lower() != 'true':
            raise ServiceError('tryon_disabled', 'Try-on testing is currently paused.')
        return super().admit(*args, **kwargs)

    def availability(self, uid):
        if os.environ.get('TRYON_ENABLED', 'false').lower() != 'true':
            return {'enabled': False, 'remainingToday': 0, 'dailyLimit': TRYON_PER_USER_DAY,
                    'unlimitedPersonalTesting': False}
        return super().availability(uid)


def build_app():
    project = os.environ['VYOORA_AUTH_PROJECT']
    cloud_project = os.environ['GOOGLE_CLOUD_PROJECT']
    bucket_name = os.environ['VYOORA_WARDROBE_BUCKET']
    if any(os.environ.get(key) for key in ('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST')):
        raise RuntimeError('Production V2 must not use emulators')
    if project.startswith('demo-') or cloud_project.startswith('demo-'):
        raise RuntimeError('Production V2 requires real cloud and authentication projects')
    identity = FirebaseIdentity(project)
    credentials, _ = google.auth.default()
    bucket = storage.Client(project=cloud_project, credentials=credentials).bucket(bucket_name)
    bucket.reload()
    if (not bucket.iam_configuration.uniform_bucket_level_access_enabled or
        bucket.iam_configuration.public_access_prevention != 'enforced' or
        bucket.versioning_enabled or bucket.soft_delete_policy.retention_duration_seconds):
        raise RuntimeError('Wardrobe requires private storage with permanent object deletion')
    dispatcher = TaskDispatcher(tasks_v2.CloudTasksClient(credentials=credentials),
        os.environ['VYOORA_TASK_QUEUE'], os.environ['VYOORA_TASK_AUDIENCE'],
        os.environ['VYOORA_TASK_SERVICE_ACCOUNT'])
    wardrobe = GCSWardrobe(bucket)
    # Reuse policy, memberships and reservations exactly as stored. Deployment
    # never seeds/resets counters or grants a client its own test entitlement.
    guard = ProductionTryOnGuard(firestore.Client(project=cloud_project, credentials=credentials))
    service = QueuedTryOnService(guard, TryOnMedia(bucket), wardrobe, credentials,
        cloud_project, looks=SavedLooks(bucket), dispatcher=dispatcher)
    app = create_wardrobe_app(identity, wardrobe, tryon=service,
        origins=filter(None, os.environ.get('CORS_ORIGINS', '').split(',')))
    register_task_route(app, service, dispatcher)
    return app
