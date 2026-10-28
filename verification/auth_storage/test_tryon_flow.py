"""Full private API workflow. All provider calls here are synthetic and unbilled."""
import io
import os
import subprocess
import uuid
from datetime import datetime, timezone, timedelta
import pytest
from PIL import Image
from test_access import setup, headers, photo
from test_wardrobe import MemoryWardrobe
from access import AccessDenied
from wardrobe import GCSWardrobe, create_wardrobe_app, normalize_image
from tryon import TryOnService
from tryon_media import TryOnMedia, CONSENT_VERSION
from safety import TryOnGuard, ServiceError, TRYON_CONTROL_COLLECTION, TRYON_JOB_COLLECTION

pytestmark=pytest.mark.skipif(not os.environ.get('FIRESTORE_EMULATOR_HOST'),reason='Isolated Firestore emulator required')


def output():
    b=io.BytesIO();Image.new('RGB',(64,96),'navy').save(b,format='PNG');return b.getvalue()


class MemoryMedia:
    def __init__(self,clock):self.clock=clock;self.photos={};self.previews={}
    def upload_reference(self,uid,stream):
        data=normalize_image(stream);now=self.clock();i=uuid.uuid4().hex;exp=(now+timedelta(days=7)).isoformat().replace('+00:00','Z')
        r={'schemaVersion':1,'id':i,'ownerId':uid,'createdAt':now.isoformat().replace('+00:00','Z'),
           'consentedAt':now.isoformat().replace('+00:00','Z'),'expiresAt':exp,'consentVersion':CONSENT_VERSION,
           'image':{'ownerId':uid,'imageId':i,'kind':'referencePhoto','expiresAt':exp}}
        self.photos[(uid,i)]=(r,data);return r
    def reference(self,uid,i,*,data=False):
        if (uid,i) not in self.photos:raise AccessDenied('not_found',404)
        r,b=self.photos[(uid,i)]
        if self.clock()>=datetime.fromisoformat(r['expiresAt']):raise AccessDenied('reference_expired',410)
        return (r,b) if data else r
    def references(self,uid):return [r for (owner,_),(r,b) in self.photos.items() if owner==uid and self.clock()<datetime.fromisoformat(r['expiresAt'])]
    def delete_reference(self,uid,i):self.photos.pop((uid,i),None)
    def put_preview(self,uid,i,ref,data,mime,expires):self.previews[(uid,i)]=(data,mime)
    def preview(self,uid,i):
        if (uid,i) not in self.previews:raise AccessDenied('not_found',404)
        return self.previews[(uid,i)]
    def delete_preview(self,uid,i):self.previews.pop((uid,i),None)


@pytest.fixture(params=['memory']+(['gcs'] if os.environ.get('VYOORA_V2_VERIFY_BUCKET') else []))
def flow(setup,request):
    from google.cloud import firestore
    assert os.environ['FIRESTORE_EMULATOR_HOST'].split(':')[0] in {'127.0.0.1','localhost'}
    identity,people=setup;client=firestore.Client(project='demo-vyoora-tryon-flow')
    for name in (TRYON_CONTROL_COLLECTION,TRYON_JOB_COLLECTION):
        for s in client.collection(name).stream():s.reference.delete()
    now=[datetime.now(timezone.utc)];g=TryOnGuard(client,clock=lambda:now[0])
    g.controls.document('policy').set({'enabled':True,'daily_budget_micro_usd':1_000_000,'monthly_budget_micro_usd':5_000_000,'per_user_day':3})
    for p in people.values():g.controls.document('member_'+g.actor(p['uid'])).set({'enabled':True})
    if request.param=='gcs':
        from google.cloud import storage
        from google.oauth2.credentials import Credentials
        credentials=Credentials(subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip())
        bucket=storage.Client(project='vyoora-backend',credentials=credentials).bucket(os.environ['VYOORA_V2_VERIFY_BUCKET'])
        wardrobe=GCSWardrobe(bucket);media=TryOnMedia(bucket,clock=lambda:now[0])
    else:
        wardrobe=MemoryWardrobe()
        def item(uid,i):
            if (uid,i) not in wardrobe.items:raise AccessDenied('not_found',404)
            return wardrobe.items[(uid,i)][0]
        wardrobe.item=item;media=MemoryMedia(lambda:now[0])
    calls=[]
    def provider(person,garment,**kw):kw['guard'].start_attempt(kw['job_key']);calls.append((person,garment));return output(),'image/png'
    service=TryOnService(g,media,wardrobe,None,'demo-vyoora',provider=provider)
    app=create_wardrobe_app(identity,wardrobe,tryon=service);api=app.test_client()
    yield api,people,service,now,calls
    if request.param=='gcs':
        for p in people.values():
            for kind in ('wardrobe','reference-photos','try-on'):
                for blob in bucket.list_blobs(prefix=f'{kind}/{p["uid"]}/'):blob.delete()
    client.close()


def garment(api,p):
    r=api.post('/v2/wardrobe',headers=headers(p),data={'name':'Navy sweater','category':'top','consent':'granted','image':(photo(),'garment.png')})
    assert r.status_code==201;return r.json['item']['id']

def reference(api,p,**override):
    data={'consent':'granted','consentVersion':CONSENT_VERSION,'adultPermission':'confirmed','image':(photo(),'person.png')};data.update(override)
    return api.post('/v2/reference-photos',headers=headers(p),data=data)

def submit(api,p,g,r,id='job',**overrides):
    data={'jobId':id,'garmentId':g,'referenceId':r,'consentVersion':CONSENT_VERSION};data.update(overrides)
    return api.post('/v2/try-on/jobs',headers=headers(p),json=data)

def inputs(flow):
    api,people,s,now,calls=flow;a=people['alice'];g=garment(api,a);r=reference(api,a)
    assert r.status_code==201
    return a,g,r.json['item']['id']


def test_reference_upload_requires_explicit_current_consent_and_ownership(flow):
    api,p,s,now,calls=flow;a=p['alice'];b=p['bob']
    for args in ({'consent':'no'},{'consentVersion':'old'},{'adultPermission':'no'}):
        assert reference(api,a,**args).status_code==400
    response=reference(api,a);assert response.status_code==201
    r=response.json['item'];assert datetime.fromisoformat(r['expiresAt'])-now[0]==timedelta(days=7)
    assert 'url' not in r and 'imageUrl' not in r
    assert api.get('/v2/reference-photos',headers=headers(a)).json['items']==[r]
    assert api.get('/v2/reference-photos',headers=headers(b)).json['items']==[]
    image=api.get(f'/v2/reference-photos/{r["id"]}/image',headers=headers(a))
    assert image.status_code==200 and image.headers['Cache-Control']=='private, no-store, max-age=0'
    assert api.get(f'/v2/reference-photos/{r["id"]}/image',headers=headers(b)).status_code in (404,410)
    assert api.delete(f'/v2/reference-photos/{r["id"]}',headers=headers(b)).status_code==204
    assert api.get(f'/v2/reference-photos/{r["id"]}/image',headers=headers(a)).status_code==200


def test_durable_job_polling_success_private_output_and_idempotency(flow):
    api,p,s,now,calls=flow;a,g,r=inputs(flow)
    created=submit(api,a,g,r);assert created.status_code==202 and created.json['job']['status']=='queued'
    assert submit(api,a,g,r).json['job']['id']=='job'
    assert len(list(s.guard.jobs.stream()))==1
    key=s.guard.job_ref(a['uid'],'job').id;s.process_one(key)
    assert len(calls)==1
    job=api.get('/v2/try-on/jobs/job',headers=headers(a)).json['job']
    assert job['status']=='succeeded' and job['aiGenerated'] is True
    image=api.get('/v2/try-on/jobs/job/image',headers=headers(a))
    assert image.status_code==200 and image.mimetype=='image/png' and image.data==output()
    assert image.headers['Cache-Control']=='private, no-store, max-age=0'
    assert api.get('/v2/try-on/jobs/job',headers=headers(p['bob'])).status_code==404
    assert api.get('/v2/try-on/jobs/job/image',headers=headers(p['bob'])).status_code==404
    assert api.delete('/v2/try-on/jobs/job',headers=headers(p['bob'])).status_code==404
    assert submit(api,a,g,r).json['job']['status']=='succeeded'
    s.process_one(key);assert len(calls)==1
    assert s.guard.availability(a['uid'])['remainingToday']==2


def test_queued_cancel_and_network_replay_never_dispatch_or_refund(flow):
    api,p,s,now,calls=flow;a,g,r=inputs(flow);assert submit(api,a,g,r).status_code==202
    assert api.delete('/v2/try-on/jobs/job',headers=headers(a)).json['job']['status']=='cancelled'
    s.process_one(s.guard.job_ref(a['uid'],'job').id)
    assert calls==[] and s.guard.availability(a['uid'])['remainingToday']==2
    assert submit(api,a,g,r).json['job']['status']=='cancelled'
    assert api.get('/v2/try-on/jobs/job/image',headers=headers(a)).status_code==409


def test_running_cancel_discards_provider_output(flow):
    api,p,s,now,calls=flow;a,g,r=inputs(flow);submit(api,a,g,r)
    def cancelled(person,garment,**kw):
        kw['guard'].start_attempt(kw['job_key']);calls.append(True)
        assert api.delete('/v2/try-on/jobs/job',headers=headers(a)).status_code==200
        return output(),'image/png'
    s.provider=cancelled;s.process_one(s.guard.job_ref(a['uid'],'job').id)
    assert api.get('/v2/try-on/jobs/job',headers=headers(a)).json['job']['status']=='cancelled'
    assert api.get('/v2/try-on/jobs/job/image',headers=headers(a)).status_code==409 and len(calls)==1
    with pytest.raises(AccessDenied):s.media.preview(a['uid'],'job')


def test_reference_deletion_revokes_access_cancels_jobs_and_cleans_objects(flow):
    api,p,s,now,calls=flow;a,g,r=inputs(flow);submit(api,a,g,r)
    s.process_one(s.guard.job_ref(a['uid'],'job').id)
    assert api.delete('/v2/reference-photos/'+r,headers=headers(a)).status_code==204
    assert api.get('/v2/reference-photos',headers=headers(a)).json['items']==[]
    assert api.get('/v2/reference-photos/'+r+'/image',headers=headers(a)).status_code==410
    assert api.get('/v2/try-on/jobs/job',headers=headers(a)).json['job']['status']=='cancelled'
    assert api.get('/v2/try-on/jobs/job/image',headers=headers(a)).status_code==409
    with pytest.raises(AccessDenied):s.media.preview(a['uid'],'job')
    if isinstance(s.media,TryOnMedia):
        assert not s.media.bucket.blob(f'reference-photos/{a["uid"]}/{r}.jpg').exists()
        assert not s.media.bucket.blob(f'try-on/{a["uid"]}/job').exists()


def test_revocation_before_dispatch_blocks_the_paid_attempt(flow):
    api,p,s,now,calls=flow;a,g,r=inputs(flow);submit(api,a,g,r)
    s.guard.revoke_reference(a['uid'],r)
    s.process_one(s.guard.job_ref(a['uid'],'job').id)
    assert calls==[] and s.guard.get(a['uid'],'job')['status']=='failed'
    assert s.guard.availability(a['uid'])['remainingToday']==2


def test_failure_expiry_and_entitlement_never_become_success(flow):
    api,p,s,now,calls=flow;a,g,r=inputs(flow)
    assert submit(api,a,g,r,consentVersion='old').status_code==400
    assert submit(api,p['bob'],g,r).status_code==404
    s.guard.controls.document('member_'+s.guard.actor(a['uid'])).update({'enabled':False})
    assert submit(api,a,g,r).status_code==403 and calls==[]
    s.guard.controls.document('member_'+s.guard.actor(a['uid'])).update({'enabled':True})
    assert submit(api,a,g,r).status_code==202
    def failed(person,garment,**kw):
        kw['guard'].start_attempt(kw['job_key']);raise RuntimeError('SECRET_PROVIDER_TEXT')
    s.provider=failed;s.process_one(s.guard.job_ref(a['uid'],'job').id)
    response=api.get('/v2/try-on/jobs/job',headers=headers(a));assert response.json['job']['status']=='failed'
    assert b'SECRET' not in response.data and api.get('/v2/try-on/jobs/job/image',headers=headers(a)).status_code==409
    now[0]+=timedelta(days=8)
    assert api.get('/v2/reference-photos/'+r+'/image',headers=headers(a)).status_code==410


def test_every_tryon_route_requires_verified_auth(flow):
    api,p,s,now,calls=flow
    for method,path in [('get','/v2/try-on/availability'),('get','/v2/reference-photos'),('post','/v2/reference-photos'),
        ('get','/v2/reference-photos/x/image'),('delete','/v2/reference-photos/x'),('get','/v2/try-on/jobs'),
        ('post','/v2/try-on/jobs'),('get','/v2/try-on/jobs/x'),('delete','/v2/try-on/jobs/x'),('get','/v2/try-on/jobs/x/image')]:
        assert getattr(api,method)(path).status_code==401
        assert getattr(api,method)(path,headers=headers(p['unverified'])).status_code==403
