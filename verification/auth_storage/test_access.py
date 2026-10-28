import base64
import io
import json
import os
from datetime import datetime,timezone,timedelta
import subprocess
import uuid

import pytest
import requests
from PIL import Image
from firebase_admin import auth
from access import AccessDenied,FirebaseIdentity,MemoryObjects,PrivateGCSObjects,create_verification_app

PROJECT='demo-vyoora-v2'
pytestmark=pytest.mark.skipif(not os.environ.get('FIREBASE_AUTH_EMULATOR_HOST'),reason='Local Auth emulator required')


def photo():
    b=io.BytesIO();Image.new('RGB',(20,20),'blue').save(b,format='PNG');b.seek(0);return b


@pytest.fixture
def setup():
    identity=FirebaseIdentity(PROJECT,allow_emulator=True)
    base='http://'+os.environ['FIREBASE_AUTH_EMULATOR_HOST']+'/identitytoolkit.googleapis.com/v1'
    people={}
    for name in ['alice','bob','unverified']:
        email=f'{name}-{uuid.uuid4().hex}@example.invalid';password='Synthetic-test-only-123!'
        signup=requests.post(base+'/accounts:signUp?key=demo-key',json={'email':email,'password':password,'returnSecureToken':True},timeout=10)
        signup.raise_for_status();uid=signup.json()['localId']
        if name!='unverified':auth.update_user(uid,email_verified=True,app=identity.app)
        token=requests.post(base+'/accounts:signInWithPassword?key=demo-key',json={'email':email,'password':password,'returnSecureToken':True},timeout=10)
        token.raise_for_status();people[name]={'uid':uid,'token':token.json()['idToken']}
    yield identity,people
    for person in people.values():auth.delete_user(person['uid'],app=identity.app)
    identity.close()


@pytest.fixture(params=['memory']+(['gcs'] if os.environ.get('VYOORA_V2_VERIFY_BUCKET') else []))
def context(setup,request):
    identity,people=setup
    if request.param=='memory':store=MemoryObjects()
    else:
        from google.cloud import storage
        from google.oauth2.credentials import Credentials
        token=subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip()
        bucket=storage.Client(project='vyoora-backend',credentials=Credentials(token)).bucket(os.environ['VYOORA_V2_VERIFY_BUCKET'])
        token=None;store=PrivateGCSObjects(bucket)
    now=[datetime.now(timezone.utc)];app=create_verification_app(identity,store,clock=lambda:now[0]);app.config['TESTING']=True
    client=app.test_client()
    yield client,people,store,now
    if request.param=='gcs':
        for person in people.values():
            for kind in ['wardrobe','reference-photos','saved-looks']:
                for obj in store.bucket.list_blobs(prefix=f'{kind}/{person["uid"]}/'):obj.delete()


def headers(person):return {'Authorization':'Bearer '+person['token']}
def path(person,kind='wardrobe',item='photo-1'):return f'/v2/images/{person["uid"]}/{kind}/{item}'
def upload(client,person,kind='wardrobe',item='photo-1',consent='granted'):
    return client.post(path(person,kind,item),headers=headers(person),data={'image':(photo(),'photo.png'),'consent':consent})


def test_owner_create_read_delete_and_cache_boundary(context):
    client,p,store,now=context;a=p['alice'];url=path(a)
    r=upload(client,a);assert r.status_code==201 and 'url' not in r.json
    r=client.get(url,headers=headers(a));assert r.status_code==200
    assert r.headers['Cache-Control']=='private, no-store, max-age=0'
    assert r.mimetype=='image/jpeg'
    assert client.delete(url,headers=headers(a)).status_code==204
    assert client.get(url,headers=headers(a)).status_code==404


def test_other_user_cannot_create_read_replace_or_delete(context):
    client,p,store,now=context;a=p['alice'];b=p['bob'];assert upload(client,a).status_code==201
    for method in ['get','delete']:
        assert getattr(client,method)(path(a),headers=headers(b)).status_code==403
    assert client.post(path(a),headers=headers(b),data={'image':(photo(),'x.png'),'consent':'granted'}).status_code==403
    assert client.get(path(a),headers=headers(a)).status_code==200


def test_no_auth_invalid_token_and_unverified_email_are_denied(context):
    client,p,store,now=context;a=p['alice'];u=p['unverified']
    for method in ['get','post','delete']:
        assert getattr(client,method)(path(a)).status_code==401
    assert client.get(path(a),headers={'Authorization':'Bearer invalid'}).status_code==401
    assert upload(client,u).status_code==403


def test_disabled_account_is_denied(setup):
    identity,p=setup;a=p['alice'];assert identity.verify(a['token'])==a['uid']
    auth.update_user(a['uid'],disabled=True,app=identity.app)
    with pytest.raises(AccessDenied) as error:identity.verify(a['token'])
    assert error.value.status==401


def test_expired_session_is_denied(setup):
    identity,p=setup;parts=p['alice']['token'].split('.')
    payload=json.loads(base64.urlsafe_b64decode(parts[1]+'='*(-len(parts[1])%4)))
    payload['exp']=1
    parts[1]=base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=')
    with pytest.raises(AccessDenied) as error:identity.verify('.'.join(parts))
    assert error.value.status==401


def test_reference_expires_at_seven_days_and_can_still_be_deleted(context):
    client,p,store,now=context;a=p['alice']
    r=upload(client,a,'reference-photos');assert r.status_code==201
    expiry=datetime.fromisoformat(r.json['expiresAt'])
    assert expiry==now[0]+timedelta(days=7)
    now[0]=expiry
    assert client.get(path(a,'reference-photos'),headers=headers(a)).status_code==410
    assert client.delete(path(a,'reference-photos'),headers=headers(a)).status_code==204


def test_immutable_upload_requires_consent_and_valid_image(context):
    client,p,store,now=context;a=p['alice']
    assert upload(client,a,consent='no').status_code==400
    assert upload(client,a).status_code==201
    assert upload(client,a).status_code==409
    assert client.post(path(a,item='bad'),headers=headers(a),data={'image':(io.BytesIO(b'bad'),'x.png'),'consent':'granted'}).status_code==400


def test_production_cannot_use_unsigned_emulator_tokens(monkeypatch):
    monkeypatch.setenv('K_SERVICE','production')
    with pytest.raises(RuntimeError):FirebaseIdentity(PROJECT,allow_emulator=True)


def test_real_bucket_is_private_and_has_expiry_cleanup(context):
    client,p,store,now=context
    if not isinstance(store,PrivateGCSObjects):pytest.skip('Real GCS acceptance check')
    a=p['alice'];r=upload(client,a);assert r.status_code==201
    bucket=store.bucket;bucket.reload()
    assert bucket.iam_configuration.uniform_bucket_level_access_enabled
    assert bucket.iam_configuration.public_access_prevention=='enforced'
    assert bucket.soft_delete_policy.retention_duration_seconds in [None,0]
    assert not any('allUsers' in b['members'] or 'allAuthenticatedUsers' in b['members'] for b in bucket.get_iam_policy(requested_policy_version=3).bindings)
    direct=requests.get(f'https://storage.googleapis.com/{bucket.name}/{r.json["objectKey"]}',timeout=30)
    assert direct.status_code in [401,403]
    assert any(rule.get('condition',{}).get('daysSinceCustomTime')==0 for rule in bucket.lifecycle_rules)
