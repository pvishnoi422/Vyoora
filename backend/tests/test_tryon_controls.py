import copy
from datetime import datetime, timezone, timedelta
from concurrent.futures import ThreadPoolExecutor
import os
import pytest
from safety import (TryOnGuard, ServiceError, tryon_updates, TRYON_RESERVATION,
                    TRYON_CONTROL_COLLECTION, TRYON_JOB_COLLECTION)

NOW = datetime(2026, 10, 28, 12, tzinfo=timezone.utc)


def documents():
    return {'policy': {'enabled': True, 'daily_budget_micro_usd': 1_000_000,
                       'monthly_budget_micro_usd': 5_000_000, 'per_user_day': 3},
            'member': {'enabled': True}, 'day': {}, 'month': {}, 'user_day': {}, 'global': {}, 'actor': {}}


def test_tryon_limits_are_separate_and_fail_closed():
    from safety import RESERVATIONS
    assert RESERVATIONS == {'upload': 250_000, 'chat': 10_000}
    assert TRYON_CONTROL_COLLECTION != 'vyoora_ai_guard'
    d = documents(); updates = tryon_updates(d, NOW)
    assert updates['day']['reserved_micro_usd'] == TRYON_RESERVATION
    for key, value, code in [('member', {'enabled': False}, 'tryon_not_entitled'),
                             ('day', {'reserved_micro_usd': 1_000_000}, 'tryon_budget_exhausted'),
                             ('month', {'reserved_micro_usd': 5_000_000}, 'tryon_budget_exhausted'),
                             ('user_day', {'requests': 3}, 'tryon_quota_exhausted'),
                             ('actor', {'activeJobId': 'pending'}, 'generation_in_progress')]:
        altered = copy.deepcopy(d); altered[key] = value
        with pytest.raises(ServiceError) as error: tryon_updates(altered, NOW)
        assert error.value.code == code
    for policy in [{}, {'enabled': False}, {**d['policy'], 'daily_budget_micro_usd': 2_000_000},
                   {**d['policy'], 'monthly_budget_micro_usd': True}, {**d['policy'], 'per_user_day': 4}]:
        altered = copy.deepcopy(d); altered['policy'] = policy
        with pytest.raises(ServiceError): tryon_updates(altered, NOW)


@pytest.fixture
def guard():
    if not os.environ.get('FIRESTORE_EMULATOR_HOST'): pytest.skip('Firestore emulator required')
    assert os.environ['FIRESTORE_EMULATOR_HOST'].split(':')[0] in {'127.0.0.1', 'localhost'}
    from google.cloud import firestore
    client = firestore.Client(project='demo-vyoora-tryon-core')
    for collection in (TRYON_CONTROL_COLLECTION, TRYON_JOB_COLLECTION):
        for doc in client.collection(collection).stream(): doc.reference.delete()
    now = [NOW]; guard = TryOnGuard(client, clock=lambda: now[0])
    guard.controls.document('policy').set(documents()['policy'])
    for n in range(12):
        uid = f'actor-{n}'
        guard.controls.document('member_'+guard.actor(uid)).set({'enabled': True})
        guard.grant_reference(uid, {'id': 'photo', 'expiresAt': (NOW+timedelta(days=7)).isoformat(), 'consentVersion': 'google-tryon-v1'})
    yield guard, now
    client.close()


def test_atomic_budget_across_multiple_workers(guard):
    g, now = guard
    g.controls.document('policy').update({'daily_budget_micro_usd': 3*TRYON_RESERVATION})
    def submit(n):
        try: g.admit(f'actor-{n}', 'request', 'shirt', 'photo'); return True
        except ServiceError: return False
    with ThreadPoolExecutor(max_workers=8) as pool: admitted = list(pool.map(submit, range(8)))
    # Contention may fail closed early; it must never admit over the cap.
    assert 1 <= sum(admitted) <= 3
    for n in range(8, 12):
        if sum(admitted) == 3: break
        admitted.append(submit(n))
    assert sum(admitted) == 3
    assert g.controls.document('day_20261028').get().to_dict()['reserved_micro_usd'] == 3*TRYON_RESERVATION
    assert len(list(g.jobs.stream())) == 3
    assert not list(g.client.collection('vyoora_ai_guard').stream())


def test_concurrent_idempotency_reserves_once(guard):
    g, now = guard
    def submit(_):
        try: return g.admit('actor-0', 'same-request', 'shirt', 'photo')
        except ServiceError as error:
            # A contender may fail closed before the winner commits. Recover
            # with the identical request after contention, never a new ID.
            assert error.code == 'controls_unavailable'
            return None
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(submit, range(6)))
    jobs = [job for job in results if job is not None]
    assert jobs
    assert {j['id'] for j in jobs} == {'same-request'}
    for _ in results:
        assert g.admit('actor-0', 'same-request', 'shirt', 'photo')['id'] == 'same-request'
    assert g.controls.document('day_20261028').get().to_dict()['reserved_micro_usd'] == TRYON_RESERVATION
    assert len(list(g.jobs.stream())) == 1
    with pytest.raises(ServiceError) as error: g.admit('actor-0', 'same-request', 'different-shirt', 'photo')
    assert error.value.code == 'idempotency_conflict'


def test_cancellation_and_failure_do_not_refund_or_reset_quota(guard):
    g, now = guard
    for n in range(3):
        g.admit('actor-0', f'job-{n}', 'shirt', 'photo')
        if n % 2: g.finish('actor-0', f'job-{n}', 'failed', 'generation_failed')
        else: g.cancel('actor-0', f'job-{n}')
        now[0] += timedelta(seconds=61)
    with pytest.raises(ServiceError) as error: g.admit('actor-0', 'job-4', 'shirt', 'photo')
    assert error.value.code == 'tryon_quota_exhausted'
    assert g.controls.document('day_20261028').get().to_dict()['reserved_micro_usd'] == 3*TRYON_RESERVATION
    assert g.availability('actor-0')['remainingToday'] == 0


def test_claim_and_paid_attempt_are_once_only_and_recheck_revocation(guard):
    g, now = guard
    g.admit('actor-0', 'job', 'shirt', 'photo'); key = g.job_ref('actor-0', 'job').id
    assert g.claim(key) and g.claim(key) is None
    g.start_attempt(key)
    with pytest.raises(ServiceError): g.start_attempt(key)
    g.finish('actor-0', 'job', 'failed', 'synthetic')
    g.admit('actor-0', 'revoked', 'shirt', 'photo'); key = g.job_ref('actor-0', 'revoked').id
    g.claim(key); g.revoke_reference('actor-0', 'photo')
    with pytest.raises(ServiceError) as error: g.start_attempt(key)
    assert error.value.code == 'reference_expired'
    assert g.get('actor-0', 'revoked')['attempted'] is False


def test_crash_recovery_never_retries_an_ambiguous_paid_attempt(guard):
    g, now = guard
    g.admit('actor-0', 'job', 'shirt', 'photo'); key = g.job_ref('actor-0', 'job').id
    g.claim(key); g.start_attempt(key)
    now[0] += timedelta(minutes=5)
    g.recover_stale()
    assert g.get('actor-0', 'job')['status'] == 'failed'
    assert g.claim(key) is None
    assert g.controls.document('day_20261028').get().to_dict()['reserved_micro_usd'] == TRYON_RESERVATION


def test_midnight_dispatch_and_monthly_cap_are_enforced(guard):
    g, now = guard
    g.admit('actor-0', 'late', 'shirt', 'photo'); key = g.job_ref('actor-0', 'late').id
    g.claim(key); now[0] += timedelta(days=1)
    with pytest.raises(ServiceError) as error: g.start_attempt(key)
    assert error.value.code == 'generation_expired'
    g.controls.document('month_202610').set({'reserved_micro_usd': 5_000_000})
    with pytest.raises(ServiceError) as error: g.admit('actor-1', 'next-day', 'shirt', 'photo')
    assert error.value.code == 'tryon_budget_exhausted'


def test_kill_switch_and_account_revoke_stop_dispatch(guard):
    g, now = guard
    g.admit('actor-0', 'job', 'shirt', 'photo'); key = g.job_ref('actor-0', 'job').id; g.claim(key)
    g.controls.document('policy').update({'enabled': False})
    with pytest.raises(ServiceError): g.start_attempt(key)
    assert g.get('actor-0', 'job')['attempted'] is False


def test_database_outage_has_no_local_budget_fallback():
    class Broken:
        def collection(self, name): return self
        def document(self, name): return self
        def transaction(self, **kwargs): raise RuntimeError('offline')
    with pytest.raises(ServiceError) as error: TryOnGuard(Broken()).admit('alice', 'request', 'shirt', 'photo')
    assert error.value.code == 'controls_unavailable'
