import json
from unittest.mock import Mock

import pytest
from google.api_core.exceptions import AlreadyExists

from safety import ServiceError
from tryon_dispatch import TaskDispatcher, QueuedTryOnService, register_task_route
from wardrobe import create_wardrobe_app

QUEUE = 'projects/vyoora-backend/locations/us-central1/queues/vyoora-v2'
ORIGIN = 'https://vyoora-v2.example.com'
ACCOUNT = 'vyoora-v2-tasks@vyoora-backend.iam.gserviceaccount.com'
KEY = 'a' * 64 + '_job-1'


def dispatcher(client=None):
    return TaskDispatcher(client or Mock(), QUEUE, ORIGIN, ACCOUNT)


def test_delivery_is_deduplicated_and_contains_no_photos_or_client_credentials():
    client = Mock()
    dispatch = dispatcher(client)
    dispatch(KEY)
    first = client.create_task.call_args
    dispatch(KEY)
    assert first == client.create_task.call_args
    task = first.kwargs['request']['task']
    assert json.loads(task['http_request']['body']) == {'jobKey': KEY}
    assert task['http_request']['oidc_token'] == {
        'service_account_email': ACCOUNT, 'audience': ORIGIN}
    assert task['http_request']['url'] == ORIGIN + '/internal/try-on'
    assert first.kwargs['retry'] is None
    client.create_task.side_effect = AlreadyExists('duplicate')
    dispatch(KEY)
    client.create_task.side_effect = RuntimeError('sensitive upstream detail')
    with pytest.raises(ServiceError) as error:
        dispatch(KEY)
    assert error.value.code == 'dispatch_unavailable'
    assert 'sensitive' not in str(error.value)


@pytest.mark.parametrize('origin', ['http://localhost', ORIGIN + '/path',
    'https://user:password@example.com', ORIGIN + '?key=secret'])
def test_task_destination_must_be_a_clean_https_origin(origin):
    with pytest.raises(RuntimeError):
        TaskDispatcher(Mock(), QUEUE, origin, ACCOUNT)


@pytest.mark.parametrize('status', ['queued', 'running', 'succeeded', 'failed', 'cancelled'])
def test_only_queued_idempotent_jobs_are_dispatched(status):
    guard = Mock()
    guard.get.return_value = {'id': 'job-1', 'garmentId': 'g', 'referenceId': 'r', 'status': status}
    guard.job_ref.return_value.id = KEY
    dispatch = Mock()
    service = QueuedTryOnService(guard, Mock(), Mock(), None, 'vyoora-backend', dispatcher=dispatch)
    service.create('owner', 'job-1', 'g', 'r')
    assert dispatch.call_count == (1 if status == 'queued' else 0)
    guard.admit.assert_not_called()
    # A retry cannot change selections or create a second reservation.
    with pytest.raises(ServiceError):
        service.create('owner', 'job-1', 'another-garment', 'r')
    assert dispatch.call_count == (1 if status == 'queued' else 0)


def task_api(claims=None):
    identity, store, service = Mock(), Mock(), Mock()
    service.guard.jobs.document.return_value.get.return_value.to_dict.return_value = {'status': 'succeeded'}
    app = create_wardrobe_app(identity, store)
    @app.errorhandler(ServiceError)
    def error(value):
        return {'code': value.code}, value.http_status
    verify = Mock(return_value=claims if claims is not None else {'email': ACCOUNT, 'email_verified': True})
    register_task_route(app, service, dispatcher(), verify=verify)
    return app.test_client(), service, verify


def test_ambiguous_enqueue_fails_the_job_without_refunding_or_making_a_paid_call():
    guard = Mock()
    guard.get.return_value = {'id': 'job-1', 'garmentId': 'g', 'referenceId': 'r', 'status': 'queued'}
    guard.job_ref.return_value.id = KEY
    dispatch = Mock(side_effect=ServiceError('dispatch_unavailable', 'Unavailable'))
    service = QueuedTryOnService(guard, Mock(), Mock(), None, 'vyoora-backend', dispatcher=dispatch)
    with pytest.raises(ServiceError):
        service.create('owner', 'job-1', 'g', 'r')
    guard.finish.assert_called_once_with('owner', 'job-1', 'failed', 'dispatch_unavailable')
    guard.admit.assert_not_called()
    guard.start_attempt.assert_not_called()


@pytest.mark.parametrize('claims', [
    {'email': 'other@vyoora-backend.iam.gserviceaccount.com', 'email_verified': True},
    {'email': ACCOUNT, 'email_verified': False},
    {'uid': 'firebase-user'},
])
def test_end_user_or_other_service_identity_cannot_dispatch_a_job(claims):
    api, service, verify = task_api(claims)
    assert api.post('/internal/try-on', json={'jobKey': KEY},
        headers={'Authorization': 'Bearer synthetic'}).status_code == 401
    service.process_one.assert_not_called()


def test_worker_verifies_audience_and_fails_closed_on_verification_errors():
    api, service, verify = task_api()
    assert api.post('/internal/try-on', json={'jobKey': KEY}).status_code == 401
    verify.assert_not_called()
    headers = {'Authorization': 'Bearer synthetic'}
    assert api.post('/internal/try-on', json={'jobKey': KEY}, headers=headers).status_code == 204
    assert verify.call_args.kwargs['audience'] == ORIGIN
    service.process_one.assert_called_once_with(KEY)
    verify.side_effect = ValueError('invalid signature or audience')
    assert api.post('/internal/try-on', json={'jobKey': KEY}, headers=headers).status_code == 401
    assert service.process_one.call_count == 1


def test_bad_task_payloads_never_reach_processing_and_running_job_keeps_delivery_open():
    api, service, _ = task_api()
    headers = {'Authorization': 'Bearer synthetic'}
    for data in [{'jobKey': '../other'}, {'jobKey': KEY, 'owner': 'someone'}, {'jobKey': 123}]:
        assert api.post('/internal/try-on', json=data, headers=headers).status_code == 400
    service.process_one.assert_not_called()
    service.guard.jobs.document.return_value.get.return_value.to_dict.return_value = {'status': 'running'}
    assert api.post('/internal/try-on', json={'jobKey': KEY}, headers=headers).status_code == 503
    service.guard.recover_stale.assert_called_once()
