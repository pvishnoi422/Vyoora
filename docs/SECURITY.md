# Analysis integrity and backend controls

## Result contract

A completed result includes `status: success`, `analysis_complete: true`, a
nonempty ingredient list, its matching count, validated concerns, a summary,
and a bounded score. The backend validates the model output before adding the
completion fields. Provider refusals, token-limit truncation, invalid JSON,
missing fields, unreadable labels, and unavailable integrations never become
successful results. Errors have `status: error`, `analysis_complete: false`, a
stable code, and an appropriate 4xx/5xx status. They have no score or empty
concern list masquerading as a completed assessment.

The Flutter upload flow, result screen, and history layer independently require
that contract. Old or malformed payloads produce an unavailable state. Successful
zero-concern output says only that nothing was flagged in the ingredients read;
it does not establish product safety or validate regulatory claims.

## Credentials and build boundaries

Production must mount a Secret Manager version at `/secrets/openai/api-key` and
set `OPENAI_API_KEY_FILE`. A plain `OPENAI_API_KEY` is ignored under Cloud Run.
Local development may supply a process environment key. Source `.env` files are
never automatically loaded. Provider bodies and exception messages are not
logged or returned to users. The OpenAI client has `store=false`.

Docker has an allowlist and explicit COPY statements. Only the explicit runtime
Python/configuration files and locked dependencies enter the image. Root/backend
`.gcloudignore` files also allowlist runtime build inputs for source uploads.
The container runs as UID 10001. Use a dedicated runtime service account with
Firestore data access and access to the specific AI secret; do not reuse the
project's broad default Compute service account.

## Shared rate limits and spending reservations

Before **every** provider attempt, a Firestore transaction reads the shared
policy, per-client token bucket, global bucket, UTC daily ledger, and UTC monthly
ledger. It atomically commits both rate consumption and the spend reservation.
Multiple workers/instances share the same documents. Transaction conflicts are
retried by Firestore; exhaustion or database failure denies the provider call.
There is no in-memory fallback. There are no automatic provider retries or
post-failure reservation refunds. The $5/$50 limits apply to the whole service,
not separately to each process. Policy changes must not delete/reset ledgers.

- Per client: 3 upload requests per minute, 20 chat requests per minute (token
  buckets, with bursts no larger than their capacities).
- Global: 60 AI attempts per minute across clients/endpoints.
- Upload reservation: $0.25; chat reservation: $0.01.
- User-approved policy: $5/day and $50/calendar month, UTC.
- At those limits, an upload-only workload admits at most 20 attempts/day or
  200/month. Chat shares the same pool. Failed calls also consume reservations.

Reservations deliberately overestimate allowed calls rather than reconcile to
observed usage. Unused reservations are not refunded. They are an application
admission cap, **not an invoice-wide OpenAI or cloud spending guarantee**. Calls
made elsewhere with the same key, Firestore/Cloud Run/build costs, or future
provider price changes are outside this ledger. Use a dedicated provider project
key, restrict its model permissions, monitor billing, and rotate the old key
once rollback no longer needs it. A new image-generation or try-on model must
have its own audited cost ceiling and must not reuse these reservations.

### Cost bound assumptions (checked October 27, 2026)

Models are pinned: `gpt-4o-2024-08-06` for analysis and
`gpt-4o-mini-2024-07-18` for chat. Output is capped at 2200 and 350 tokens.
Upload text is at most 24,000 UTF-8 bytes; chat text is at most 16,000 bytes.
UTF-8 byte counts conservatively bound text token counts; allow another 512
message-overhead tokens. Uploads are decoded, limited to 20 million pixels and
5 MB request bodies, normalized to one JPEG at no more than 1600 pixels per
side, with high detail. A conservative 16-tile + base allowance is 2805 image
tokens. At $2.50/M input and $10/M output for GPT-4o, that is below $0.10/call;
$0.25 reserves more than twice that bound. GPT-4o mini text rates are $0.15/M
input and $0.60/M output; the bounded chat request is below $0.003, versus a
$0.01 reservation. No tools, generated images, or provider retries are allowed.

Sources: [GPT-4o](https://developers.openai.com/api/docs/models/gpt-4o),
[GPT-4o mini](https://developers.openai.com/api/docs/models/gpt-4o-mini),
[vision token rules](https://developers.openai.com/api/docs/guides/images-vision).
Revalidate availability/prices before activation and after any model/configuration
change. Provider access was not tested with a live paid call. GPT-4o mini is marked
deprecated in the current catalog; migration needs its own compatibility/cost test.

## Caller identity, data, and scope

Current ingredient/chat endpoints have no new login requirement. Rate keys are
SHA-256 hashes of client IPs, not authorization or proof of identity. Native app
users behind one NAT share a bucket. By default forwarding headers are ignored.
`TRUSTED_PROXY_HOPS=1` is allowed only for direct Cloud Run ingress; it uses the
last platform-appended IP, not an untrusted first entry. Additional proxies need
an explicitly verified configuration. Global quotas and spend caps do not depend
on that IP distinction. CORS is an exact web-origin allowlist, not authentication.

The ledger stores counters, hashed IPs, and timestamps, not photos, prompts or
model results. Enable Firestore TTL for `expires_at`; old ledger expiry is
housekeeping, not the quota-reset mechanism. Policy never expires. There is no
paid try-on endpoint: it must additionally have verified user authentication,
entitlements/payment authorization, per-user limits, and its own cost accounting
before implementation or public release.

Production still needs the rollout in ROLLOUT.md. Repository changes alone do not
protect an older live revision.
