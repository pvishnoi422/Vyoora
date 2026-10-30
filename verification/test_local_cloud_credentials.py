import importlib.util
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import pytest


spec = importlib.util.spec_from_file_location('local_cloud_credentials',
    Path(__file__).resolve().parents[1] / 'tools' / 'local_cloud_credentials.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_cached_token_uses_actual_expiry_and_renews_before_expiration():
    expiry = datetime.now(timezone.utc) + timedelta(minutes=2)
    payload = json.dumps({'credential': {'access_token': 'synthetic',
        'token_expiry': expiry.isoformat()}})
    credentials = module.LocalGcloudCredentials()
    with patch.object(module.subprocess, 'check_output', return_value=payload) as cli:
        credentials.refresh(None)
    assert credentials.expiry == expiry.replace(tzinfo=None)
    assert credentials.expired  # google-auth refresh threshold is 3m45s.
    assert '--min-expiry=300' in cli.call_args.args[0]


@pytest.mark.parametrize('expiry', ['2000-01-01T00:00:00Z', '2030-01-01T00:00:00'])
def test_invalid_expiry_is_rejected(expiry):
    payload = json.dumps({'credential': {'access_token': 'synthetic', 'token_expiry': expiry}})
    with patch.object(module.subprocess, 'check_output', return_value=payload):
        with pytest.raises(ValueError):
            module.LocalGcloudCredentials().refresh(None)
