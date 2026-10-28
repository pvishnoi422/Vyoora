"""Private reference photos and unmodified provider previews; no public URLs."""
from datetime import datetime, timezone, timedelta
import json
import uuid
from google.api_core.exceptions import NotFound
from media_security import AccessDenied
from wardrobe import normalize_image

CONSENT_VERSION = 'google-tryon-v1'


class TryOnMedia:
    def __init__(self, bucket, clock=None):
        self.bucket = bucket
        self.clock = clock or (lambda: datetime.now(timezone.utc))

    @staticmethod
    def key(uid, kind, item_id):
        import re
        if not all(re.fullmatch(r'[A-Za-z0-9_-]{1,128}', v) for v in (uid, item_id)):
            raise AccessDenied('not_found', 404)
        return f'{kind}/{uid}/{item_id}'

    def upload_reference(self, uid, stream):
        data = normalize_image(stream)
        now = self.clock(); item_id = uuid.uuid4().hex; expires = now + timedelta(days=7)
        text = lambda d: d.isoformat().replace('+00:00', 'Z')
        record = dict(schemaVersion=1, id=item_id, ownerId=uid, createdAt=text(now), consentedAt=text(now),
                      expiresAt=text(expires), consentVersion=CONSENT_VERSION,
                      image=dict(ownerId=uid, imageId=item_id, kind='referencePhoto', expiresAt=text(expires)))
        blob = self.bucket.blob(self.key(uid, 'reference-photos', item_id)+'.jpg')
        blob.metadata = {'ownerId': uid, 'referenceRecord': json.dumps(record)}
        blob.cache_control = 'private, no-store, max-age=0'; blob.custom_time = expires
        blob.upload_from_string(data, content_type='image/jpeg', if_generation_match=0, timeout=30)
        return record

    def reference(self, uid, item_id, *, data=False):
        blob = self.bucket.blob(self.key(uid, 'reference-photos', item_id)+'.jpg')
        try:
            blob.reload(timeout=30)
            metadata = blob.metadata or {}
            if metadata.get('ownerId') != uid: raise AccessDenied('not_found', 404)
            record = json.loads(metadata['referenceRecord'])
            if record.get('ownerId') != uid or record.get('id') != item_id: raise AccessDenied('not_found', 404)
            if self.clock() >= datetime.fromisoformat(record['expiresAt']): raise AccessDenied('reference_expired', 410)
            return (record, blob.download_as_bytes(if_generation_match=blob.generation, timeout=30)) if data else record
        except NotFound: raise AccessDenied('not_found', 404) from None

    def references(self, uid):
        records = []
        for blob in self.bucket.list_blobs(prefix=f'reference-photos/{uid}/', max_results=100, timeout=30):
            metadata = blob.metadata or {}
            if metadata.get('ownerId') != uid or 'referenceRecord' not in metadata: continue
            record = json.loads(metadata['referenceRecord'])
            if (record.get('ownerId') == uid and blob.name == self.key(uid, 'reference-photos', record['id'])+'.jpg'
                and self.clock() < datetime.fromisoformat(record['expiresAt'])):
                records.append(record)
        return sorted(records, key=lambda r: r['createdAt'], reverse=True)

    def delete_reference(self, uid, item_id):
        self._delete(self.key(uid, 'reference-photos', item_id)+'.jpg')

    def put_preview(self, uid, job_id, reference_id, data, mime, expires):
        # Preserve provider bytes (including Content Credentials/watermarks).
        blob = self.bucket.blob(self.key(uid, 'try-on', job_id))
        blob.metadata = {'ownerId': uid, 'referenceId': reference_id, 'aiGenerated': 'true', 'expiresAt': expires}
        blob.cache_control = 'private, no-store, max-age=0'
        blob.custom_time = datetime.fromisoformat(expires)
        blob.upload_from_string(data, content_type=mime, if_generation_match=0, timeout=30)

    def preview(self, uid, job_id):
        blob = self.bucket.blob(self.key(uid, 'try-on', job_id))
        try:
            blob.reload(timeout=30)
            metadata = blob.metadata or {}
            if metadata.get('ownerId') != uid or self.clock() >= datetime.fromisoformat(metadata['expiresAt']):
                raise AccessDenied('not_found', 404)
            return blob.download_as_bytes(if_generation_match=blob.generation, timeout=30), blob.content_type
        except NotFound: raise AccessDenied('not_found', 404) from None

    def delete_preview(self, uid, job_id):
        self._delete(self.key(uid, 'try-on', job_id))

    def _delete(self, key):
        try:
            blob = self.bucket.blob(key); blob.reload(timeout=30)
            blob.delete(if_generation_match=blob.generation, if_metageneration_match=blob.metageneration, timeout=30)
        except NotFound: pass
