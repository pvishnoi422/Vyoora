from firebase_admin import auth
import pytest
from test_access import setup,headers,photo
from test_tryon_flow import flow,inputs,submit
from test_saved_looks import save,generate
from media_security import AccessDenied

CONFIRM={'confirmation':'delete-my-account'}

def test_confirmed_account_delete_cleans_private_objects_and_keeps_budget(flow,setup):
    api,people,service,now,calls=flow;identity,_=setup;a,ref=generate(flow);b=people['bob']
    assert save(api,a).status_code==201
    day='day_'+now[0].strftime('%Y%m%d')
    before=service.guard.controls.document(day).get().to_dict()['reserved_micro_usd']
    assert api.delete('/v2/account',headers=headers(a),json={'confirmation':'delete-my-account','uid':b['uid']}).status_code==400
    assert api.delete('/v2/account',headers=headers(a),json=CONFIRM).status_code==204
    with pytest.raises(auth.UserNotFoundError):auth.get_user(a['uid'],app=identity.app)
    assert auth.get_user(b['uid'],app=identity.app).uid==b['uid']
    assert api.get('/v2/saved-looks',headers=headers(a)).status_code==401
    assert service.guard.controls.document(day).get().to_dict()['reserved_micro_usd']==before
    assert not list(service.guard.jobs.where('ownerId','==',a['uid']).stream())
    assert not list(service.looks.bucket.list_blobs(prefix=f'saved-looks/{a["uid"]}/'))
    if hasattr(service.media,'bucket'):
        for kind in ('wardrobe','reference-photos','try-on'):
            assert not list(service.media.bucket.list_blobs(prefix=f'{kind}/{a["uid"]}/'))
    else:
        assert not [key for key in service.media.photos if key[0]==a['uid']]
        assert not [key for key in service.wardrobe.items if key[0]==a['uid']]

def test_cleanup_failure_blocks_data_and_new_work_until_delete_retry(flow,setup,monkeypatch):
    api,people,service,now,calls=flow;identity,_=setup;a,ref=generate(flow)
    assert save(api,a).status_code==201
    cleanup=service.media.delete_all
    service.media.delete_all=lambda uid:(_ for _ in ()).throw(RuntimeError('storage outage'))
    assert api.delete('/v2/account',headers=headers(a),json=CONFIRM).status_code==503
    assert auth.get_user(a['uid'],app=identity.app).uid==a['uid']
    assert api.get('/v2/wardrobe',headers=headers(a)).status_code==410
    assert api.get('/v2/try-on/jobs',headers=headers(a)).status_code==410
    assert api.get('/v2/saved-looks/job/image',headers=headers(a)).status_code==410
    service.media.delete_all=cleanup
    assert api.delete('/v2/account',headers=headers(a),json=CONFIRM).status_code==204

def test_account_delete_requires_auth_confirmation_and_recent_signin(flow,setup,monkeypatch):
    api,people,service,now,calls=flow;identity,_=setup;a=people['alice']
    assert api.delete('/v2/account',json=CONFIRM).status_code==401
    assert api.delete('/v2/account',headers=headers(people['unverified']),json=CONFIRM).status_code==403
    assert api.delete('/v2/account',headers=headers(a),json={}).status_code==400
    def old(token):raise AccessDenied('recent_signin_required',403)
    monkeypatch.setattr(identity,'require_recent',old)
    assert api.delete('/v2/account',headers=headers(a),json=CONFIRM).status_code==403
    assert auth.get_user(a['uid'],app=identity.app).uid==a['uid']

def test_upload_racing_account_deletion_removes_late_image(flow):
    api,people,service,now,calls=flow;a=people['alice'];original=service.wardrobe.create
    def create(uid,item,data):
        record=original(uid,item,data);service.guard.begin_account_deletion(uid);return record
    service.wardrobe.create=create
    response=api.post('/v2/wardrobe',headers=headers(a),data={'name':'Late upload','category':'top','consent':'granted','image':(photo(),'shirt.png')})
    assert response.status_code==410
    if hasattr(service.wardrobe,'bucket'):
        assert not list(service.wardrobe.bucket.list_blobs(prefix=f'wardrobe/{a["uid"]}/'))
    else:assert not service.wardrobe.items
