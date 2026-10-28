"""Read-only acceptance of the isolated restored service; no paid provider calls."""
from datetime import datetime,timezone
import argparse
import io
import json
from pathlib import Path
import subprocess
import requests
from PIL import Image


def cloud(args):return subprocess.check_output(['gcloud',*args],text=True)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--target',default='vyoora-v11-rollback-drill')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    m=json.loads(Path(__file__).with_name('v11.json').read_text())
    if args.target==m['productionService']:raise SystemExit('The drill never targets production')
    def description(name):return json.loads(cloud(['run','services','describe',name,
        '--project='+m['project'],'--region='+m['region'],'--format=json']))
    before=description(m['productionService'])['status']['traffic']
    restored=description(args.target);spec=restored['spec']['template']['spec']
    assert spec['containers'][0]['image']==m['image']
    assert spec['serviceAccountName']==m['runtimeIdentity']
    env={e['name']:e for e in spec['containers'][0].get('env',[])}
    assert 'OPENAI_API_KEY' not in env and env['AI_ENABLED']['value']=='false'
    url=restored['status']['url']
    assert requests.get(url+'/health',timeout=30).status_code in [401,403]
    token=cloud(['auth','print-identity-token']).strip();headers={'Authorization':'Bearer '+token}
    root=requests.get(url+'/',headers=headers,timeout=30)
    assert root.status_code==200 and root.json()['version']=='11'
    assert requests.get(url+'/health',headers=headers,timeout=30).status_code==200
    image=io.BytesIO();Image.new('RGB',(12,12),'white').save(image,format='PNG');image.seek(0)
    response=requests.post(url+'/upload',headers=headers,files={'image':('synthetic.png',image,'image/png')},timeout=50)
    assert response.status_code==503 and response.json()['code']=='ai_disabled'
    assert response.json()['analysis_complete'] is False and 'smart_score' not in response.json()
    invalid=requests.post(url+'/upload',headers=headers,files={'image':('invalid.jpg',b'invalid','image/jpeg')},timeout=30)
    assert invalid.status_code==400 and invalid.json()['analysis_complete'] is False
    assert requests.post(url+'/try-on',headers=headers,timeout=30).status_code==404
    after=description(m['productionService'])['status']['traffic']
    assert before==after
    report={'testedAt':datetime.now(timezone.utc).isoformat(),'sourceCommit':m['sourceCommit'],
        'sourceTag':m['release'],'image':m['image'],'restoredService':args.target,
        'restoredRevision':restored['status']['latestReadyRevisionName'],
        'privateService':True,'health':'passed','v11Version':'passed',
        'aiDisabledFailure':'passed','invalidImageFailure':'passed','tryOnAbsent':True,
        'productionTrafficUnchanged':True,'productionTraffic':after,
        'paidProviderCalls':0,'quotaPolicyOrLedgerWrites':0}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))

if __name__=='__main__':main()
