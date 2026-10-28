# V2 identity and private-image decision

Status: approach selected and verified on October 27, 2026. Production sign-in
and photo-upload activation are separate integration/release work. No V2 media
route was added to the live V11 backend.

## Decision

Use Firebase Authentication for identity and a backend-mediated, private Google
Cloud Storage bucket for photos. The identity boundary validates Firebase ID
tokens, checks revocation/disabled-user state, requires verified email, rejects
anonymous accounts, and derives the owner UID from the validated token. A caller
cannot supply a different owner in a body or object path.

Every image read, create, and delete passes through that boundary. The reference
implementation in `verification/auth_storage/access.py` returns image bytes to
an authenticated owner with `Cache-Control: private, no-store, max-age=0`.
It does not return public URLs, permanent Firebase download tokens, or bearer
signed URLs. Google Cloud Storage's native objects are inaccessible to anonymous
clients. CORS is not an ownership or authentication check.

Object keys have one server-controlled form:

```text
wardrobe/{verifiedUid}/{imageId}.jpg
reference-photos/{verifiedUid}/{imageId}.jpg
saved-looks/{verifiedUid}/{imageId}.jpg
```

IDs reject path traversal. Creates require consent, decode and normalize a valid
image, strip original metadata through JPEG re-encoding, and use a generation
precondition so a duplicate ID cannot overwrite a previous image. Stored owner
metadata is checked again before bytes leave the server. Metadata persistence
and saved-look relationship resolution must also validate ownership when their
future database endpoints are implemented.

## Expiry and deletion

Reference photos expire after seven days; saved-look previews after 30 days.
Wardrobe images remain until owner deletion. Expiry is enforced at the API
boundary immediately, including the exact expiry timestamp. Owners can delete
an expired object. A GCS lifecycle rule deletes reference/preview objects after
their custom-time expiry; physical lifecycle deletion is asynchronous. The test
bucket disables soft delete and object versioning is not enabled. These policies
need confirmation against the production privacy requirements before real
customer photos are enabled.

We tested immediate access expiry and owner deletion of real synthetic objects.
We verified the real bucket lifecycle configuration; we did not accelerate the
provider's scheduled lifecycle deletion clock or claim that it runs instantly.

## Verification evidence

[Recorded evidence](evidence/auth-storage-verification.json) includes:

- Real Firebase Auth emulator accounts, actual issued ID tokens, verified-email
  enforcement, disabled accounts, invalid tokens, and expired sessions.
- Owner create/read/delete and cross-user create/read/replace/delete denial.
- Unauthenticated denial, consent and valid-image requirements, immutable create,
  expiry boundary, deletion after expiry, and private response caching.
- Real private GCS acceptance using the isolated bucket
  `vyoora-backend-v2-private-20261027`: uniform bucket-level access, public access
  prevention enforced, no public IAM principals, anonymous download denied,
  lifecycle configuration verified, and all test images removed afterward.
- 14 passed, one skipped. The single skip is the memory-test duplicate of the
  real-bucket configuration case. No production user account, photo, or provider
  key was used for this verification.

Authentication emulator tokens are unsigned. The reference verifier permits
that mode only when explicitly requested, on loopback, for a `demo-` project,
and outside Cloud Run. A test proves that a production Cloud Run environment
cannot enable emulator verification. Real production verification uses the
provider's signed ID tokens; emulator results do not prove a production OAuth
provider/app registration is already configured.

## Production activation requirements

Register the intended Firebase project and application, enable chosen sign-in
providers, configure verified identities in Flutter, and connect automatic token
refresh/logout without storing tokens in scan history or model JSON. Provision
a separate V2 runtime identity with only the necessary identity-read permission
and bucket object access. Keep user-image IAM separate from build/source buckets.

Before activation, apply the privacy-approved retention policy, test real signed
tokens and disabled/revoked sessions, add quotas/upload limits and abuse controls,
and wire the verified media boundary into the V2 backend. The verification app
is not a production deployment artifact or a claim that an upload feature has
already shipped. Paid try-on additionally needs entitlements and separately
bounded AI cost accounting.

## Reproduce

```sh
python -m pip install -r verification/auth_storage/requirements.txt
npm ci --prefix verification/auth_storage
npm test --prefix verification/auth_storage
```

The default suite uses the local demo Auth emulator and an in-memory object
adapter. To repeat real-bucket acceptance, the operator must explicitly set
`VYOORA_V2_VERIFY_BUCKET` to the isolated verification bucket and have authorized
cloud CLI credentials. The test uses synthetic accounts and removes only objects
under their freshly generated user IDs. No production credential belongs in CI.

References: [Firebase ID-token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens),
[authentication emulator isolation](https://firebase.google.com/docs/emulator-suite/connect_auth),
[GCS public access prevention](https://cloud.google.com/storage/docs/public-access-prevention).
