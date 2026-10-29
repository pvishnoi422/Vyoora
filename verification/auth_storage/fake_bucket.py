"""Small GCS-contract double; live-bucket runs use the actual SDK instead."""
from copy import deepcopy
from threading import Lock
from types import SimpleNamespace
from google.api_core.exceptions import NotFound, PreconditionFailed

class FakeBucket:
    def __init__(self): self.values = {}; self.lock = Lock(); self.counter = 0
    def blob(self, name): return Blob(self, name)
    def list_blobs(self, *, prefix, max_results=None, page_size=None, page_token=None, **_):
        values = []
        for name in sorted(self.values):
            if name.startswith(prefix):
                blob = self.blob(name); blob.reload(); values.append(blob)
        start = int(page_token or 0); end = start + (max_results or len(values))
        page = values[start:end]
        return Page(page, str(end) if end < len(values) else None)

class Page(list):
    def __init__(self, values, token): super().__init__(values); self.next_page_token = token
    @property
    def pages(self): return iter([iter(self)])

class Blob:
    def __init__(self, bucket, name): self.bucket = bucket; self.name = name; self.metadata = None; self.content_type = None; self.cache_control = None; self.custom_time = None
    def reload(self, **_):
        if self.name not in self.bucket.values: raise NotFound('missing')
        self.__dict__.update(deepcopy(self.bucket.values[self.name][1]))
    def upload_from_string(self, data, content_type, if_generation_match=None, **_):
        with self.bucket.lock:
            if if_generation_match == 0 and self.name in self.bucket.values: raise PreconditionFailed('exists')
            self.bucket.counter += 1; self.generation = self.bucket.counter; self.metageneration = 1; self.content_type = content_type
            state = {k: deepcopy(v) for k,v in vars(self).items() if k not in {'bucket','name'}}
            self.bucket.values[self.name] = (bytes(data), state)
    def download_as_bytes(self, if_generation_match=None, **_):
        self.reload()
        if if_generation_match is not None and self.generation != if_generation_match: raise PreconditionFailed('changed')
        return self.bucket.values[self.name][0]
    def delete(self, if_generation_match=None, if_metageneration_match=None, **_):
        with self.bucket.lock:
            self.reload()
            if if_generation_match is not None and self.generation != if_generation_match: raise PreconditionFailed('changed')
            del self.bucket.values[self.name]
