"""One explicitly requested private generation, using only public sample inputs.

Supply local files from official provider public examples. No real
user photos or tokens are written to logs. Failed calls are never auto-retried.
"""
import argparse
import json
from pathlib import Path
import time
import uuid
import requests

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--person',type=Path,required=True)
parser.add_argument('--garment',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--account',choices=('alice','bob'),default='alice',help='Dedicated local test account; all quotas still apply')
args=parser.parse_args()
base='http://127.0.0.1:7359'
session=requests.Session()
signin=requests.post('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key',
    json={'email':args.account+'@vyoora.example.invalid','password':'Vyoora-local-only-2026!','returnSecureToken':True},timeout=20)
signin.raise_for_status();session.headers['Authorization']='Bearer '+signin.json()['idToken'];signin=None

def checked(response, allowed=(200,201,202)):
    if response.status_code not in allowed:
        try: code=response.json().get('code','request_failed')
        except Exception: code='request_failed'
        raise RuntimeError(f'Private test failed: HTTP {response.status_code}, {code}')
    return response

wardrobe=checked(session.post(base+'/v2/wardrobe',data={'name':'Sample navy sweater','category':'top','color':'navy','consent':'granted'},
    files={'image':('garment.jpg',args.garment.read_bytes(),'image/jpeg')},timeout=45)).json()['item']
reference=checked(session.post(base+'/v2/reference-photos',
    data={'consent':'granted','consentVersion':'google-tryon-v1','adultPermission':'confirmed'},
    files={'image':('person.jpg',args.person.read_bytes(),'image/jpeg')},timeout=45)).json()['item']
payload={'jobId':uuid.uuid4().hex,'garmentId':wardrobe['id'],'referenceId':reference['id'],'consentVersion':'google-tryon-v1'}
job=checked(session.post(base+'/v2/try-on/jobs',json=payload,timeout=45)).json()['job']
print(json.dumps({'phase':'submitted','jobId':job['id'],'status':job['status']}),flush=True)
deadline=time.monotonic()+240
while job['status'] in ('queued','running') and time.monotonic()<deadline:
    time.sleep(2)
    job=checked(session.get(base+'/v2/try-on/jobs/'+job['id'],timeout=20)).json()['job']
evidence={'job':job,'source':'Official provider public example images','garmentId':wardrobe['id'],'referenceId':reference['id']}
args.output.parent.mkdir(parents=True,exist_ok=True)
if job['status']!='succeeded':
    args.output.with_suffix('.json').write_text(json.dumps(evidence,indent=2))
    raise RuntimeError('Generation did not succeed: '+str(job.get('errorCode',job['status'])))
image=checked(session.get(base+'/v2/try-on/jobs/'+job['id']+'/image',timeout=45))
assert image.headers.get('Cache-Control')=='private, no-store, max-age=0'
args.output.write_bytes(image.content)
# Replay the same request: no additional reservation/quota consumption.
before=checked(session.get(base+'/v2/try-on/availability',timeout=20)).json()['remainingToday']
replay=checked(session.post(base+'/v2/try-on/jobs',json=payload,timeout=45)).json()['job']
after=checked(session.get(base+'/v2/try-on/availability',timeout=20)).json()['remainingToday']
assert replay['id']==job['id'] and replay['status']=='succeeded' and before==after
# A second verified account cannot read this job or its image.
other_account='bob' if args.account=='alice' else 'alice'
bob=requests.post('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key',
    json={'email':other_account+'@vyoora.example.invalid','password':'Vyoora-local-only-2026!','returnSecureToken':True},timeout=20)
bob.raise_for_status();other={'Authorization':'Bearer '+bob.json()['idToken']};bob=None
assert requests.get(base+'/v2/try-on/jobs/'+job['id'],headers=other,timeout=20).status_code==404
assert requests.get(base+'/v2/try-on/jobs/'+job['id']+'/image',headers=other,timeout=20).status_code==404
other=None
evidence.update(idempotencyPassed=True,ownershipIsolationPassed=True,remainingToday=after,mimeType=image.headers['Content-Type'])
args.output.with_suffix('.json').write_text(json.dumps(evidence,indent=2))
session.headers.clear();session.close()
print(json.dumps({'phase':'succeeded','image':str(args.output),'remainingToday':after,'isolation':'passed','idempotency':'passed'}),flush=True)
