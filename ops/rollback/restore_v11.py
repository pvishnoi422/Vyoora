"""Restore the pinned V11 image to isolated staging by default. Never resets quotas."""
import argparse
import json
from pathlib import Path
import subprocess


def restore_command(manifest, target, secret_version, *, production_staging=False, ai_enabled=False):
    if target == manifest['productionService'] and not production_staging:
        raise ValueError('Production requires --production-staging; traffic is never moved by this script')
    if not secret_version.isdigit() or int(secret_version)<1:
        raise ValueError('An explicitly approved numeric secret version is required')
    env = {'AI_ENABLED':str(ai_enabled).lower(), 'OPENAI_API_KEY_FILE':manifest['secretMount'],
           'TRUSTED_PROXY_HOPS':'1','FIRESTORE_DATABASE':manifest['firestoreDatabase'],
           'GOOGLE_CLOUD_PROJECT':manifest['project']}
    command = ['gcloud','run','deploy',target,'--project='+manifest['project'],
        '--region='+manifest['region'],'--image='+manifest['image'],
        '--service-account='+manifest['runtimeIdentity'],
        '--set-env-vars='+','.join(k+'='+v for k,v in env.items()),
        '--set-secrets='+manifest['secretMount']+'='+manifest['secretName']+':'+secret_version,
        '--cpu='+manifest['cpu'],'--memory='+manifest['memory'],
        '--concurrency='+manifest['concurrency'],'--timeout='+manifest['timeoutSeconds'],
        '--max-instances='+('1' if target!=manifest['productionService'] else manifest['maxInstances']),
        '--min-instances=0','--quiet','--format=value(status.url)']
    if target == manifest['productionService']:
        command += ['--no-traffic','--tag=v11-restore']
    else:
        command += ['--no-allow-unauthenticated']
    return command


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--manifest',type=Path,default=Path(__file__).with_name('v11.json'))
    parser.add_argument('--target',default='vyoora-v11-rollback-drill')
    parser.add_argument('--secret-version',required=True)
    parser.add_argument('--production-staging',action='store_true')
    parser.add_argument('--ai-enabled',action='store_true')
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    manifest=json.loads(args.manifest.read_text())
    command=restore_command(manifest,args.target,args.secret_version,
        production_staging=args.production_staging,ai_enabled=args.ai_enabled)
    print(' '.join(command),flush=True)
    if args.apply:subprocess.run(command,check=True)
    else:print('Preview only; no cloud resources changed.')

if __name__=='__main__':main()
