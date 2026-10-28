"""Run with the emulator, never against production or a real billing project."""
import os
from concurrent.futures import ThreadPoolExecutor
import pytest
from safety import FirestoreGuard,ServiceError

pytestmark=pytest.mark.skipif(not os.environ.get('FIRESTORE_EMULATOR_HOST'),reason='Firestore emulator not configured')


def test_atomic_global_budget_across_clients(monkeypatch):
    from google.cloud import firestore
    monkeypatch.setenv('AI_ENABLED','true')
    client=firestore.Client(project='demo-vyoora')
    col=client.collection('vyoora_ai_guard')
    for doc in col.stream():doc.reference.delete()
    col.document('policy').set({'enabled':True,'daily_budget_micro_usd':500_000,'monthly_budget_micro_usd':5_000_000})
    guards=[FirestoreGuard(client=firestore.Client(project='demo-vyoora')) for _ in range(8)]
    def attempt(n):
        try:guards[n%8].reserve(f'actor-{n}','upload');return True
        except ServiceError:return False
    with ThreadPoolExecutor(max_workers=8) as pool:
        allowed=list(pool.map(attempt,range(8)))
    # Contention can exhaust transaction retries and safely reject a request.
    # Check accounting before filling the remaining budget without contention.
    assert 1 <= sum(allowed) <= 2
    days=[d.to_dict() for d in col.stream() if d.id.startswith('day_')]
    assert len(days)==1 and days[0]['reserved_micro_usd']==sum(allowed)*250_000
    assert days[0]['requests']==sum(allowed)
    for n in range(8,10):
        if sum(allowed)==2:break
        allowed.append(attempt(n))
    assert sum(allowed)==2
    assert not attempt(10)
    days=[d.to_dict() for d in col.stream() if d.id.startswith('day_')]
    assert len(days)==1 and days[0]['reserved_micro_usd']==500_000
