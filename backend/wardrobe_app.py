"""Separate V2 entrypoint. No AI key or V11 application import."""
import os
from google.cloud import storage
from media_security import FirebaseIdentity
from wardrobe import GCSWardrobe, create_wardrobe_app


def build_app():
    project = os.environ['VYOORA_AUTH_PROJECT']
    bucket_name = os.environ['VYOORA_WARDROBE_BUCKET']
    identity = FirebaseIdentity(project)
    bucket = storage.Client().bucket(bucket_name)
    bucket.reload()
    if (not bucket.iam_configuration.uniform_bucket_level_access_enabled or
        bucket.iam_configuration.public_access_prevention != 'enforced' or
        bucket.versioning_enabled or bucket.soft_delete_policy.retention_duration_seconds):
        raise RuntimeError('Wardrobe requires private storage with permanent object deletion')
    return create_wardrobe_app(identity, GCSWardrobe(bucket),
                              origins=os.environ.get('CORS_ORIGINS', '').split(','))


app = build_app()
