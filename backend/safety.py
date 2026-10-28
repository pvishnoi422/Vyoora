"""Shared, fail-closed admission control. No paid call precedes a reservation."""
from datetime import datetime, timezone, timedelta
import hashlib
import math
import os


class ServiceError(Exception):
    def __init__(self, code, message, http_status=503, retry_after=None):
        super().__init__(message)
        self.code, self.message, self.http_status = code, message, http_status
        self.retry_after = retry_after


# Conservative reservations, not usage estimates or a provider billing meter.
# See docs/SECURITY.md for the bounded request/pricing assumptions.
RESERVATIONS = {"upload": 250_000, "chat": 10_000}  # USD millionths
RATES = {"upload": (3, 60), "chat": (20, 60)}


def consume_bucket(state, capacity, period, now):
    """Token bucket: no fixed-window boundary burst and no worker-local state."""
    last = float(state.get("updated", now))
    available = min(capacity, float(state.get("tokens", capacity)) + max(0, now-last)*capacity/period)
    if available < 1:
        raise ServiceError("rate_limited", "Too many requests. Please try again shortly.", 429,
                           max(1, math.ceil((1-available)*period/capacity)))
    return {"tokens": available-1, "updated": max(now, last)}


def reservation_updates(documents, endpoint, now):
    """Pure policy evaluation used inside one database transaction."""
    policy = documents["policy"]
    if policy.get("enabled") is not True:
        raise ServiceError("ai_disabled", "Analysis is temporarily unavailable.")
    daily, monthly = policy.get("daily_budget_micro_usd"), policy.get("monthly_budget_micro_usd")
    if type(daily) is not int or type(monthly) is not int or daily <= 0 or monthly <= 0:
        raise ServiceError("controls_unavailable", "Analysis is temporarily unavailable.")
    cost = RESERVATIONS[endpoint]
    for period, cap in [("day", daily), ("month", monthly)]:
        if documents[period].get("reserved_micro_usd", 0) + cost > cap:
            raise ServiceError("budget_exhausted", "Analysis is paused because its usage limit was reached.", 429, 3600)
    capacity, interval = RATES[endpoint]
    updates = {"actor": consume_bucket(documents["actor"], capacity, interval, now),
               "global": consume_bucket(documents["global"], 60, 60, now)}
    for period in ["day", "month"]:
        old = documents[period]
        updates[period] = {"reserved_micro_usd": old.get("reserved_micro_usd", 0)+cost,
                           "requests": old.get("requests", 0)+1}
    return updates


class FirestoreGuard:
    def __init__(self, client=None, clock=None):
        self._client = client
        self.clock = clock or (lambda: datetime.now(timezone.utc))

    def reserve(self, actor, endpoint):
        if os.environ.get("AI_ENABLED", "false").lower() != "true":
            raise ServiceError("ai_disabled", "Analysis is temporarily unavailable.")
        try:
            from google.cloud import firestore
            if self._client is None:
                self._client = firestore.Client(database=os.environ.get("FIRESTORE_DATABASE", "(default)"))
            collection = self._client.collection("vyoora_ai_guard")
            now = self.clock()
            actor_hash = hashlib.sha256(actor.encode()).hexdigest()
            refs = {
                "policy": collection.document("policy"),
                "actor": collection.document(f"actor_{endpoint}_{actor_hash}"),
                "global": collection.document("global"),
                "day": collection.document("day_"+now.strftime("%Y%m%d")),
                "month": collection.document("month_"+now.strftime("%Y%m")),
            }

            @firestore.transactional
            def admit(transaction):
                documents = {k: ref.get(transaction=transaction).to_dict() or {} for k, ref in refs.items()}
                updates = reservation_updates(documents, endpoint, now.timestamp())
                for key, data in updates.items():
                    # TTL is housekeeping, never the mechanism that resets counters.
                    expiry = now+timedelta(days=2 if key in {"actor", "global"} else 65)
                    transaction.set(refs[key], {**data, "expires_at": expiry})
            admit(self._client.transaction(max_attempts=5))
        except ServiceError:
            raise
        except Exception:
            # Database timeouts, permission errors, absent policy, and contention
            # all stop provider requests. Never silently use an in-memory limiter.
            raise ServiceError("controls_unavailable", "Analysis is temporarily unavailable.") from None


# The pinned Google virtual-try-on-001 price is $0.06/output; reserve $0.10
# for one output, no retries. This ledger NEVER uses the skincare AI counters.
# https://cloud.google.com/vertex-ai/generative-ai/pricing
TRYON_RESERVATION = 100_000
TRYON_DAY_CAP = 1_000_000
TRYON_MONTH_CAP = 5_000_000
TRYON_PER_USER_DAY = 3
TRYON_CONTROL_COLLECTION = 'vyoora_tryon_v2'
TRYON_JOB_COLLECTION = 'vyoora_tryon_jobs_v2'


def tryon_updates(documents, now):
    policy = documents['policy']
    if policy.get('enabled') is not True:
        raise ServiceError('tryon_disabled', 'Try-on testing is currently paused.', 503)
    if documents['member'].get('enabled') is not True:
        raise ServiceError('tryon_not_entitled', 'Try-on is only available to approved test accounts.', 403)
    day, month, per_user = (policy.get(k) for k in ('daily_budget_micro_usd', 'monthly_budget_micro_usd', 'per_user_day'))
    if (type(day) is not int or not 0 < day <= TRYON_DAY_CAP or
        type(month) is not int or not 0 < month <= TRYON_MONTH_CAP or
        type(per_user) is not int or not 0 < per_user <= TRYON_PER_USER_DAY):
        raise ServiceError('controls_unavailable', 'Try-on controls are unavailable.')
    for period, cap in [('day', day), ('month', month)]:
        reserved = documents[period].get('reserved_micro_usd', 0)
        if type(reserved) is not int or reserved < 0:
            raise ServiceError('controls_unavailable', 'Try-on controls are unavailable.')
        if reserved + TRYON_RESERVATION > cap:
            raise ServiceError('tryon_budget_exhausted', 'The separate try-on testing budget has been reached.', 429)
    used = documents['user_day'].get('requests', 0)
    if type(used) is not int or used < 0:
        raise ServiceError('controls_unavailable', 'Try-on controls are unavailable.')
    if used >= per_user:
        raise ServiceError('tryon_quota_exhausted', 'Your daily try-on limit has been reached.', 429)
    if documents['actor'].get('activeJobId'):
        raise ServiceError('generation_in_progress', 'You already have a generation in progress.', 409)
    updates = {'user_day': {'requests': used+1},
               'global': consume_bucket(documents['global'], 6, 60, now.timestamp())}
    for period in ('day', 'month'):
        old = documents[period]
        updates[period] = {'reserved_micro_usd': old.get('reserved_micro_usd', 0)+TRYON_RESERVATION,
                           'requests': old.get('requests', 0)+1}
    return updates


class TryOnGuard:
    """Atomic admission, durable jobs, entitlement, and at-most-one paid attempt.

    No automatic provider retry or refund after cancellation, failure or timeout.
    Expired/running jobs are failed conservatively instead of re-dispatched.
    """
    def __init__(self, client, clock=None):
        self.client = client
        self.controls = client.collection(TRYON_CONTROL_COLLECTION)
        self.jobs = client.collection(TRYON_JOB_COLLECTION)
        self.clock = clock or (lambda: datetime.now(timezone.utc))

    @staticmethod
    def actor(uid):
        return hashlib.sha256(uid.encode()).hexdigest()

    def reference_ref(self, uid, ref_id):
        return self.controls.document('ref_'+self.actor(uid)+'_'+ref_id)

    def grant_reference(self, uid, record):
        self.reference_ref(uid, record['id']).create({'active': True, 'ownerId': uid,
            'expiresAt': record['expiresAt'], 'consentVersion': record['consentVersion'],
            'expires_at': datetime.fromisoformat(record['expiresAt'])})

    def check_reference(self, uid, ref_id, transaction=None):
        ref = self.reference_ref(uid, ref_id)
        data = ref.get(transaction=transaction).to_dict() or {}
        if (data.get('ownerId') != uid or data.get('active') is not True or
            data.get('consentVersion') != 'google-tryon-v1' or
            self.clock() >= datetime.fromisoformat(data.get('expiresAt', '1970-01-01T00:00:00Z'))):
            raise ServiceError('reference_expired', 'Upload a new reference photo and confirm consent.', 410)
        return data

    def revoke_reference(self, uid, ref_id):
        self.reference_ref(uid, ref_id).set({'active': False, 'ownerId': uid}, merge=True)

    def job_ref(self, uid, job_id):
        import re
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', job_id):
            raise ServiceError('not_found', 'Generation not found.', 404)
        return self.jobs.document(self.actor(uid)+'_'+job_id)

    def get(self, uid, job_id):
        data = self.job_ref(uid, job_id).get().to_dict() or {}
        if data.get('ownerId') != uid:
            raise ServiceError('not_found', 'Generation not found.', 404)
        return data

    def list(self, uid):
        from google.cloud.firestore_v1.base_query import FieldFilter
        rows = [s.to_dict() for s in self.jobs.where(filter=FieldFilter('ownerId', '==', uid)).limit(100).stream()]
        return sorted(rows, key=lambda j: j['createdAt'], reverse=True)[:25]

    def for_reference(self, uid, reference_id):
        from google.cloud.firestore_v1.base_query import FieldFilter
        return [s.to_dict() for s in self.jobs.where(filter=FieldFilter('referenceId', '==', reference_id)).stream()
                if s.to_dict().get('ownerId') == uid]

    def admit(self, uid, job_id, garment_id, reference_id):
        from google.cloud import firestore
        now = self.clock(); actor = self.actor(uid); ref = self.job_ref(uid, job_id)
        refs = {'policy': self.controls.document('policy'), 'member': self.controls.document('member_'+actor),
                'actor': self.controls.document('actor_'+actor), 'global': self.controls.document('global'),
                'day': self.controls.document('day_'+now.strftime('%Y%m%d')),
                'month': self.controls.document('month_'+now.strftime('%Y%m')),
                'user_day': self.controls.document('user_'+actor+'_'+now.strftime('%Y%m%d'))}

        @firestore.transactional
        def reserve(transaction):
            old = ref.get(transaction=transaction).to_dict()
            if old:
                if old.get('ownerId') != uid or old.get('garmentId') != garment_id or old.get('referenceId') != reference_id:
                    raise ServiceError('idempotency_conflict', 'This request ID already belongs to another selection.', 409)
                return old
            consent = self.check_reference(uid, reference_id, transaction)
            documents = {k: r.get(transaction=transaction).to_dict() or {} for k, r in refs.items()}
            updates = tryon_updates(documents, now)
            text = now.isoformat().replace('+00:00', 'Z')
            job = dict(id=job_id, ownerId=uid, garmentId=garment_id, referenceId=reference_id,
                       status='queued', createdAt=text, consentedAt=text, consentVersion='google-tryon-v1',
                       reservedDay=now.strftime('%Y%m%d'), reservedMicroUsd=TRYON_RESERVATION,
                       expiresAt=consent['expiresAt'], attempted=False, kind='tryon',
                       expires_at=datetime.fromisoformat(consent['expiresAt']))
            for key, data in updates.items():
                transaction.set(refs[key], {**data, 'expires_at': now+timedelta(days=65)})
            transaction.set(refs['actor'], {'activeJobId': job_id, 'expires_at': now+timedelta(days=8)})
            transaction.create(ref, job)
            return job
        try:
            return reserve(self.client.transaction(max_attempts=8))
        except ServiceError:
            raise
        except Exception:
            # A competing identical submission may already have committed, or
            # the commit acknowledgement may have been lost. Read that durable
            # job rather than reserving again or reporting a false failure.
            try:
                existing = ref.get().to_dict() or {}
            except Exception:
                existing = {}
            if (existing.get('ownerId') == uid and existing.get('garmentId') == garment_id
                and existing.get('referenceId') == reference_id):
                return existing
            raise ServiceError('controls_unavailable', 'Try-on controls are unavailable.') from None

    def claim(self, key):
        from google.cloud import firestore
        ref = self.jobs.document(key); now = self.clock()
        @firestore.transactional
        def claim_one(transaction):
            job = ref.get(transaction=transaction).to_dict() or {}
            if job.get('status') != 'queued': return None
            transaction.update(ref, {'status': 'running', 'startedAt': now.isoformat().replace('+00:00', 'Z')})
            return {**job, 'status': 'running'}
        return claim_one(self.client.transaction(max_attempts=8))

    def start_attempt(self, key):
        from google.cloud import firestore
        ref = self.jobs.document(key); now = self.clock()
        @firestore.transactional
        def start(transaction):
            job = ref.get(transaction=transaction).to_dict() or {}
            if job.get('status') != 'running' or job.get('attempted') is not False:
                raise ServiceError('generation_cancelled', 'This generation is no longer active.', 409)
            if (job.get('reservedDay') != now.strftime('%Y%m%d') or
                now-datetime.fromisoformat(job['createdAt']) > timedelta(minutes=5)):
                raise ServiceError('generation_expired', 'The queued request expired. Start a new generation.', 410)
            self.check_reference(job['ownerId'], job['referenceId'], transaction)
            policy = self.controls.document('policy').get(transaction=transaction).to_dict() or {}
            member = self.controls.document('member_'+self.actor(job['ownerId'])).get(transaction=transaction).to_dict() or {}
            if policy.get('enabled') is not True or member.get('enabled') is not True:
                raise ServiceError('tryon_disabled', 'Try-on testing is paused.')
            if job.get('reservedMicroUsd') != TRYON_RESERVATION:
                raise ServiceError('controls_unavailable', 'Try-on controls are unavailable.')
            transaction.update(ref, {'attempted': True, 'attemptedAt': now.isoformat().replace('+00:00', 'Z')})
        start(self.client.transaction(max_attempts=8))

    def finish(self, uid, job_id, status, error=None):
        from google.cloud import firestore
        ref = self.job_ref(uid, job_id); actor_ref = self.controls.document('actor_'+self.actor(uid))
        @firestore.transactional
        def finish_one(transaction):
            job = ref.get(transaction=transaction).to_dict() or {}
            actor = actor_ref.get(transaction=transaction).to_dict() or {}
            if job.get('ownerId') != uid: raise ServiceError('not_found', 'Generation not found.', 404)
            if job.get('status') == 'cancelled' and status != 'cancelled': return False
            if status != 'cancelled' and job.get('status') not in {'queued', 'running'}: return False
            if status == 'succeeded':
                if job.get('status') != 'running': return False
                self.check_reference(uid, job['referenceId'], transaction)
            transaction.update(ref, {'status': status, 'errorCode': error,
                'completedAt': self.clock().isoformat().replace('+00:00', 'Z')})
            if actor.get('activeJobId') == job_id:
                transaction.update(actor_ref, {'activeJobId': None})
            return True
        return finish_one(self.client.transaction(max_attempts=8))

    def cancel(self, uid, job_id):
        # Completed previews may also be deleted by cancellation/revocation.
        return self.finish(uid, job_id, 'cancelled')

    def pending(self):
        from google.cloud.firestore_v1.base_query import FieldFilter
        return list(self.jobs.where(filter=FieldFilter('status', '==', 'queued')).limit(10).stream())

    def recover_stale(self):
        from google.cloud.firestore_v1.base_query import FieldFilter
        for snapshot in self.jobs.where(filter=FieldFilter('status', '==', 'running')).limit(30).stream():
            job = snapshot.to_dict()
            if self.clock()-datetime.fromisoformat(job['startedAt']) > timedelta(minutes=4):
                self.finish(job['ownerId'], job['id'], 'failed', 'generation_interrupted')

    def availability(self, uid):
        now = self.clock(); actor = self.actor(uid)
        policy = self.controls.document('policy').get().to_dict() or {}
        member = self.controls.document('member_'+actor).get().to_dict() or {}
        count = self.controls.document('user_'+actor+'_'+now.strftime('%Y%m%d')).get().to_dict() or {}
        return {'enabled': policy.get('enabled') is True and member.get('enabled') is True,
                'remainingToday': max(0, min(TRYON_PER_USER_DAY, policy.get('per_user_day', 0))-count.get('requests', 0)),
                'dailyLimit': min(TRYON_PER_USER_DAY, policy.get('per_user_day', 0))}
