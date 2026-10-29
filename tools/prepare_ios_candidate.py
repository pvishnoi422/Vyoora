"""Fail-closed release preflight; --build archives only a configured, signed app.

Accepts public Firebase client configuration, never a provider/service-account key.
Does not upload or alter Cloud Run, Firebase accounts, budgets or V11 revisions.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import urlparse

V11_HOSTS = {'vyoora-backend-dfdqi4ojza-uc.a.run.app', 'vyoora-backend-315311834855.us-central1.run.app'}

def validate(config):
    if not isinstance(config,dict) or any(not isinstance(value,str) for value in config.values()):
        return ['Release configuration must be an object of public string settings.']
    errors = []
    allowed = {'FIREBASE_PROJECT_ID', 'FIREBASE_API_KEY', 'AUTH_EMULATOR_HOST', 'WARDROBE_API_BASE_URL'}
    if set(config)-allowed: errors.append('Unexpected configuration fields; never bundle provider credentials.')
    project = config.get('FIREBASE_PROJECT_ID','')
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,62}',project) or project.startswith('demo-'):
        errors.append('A production Firebase project is required.')
    if not re.fullmatch(r'AIza[A-Za-z0-9_-]{20,}',config.get('FIREBASE_API_KEY','')):
        errors.append('The production Firebase public client API key is missing.')
    if config.get('AUTH_EMULATOR_HOST'): errors.append('Release builds must not use the Auth emulator.')
    uri = urlparse(config.get('WARDROBE_API_BASE_URL',''))
    if (uri.scheme!='https' or not uri.hostname or uri.hostname in {'localhost','127.0.0.1'} or
        uri.username or uri.password or uri.query or uri.fragment or uri.path not in {'','/'}):
        errors.append('The separate V2 HTTPS backend origin is required.')
    if uri.hostname in V11_HOSTS or (uri.hostname or '').startswith('vyoora-backend-'):
        errors.append('V2 must not point to the live V11 backend.')
    return errors

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,required=True)
    parser.add_argument('--build',action='store_true')
    args=parser.parse_args()
    try: config=json.loads(args.config.read_text()); errors=validate(config)
    except (OSError,ValueError,TypeError): errors=['Readable public release configuration is required.']
    signing=subprocess.run(['security','find-identity','-v','-p','codesigning'],capture_output=True,text=True)
    if '0 valid identities found' in signing.stdout or signing.returncode:
        errors.append('An Apple signing certificate and its private key are required.')
    print(json.dumps({'readyToBuild':not errors,'blockers':errors,'bundleId':'com.priya.vyoora',
        'version':'2.0.0+17','uploaded':False},indent=2))
    if errors:return 2
    if args.build:
        root=Path(__file__).resolve().parents[1]
        return subprocess.call(['flutter','build','ipa','--release','--dart-define-from-file='+str(args.config.resolve()),
            '--export-options-plist=ios/ExportOptions.plist'],cwd=root)
    return 0

if __name__=='__main__':raise SystemExit(main())
