# Provider-key rotation dependencies

Documentation complete: October 27, 2026. Actual key replacement/revocation has
not been performed. The owner is unsure whether the existing key is used by
other applications; that unknown is an explicit dependency for revocation.

## Current verified configuration

V11 mounts `vyoora-openai-api-key`, pinned version 1, at
`/secrets/openai/api-key`. Its dedicated runtime identity is
`vyoora-runtime@vyoora-backend.iam.gserviceaccount.com`. The running revision is
`vyoora-backend-00026-kij`; there is no plaintext API-key environment variable in
that revision. Historical revisions or older build artifacts can retain the
original key, so Secret Manager migration did not invalidate those copies.

The shared admission policy is in `vyoora_ai_guard/policy`. Daily/monthly
reservations must survive rotation, redeployment and rollback. The V11 rollback
helper requires an explicit approved numeric secret version; it must not restore
a revoked version merely because that version was present in the first manifest.

## Dependency checklist

| Dependency | Current state | Responsible role / evidence needed |
| --- | --- | --- |
| Provider organization/project and key administrator | Not independently confirmed | Provider account owner identifies the project and an authorized key administrator. |
| Other consumers of the original key | Unknown; owner explicitly unsure | Account owner/application owners inventory usage and confirm migration responsibilities. Never revoke on assumption. |
| Dedicated replacement permissions and expiry | Plan documented; key not created | Key administrator selects only the model-request permissions needed by Vyoora, verifies effective project roles and applicable key-governance/expiry policy. No admin key is placed in the app. |
| Secret Manager version creation | Existing secret and runtime access are available | Authorized operator saves the replacement as a new version without chat/Git/log exposure and records its numeric version identifier. |
| Staging credential change | Procedure available | Deploy a zero-production-traffic guarded revision using that explicit version; verify health, failure contract, shared quotas and a separately approved bounded AI acceptance call. |
| Rollback compatibility | Tested V11 image/source retained | Keep a still-valid approved secret version for rollback, preserve the policy/ledger, and use the V11 restore manifest. |
| Traffic activation and monitoring | Controlled rollout is supported | Operator switches only after staging acceptance and checks authentication/provider errors and reservation accounting. |
| Original-key revocation | Waiting for consumer inventory/migration | Key administrator revokes only after every known consumer has migrated or its owner approves the impact. |
| Historical-copy exposure | Original key remains valid | Revocation, rather than deleting one artifact, invalidates copies. Review historical artifacts under the normal retention policy afterward. |

## Execution order

1. Confirm provider ownership and inventory consumers; choose a Vyoora-specific
   replacement and, where appropriate, a separate project boundary.
2. Create the replacement under the provider's effective permissions and expiry
   policy. Existing inference credentials do not prove access to administer keys.
3. Save a new Secret Manager version; grant no additional browser/client access.
4. Stage the pinned V11 image with that version, with production traffic unchanged.
5. Verify model access, the result contract and the existing guard; make a bounded
   paid acceptance call only with the applicable authorization/reservation.
6. Activate the credential-bearing revision, monitor, and update the approved
   rollback secret-version reference. Keep the shared budget counters intact.
7. Coordinate remaining consumers, then revoke the original key. Remove the old
   secret version only after the rollback/recovery dependency has been resolved.

If staging fails, keep production on its existing valid revision. If a live key
fails, pause AI through the existing policy and use a still-valid approved secret
with the guarded V11 image; do not return to an unguarded V10 deployment.

## Completion boundary

This item asked for dependencies to be documented. The checklist, owners, unknowns,
execution sequence and rollback conditions are recorded here. It does not claim
that unknown consumers have been identified or that the original key was revoked.
Neither uncertainty blocks basic V2 navigation/model work. Resolving the credential
inventory remains an operational follow-up before retiring the shared key.

Sources: [OpenAI production/key-rotation guidance](https://developers.openai.com/api/docs/guides/production-best-practices),
[effective role and key permissions](https://developers.openai.com/api/docs/guides/rbac).
