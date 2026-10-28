import base64
import io
import json
import math
from types import SimpleNamespace
import pytest
from PIL import Image
from provider import virtual_tryon, TRYON_MODEL, TRYON_OUTPUT_TOKENS, TRYON_PROMPT_BYTE_LIMIT, GARMENT_PRESERVATION_PROMPT
from safety import ServiceError, TRYON_RESERVATION


def png():
    stream=io.BytesIO();Image.new('RGB',(64,96),'blue').save(stream,format='PNG');return stream.getvalue()


def image_result(data=None,mime='image/png',finish='STOP'):
    return {'candidates':[{'finishReason':finish,'content':{'parts':[{'inlineData':{'mimeType':mime,'data':base64.b64encode(data or png()).decode()}}]}}]}


class Credentials:
    def before_request(self, request, method, url, headers):headers['Authorization']='Bearer synthetic'

class Response:
    def __init__(self,body,status=200):self.body=json.dumps(body).encode();self.status_code=status;self.closed=False
    def iter_content(self,size):yield self.body
    def close(self):self.closed=True

class Transport:
    def __init__(self,response,events):self.response=response;self.events=events;self.calls=[]
    def post(self,url,**kwargs):self.events.append('provider');self.calls.append((url,kwargs));return self.response


def invoke(monkeypatch,body,*,reject=False,status=200):
    monkeypatch.setenv('TRYON_ENABLED','true');monkeypatch.delenv('FIRESTORE_EMULATOR_HOST',raising=False)
    events=[];response=Response(body,status);transport=Transport(response,events)
    def start(key):
        events.append('reserve-checked')
        if reject:raise ServiceError('tryon_budget_exhausted','Paused',429)
    call=lambda:virtual_tryon(png(),png(),credentials=Credentials(),guard=SimpleNamespace(start_attempt=start),
        job_key='synthetic',project='test-project',session=transport)
    return call,transport,events,response


def test_preservation_prompt_full_inputs_and_boundaries(monkeypatch):
    data=png();call,transport,events,response=invoke(monkeypatch,image_result(data));assert call()==(data,'image/png')
    assert events==['reserve-checked','provider'] and len(transport.calls)==1 and response.closed
    url,kwargs=transport.calls[0]
    assert url.startswith('https://aiplatform.us.rep.googleapis.com/v1/')
    assert url.endswith('/models/'+TRYON_MODEL+':generateContent') and '/locations/us/' in url
    assert kwargs['allow_redirects'] is False and kwargs['timeout']==(10,120)
    body=kwargs['json'];config=body['generationConfig']
    assert config=={'candidateCount':1,'maxOutputTokens':2048,'responseModalities':['IMAGE'],
        'thinkingConfig':{'thinkingLevel':'MINIMAL','includeThoughts':False},'imageConfig':{'imageSize':'1K','aspectRatio':'2:3'}}
    assert 'tools' not in body
    parts=body['contents'][0]['parts'];assert parts[0]['text']==GARMENT_PRESERVATION_PROMPT
    assert 'Do not shorten, crop' in parts[0]['text'] and 'do not inherit a cropped hem' in parts[0]['text']
    images=[p['inlineData'] for p in parts if 'inlineData' in p]
    assert len(images)==2 and all(base64.b64decode(p['data'])==data for p in images)
    assert sum(len(p.get('text','').encode()) for p in parts)<=TRYON_PROMPT_BYTE_LIMIT
    assert all(s['threshold']=='BLOCK_MEDIUM_AND_ABOVE' for s in body['safetySettings'])


def test_reviewed_worst_case_token_cost_fits_reservation():
    # $0.55/M input, $66/M output in US. Treat all output as expensive image tokens.
    ceiling=math.ceil((2*1120+TRYON_PROMPT_BYTE_LIMIT)*.55+TRYON_OUTPUT_TOKENS*66)
    assert ceiling==137527 and ceiling<TRYON_RESERVATION==150000


def test_no_paid_call_after_control_rejection(monkeypatch):
    call,transport,events,_=invoke(monkeypatch,{},reject=True)
    with pytest.raises(ServiceError):call()
    assert transport.calls==[] and events==['reserve-checked']


@pytest.mark.parametrize('body',[{}, {'candidates':[]}, {'candidates':[{},{}]}, image_result(finish='MAX_TOKENS'),
    {'promptFeedback':{'blockReason':'SAFETY'}},
    {'candidates':[{'finishReason':'STOP','content':{'parts':[{'text':'No image'}]}}]},
    {'candidates':[{'finishReason':'STOP','content':{'parts':[{'inlineData':{'mimeType':'image/png','data':'bad'}}]}}]},
    {'candidates':[{'finishReason':'STOP','content':{'parts':[{'fileData':{'fileUri':'https://private.invalid'}}]}}]}])
def test_invalid_blocked_truncated_or_url_outputs_are_not_success(monkeypatch,body):
    call,transport,events,response=invoke(monkeypatch,body)
    with pytest.raises(ServiceError):call()
    assert len(transport.calls)==1 and response.closed


def test_multiple_output_images_are_rejected(monkeypatch):
    body=image_result();body['candidates'][0]['content']['parts']*=2
    call,*_=invoke(monkeypatch,body)
    with pytest.raises(ServiceError):call()


def test_upstream_errors_are_sanitized_without_retry(monkeypatch):
    call,transport,events,response=invoke(monkeypatch,{'error':'SECRET_API_RESPONSE'},status=403)
    with pytest.raises(ServiceError) as error:call()
    assert error.value.code=='provider_access_denied' and 'SECRET' not in str(error.value)
    assert len(transport.calls)==1


def test_truncated_image_is_not_a_successful_preview(monkeypatch):
    stream=io.BytesIO();Image.new('RGB',(64,96),'blue').save(stream,format='JPEG')
    call,transport,events,response=invoke(monkeypatch,image_result(stream.getvalue()[:-32],mime='image/jpeg'))
    with pytest.raises(ServiceError):call()
    assert len(transport.calls)==1


def test_emulator_budgets_cannot_authorize_paid_generation(monkeypatch):
    monkeypatch.setenv('TRYON_ENABLED','true');monkeypatch.setenv('FIRESTORE_EMULATOR_HOST','127.0.0.1:8085')
    with pytest.raises(ServiceError) as error:virtual_tryon(png(),png(),credentials=None,guard=None,job_key='x',project='test-project')
    assert error.value.code=='tryon_disabled'


def test_oversized_image_dimensions_are_rejected_before_dispatch(monkeypatch):
    monkeypatch.setenv('TRYON_ENABLED','true');monkeypatch.delenv('FIRESTORE_EMULATOR_HOST',raising=False)
    stream=io.BytesIO();Image.new('RGB',(1601,2),'blue').save(stream,format='PNG')
    with pytest.raises(ServiceError) as error:
        virtual_tryon(png(),stream.getvalue(),credentials=None,guard=None,job_key='x',project='test-project')
    assert error.value.code=='invalid_request'
