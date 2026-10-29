"""Owner-only saved output copies. Original provider bytes are never re-encoded."""
from datetime import datetime, timedelta, timezone
import json
from google.api_core.exceptions import NotFound, PreconditionFailed
from media_security import AccessDenied
from tryon_media import TryOnMedia


class SavedLooks:
    def __init__(self, bucket, clock=None):
        self.bucket = bucket
        self.clock = clock or (lambda: datetime.now(timezone.utc))

    def blob(self, uid, item_id):
        return self.bucket.blob(TryOnMedia.key(uid, 'saved-looks', item_id))

    def record(self, blob, uid):
        metadata = blob.metadata or {}
        record = json.loads(metadata.get('savedLookRecord', '{}'))
        if (metadata.get('ownerId') != uid or record.get('ownerId') != uid or
            blob.name != self.blob(uid, record.get('id', '')).name):
            raise AccessDenied('not_found', 404)
        if self.clock() >= datetime.fromisoformat(record['expiresAt']):
            raise AccessDenied('not_found', 404)
        return record

    def get(self, uid, item_id, *, image=False):
        blob = self.blob(uid, item_id)
        try:
            blob.reload(timeout=30)
            record = self.record(blob, uid)
            if image:
                return record, blob.download_as_bytes(if_generation_match=blob.generation, timeout=30), blob.content_type
            return record
        except NotFound: raise AccessDenied('not_found', 404) from None

    def list(self, uid, page_token=None):
        iterator = self.bucket.list_blobs(prefix=f'saved-looks/{uid}/', page_token=page_token,
            max_results=40, page_size=40, timeout=30)
        page = next(iterator.pages)
        records = []
        for blob in page:
            try: records.append(self.record(blob, uid))
            except AccessDenied: continue
        return records, iterator.next_page_token

    def save(self, uid, job, title, data, mime):
        now = self.clock(); expires = now + timedelta(days=30)
        text = lambda d: d.isoformat().replace('+00:00', 'Z')
        record = dict(schemaVersion=1, id=job['id'], ownerId=uid, title=title,
            items=[dict(ownerId=uid, id=job['garmentId'])],
            referencePhoto=dict(ownerId=uid, id=job['referenceId']),
            preview=dict(ownerId=uid, imageId=job['id'], kind='savedLook', expiresAt=text(expires)),
            state='saved', createdAt=text(now), updatedAt=text(now), expiresAt=text(expires))
        blob = self.blob(uid, job['id'])
        blob.metadata = {'ownerId': uid, 'referenceId': job['referenceId'],
            'savedLookRecord': json.dumps(record, separators=(',', ':')), 'aiGenerated': 'true'}
        blob.cache_control = 'private, no-store, max-age=0'; blob.custom_time = expires
        try: blob.upload_from_string(data, content_type=mime, if_generation_match=0, timeout=30)
        except PreconditionFailed: return self.get(uid, job['id'])
        return record

    def delete(self, uid, item_id):
        blob = self.blob(uid, item_id)
        try:
            blob.reload(timeout=30)
            if (blob.metadata or {}).get('ownerId') != uid: raise AccessDenied('not_found', 404)
            blob.delete(if_generation_match=blob.generation, if_metageneration_match=blob.metageneration, timeout=30)
        except NotFound: pass

    def delete_reference(self, uid, reference_id):
        # No result limit: consent revocation removes every associated look.
        for blob in self.bucket.list_blobs(prefix=f'saved-looks/{uid}/', timeout=30):
            metadata = blob.metadata or {}
            if metadata.get('ownerId') == uid and metadata.get('referenceId') == reference_id:
                blob.delete(if_generation_match=blob.generation, if_metageneration_match=blob.metageneration, timeout=30)

    def delete_all(self, uid):
        for blob in self.bucket.list_blobs(prefix=f'saved-looks/{uid}/', timeout=30):
            blob.delete(if_generation_match=blob.generation, if_metageneration_match=blob.metageneration, timeout=30)
