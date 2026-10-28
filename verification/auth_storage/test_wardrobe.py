"""Acceptance tests against the actual wardrobe routes and Firebase sessions."""
import copy
import io
import os
import subprocess
import uuid

import pytest
from google.api_core.exceptions import ServiceUnavailable
from PIL import Image
from test_access import setup, headers, photo
from access import AccessDenied
from wardrobe import GCSWardrobe, create_wardrobe_app


class MemoryWardrobe:
    def __init__(self): self.items = {}
    def create(self, uid, item, data):
        self.items[(uid, item['id'])] = (copy.deepcopy(item), data)
        return item
    def list(self, uid, page=None):
        return [copy.deepcopy(item) for (owner, _), (item, data) in self.items.items() if owner == uid], None
    def read(self, uid, item_id):
        if (uid, item_id) not in self.items: raise AccessDenied('not_found', 404)
        return self.items[(uid, item_id)][1]
    def delete(self, uid, item_id): self.items.pop((uid, item_id), None)


@pytest.fixture(params=['memory'] + (['gcs'] if os.environ.get('VYOORA_V2_VERIFY_BUCKET') else []))
def wardrobe(setup, request):
    identity, people = setup
    if request.param == 'gcs':
        from google.cloud import storage
        from google.oauth2.credentials import Credentials
        credentials = Credentials(subprocess.check_output(['gcloud', 'auth', 'print-access-token'], text=True).strip())
        store = GCSWardrobe(storage.Client(project='vyoora-backend', credentials=credentials).bucket(os.environ['VYOORA_V2_VERIFY_BUCKET']))
    else:
        store = MemoryWardrobe()
    app = create_wardrobe_app(identity, store, origins=['http://localhost:7357'])
    yield app.test_client(), people, store, identity
    if request.param == 'gcs':
        for person in people.values():
            for blob in store.bucket.list_blobs(prefix=f'wardrobe/{person["uid"]}/'): blob.delete()


def upload(client, person, **fields):
    data = {'image': (photo(), 'garment.png'), 'name': 'Blue shirt', 'category': 'top',
            'color': 'blue', 'consent': 'granted'}
    data.update(fields)
    return client.post('/v2/wardrobe', headers=headers(person), data=data)


def test_real_upload_persists_across_app_restart_and_delete_cleans_storage(wardrobe):
    client, people, store, identity = wardrobe
    alice = people['alice']
    response = upload(client, alice)
    assert response.status_code == 201
    item = response.json['item']; item_id = item['id']
    assert item['ownerId'] == alice['uid'] and item['image']['imageId'] == item_id
    assert 'url' not in item and 'imageUrl' not in item
    # New app + new repository instance read durable data, not process-local records.
    restarted = GCSWardrobe(store.bucket) if isinstance(store, GCSWardrobe) else store
    client = create_wardrobe_app(identity, restarted).test_client()
    assert client.get('/v2/wardrobe', headers=headers(alice)).json['items'] == [item]
    response = client.get(f'/v2/wardrobe/{item_id}/image', headers=headers(alice))
    assert response.status_code == 200 and response.mimetype == 'image/jpeg'
    assert response.headers['Cache-Control'] == 'private, no-store, max-age=0'
    with Image.open(io.BytesIO(response.data)) as image:
        assert image.format == 'JPEG' and 'exif' not in image.info
    if isinstance(store, GCSWardrobe):
        blob = store.bucket.get_blob(f'wardrobe/{alice["uid"]}/{item_id}.jpg')
        assert blob is not None and 'wardrobeRecord' in blob.metadata
    assert client.delete(f'/v2/wardrobe/{item_id}', headers=headers(alice)).status_code == 204
    assert client.get('/v2/wardrobe', headers=headers(alice)).json['items'] == []
    assert client.get(f'/v2/wardrobe/{item_id}/image', headers=headers(alice)).status_code == 404
    assert client.delete(f'/v2/wardrobe/{item_id}', headers=headers(alice)).status_code == 204
    if isinstance(store, GCSWardrobe):
        assert not list(store.bucket.list_blobs(prefix=f'wardrobe/{alice["uid"]}/{item_id}'))
        assert not list(store.bucket.list_blobs(prefix=f'wardrobe/{alice["uid"]}/{item_id}', versions=True))


def test_two_accounts_isolated_lists_images_delete_and_owner_injection(wardrobe):
    client, people, store, identity = wardrobe
    a, b = people['alice'], people['bob']
    aid = upload(client, a).json['item']['id']
    bid = upload(client, b, name='Bobs coat', category='outerwear').json['item']['id']
    assert [i['id'] for i in client.get('/v2/wardrobe', headers=headers(a)).json['items']] == [aid]
    assert [i['id'] for i in client.get('/v2/wardrobe', headers=headers(b)).json['items']] == [bid]
    assert client.get(f'/v2/wardrobe/{aid}/image', headers=headers(b)).status_code == 404
    assert client.delete(f'/v2/wardrobe/{aid}', headers=headers(b)).status_code == 204
    assert client.get(f'/v2/wardrobe/{aid}/image', headers=headers(a)).status_code == 200
    assert upload(client, b, ownerId=a['uid']).status_code == 400
    assert upload(client, b, imageId=aid).status_code == 400
    assert client.get('/v2/wardrobe?ownerId='+a['uid'], headers=headers(b)).json['items'][0]['id'] == bid


def test_auth_consent_type_and_size_validation(wardrobe):
    client, people, store, identity = wardrobe
    for method, path in [('get', '/v2/wardrobe'), ('post', '/v2/wardrobe'),
                         ('delete', '/v2/wardrobe/id'), ('get', '/v2/wardrobe/id/image')]:
        assert getattr(client, method)(path).status_code == 401
        assert getattr(client, method)(path, headers={'Authorization': 'Bearer invalid'}).status_code == 401
    assert upload(client, people['unverified']).status_code == 403
    a = people['alice']
    for fields in [dict(name=''), dict(category='invalid'), dict(consent='no'),
                   dict(image=(io.BytesIO(b'bad'), 'x.jpg')), dict(name='x'*101)]:
        assert upload(client, a, **fields).status_code == 400
    assert upload(client, a, image=(io.BytesIO(b'x'*(5*1024*1024)), 'x.jpg')).status_code == 413
    assert client.get('/v2/wardrobe', headers={**headers(a), 'Origin':'https://evil.invalid'}).status_code == 403
    response = client.options('/v2/wardrobe/a', headers={'Origin':'http://localhost:7357', 'Access-Control-Request-Method':'DELETE'})
    assert response.headers['Access-Control-Allow-Methods'] == 'GET, POST, DELETE, OPTIONS'
    assert client.get('/v2/wardrobe', headers={**headers(a), 'Origin':'http://localhost:7357'}).headers['Access-Control-Allow-Origin'] == 'http://localhost:7357'


def test_storage_failure_is_not_success_and_does_not_remove_item(wardrobe, monkeypatch):
    client, people, store, identity = wardrobe
    a = people['alice']; item_id = upload(client, a).json['item']['id']
    original = store.delete
    def fail(*args): raise ServiceUnavailable('synthetic private diagnostic must not escape')
    monkeypatch.setattr(store, 'delete', fail)
    response = client.delete(f'/v2/wardrobe/{item_id}', headers=headers(a))
    assert response.status_code == 503 and response.json['code'] == 'storage_unavailable'
    assert b'diagnostic' not in response.data
    assert client.get(f'/v2/wardrobe/{item_id}/image', headers=headers(a)).status_code == 200
    monkeypatch.setattr(store, 'delete', original)


def test_gcs_owner_metadata_tampering_denies_read_list_delete(wardrobe):
    client, people, store, identity = wardrobe
    if not isinstance(store, GCSWardrobe): pytest.skip('Requires actual GCS metadata')
    a = people['alice']; item_id = upload(client, a).json['item']['id']
    blob = store.bucket.get_blob(f'wardrobe/{a["uid"]}/{item_id}.jpg')
    data = blob.metadata; data['ownerId'] = people['bob']['uid']; blob.metadata = data; blob.patch()
    assert client.get(f'/v2/wardrobe/{item_id}/image', headers=headers(a)).status_code == 404
    assert client.get('/v2/wardrobe', headers=headers(a)).status_code == 404
    assert client.delete(f'/v2/wardrobe/{item_id}', headers=headers(a)).status_code == 404
    assert store.bucket.get_blob(blob.name) is not None
