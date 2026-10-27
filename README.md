# Vyoora

The maintained source is **`pvishnoi422/Vyoora`, branch `maintenance/secure-foundation`**.
The original upstream is `vyooramedia/Vyoora`. Older local folders and ZIPs are
historical snapshots, not additional maintained applications.

This branch combines the Desktop v10 application's onboarding, profile, history,
and interface with the upstream checkout's complete platform scaffolding.
See [consolidation notes](docs/CONSOLIDATION.md) for provenance and retained history.

## Run and verify

```sh
flutter pub get
flutter test
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter build web --release
python3.11 -m venv .venv
.venv/bin/pip install -r backend/requirements.lock pytest
.venv/bin/python -m pytest backend/tests -q
```

AI endpoints are **disabled by default**. They require a runtime credential,
`AI_ENABLED=true`, and an enabled shared Firestore policy with a positive budget.
For local development use application-default credentials or the Firestore
emulator and a separately supplied test-project key. Do not commit local keys.

The API has one maintained entry point: `backend/app.py`. All AI calls go through
`backend/provider.py`, which requires an atomic reservation in `backend/safety.py`.
There is no fitting-room/try-on endpoint in this branch.

## Deployment

[Security and budget design](docs/SECURITY.md) describes failure semantics,
credentials, counter storage, and spending assumptions.
[Production rollout](docs/ROLLOUT.md) contains the explicit activation and rollback
steps. The approved policy limits are **$5/day and $50/month** in USD reservations;
the checked-in policy starts disabled. Publishing this branch does not deploy it.

The inactive CI template in `ops/verify.workflow.yml` runs Flutter regression
tests and a web build, backend/emulator tests, dependency auditing, and a non-root
container build check. GitHub rejected activating it because the saved credential
lacks the `workflow` scope. After authorization, place it at
`.github/workflows/verify.yml`. It never receives production keys.
