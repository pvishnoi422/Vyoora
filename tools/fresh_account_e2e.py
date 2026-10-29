"""One public-sample paid generation under the existing private-test ledger.

Only loopback demo Auth is used. Tokens never leave process memory or logs.
Run generate, then native export tests, then cleanup. Never resets any quota.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid
import requests

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('phase',choices=['generate','cleanup'])
parser.add_argument('--manifest',type=Path,required=True)
parser.add_argument('--person',type=Path)
parser.add_argument('--garment',type=Path)
args=parser.parse_args()
base='http://127.0.0.1:7359'; auth='http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:'
def checked(response):
    if response.status_code not in (200,201,202,204):
        try:code=response.json().get('code',response.json().get('error',{}).get('message','request_failed'))
        except Exception:code='request_failed'
        raise RuntimeError(f'HTTP {response.status_code}: {code}')
    return response

session=requests.Session()
if args.phase=='generate':
    assert args.person and args.garment and not args.manifest.exists(), 'Use a new manifest; no automatic second generation.'
    info={'email':'qa-'+uuid.uuid4().hex+'@vyoora.example.invalid','password':'Vyoora-local-only-2026!',
        'jobId':uuid.uuid4().hex,'source':'Public Google/Fal provider examples','paidAttempts':0}
    result=checked(requests.post(auth+'signUp?key=demo-key',json={'email':info['email'],'password':info['password'],'returnSecureToken':True},timeout=15)).json()
    info['uid']=result['localId']; token=result['idToken']; result=None
    checked(requests.post(auth+'sendOobCode?key=demo-key',json={'requestType':'VERIFY_EMAIL','idToken':token},timeout=15))
    codes=checked(requests.get('http://127.0.0.1:9099/emulator/v1/projects/demo-vyoora-v2/oobCodes',timeout=15)).json()['oobCodes']
    code=next(c['oobCode'] for c in reversed(codes) if c['email']==info['email'] and c['requestType']=='VERIFY_EMAIL')
    checked(requests.post(auth+'update?key=demo-key',json={'oobCode':code},timeout=15)); code=None;codes=None;token=None
    # Explicitly entitle this requested fresh-account test, without changing any
    # existing member, daily counter, monthly counter or control policy.
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
    from google.cloud import firestore
    from google.oauth2.credentials import Credentials
    from safety import TryOnGuard
    secret=subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip()
    cloud=firestore.Client(project='vyoora-backend',credentials=Credentials(secret));secret=None
    guard=TryOnGuard(cloud); policy=guard.controls.document('policy').get().to_dict()
    assert policy=={'enabled':True,'daily_budget_micro_usd':1_000_000,'monthly_budget_micro_usd':5_000_000,'per_user_day':3}, 'Do not alter the shared policy'
    guard.controls.document('member_'+guard.actor(info['uid'])).create({'enabled':True})
    cloud.close()
else:info=json.loads(args.manifest.read_text())
result=checked(requests.post(auth+'signInWithPassword?key=demo-key',json={'email':info['email'],'password':info['password'],'returnSecureToken':True},timeout=15)).json()
session.headers['Authorization']='Bearer '+result['idToken'];result=None
if args.phase=='generate':
    garment=checked(session.post(base+'/v2/wardrobe',data={'name':'Fresh account navy sweater','category':'top','consent':'granted'},files={'image':('garment.jpg',args.garment.read_bytes(),'image/jpeg')},timeout=45)).json()['item']
    ref=checked(session.post(base+'/v2/reference-photos',data={'consent':'granted','consentVersion':'google-tryon-v1','adultPermission':'confirmed'},files={'image':('person.jpg',args.person.read_bytes(),'image/jpeg')},timeout=45)).json()['item']
    info.update(garmentId=garment['id'],referenceId=ref['id'])
    # Persist the synthetic account/job IDs before dispatch; never repeat a lost call with a new ID.
    args.manifest.write_text(json.dumps(info,indent=2))
    payload={'jobId':info['jobId'],'garmentId':info['garmentId'],'referenceId':info['referenceId'],'consentVersion':'google-tryon-v1'}
    job=checked(session.post(base+'/v2/try-on/jobs',json=payload,timeout=45)).json()['job']
    print(json.dumps({'stage':'generation_submitted','jobId':job['id']}),flush=True)
    deadline=time.monotonic()+240
    while job['status'] in ('queued','running') and time.monotonic()<deadline:
        time.sleep(2);job=checked(session.get(base+'/v2/try-on/jobs/'+job['id'],timeout=20)).json()['job']
    assert job['status']=='succeeded', job.get('errorCode',job['status'])
    original=checked(session.get(base+'/v2/try-on/jobs/'+job['id']+'/image',timeout=45)).content
    info['originalSha256']=hashlib.sha256(original).hexdigest();info['paidAttempts']=1
    look=checked(session.post(base+'/v2/saved-looks',json={'jobId':job['id'],'title':'Fresh account E2E look','consentVersion':'saved-looks-v1'},timeout=45)).json()['item']
    assert look['id']==job['id']
    saved=checked(session.get(base+'/v2/saved-looks/'+job['id']+'/image',timeout=45)).content
    assert saved==original
    info.update(saved=True,exportPending=True)
    args.manifest.write_text(json.dumps(info,indent=2))
    print(json.dumps({'stage':'saved','paidAttempts':1,'originalUnchanged':True}),flush=True)
else:
    # A fresh HTTP session/process must see the persisted record.
    look_id=info['jobId']
    response=session.get(base+'/v2/saved-looks/'+look_id+'/image',timeout=45)
    if response.status_code==200:
        assert hashlib.sha256(response.content).hexdigest()==info['originalSha256']
        checked(session.delete(base+'/v2/saved-looks/'+look_id,timeout=45))
    else:assert response.status_code==404 # native UI may already have deleted it
    assert session.get(base+'/v2/saved-looks/'+look_id+'/image',timeout=45).status_code==404
    original=checked(session.get(base+'/v2/try-on/jobs/'+look_id+'/image',timeout=45)).content
    assert hashlib.sha256(original).hexdigest()==info['originalSha256']
    checked(session.delete(base+'/v2/reference-photos/'+info['referenceId'],timeout=45))
    checked(session.delete(base+'/v2/wardrobe/'+info['garmentId'],timeout=45))
    info.update(deleted=True,storedOriginalUnchangedByExport=True)
    args.manifest.write_text(json.dumps(info,indent=2))
    print(json.dumps({'stage':'cleanup_verified','savedImageGone':True,'originalUnchangedByExport':True}),flush=True)
session.headers.clear();session.close()
