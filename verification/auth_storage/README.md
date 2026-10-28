# Isolated auth/storage verification

This reference boundary is not imported or shipped by the V11 application.
Use Python 3.11+ and Node 22. Install `requirements.txt`, run `npm ci`, then
`npm test`. Firebase CLI supplies the local demo-project Auth emulator.

Default tests exercise real emulator identities and an in-memory object adapter.
Set `VYOORA_V2_VERIFY_BUCKET=vyoora-backend-v2-private-20261027` only when explicitly
running real private-bucket acceptance with an authorized cloud CLI identity.
The suite creates synthetic `.invalid` accounts, deletes them, and removes only
objects under their fresh generated UIDs. It never needs an AI provider key.

Credentials and tokens must not be printed, committed, or stored in model JSON.
Production must never enable the unsigned emulator path. See
`docs/v2/AUTH_AND_PRIVATE_IMAGES.md` from the repository root for the decision,
verified cases, limitations and production activation requirements.
