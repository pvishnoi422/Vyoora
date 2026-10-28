# Production rollout: approval required before activation

The fork/branch and tests are reviewable changes. The live service remains on its
previous revision until this rollout is explicitly approved. The selected
reservation policy is $5/day and $50/month, initially disabled. No try-on endpoint
is created by these steps. Firestore, Secret Manager, build and Cloud Run usage
can incur cloud charges separate from the AI reservation cap.

## Prerequisites and prepare

Use the reviewed commit, not an uncommitted local tree. Confirm current provider
access to the pinned model snapshots and revalidate their cost ceilings. Models
are inherited from the application and marked deprecated in the official catalog;
do not enable service if the selected snapshots are unavailable. Real AI analysis
quality and signed native device builds still require acceptance testing.

Record the current service description, ready revision, traffic and image digest
privately before changing anything. Do not place a full service description in
Git: it may contain the old plaintext API key.

After approval, using the existing authenticated cloud CLI:

```sh
gcloud services enable firestore.googleapis.com secretmanager.googleapis.com \
  cloudbuild.googleapis.com artifactregistry.googleapis.com run.googleapis.com \
  --project=vyoora-backend
# Create only if a suitable default database does not already exist.
gcloud firestore databases create --database='(default)' --location=us-central1 \
  --type=firestore-native --project=vyoora-backend
# Create only if absent.
gcloud iam service-accounts create vyoora-runtime --project=vyoora-backend

gcloud projects add-iam-policy-binding vyoora-backend \
  --member=serviceAccount:vyoora-runtime@vyoora-backend.iam.gserviceaccount.com \
  --role=roles/datastore.user
```

Configure the Firestore database's client access rules to deny client SDK access;
only the backend service account should write guard state through IAM. Do not
put the AI ledger in a client-writable Firebase database. Enable TTL on the
`vyoora_ai_guard` collection group's `expires_at` field. This deletes obsolete
counter/hashed-IP records; it does not reset active spend ledgers.

```sh
gcloud firestore fields ttls update expires_at --collection-group=vyoora_ai_guard \
  --enable-ttl --database='(default)' --project=vyoora-backend

python ops/migrate_openai_secret.py --project=vyoora-backend --apply
# Record the numeric secret version printed above; do not use 'latest'.
gcloud secrets add-iam-policy-binding vyoora-openai-api-key \
  --member=serviceAccount:vyoora-runtime@vyoora-backend.iam.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor --project=vyoora-backend

# Seed the disabled policy. This never deletes or resets existing spend counters.
python ops/set_ai_policy.py --project=vyoora-backend --use-gcloud --apply
```

The secret migration reads the existing service key in memory and passes it to
Secret Manager over stdin. It does not print it or write it into a file. If the
key has already been migrated, use its existing pinned version rather than
creating a duplicate. Rotate the provider key after the successful transition;
rotation requires access to the provider account and is not automated here.

## Build and stage without production traffic

Build from the repository's `backend/` context with a tag equal to the reviewed
Git commit, then resolve the built digest. Fill in the two explicit reviewed
values below; these are identifiers, never secret contents.

```sh
task_commit=$(git rev-parse HEAD)
gcloud builds submit backend --project=vyoora-backend --region=us-central1 \
  --tag="us-central1-docker.pkg.dev/vyoora-backend/cloud-run-source-deploy/vyoora-backend:$task_commit"
# Resolve that tag and use the returned sha256 digest as REVIEWED_DIGEST.
# Use the numeric secret version from migration as REVIEWED_SECRET_VERSION.
gcloud run deploy vyoora-backend --project=vyoora-backend --region=us-central1 \
  --image=us-central1-docker.pkg.dev/vyoora-backend/cloud-run-source-deploy/vyoora-backend@REVIEWED_DIGEST \
  --service-account=vyoora-runtime@vyoora-backend.iam.gserviceaccount.com \
  --remove-env-vars=OPENAI_API_KEY \
  --update-env-vars='AI_ENABLED=false,OPENAI_API_KEY_FILE=/secrets/openai/api-key,TRUSTED_PROXY_HOPS=1,FIRESTORE_DATABASE=(default)' \
  --update-secrets=/secrets/openai/api-key=vyoora-openai-api-key:REVIEWED_SECRET_VERSION \
  --cpu=1 --memory=2Gi --concurrency=20 --max-instances=5 --timeout=90 \
  --no-traffic --tag=guarded-staging
```

Leave CORS unset for native clients; configure exact origins only if the web
application is hosted. Verify root and health on the tagged staging URL. A valid
image upload must return an explicit unavailable response while AI is disabled;
it must not return a successful score. Confirm the revision is non-root, uses
the dedicated identity and pinned secret file, and has no OPENAI_API_KEY variable.

## Activation and rollback

After the staged checks pass and production activation is approved, enable the
shared policy with the selected caps; then create a guarded revision with
`AI_ENABLED=true` while preserving its secret, image digest and no-traffic state.
Do a controlled real analysis with explicit acceptance of its reserved AI cost.
Verify contract fields, actual provider usage versus the reservation, unreadable
label behavior, quota responses, and legacy-client error handling. Do not route
traffic if those checks fail.

```sh
python ops/set_ai_policy.py --project=vyoora-backend --use-gcloud --enable --apply
# Set AI_ENABLED=true on a no-traffic revision, record that specific revision,
# validate it, then explicitly move all traffic to it. Clear obsolete tagged
# revisions so an unguarded revision cannot remain publicly invokable by tag.
# gcloud run services update-traffic ... --to-revisions=REVIEWED_REVISION=100 --clear-tags
```

Deploy the Flutter client update separately through the intended distribution
channels. Legacy clients cannot show the new unavailable screen, but the updated
backend's non-200 error responses prevent failed analyses from reaching their
normal results flow. Until a guarded backend is deployed, those live failure
semantics remain unchanged.

For an emergency pause, write the disabled shared policy using set_ai_policy.py
without `--enable`, and set `AI_ENABLED=false` on the guarded service. Shared
policy changes stop subsequent reservations across instances; requests already
reserved may finish and retain their reservation. Do not roll back to an old
unguarded public revision as a spending-control rollback. Preserve the daily and
monthly ledger through every deploy, pause, rollback or secret rotation.
