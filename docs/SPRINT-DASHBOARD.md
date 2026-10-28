# Vyoora V2 sprint dashboard

Updated: October 27, 2026 (America/New_York).

**Sprint implementation: 6 of 6 items complete.** Hosted verification of the published V2 change is tracked separately below. V2 foundations remain on the development branch; production continues to run V11.

## Source and release separation

- Stable branch: [`maintenance/secure-foundation`](https://github.com/pvishnoi422/Vyoora/tree/maintenance/secure-foundation).
- V2 branch: [`development/v2`](https://github.com/pvishnoi422/Vyoora/tree/development/v2), created from maintained commit `78cd6eecff628d69c40a16190bec0c7b109d10cd`.
- Pinned V11 source: [`v11-rollback-2026-10-27`](https://github.com/pvishnoi422/Vyoora/tree/v11-rollback-2026-10-27), code commit `481824d`.
- Production remains 100% on guarded V11 revision `vyoora-backend-00026-kij`. No paid fitting-room route or V2 media route is exposed there.

## Completed sprint board

| ID | Item | Status | Completion evidence |
| --- | --- | --- | --- |
| V2-01 | Create a V2 development branch from the maintained source | Complete | `development/v2` exists locally and remotely, with maintained commit `78cd6ee` as its starting point. |
| V2-02 | Implement basic Fashion/Wardrobe navigation in Flutter | Complete | Fashion is reachable from the app shell; Wardrobe, Reference photos, and Saved looks have working routes/back paths. Existing destinations remain reachable. Navigation tests include a 320px phone layout. |
| V2-03 | Define wardrobe item, reference photo, and saved-look models | Complete | Typed, versioned JSON records validate IDs, owner relationships, timestamps, consent/expiry, image kinds and saved-look references. Serialization and invalid/cross-user data tests pass. |
| V2-04 | Verify authentication and private image-storage approach | Complete — approach verified | Firebase Auth verification and backend-mediated private GCS access passed emulator and real private-bucket acceptance. Owner-only access, invalid/expired/disabled sessions, expiry and deletion were tested. Production sign-in/upload activation remains future integration work. |
| V2-05 | Document provider-key rotation dependencies | Complete — documentation delivered | Dedicated dependency inventory, responsible roles, unknown consumers, replacement/staging sequence, secret versioning and rollback conditions are documented. The original shared key was not revoked. |
| V2-06 | Preserve a tested V11 rollback path | Complete | Source tag, immutable image tag/KEEP policy, restore manifest/helper, six restore-plan tests and an actual private Cloud Run restore drill are preserved. No production traffic, paid calls, or budget counters were changed by the drill. |

## Evidence

All implementation links below explicitly target the V2 branch, so this dashboard can also be read from the stable branch.

- [Fashion/Wardrobe screens](https://github.com/pvishnoi422/Vyoora/blob/development/v2/lib/screens/fashion/fashion_screen.dart) and [navigation tests](https://github.com/pvishnoi422/Vyoora/blob/development/v2/test/fashion_navigation_test.dart).
- [Domain models](https://github.com/pvishnoi422/Vyoora/blob/development/v2/lib/models/fashion/domain.dart) and [model tests](https://github.com/pvishnoi422/Vyoora/blob/development/v2/test/fashion_models_test.dart).
- [Auth/private-image decision](https://github.com/pvishnoi422/Vyoora/blob/development/v2/docs/v2/AUTH_AND_PRIVATE_IMAGES.md) and [recorded real-bucket/emulator verification](https://github.com/pvishnoi422/Vyoora/blob/development/v2/docs/v2/evidence/auth-storage-verification.json).
- [Provider-key dependency document](https://github.com/pvishnoi422/Vyoora/blob/development/v2/docs/v2/PROVIDER_KEY_ROTATION.md).
- [V11 rollback runbook](https://github.com/pvishnoi422/Vyoora/blob/development/v2/docs/v2/V11_ROLLBACK.md), [manifest](https://github.com/pvishnoi422/Vyoora/blob/development/v2/ops/rollback/v11.json) and [private restore-drill evidence](https://github.com/pvishnoi422/Vyoora/blob/development/v2/docs/v2/evidence/v11-rollback-drill.json).

## Validation status

- Flutter: 15 tests passed; release web build passed; analyzer reports no errors, with existing notices/warnings retained.
- Auth/private images: 14 tests passed and one memory-only duplicate case skipped, using synthetic accounts and a real private verification bucket. All synthetic images were removed.
- V11 recovery: six restore-plan tests and the private Cloud Run restore drill passed. The retained image is protected by a KEEP policy.
- Hosted CI: publication and final run link pending. The workflow now covers the V2 branch, Flutter, backend/restore plans, container checks and authentication-emulator verification.

## Remaining operational dependencies and release gates

These do not reopen the six completed foundation items:

1. **Original key retirement:** the owner is unsure which other applications use it. Consumer discovery/coordination is still required before revocation. The dependency document is complete; rotation itself was not this sprint item.
2. **Production identity/media integration:** register/configure the real auth application, wire verified sessions into Flutter and the V2 backend, apply privacy-approved retention, and test real production provider configuration before customer photos are enabled. The approach is verified; no production login/upload feature is claimed.
3. **Paid try-on release:** select the provider/model, verify bounded cost reservations, and implement verified user entitlements/payment authorization before exposing any paid endpoint.
4. **Client distribution:** V2 has been built and tested, not distributed through app stores. Existing V11 service traffic remains unchanged.

There is no remaining implementation blocker for the six requested sprint foundations. Future deployment, original-key revocation, and paid fitting-room work retain the explicit gates above.
