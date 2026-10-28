import base64
import io
import json
from types import SimpleNamespace
import pytest
from PIL import Image
from provider import virtual_tryon, TRYON_MODEL
from safety import ServiceError


def png():
    stream=io.BytesIO(); Image.new('RGB',(64,96),'blue').save(stream,format='PNG'); return stream.getvalue()


class Credentials:
    def before_request(self, request, method, url, headers): headers['Authorization']='Bearer synthetic'


class Response:
    def __init__(self, body, status=200): self.body=json.dumps(body).encode();self.status_code=status;self.closed=False
    def iter_content(self, size): yield self.body
    def close(self): self.closed=True


class Transport:
    def __init__(self, response, events): self.response=response;self.events=events;self.calls=[]
    def post(self, url, **kwargs):
        self.events.append('provider');self.calls.append((url,kwargs));return self.response


def invoke(monkeypatch, body, *, reject=False, status=200):
    monkeypatch.setenv('TRYON_ENABLED','true'); monkeypatch.delenv('FIRESTORE_EMULATOR_HOST',raising=False)
    events=[];response=Response(body,status);transport=Transport(response,events)
    def start(key):
        events.append('reserve-checked')
        if reject: raise ServiceError('tryon_budget_exhausted','Paused',429)
    guard=SimpleNamespace(start_attempt=start)
    call=lambda:virtual_tryon(png(),png(),credentials=Credentials(),guard=guard,job_key='synthetic',
                             project='test-project',session=transport)
    return call,transport,events,response


def test_pinned_single_output_one_attempt_and_boundaries(monkeypatch):
    data=png();call,transport,events,response=invoke(monkeypatch,{'predictions':[{'mimeType':'image/png','bytesBase64Encoded':base64.b64encode(data).decode()}]})
    assert call()==(data,'image/png')
    assert events==['reserve-checked','provider'] and len(transport.calls)==1 and response.closed
    url,kwargs=transport.calls[0]
    assert url.endswith('/models/'+TRYON_MODEL+':predict')
    assert kwargs['allow_redirects'] is False and kwargs['timeout']==(10,120)
    assert kwargs['json']['parameters']=={'sampleCount':1,'personGeneration':'allow-adult',
        'safetySetting':'block-medium-and-above','addWatermark':True,'outputOptions':{'mimeType':'image/png'}}
    assert len(kwargs['json']['instances'])==1 and len(kwargs['json']['instances'][0]['productImages'])==1


def test_nested_current_response_schema(monkeypatch):
    data=png();call,*_=invoke(monkeypatch,{'predictions':[{'images':[{'mimeType':'image/png','bytesBase64Encoded':base64.b64encode(data).decode()}]}]})
    assert call()==(data,'image/png')


def test_no_paid_call_after_control_rejection(monkeypatch):
    call,transport,events,_=invoke(monkeypatch,{},reject=True)
    with pytest.raises(ServiceError):call()
    assert transport.calls==[] and events==['reserve-checked']


@pytest.mark.parametrize('body',[{'predictions':[]},{'predictions':[{},{}]},
    {'predictions':[{'mimeType':'image/png','gcsUri':'https://private.invalid/secret'}]},
    {'predictions':[{'mimeType':'image/png','bytesBase64Encoded':'not an image'}]},
    {'predictions':[{'raiFilteredReason':'sensitive provider text'}]}])
def test_invalid_blocked_or_url_outputs_never_become_success(monkeypatch,body):
    call,transport,events,response=invoke(monkeypatch,body)
    with pytest.raises(ServiceError) as error:call()
    assert len(transport.calls)==1 and response.closed
    assert 'sensitive' not in str(error.value)


def test_upstream_errors_are_sanitized_without_retry(monkeypatch):
    call,transport,events,response=invoke(monkeypatch,{'error':'SECRET_API_RESPONSE'},status=403)
    with pytest.raises(ServiceError) as error:call()
    assert error.value.code=='provider_access_denied' and 'SECRET' not in str(error.value)
    assert len(transport.calls)==1


def test_truncated_image_is_not_a_successful_preview(monkeypatch):
    stream=io.BytesIO();Image.new('RGB',(64,96),'blue').save(stream,format='JPEG')
    call,transport,events,response=invoke(monkeypatch,{'predictions':[{'mimeType':'image/jpeg',
        'bytesBase64Encoded':base64.b64encode(stream.getvalue()[:-32]).decode()}]})
    with pytest.raises(ServiceError):call()
    assert len(transport.calls)==1


def test_emulator_budgets_can_never_authorize_real_paid_generation(monkeypatch):
    monkeypatch.setenv('TRYON_ENABLED','true');monkeypatch.setenv('FIRESTORE_EMULATOR_HOST','127.0.0.1:8085')
    with pytest.raises(ServiceError) as error:
        virtual_tryon(png(),png(),credentials=None,guard=None,job_key='x',project='test-project')
    assert error.value.code=='tryon_disabled'
