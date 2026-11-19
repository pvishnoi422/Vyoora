"""Production acceptance with fresh synthetic accounts; unbilled by default.

Tests the deployed API, not an in-process app. Default mode makes no AI requests
or usage-counter changes. Explicit one-generation mode uses the normal shared
reservation, with no retries, policy changes or refunds. Cleanup is restricted
to accounts and objects created by this run.
"""
import argparse
from datetime import datetime, timezone
import io
import json
import os
from pathlib import Path
import secrets
import sys
import time
import uuid

import firebase_admin
from firebase_admin import auth, credentials
from google.cloud import firestore, storage
from PIL import Image
import requests

from local_cloud_credentials import LocalGcloudCredentials
from prepare_ios_candidate import validate

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from safety import TryOnGuard

BUCKET = 'vyoora-backend-v2-private-20261027'


class AcceptanceFailure(RuntimeError):
    pass


def verify(config, *, generate=False, person_path=None, garment_path=None, output=None):
    if validate(config) or any(os.environ.get(key) for key in
            ('K_SERVICE', 'FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST')):
        raise RuntimeError('Real, separate production release configuration is required.')
    project, key, base = (config[name] for name in
        ('FIREBASE_PROJECT_ID', 'FIREBASE_API_KEY', 'WARDROBE_API_BASE_URL'))
    cloud = LocalGcloudCredentials()
    cloud._quota_project_id = project

    class OwnerCredential(credentials.Base):
        def get_credential(self): return cloud

    app = firebase_admin.initialize_app(OwnerCredential(), {'projectId': project}, name='release-v2-' + uuid.uuid4().hex)
    database = firestore.Client(project=project, credentials=cloud)
    guard = TryOnGuard(database)
    bucket = storage.Client(project=project, credentials=cloud).bucket(BUCKET)
    session = requests.Session()
    people = []
    now = datetime.now(timezone.utc)
    budget_ids = ['policy', 'global', 'day_' + now.strftime('%Y%m%d'), 'month_' + now.strftime('%Y%m')]

    def budgets(): return {name: guard.controls.document(name).get().to_dict() for name in budget_ids}
    before = budgets()

    def api(method, path, person=None, expected=200, **kwargs):
        headers = {'Authorization': 'Bearer ' + person['token']} if person else {}
        response = session.request(method, base.rstrip('/') + path, headers=headers, timeout=45, **kwargs)
        if response.status_code != expected:
            try: code = response.json().get('code', 'request_failed')
            except (ValueError, AttributeError): code = 'request_failed'
            raise AcceptanceFailure(f'{method} {path}: HTTP {response.status_code}, {code}')
        return response

    def password_signin(person):
        response = session.post('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',
            params={'key': key}, json={'email': person['email'], 'password': person['password'],
                'returnSecureToken': True}, timeout=25)
        if response.status_code != 200: raise RuntimeError('Synthetic account sign-in failed.')
        person['token'] = response.json()['idToken']

    image = io.BytesIO()
    Image.new('RGB', (32, 48), 'navy').save(image, format='PNG')
    image = image.getvalue()
    person_image = person_path.read_bytes() if generate else image
    garment_image = garment_path.read_bytes() if generate else image
    result = {}
    expected_budget = before
    try:
        api('GET', '/v2/wardrobe', expected=401)
        api('POST', '/internal/try-on', expected=401, json={})
        for _ in range(2):
            person = {'email': 'release-v2-' + uuid.uuid4().hex + '@vyoora.example.invalid',
                'password': secrets.token_urlsafe(32), 'deleted': False}
            response = session.post('https://identitytoolkit.googleapis.com/v1/accounts:signUp', params={'key': key},
                json={'email': person['email'], 'password': person['password'], 'returnSecureToken': True}, timeout=25)
            if response.status_code != 200: raise RuntimeError('Synthetic account creation failed.')
            person.update(uid=response.json()['localId'], token=response.json()['idToken'])
            people.append(person)
            assert api('GET', '/v2/wardrobe', person, expected=403).json()['code'] == 'verified_account_required'
            auth.update_user(person['uid'], email_verified=True, app=app)
            password_signin(person)
            assert api('GET', '/v2/wardrobe', person, expected=403).json()['code'] == 'private_test_required'
            guard.controls.document('member_' + guard.actor(person['uid'])).create({'enabled': True})
            assert api('GET', '/v2/wardrobe', person).json()['items'] == []
        alice, bob = people
        result['signed_in_testers_only'] = True
        print(json.dumps({'stage': 'verified_test_accounts_enrolled'}), flush=True)
        garment = api('POST', '/v2/wardrobe', alice, expected=201,
            data={'name': 'Synthetic production check', 'category': 'top', 'consent': 'granted'},
            files={'image': ('sample', garment_image, 'application/octet-stream')}).json()['item']
        item = garment['id']
        assert garment['ownerId'] == alice['uid']
        response = api('GET', '/v2/wardrobe/' + item + '/image', alice)
        assert response.headers['Cache-Control'] == 'private, no-store, max-age=0'
        api('GET', '/v2/wardrobe/' + item + '/image', bob, expected=404)
        api('DELETE', '/v2/wardrobe/' + item, bob, expected=204)
        api('GET', '/v2/wardrobe/' + item + '/image', alice)
        assert api('GET', '/v2/wardrobe', bob).json()['items'] == []
        anonymous = session.get(f'https://storage.googleapis.com/{BUCKET}/wardrobe/{alice["uid"]}/{item}.jpg', timeout=25)
        assert anonymous.status_code in (401, 403)
        result['wardrobe_storage_and_isolation'] = True
        print(json.dumps({'stage': 'wardrobe_storage_and_isolation_verified'}), flush=True)
        reference = api('POST', '/v2/reference-photos', alice, expected=201,
            data={'consent': 'granted', 'consentVersion': 'google-tryon-v1', 'adultPermission': 'confirmed'},
            files={'image': ('sample', person_image, 'application/octet-stream')}).json()['item']
        ref = reference['id']
        api('GET', '/v2/reference-photos/' + ref + '/image', alice)
        api('GET', '/v2/reference-photos/' + ref + '/image', bob, expected=410)
        assert api('GET', '/v2/saved-looks', alice).json()['items'] == []
        assert api('GET', '/v2/try-on/jobs', alice).json()['items'] == []
        assert api('GET', '/v2/try-on/availability', alice).json()['enabled'] is generate
        payload = {'jobId': uuid.uuid4().hex, 'garmentId': item, 'referenceId': ref,
                   'consentVersion': 'google-tryon-v1'}
        if generate:
            # Exactly one POST of a new job ID. Lost responses/provider failures
            # never create a second job or refund the original reservation.
            job = api('POST', '/v2/try-on/jobs', alice, expected=202, json=payload).json()['job']
            print(json.dumps({'stage': 'one_generation_submitted'}), flush=True)
            deadline = time.monotonic() + 300
            while job['status'] in ('queued', 'running') and time.monotonic() < deadline:
                time.sleep(2)
                job = api('GET', '/v2/try-on/jobs/' + payload['jobId'], alice).json()['job']
            if job['status'] != 'succeeded':
                raise AcceptanceFailure('Generation ended: ' + str(job.get('errorCode') or job['status']))
            original = api('GET', '/v2/try-on/jobs/' + payload['jobId'] + '/image', alice).content
            api('GET', '/v2/try-on/jobs/' + payload['jobId'] + '/image', bob, expected=404)
            api('POST', '/v2/saved-looks', alice, expected=201,
                json={'jobId': payload['jobId'], 'title': 'Public-sample production check', 'consentVersion': 'saved-looks-v1'})
            saved = api('GET', '/v2/saved-looks/' + payload['jobId'] + '/image', alice).content
            assert saved == original
            api('GET', '/v2/saved-looks/' + payload['jobId'] + '/image', bob, expected=404)
            expected_budget = budgets()
            for name in budget_ids[2:]:
                assert expected_budget[name]['reserved_micro_usd'] == (before[name] or {}).get('reserved_micro_usd', 0) + 150_000
            api('POST', '/v2/try-on/jobs', alice, expected=202, json=payload)
            assert budgets() == expected_budget
            if output:
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(original)
            result.update(one_generation_and_review_succeeded=True, saved_original_unchanged=True,
                generation_replay_did_not_charge=True, reservation_micro_usd=150_000)
        else:
            assert api('POST', '/v2/try-on/jobs', alice, expected=503,
                json=payload).json()['code'] == 'tryon_disabled'
        result['reference_privacy_verified'] = True
        for person in people:
            password_signin(person)
            old_token = person['token']
            api('DELETE', '/v2/account', person, expected=204, json={'confirmation': 'delete-my-account'})
            person['deleted'] = True
            api('GET', '/v2/wardrobe', {'token': old_token}, expected=401)
            for prefix in ('wardrobe', 'reference-photos', 'try-on', 'saved-looks'):
                assert not list(bucket.list_blobs(prefix=prefix + '/' + person['uid'] + '/'))
        result['account_cleanup_and_session_revocation'] = True
        assert budgets() == expected_budget
        result['cleanup_preserved_shared_budget_records'] = True
        result['paid_generation_attempts'] = 1 if generate else 0
        return result
    finally:
        # Failure cleanup is independent of the runtime under test. Only these
        # newly created UIDs are eligible; shared policy/usage records are intact.
        for person in people:
            if person['deleted']: continue
            guard.begin_account_deletion(person['uid'])
            for prefix in ('wardrobe', 'reference-photos', 'try-on', 'saved-looks'):
                for blob in bucket.list_blobs(prefix=prefix + '/' + person['uid'] + '/'):
                    blob.delete(if_generation_match=blob.generation)
            guard.delete_account_records(person['uid'])
            try: auth.delete_user(person['uid'], app=app)
            except auth.UserNotFoundError: pass
        session.close()
        database.close()
        firebase_admin.delete_app(app)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--one-paid-generation', action='store_true')
    parser.add_argument('--person', type=Path)
    parser.add_argument('--garment', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.one_paid_generation and (not args.person or not args.garment):
        parser.error('One-generation mode requires explicitly selected person and garment files.')
    if not args.one_paid_generation and (args.person or args.garment or args.output):
        parser.error('Sample input/output paths require explicit one-generation mode.')
    try: result = verify(json.loads(args.config.read_text()), generate=args.one_paid_generation,
        person_path=args.person, garment_path=args.garment, output=args.output)
    except Exception as error:
        # Never stringify transport exceptions: their URLs can contain API keys.
        result = {'passed': False, 'failureType': type(error).__name__}
        if isinstance(error, AcceptanceFailure): result['check'] = str(error)
        print(json.dumps(result))
        return 1
    print(json.dumps({'passed': True, **result}, indent=2))
    return 0


if __name__ == '__main__': raise SystemExit(main())
