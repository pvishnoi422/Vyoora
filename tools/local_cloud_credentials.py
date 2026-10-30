"""Renewable credentials for the loopback development server only."""
import json
import subprocess
from datetime import datetime, timezone

from google.auth.credentials import Credentials


class LocalGcloudCredentials(Credentials):
    def refresh(self, request):
        # gcloud may return a cached token. Use its real expiry rather than
        # assuming it has another 45 minutes of validity.
        result = subprocess.check_output(
            ['gcloud', 'config', 'config-helper', '--min-expiry=300', '--format=json'],
            text=True,
        )
        credentials = json.loads(result)['credential']
        expiry = datetime.fromisoformat(credentials['token_expiry'].replace('Z', '+00:00'))
        if expiry.tzinfo is None:
            raise ValueError('Cloud session expiry must include a timezone')
        if expiry <= datetime.now(timezone.utc):
            raise ValueError('Cloud session has expired')
        self.token = credentials['access_token']
        self.expiry = expiry.astimezone(timezone.utc).replace(tzinfo=None)
