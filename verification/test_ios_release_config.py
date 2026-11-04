import importlib.util
from types import SimpleNamespace
import pytest
from pathlib import Path

path=Path(__file__).resolve().parents[1]/'tools/prepare_ios_candidate.py'
spec=importlib.util.spec_from_file_location('ios_release',path)
release=importlib.util.module_from_spec(spec);spec.loader.exec_module(release)

def test_release_configuration_cannot_use_demo_v11_http_or_provider_secrets():
    valid={'FIREBASE_PROJECT_ID':'vyoora-production','FIREBASE_API_KEY':'AIza'+'x'*30,
        'AUTH_EMULATOR_HOST':'','WARDROBE_API_BASE_URL':'https://vyoora-v2-abc.us-central1.run.app'}
    assert release.validate(valid)==[]
    for changes in [{'FIREBASE_PROJECT_ID':'demo-vyoora'}, {'FIREBASE_API_KEY':''},
        {'AUTH_EMULATOR_HOST':'127.0.0.1:9099'}, {'WARDROBE_API_BASE_URL':'http://localhost:7359'},
        {'WARDROBE_API_BASE_URL':'https://vyoora-backend-dfdqi4ojza-uc.a.run.app'},
        {'OPENAI_API_KEY':'synthetic-do-not-bundle'}]:
        assert release.validate(valid|changes)


@pytest.mark.parametrize('origin', ['https://127.0.0.1', 'https://10.0.0.1',
    'https://[::1]', 'https://preview.local', 'https://example.com',
    'https://vyoora.example.invalid', 'https://vyoora-v2.test', 'https://example.com:invalid',
    'https://[invalid', 'https://vyoora-v2.run.app:8443', 'https://vyoora-v2.run.app\\@localhost'])
def test_release_rejects_private_placeholder_and_malformed_origins(origin):
    assert release.production_origin(origin) is None


def test_distribution_identity_must_belong_to_the_existing_app_team():
    def result(label, code=0):
        return SimpleNamespace(returncode=code, stdout='  1) ' + 'A'*40 + ' "' + label + '"\n')
    assert not release.signing_errors(result('Apple Distribution: Priya Vishnoi (MB3R9F8FF6)'))
    for label in ['Apple Development: Priya Vishnoi (MB3R9F8FF6)',
        'Apple Distribution: Someone Else (OTHERTEAM1)', '']:
        assert release.signing_errors(result(label))
    assert release.signing_errors(result('Apple Distribution: Priya Vishnoi (MB3R9F8FF6)', 1))
