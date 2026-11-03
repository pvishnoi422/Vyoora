import json
import math
from types import SimpleNamespace

import pytest

from provider import (review_tryon, TRYON_REVIEW_FIELDS, TRYON_REVIEW_VERSION,
    TRYON_REVIEW_OUTPUT_TOKENS, TRYON_OUTPUT_TOKENS, TRYON_PROMPT_BYTE_LIMIT)
from safety import ServiceError, TRYON_RESERVATION
from test_tryon_provider import png, Credentials, Response, Transport


def response(verdict):
    return {'candidates': [{'finishReason': 'STOP', 'content': {'parts': [
        {'text': json.dumps(verdict)}]}}]}


def invoke(monkeypatch, body, *, reject=False, status=200):
    monkeypatch.setenv('TRYON_ENABLED', 'true')
    monkeypatch.delenv('FIRESTORE_EMULATOR_HOST', raising=False)
    events = []
    transport = Transport(Response(body, status), events)
    def admit(key):
        events.append('review-authorized')
        if reject: raise ServiceError('generation_cancelled', 'Cancelled', 409)
    call = lambda: review_tryon(png(), png(), png(), credentials=Credentials(),
        guard=SimpleNamespace(start_review_attempt=admit), job_key='synthetic',
        project='test-project', session=transport)
    return call, transport, events


def test_only_complete_explicit_pass_is_publishable(monkeypatch):
    call, transport, events = invoke(monkeypatch, response(dict.fromkeys(TRYON_REVIEW_FIELDS, True)))
    assert call() == TRYON_REVIEW_VERSION
    assert events == ['review-authorized', 'provider'] and transport.response.closed
    url, request = transport.calls[0]
    assert '/locations/us/' in url and request['allow_redirects'] is False
    config = request['json']['generationConfig']
    assert config['maxOutputTokens'] == 96 and config['responseModalities'] == ['TEXT']
    assert config['candidateCount'] == 1 and 'tools' not in request['json']
    parts = request['json']['contents'][0]['parts']
    assert len([p for p in parts if 'inlineData' in p]) == 3
    assert 'invented slit' in parts[0]['text'] and 'untrusted evidence' in parts[0]['text']
    assert sum(len(p.get('text', '').encode()) for p in parts) <= TRYON_PROMPT_BYTE_LIMIT


@pytest.mark.parametrize('field', TRYON_REVIEW_FIELDS)
def test_any_failed_or_uncertain_check_rejects_output(monkeypatch, field):
    verdict = dict.fromkeys(TRYON_REVIEW_FIELDS, True); verdict[field] = False
    call, transport, _ = invoke(monkeypatch, response(verdict))
    with pytest.raises(ServiceError) as error: call()
    assert error.value.code == 'preview_rejected'
    assert len(transport.calls) == 1 and transport.response.closed


@pytest.mark.parametrize('body', [{}, response({}), response(dict.fromkeys(TRYON_REVIEW_FIELDS, 'true')),
    {'candidates': [{'finishReason': 'MAX_TOKENS'}]},
    {'promptFeedback': {'blockReason': 'SAFETY'}},
    {'candidates': [{'finishReason': 'STOP', 'content': {'parts': [{'text': 'SAFE'}]}}]},
    {'candidates': [{'finishReason': 'STOP', 'content': {'parts': [
        {'text': '{"certain":false,"certain":true}'}]}}]}])
def test_missing_malformed_truncated_verdicts_withhold_image(monkeypatch, body):
    call, transport, _ = invoke(monkeypatch, body)
    with pytest.raises(ServiceError) as error: call()
    assert error.value.code == 'preview_review_unavailable'
    assert len(transport.calls) == 1 and transport.response.closed


def test_rating_overrides_otherwise_positive_verdict(monkeypatch):
    body = response(dict.fromkeys(TRYON_REVIEW_FIELDS, True))
    body['candidates'][0]['safetyRatings'] = [{'probability': 'LOW', 'blocked': False}]
    call, _, _ = invoke(monkeypatch, body)
    with pytest.raises(ServiceError) as error: call()
    assert error.value.code == 'preview_rejected'


def test_cancelled_or_unreserved_review_never_dispatches(monkeypatch):
    call, transport, _ = invoke(monkeypatch, {}, reject=True)
    with pytest.raises(ServiceError): call()
    assert transport.calls == []


def test_outage_is_sanitized_and_never_retried(monkeypatch):
    call, transport, _ = invoke(monkeypatch, {'error': 'SECRET'}, status=503)
    with pytest.raises(ServiceError) as error: call()
    assert error.value.code == 'preview_review_unavailable' and 'SECRET' not in str(error.value)
    assert len(transport.calls) == 1


def test_combined_generation_and_review_fit_original_reservation():
    generation = (2*1120+TRYON_PROMPT_BYTE_LIMIT)*.55 + TRYON_OUTPUT_TOKENS*66
    review = (3*1120+TRYON_PROMPT_BYTE_LIMIT)*.55 + TRYON_REVIEW_OUTPUT_TOKENS*66
    assert math.ceil(generation+review) == 146837 < TRYON_RESERVATION == 150000
