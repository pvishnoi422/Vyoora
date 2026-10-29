from datetime import timedelta
import hashlib
from concurrent.futures import ThreadPoolExecutor
import pytest
from test_tryon_flow import flow, inputs, submit, headers
from test_access import setup
from saved_looks import SavedLooks
from media_security import AccessDenied


def save(api, person, job='job', **override):
    body = dict(jobId=job, title='Navy sweater look', consentVersion='saved-looks-v1'); body.update(override)
    return api.post('/v2/saved-looks', headers=headers(person), json=body)

def generate(flow):
    api, people, service, now, calls = flow
    a, garment, reference = inputs(flow)
    assert submit(api,a,garment,reference).status_code == 202
    service.process_one(service.guard.job_ref(a['uid'],'job').id)
    assert len(calls) == 1
    return a, reference

def test_save_reopen_restart_expire_delete_original_unchanged(flow):
    api, people, service, now, calls = flow; a, reference = generate(flow)
    original = service.preview(a['uid'],'job')[0]; digest = hashlib.sha256(original).digest()
    response = save(api,a); assert response.status_code == 201
    record = response.json['item']; assert record['ownerId']==a['uid'] and record['state']=='saved'
    # Replaying save creates no second image, no paid request or new expiry.
    assert save(api,a).json['item'] == record and len(calls)==1
    assert api.get('/v2/saved-looks',headers=headers(a)).json['items']==[record]
    # A new service object simulates an application/backend restart.
    service.looks = SavedLooks(service.looks.bucket, clock=lambda:now[0])
    image = api.get('/v2/saved-looks/job/image',headers=headers(a))
    assert image.status_code==200 and image.data==original
    assert image.headers['Cache-Control']=='private, no-store, max-age=0'
    assert hashlib.sha256(service.preview(a['uid'],'job')[0]).digest()==digest
    now[0] += timedelta(days=8)
    assert api.get('/v2/try-on/jobs/job/image',headers=headers(a)).status_code==410
    assert api.get('/v2/saved-looks/job/image',headers=headers(a)).status_code==200
    now[0] += timedelta(days=23)
    assert api.get('/v2/saved-looks/job/image',headers=headers(a)).status_code==404
    assert api.get('/v2/saved-looks',headers=headers(a)).json['items']==[]
    assert api.delete('/v2/saved-looks/job',headers=headers(a)).status_code==204
    assert not list(service.looks.bucket.list_blobs(prefix=f'saved-looks/{a["uid"]}/'))

def test_owner_isolation_consent_and_explicit_reference_deletion(flow):
    api, people, service, now, calls = flow; a, reference = generate(flow); b=people['bob']
    assert save(api,a,consentVersion='unknown').status_code==400
    assert save(api,a).status_code==201
    for path in ('/v2/saved-looks/job','/v2/saved-looks/job/image'):
        assert api.get(path,headers=headers(b)).status_code==404
    assert save(api,b).status_code==404
    assert api.get('/v2/saved-looks',headers=headers(b)).json['items']==[]
    assert api.delete('/v2/saved-looks/job',headers=headers(b)).status_code==204
    assert api.get('/v2/saved-looks/job/image',headers=headers(a)).status_code==200
    assert api.delete('/v2/reference-photos/'+reference,headers=headers(a)).status_code==204
    assert api.get('/v2/saved-looks/job/image',headers=headers(a)).status_code==404
    assert save(api,a).status_code in (409,410)
    assert not list(service.looks.bucket.list_blobs(prefix=f'saved-looks/{a["uid"]}/'))

def test_revocation_racing_save_discards_new_copy(flow):
    api, people, service, now, calls = flow; a, reference = generate(flow)
    original_save = service.looks.save
    def racing(*args, **kwargs):
        record = original_save(*args, **kwargs)
        service.guard.revoke_reference(a['uid'],reference)
        return record
    service.looks.save = racing
    assert save(api,a).status_code==410
    assert not list(service.looks.bucket.list_blobs(prefix=f'saved-looks/{a["uid"]}/'))

def test_cleanup_failure_keeps_saved_outputs_inaccessible(flow):
    api, people, service, now, calls = flow; a, reference = generate(flow)
    assert save(api,a).status_code==201
    original = service.looks.delete_reference
    service.looks.delete_reference = lambda *a: (_ for _ in ()).throw(RuntimeError('outage'))
    assert api.delete('/v2/reference-photos/'+reference,headers=headers(a)).status_code==503
    assert api.get('/v2/saved-looks/job/image',headers=headers(a)).status_code==410
    assert api.get('/v2/saved-looks',headers=headers(a)).json['items']==[]
    service.looks.delete_reference = original
    assert api.delete('/v2/reference-photos/'+reference,headers=headers(a)).status_code==204

def test_saved_routes_require_verified_account(flow):
    api, people, service, now, calls = flow
    for method,path in [('get','/v2/saved-looks'),('post','/v2/saved-looks'),('get','/v2/saved-looks/x'),('delete','/v2/saved-looks/x'),('get','/v2/saved-looks/x/image')]:
        assert getattr(api,method)(path).status_code==401
        assert getattr(api,method)(path,headers=headers(people['unverified'])).status_code==403
