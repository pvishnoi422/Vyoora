"""Copy the existing runtime key to Secret Manager without printing its value.

Does not deploy or remove the old environment value. After approving the
rollout, deploy with a pinned secret version and remove OPENAI_API_KEY.
"""
import argparse
import json
import subprocess

p=argparse.ArgumentParser()
p.add_argument('--project',required=True)
p.add_argument('--region',default='us-central1')
p.add_argument('--service',default='vyoora-backend')
p.add_argument('--apply',action='store_true')
a=p.parse_args()
secret='vyoora-openai-api-key'
if not a.apply:
    print(f'Preview: migrate {a.project}/{a.service} runtime key to secret {secret}; no changes made.')
    raise SystemExit(0)

def command(args,input=None):
    result=subprocess.run(['gcloud',*args,'--project',a.project,'--quiet'],input=input,
                          capture_output=True,text=True)
    if result.returncode:
        # Deliberately never print a provider's raw error/stdout containing data.
        raise SystemExit('Cloud operation failed. Review its status in the cloud console; secret values were not printed.')
    return result.stdout

service=json.loads(command(['run','services','describe',a.service,'--region',a.region,'--format=json']))
key=next((e.get('value') for c in service['spec']['template']['spec']['containers']
          for e in c.get('env',[]) if e['name']=='OPENAI_API_KEY'),None)
if not key:
    raise SystemExit('No plaintext runtime key found. If already migrated, use the existing secret version.')
# This secret name is reserved for Vyoora. Reuse its existing resource on repeat.
probe=subprocess.run(['gcloud','secrets','describe',secret,'--project',a.project,'--format=value(name)'],capture_output=True,text=True)
if probe.returncode:
    command(['secrets','create',secret,'--replication-policy=automatic'])
version=command(['secrets','versions','add',secret,'--data-file=-','--format=value(name)'],input=key)
key=None
print('Secret version:',version.strip())
