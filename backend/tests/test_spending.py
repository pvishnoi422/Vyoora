import copy
from types import SimpleNamespace
import pytest
import provider
from safety import ServiceError,consume_bucket,reservation_updates,FirestoreGuard


def documents():
    return {'policy':{'enabled':True,'daily_budget_micro_usd':5_000_000,'monthly_budget_micro_usd':50_000_000},
            'actor':{},'global':{},'day':{},'month':{}}


def test_daily_limit_reserves_inflight_requests():
    d=documents()
    for n in range(20):
        updates=reservation_updates(d,'upload',n*61)
        d.update(updates)
    assert d['day']['reserved_micro_usd']==5_000_000
    with pytest.raises(ServiceError,match='usage limit'):
        reservation_updates(d,'upload',1300)


def test_monthly_cap_survives_daily_reset():
    d=documents();d['month']={'reserved_micro_usd':50_000_000}
    with pytest.raises(ServiceError) as error:reservation_updates(d,'chat',0)
    assert error.value.code=='budget_exhausted'


def test_bucket_does_not_reset_at_minute_boundary():
    state={}
    for _ in range(3):state=consume_bucket(state,3,60,59)
    with pytest.raises(ServiceError):consume_bucket(state,3,60,61)
    assert consume_bucket(state,3,60,80)['tokens']>=0


@pytest.mark.parametrize('policy',[{}, {'enabled':False}, {'enabled':True},
    {'enabled':True,'daily_budget_micro_usd':0,'monthly_budget_micro_usd':50_000_000}])
def test_absent_or_disabled_policy_fails_closed(policy):
    d=documents();d['policy']=policy
    with pytest.raises(ServiceError):reservation_updates(d,'upload',0)


def test_global_rate_applies_across_actors():
    d=documents();d['policy'].update(daily_budget_micro_usd=100_000_000)
    for _ in range(60):
        d['actor']={};d.update(reservation_updates(d,'chat',0))
    d['actor']={}
    with pytest.raises(ServiceError) as error:reservation_updates(d,'chat',0)
    assert error.value.code=='rate_limited'


def test_database_outage_has_no_local_fallback(monkeypatch):
    monkeypatch.setenv('AI_ENABLED','true')
    class Broken:
        def collection(self,*a):raise RuntimeError('private backend details')
    with pytest.raises(ServiceError) as error:FirestoreGuard(client=Broken()).reserve('ip','chat')
    assert error.value.code=='controls_unavailable'
    assert 'private' not in str(error.value)


def test_kill_switch_stops_before_database(monkeypatch):
    monkeypatch.delenv('AI_ENABLED',raising=False)
    with pytest.raises(ServiceError) as error:FirestoreGuard(client=object()).reserve('ip','upload')
    assert error.value.code=='ai_disabled'


def test_no_provider_attempt_after_rejection(monkeypatch):
    calls=[]
    def reject(*a):raise ServiceError('budget_exhausted','Paused',429)
    monkeypatch.setattr(provider,'api_key',lambda:'test-key')
    monkeypatch.setattr(provider,'guard',SimpleNamespace(reserve=reject))
    monkeypatch.setattr(provider,'_client',SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=lambda **kw:calls.append(kw)))))
    with pytest.raises(ServiceError):provider.complete('chat','ip',[{'role':'user','content':'Hello'}])
    assert calls==[]


def test_provider_failure_retains_one_reservation_and_no_details(monkeypatch):
    reservations=[];attempts=[]
    def fail(**kw):attempts.append(kw);raise RuntimeError('SECRET_UPSTREAM_CONTENT')
    monkeypatch.setattr(provider,'api_key',lambda:'test-key')
    monkeypatch.setattr(provider,'guard',SimpleNamespace(reserve=lambda *a:reservations.append(a)))
    monkeypatch.setattr(provider,'_client',SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=fail))))
    with pytest.raises(ServiceError) as error:provider.complete('chat','ip',[{'role':'user','content':'Hello'}])
    assert len(reservations)==len(attempts)==1
    assert attempts[0]['max_tokens']==350 and attempts[0]['store'] is False
    assert 'SECRET' not in str(error.value)


def test_production_rejects_plain_environment_key(monkeypatch):
    monkeypatch.setenv('K_SERVICE','production');monkeypatch.setenv('OPENAI_API_KEY','not-a-real-key')
    monkeypatch.delenv('OPENAI_API_KEY_FILE',raising=False)
    assert provider.api_key() is None


def test_secret_file_is_supported(monkeypatch,tmp_path):
    p=tmp_path/'secret';p.write_text('sample-secret\n')
    monkeypatch.setenv('K_SERVICE','production');monkeypatch.setenv('OPENAI_API_KEY_FILE',str(p))
    assert provider.api_key()=='sample-secret'


def test_input_ceiling_is_enforced_before_reserving(monkeypatch):
    monkeypatch.setattr(provider,'api_key',lambda:'test-key')
    monkeypatch.setattr(provider,'guard',SimpleNamespace(reserve=lambda *a:pytest.fail('Reservation made')))
    with pytest.raises(ServiceError) as error:provider.complete('chat','ip',[{'role':'user','content':'x'*16001}])
    assert error.value.http_status==400


def test_missing_secret_never_reaches_provider_or_database(monkeypatch):
    monkeypatch.setattr(provider,'api_key',lambda:None)
    monkeypatch.setattr(provider,'guard',SimpleNamespace(reserve=lambda *a:pytest.fail('Reservation made')))
    with pytest.raises(ServiceError) as error:provider.complete('upload','ip',[])
    assert error.value.code=='ai_unavailable'


def test_real_sdk_transport_preserves_limits_and_reserves_first(monkeypatch):
    import httpx
    import json
    from openai import OpenAI
    events=[]
    def respond(request):
        events.append('provider')
        body=json.loads(request.content)
        assert body['max_tokens']==350 and body['store'] is False
        assert body['model']==provider.CHAT_MODEL
        return httpx.Response(200,json={'id':'chatcmpl-test','object':'chat.completion','created':0,
            'model':provider.CHAT_MODEL,'choices':[{'index':0,'finish_reason':'stop',
            'message':{'role':'assistant','content':'Completed reply.'}}]})
    client=OpenAI(api_key='test-only',max_retries=0,
        http_client=httpx.Client(transport=httpx.MockTransport(respond)))
    monkeypatch.setattr(provider,'_client',client)
    monkeypatch.setattr(provider,'api_key',lambda:'test-only')
    monkeypatch.setattr(provider,'guard',SimpleNamespace(reserve=lambda *a:events.append('reserve')))
    assert provider.complete('chat','actor',[{'role':'user','content':'Hello'}])=='Completed reply.'
    assert events==['reserve','provider']
    assert client.max_retries==0
    client.close()
