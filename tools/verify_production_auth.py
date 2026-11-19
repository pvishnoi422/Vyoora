"""Check real release email/password auth with one disposable synthetic account.

Runs locally with the signed-in cloud owner's credentials. Does not use an
emulator, send email, call an AI provider, touch media, or change budget records.
Passwords, links, tokens and API keys stay in memory and are never printed.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import sys
from urllib.parse import urlparse, parse_qs
import uuid

import firebase_admin
from firebase_admin import auth, credentials
import requests

from local_cloud_credentials import LocalGcloudCredentials

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from media_security import AccessDenied, FirebaseIdentity


def verify(config):
    if any(os.environ.get(name) for name in ('K_SERVICE', 'FIREBASE_AUTH_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST')):
        raise RuntimeError('This check requires local execution against real authentication.')
    project, key = config.get('FIREBASE_PROJECT_ID', ''), config.get('FIREBASE_API_KEY', '')
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,62}', project) or project.startswith('demo-') or not key.startswith('AIza'):
        raise RuntimeError('Production public client configuration is required.')

    class OwnerCredential(credentials.Base):
        def get_credential(self):
            credential = LocalGcloudCredentials()
            credential._quota_project_id = project
            return credential

    app = firebase_admin.initialize_app(OwnerCredential(), {'projectId': project}, name='release-auth-' + uuid.uuid4().hex)
    # Reuse the shipped verifier with an explicitly credentialed local admin app.
    identity = FirebaseIdentity.__new__(FirebaseIdentity)
    identity.app = app
    created_uid = None
    session = requests.Session()
    email = 'release-auth-' + uuid.uuid4().hex + '@vyoora.example.invalid'
    password = secrets.token_urlsafe(32)
    results = {}

    def call(method, data):
        response = session.post('https://identitytoolkit.googleapis.com/v1/accounts:' + method,
            params={'key': key}, json=data, timeout=25)
        if response.status_code != 200: raise RuntimeError('Authentication check failed at ' + method + ': HTTP ' + str(response.status_code))
        return response.json()

    try:
        print(json.dumps({'stage': 'signup'}), flush=True)
        signup = call('signUp', {'email': email, 'password': password, 'returnSecureToken': True})
        created_uid = signup['localId']
        print(json.dumps({'stage': 'verify_unverified_session'}), flush=True)
        try: identity.verify(signup['idToken'])
        except AccessDenied as error: assert error.status == 403
        else: raise AssertionError('An unverified email was accepted')
        results['unverifiedEmailRejected'] = True

        print(json.dumps({'stage': 'verification_link'}), flush=True)
        link = auth.generate_email_verification_link(email, app=app)
        code = parse_qs(urlparse(link).query)['oobCode'][0]
        call('update', {'oobCode': code})
        link = code = None
        signin = call('signInWithPassword', {'email': email, 'password': password, 'returnSecureToken': True})
        assert identity.verify(signin['idToken']) == created_uid
        identity.require_recent(signin['idToken'])
        results['verifiedPasswordSignIn'] = True

        response = session.post('https://securetoken.googleapis.com/v1/token', params={'key': key},
            data={'grant_type': 'refresh_token', 'refresh_token': signin['refreshToken']}, timeout=25)
        if response.status_code != 200: raise RuntimeError('Token refresh check failed: HTTP ' + str(response.status_code))
        assert identity.verify(response.json()['id_token']) == created_uid
        results['sessionRefresh'] = True

        auth.update_user(created_uid, disabled=True, app=app)
        try: identity.verify(signin['idToken'])
        except AccessDenied as error: assert error.status == 401
        else: raise AssertionError('A disabled account was accepted')
        results['disabledAccountRejected'] = True

        auth.update_user(created_uid, disabled=False, app=app)
        signin = call('signInWithPassword', {'email': email, 'password': password, 'returnSecureToken': True})
        identity.delete_user(created_uid)
        try: identity.verify(signin['idToken'])
        except AccessDenied as error: assert error.status == 401
        else: raise AssertionError('A deleted account was accepted')
        results['deletedAccountSessionRejected'] = True
        results['verificationEmailDeliveryTested'] = False
        return results
    finally:
        if created_uid:
            try: auth.delete_user(created_uid, app=app)
            except auth.UserNotFoundError: pass
        session.close()
        firebase_admin.delete_app(app)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    args = parser.parse_args()
    try:
        result = verify(json.loads(args.config.read_text()))
    except Exception as error:
        message = str(error).lower()
        reason = 'quota_project' if 'quota' in message else 'oauth_scope' if 'scope' in message else 'permission' if 'permission' in message else 'check_failed'
        print(json.dumps({'passed': False, 'failureType': type(error).__name__, 'reason': reason}))
        return 1
    print(json.dumps({'passed': True, **result}, indent=2))
    return 0


if __name__ == '__main__': raise SystemExit(main())
