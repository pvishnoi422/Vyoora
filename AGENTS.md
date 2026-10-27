# Maintained Vyoora application

- Source of truth: this repository's `maintenance/secure-foundation` branch.
- Preserve the explicit analysis contract: only a structurally validated result
  with status=success, analysis_complete=true and at least one ingredient may
  produce a score, a zero-concern message, or a completed history record.
- Failed, unreadable, malformed and legacy/unverified results are not successes.
- All paid requests must use backend/provider.py and backend/safety.py. No direct
  SDK calls, in-memory quota fallback, silent provider retries, or refunds after
  an ambiguous failure. Extend bounded input/output pricing before any new model.
- Never read a source .env in production, commit keys, log provider bodies, or
  add credentials to a build context. Production uses a mounted secret file.
- Shared budget policy is authoritative. Never reset its counters during deploy.
- Run Flutter tests/analyzer/web build and backend tests. Run the Firestore
  integration test with an emulator for counter/transaction changes.
- New paid try-on endpoints require a separate authenticated-user and entitlement
  design; do not expose them as part of maintenance changes.
