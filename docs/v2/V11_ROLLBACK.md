# Tested V11 rollback path

Validated October 27, 2026 (America/New_York). The restore drill completed on
isolated staging with no production traffic change, no paid provider call and no
quota-policy/ledger writes. [Recorded result](evidence/v11-rollback-drill.json).

## Pinned baseline

- Source commit: `481824da4cd73588d4d2fa9f13a9c51427aa8648`.
- Source tag: `v11-rollback-2026-10-27` (published to the maintained fork).
- Image: `us-central1-docker.pkg.dev/vyoora-backend/cloud-run-source-deploy/vyoora-backend@sha256:fe35748978a128bc462dc9da247f7414f9ae8c3d69c5eee64cd465939ffc3a36`.
- Retention tag: `v11-rollback-2026-10-27`; Artifact Registry KEEP policy protects
  images tagged with `v11-rollback-` from automated cleanup.
- [Restore manifest](../../ops/rollback/v11.json) records region, runtime identity,
  image, secret reference, policy location and resource configuration.

## What the drill proved

The exact image was redeployed as private service `vyoora-v11-rollback-drill`,
revision `vyoora-v11-rollback-drill-00001-s78`. Anonymous access was denied; an
operator-authenticated request reached version 11 and healthy status. A valid
synthetic image with AI disabled returned explicit HTTP 503 `ai_disabled`,
`analysis_complete: false` and no score. Invalid images returned HTTP 400. The
try-on route remained absent. Production stayed 100% on `vyoora-backend-00026-kij`.

The drill verifies recovery of the guarded service and its fail-closed behavior.
It intentionally does not simulate a production outage or move live customer
traffic. The functional V11 image had already passed real analysis/chat staging
acceptance and the baseline CI checks before this drill.

## Reproduce isolated recovery

```sh
python ops/rollback/restore_v11.py --secret-version=APPROVED_NUMERIC_VERSION
# Review the preview, then run the same command with --apply.
python ops/rollback/drill_v11.py --output=docs/v2/evidence/v11-rollback-drill.json
```

Use a valid approved numeric secret version; `latest`, zero and invalid versions
are rejected. The default target is private and starts with AI disabled, min
instances zero and max instances one. The helper does not change the shared
policy or ledger. Six plan tests cover production gating, private defaults,
no automatic traffic move, and secret-version pinning.

## Production recovery procedure

1. Diagnose the failure and identify the pinned image and a valid approved secret
   version. A revoked old key is never a valid rollback dependency.
2. Run the helper with `--target=vyoora-backend --production-staging` to preview a
   no-traffic V11 restore revision. Add `--apply` only for an authorized recovery.
   Existing production invoker permissions are preserved.
3. Verify the staged revision, credential mount and guard. Enable AI only after
   its provider and shared controls are ready; keep AI disabled for a safe pause.
4. Record the staged revision name. Move traffic to that exact revision only
   after acceptance, then verify the live contract and remove temporary tags.
5. Preserve the current shared counters throughout; never seed/reset them as a
   rollback step. Record the traffic move and update the recovery evidence.

For an urgent spending pause, the existing disabled shared policy is sufficient
to stop new reservations; in-flight reserved calls may complete. Do not use an
unguarded V10 revision or reset budgets as a recovery mechanism.

The private drill service remains at min instances zero. It contains the V11
runtime and a secret reference, not a copied key in source or a plaintext key
variable. Routine image retention does not replace a future revalidation of
provider access, valid secret versions and recovery permissions.
