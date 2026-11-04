from types import SimpleNamespace
from unittest.mock import Mock

import pytest

import wardrobe_app as runtime


@pytest.fixture
def configured(monkeypatch):
    for key in ('FIREBASE_AUTH_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST'):
        monkeypatch.delenv(key, raising=False)
    settings = {
        'GOOGLE_CLOUD_PROJECT': 'vyoora-backend',
        'VYOORA_AUTH_PROJECT': 'vyoora-backend',
        'VYOORA_WARDROBE_BUCKET': 'private-v2',
        'VYOORA_TASK_QUEUE': 'projects/vyoora-backend/locations/us-central1/queues/vyoora-v2',
        'VYOORA_TASK_AUDIENCE': 'https://vyoora-v2.example.com',
        'VYOORA_TASK_SERVICE_ACCOUNT': 'vyoora-v2-tasks@vyoora-backend.iam.gserviceaccount.com',
    }
    for key, value in settings.items():
        monkeypatch.setenv(key, value)
    identity, firestore, tasks, bucket = Mock(), Mock(), Mock(), Mock()
    bucket.iam_configuration = SimpleNamespace(uniform_bucket_level_access_enabled=True,
        public_access_prevention='enforced')
    bucket.versioning_enabled = False
    bucket.soft_delete_policy.retention_duration_seconds = 0
    monkeypatch.setattr(runtime, 'FirebaseIdentity', Mock(return_value=identity))
    monkeypatch.setattr(runtime.google.auth, 'default', Mock(return_value=(Mock(), 'vyoora-backend')))
    monkeypatch.setattr(runtime.storage, 'Client', Mock(return_value=Mock(bucket=Mock(return_value=bucket))))
    monkeypatch.setattr(runtime.firestore, 'Client', Mock(return_value=firestore))
    monkeypatch.setattr(runtime.tasks_v2, 'CloudTasksClient', Mock(return_value=tasks))
    return identity, firestore, tasks, bucket


def test_production_factory_wires_all_private_features_without_mutating_the_ledger(configured):
    identity, firestore, tasks, _ = configured
    app = runtime.build_app()
    paths = {rule.rule for rule in app.url_map.iter_rules()}
    assert {'/v2/wardrobe', '/v2/reference-photos', '/v2/try-on/jobs',
        '/v2/saved-looks', '/v2/account', '/internal/try-on'} <= paths
    api = app.test_client()
    assert api.get('/healthz').status_code == 200
    for path in ('/v2/wardrobe', '/v2/reference-photos', '/v2/try-on/jobs', '/v2/saved-looks'):
        assert api.get(path).status_code == 401
    assert api.delete('/v2/account').status_code == 401
    assert api.post('/internal/try-on', json={}).status_code == 401
    assert all(call[0] == 'collection' for call in firestore.mock_calls)
    tasks.create_task.assert_not_called()
    identity.delete_user.assert_not_called()


@pytest.mark.parametrize('key', ['FIREBASE_AUTH_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST'])
def test_production_factory_rejects_both_emulators_before_cloud_access(configured, monkeypatch, key):
    monkeypatch.setenv(key, '127.0.0.1:9099')
    with pytest.raises(RuntimeError, match='emulators'):
        runtime.build_app()
    runtime.FirebaseIdentity.assert_not_called()


@pytest.mark.parametrize('unsafe', ['public', 'acl', 'versioning', 'soft_delete'])
def test_production_factory_requires_private_storage_and_deletion(configured, unsafe):
    bucket = configured[3]
    if unsafe == 'public': bucket.iam_configuration.public_access_prevention = 'inherited'
    if unsafe == 'acl': bucket.iam_configuration.uniform_bucket_level_access_enabled = False
    if unsafe == 'versioning': bucket.versioning_enabled = True
    if unsafe == 'soft_delete': bucket.soft_delete_policy.retention_duration_seconds = 604800
    with pytest.raises(RuntimeError, match='private storage'):
        runtime.build_app()


def test_disabled_runtime_does_not_reserve_a_generation(configured, monkeypatch):
    from safety import ServiceError
    monkeypatch.delenv('TRYON_ENABLED', raising=False)
    client = Mock()
    guard = runtime.ProductionTryOnGuard(client)
    assert guard.availability('owner')['enabled'] is False
    with pytest.raises(ServiceError) as error:
        guard.admit('owner', 'job-1', 'garment', 'photo')
    assert error.value.code == 'tryon_disabled'
    assert all(call[0] == 'collection' for call in client.mock_calls)
