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
