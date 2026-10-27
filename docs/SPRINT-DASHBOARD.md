# Vyoora V2 sprint dashboard

Updated: October 27, 2026 (America/New_York).

**Sprint progress: 0 of 6 items complete.** All six requested follow-ups remain open. Implementation and deployment of V2 are separate from this dashboard update.

## Maintained foundation

- Source of truth: [pvishnoi422/Vyoora](https://github.com/pvishnoi422/Vyoora), default branch `maintenance/secure-foundation`; write access is confirmed.
- Tested V11 code baseline: [`481824d`](https://github.com/pvishnoi422/Vyoora/commit/481824da4cd73588d4d2fa9f13a9c51427aa8648). [Hosted checks passed](https://github.com/pvishnoi422/Vyoora/actions/runs/40587129976), including 42 backend tests, six Flutter tests, image build, dependency audit, and release web build.
- Production: `vyoora-backend-00026-kij`, us-central1, serving 100% of traffic. Guarded error responses, shared rate limits, Secret Manager mounting, and $5/day and $50/month reservation limits are active.
- Flutter client distribution remains pending. No Fashion/Wardrobe feature or paid try-on endpoint is deployed.

## Sprint board

| ID | Item | Status | Dependency / remaining work | Completion evidence required |
| --- | --- | --- | --- | --- |
| V2-01 | Create a V2 development branch from the maintained source | Open — ready to start | No external blocker. Choose the branch name and branch from the maintained HEAD, recording the V11 code baseline. | Branch exists locally and remotely, has the correct parent/history, and its starting commit is recorded. |
| V2-02 | Implement basic Fashion/Wardrobe navigation in Flutter | Open — waiting on V2-01 | Work belongs on the V2 branch. Existing Home, History, Ask Lumi, and Profile navigation must remain usable. | Fashion and Wardrobe screens are reachable; back/tab behavior and existing routes pass widget tests. |
| V2-03 | Define wardrobe item, reference photo, and saved-look models | Open — waiting on V2-01; ownership design needed | Agree on relationships, user ownership, private asset references, serialization, and deletion behavior alongside V2-04. Model drafts can proceed before infrastructure is provisioned. | Typed models and serialization tests cover IDs, relationships, ownership, timestamps/schema version, and missing/invalid data. |
| V2-04 | Verify authentication and private image-storage approach | Open — architecture and verification needed | Current app has no verified end-user login/token enforcement. No dedicated user-image bucket or user-isolation tests were found. Select and validate the identity/storage approach. | Documented decision plus tests proving owner access, cross-user denial, unauthenticated denial, private object access, expiry, and deletion/retention behavior. |
| V2-05 | Document provider-key rotation dependencies | Open — initial notes exist; ownership unresolved | The owner is unsure whether the existing key is shared. Complete the dependency inventory and reviewed replacement/revocation sequence; see below. Documenting known dependencies can proceed now. | Dependency checklist identifies affected apps/owners, credential access, replacement version, staging verification, rollback, and the condition for revoking the original key. |
| V2-06 | Preserve a tested V11 rollback path | Open — restore procedure and drill needed | The tested V11 source and image exist. A pinned rollback manifest/release and a restore drill are still outstanding. | Retained immutable image and source reference; runtime/secret/policy references; an isolated staging restore drill with recorded results and no reset of shared spend counters. |

## Blockers and decisions

### B1 — End-user identity and private image ownership are unverified

A service account and Secret Manager protect backend infrastructure; they do not authenticate app users or enforce ownership of wardrobe photos. The current client uses local scan history. Wardrobe item, reference photo, and saved-look persistence are not implemented.

The two current project buckets are build/source buckets: `run-sources-vyoora-backend-us-central1` and `vyoora-backend_cloudbuild`. No dedicated private wardrobe/reference-image bucket was found. Its access controls, object naming, server-side authorization, and lifecycle remain to be designed and tested. Existing build buckets should not be treated as the user-photo store.

**Unblocks:** final model ownership/storage fields, persistent wardrobe/photo features, and any paid fitting-room release. Basic navigation and model drafts can proceed independently on the V2 branch.

### B2 — The original provider key's other consumers are unknown

The existing key was copied into Secret Manager; it was not rotated or revoked. Historical revisions/artifacts may retain copies. The owner has not confirmed which other applications use it.

The rotation dependency document must capture:

1. Provider account/project owner and access to create a dedicated Vyoora replacement key.
2. Inventory of existing-key consumers and the people responsible for their migration.
3. Intended permissions/models for the replacement and a new Secret Manager version.
4. A staging rollout and controlled acceptance check using the replacement.
5. A rollback procedure that keeps valid credentials and the existing shared budget ledger.
6. Verification that other consumers have migrated before revoking the original key.

**Blocker:** revocation of the original key awaits consumer/owner confirmation. Creating an isolated replacement can be planned independently; the key must never be pasted into chat or Git. The documentation item remains open until its dependency checklist is reviewed.

### B3 — A tested live V11 baseline exists; the rollback drill is outstanding

Verified retained image:

```text
us-central1-docker.pkg.dev/vyoora-backend/cloud-run-source-deploy/vyoora-backend@sha256:fe35748978a128bc462dc9da247f7414f9ae8c3d69c5eee64cd465939ffc3a36
```

A rollback manifest should pin the source/image, runtime identity/configuration, and an approved valid Secret Manager version. It must preserve the shared policy and ledger, including reservations already consumed. If keys rotate, an invalidated old key must not become a rollback dependency.

Run a restore drill on isolated staging and record health, explicit failure states, guard enforcement, and any approved paid acceptance call. Verify image retention and recoverability before relying on the path. Avoid an unguarded V10 revision as a security rollback.

**Release gate:** the V11 rollback path must be demonstrated before a V2 backend replaces production. This does not prevent creating the V2 branch or developing navigation.

## Suggested execution order

1. Record/pin the V11 baseline and create the V2 branch (V2-06 preparation, V2-01).
2. Draft models and the auth/private-storage decision together (V2-03, V2-04).
3. Implement and test Fashion/Wardrobe navigation (V2-02).
4. Complete the key dependency checklist and coordinate credential isolation (V2-05).
5. Run and record the V11 rollback drill before a V2 production release (V2-06).

No external blocker was found for starting the V2 branch, navigation scaffolding, or model drafts. Authentication/private storage and tested rollback remain release gates; unknown key consumers block safe revocation.

## Evidence and related documents

- Repository branches, default branch, write permission, and V11 CI were rechecked for this update. No V2 development branch was present.
- Production traffic and retention of the immutable V11 image were rechecked without changing cloud resources.
- [`HomeShell`](../lib/screens/home_shell.dart) currently contains the four existing tabs; Fashion/Wardrobe navigation is absent.
- [`StorageService`](../lib/services/storage_service.dart) handles local scan history; [`pubspec.yaml`](../pubspec.yaml) has no end-user auth integration.
- [Consolidation](CONSOLIDATION.md), [security controls](SECURITY.md), [rollout and emergency pause](ROLLOUT.md), and [baseline validation](VALIDATION.md).

The earlier security/rollout documents were written before production activation. This dashboard records the subsequently verified live V11 state; it does not imply that V2 work, credential rotation, client distribution, or a rollback drill has been completed.
