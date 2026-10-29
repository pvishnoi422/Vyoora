import importlib.util
from pathlib import Path

path=Path(__file__).resolve().parents[1]/'tools/prepare_ios_candidate.py'
spec=importlib.util.spec_from_file_location('ios_release',path)
release=importlib.util.module_from_spec(spec);spec.loader.exec_module(release)

def test_release_configuration_cannot_use_demo_v11_http_or_provider_secrets():
    valid={'FIREBASE_PROJECT_ID':'vyoora-production','FIREBASE_API_KEY':'AIza'+'x'*30,
        'AUTH_EMULATOR_HOST':'','WARDROBE_API_BASE_URL':'https://vyoora-v2.example.invalid'}
    assert release.validate(valid)==[]
    for changes in [{'FIREBASE_PROJECT_ID':'demo-vyoora'}, {'FIREBASE_API_KEY':''},
        {'AUTH_EMULATOR_HOST':'127.0.0.1:9099'}, {'WARDROBE_API_BASE_URL':'http://localhost:7359'},
        {'WARDROBE_API_BASE_URL':'https://vyoora-backend-dfdqi4ojza-uc.a.run.app'},
        {'OPENAI_API_KEY':'synthetic-do-not-bundle'}]:
        assert release.validate(valid|changes)
