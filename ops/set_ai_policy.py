"""Explicit operator action; never resets existing rate or spend counters."""
import argparse
import json
import subprocess
from google.oauth2.credentials import Credentials
from pathlib import Path
from google.cloud import firestore

parser = argparse.ArgumentParser()
parser.add_argument('--project', required=True)
parser.add_argument('--database', default='(default)')
parser.add_argument('--enable', action='store_true')
parser.add_argument('--use-gcloud', action='store_true', help='Use current CLI identity without persisting tokens')
parser.add_argument('--apply', action='store_true')
args = parser.parse_args()
policy = json.loads((Path(__file__).parents[1]/'backend/ai-policy.json').read_text())
policy['enabled'] = args.enable
print(json.dumps({'project':args.project, 'database':args.database, 'policy':policy}, indent=2))
if args.apply:
    credentials = None
    if args.use_gcloud:
        result = subprocess.run(['gcloud', 'auth', 'print-access-token'], capture_output=True, text=True)
        if result.returncode:
            raise SystemExit('Cloud authentication failed.')
        credentials = Credentials(result.stdout.strip())
    firestore.Client(project=args.project, database=args.database, credentials=credentials).collection('vyoora_ai_guard').document('policy').set(policy)
else:
    print('Preview only. Add --apply to write this policy.')
