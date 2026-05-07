import json
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_submit_review_success():
    resp = client.post("/place/review", json={
        "place_name": "비자림",
        "tags": ["감동이에요", "신기해요"],
        "note": "천년 나무 앞에서 설화가 실감났어요",
        "device_id": "test-device-001"
    })
    assert resp.status_code == 201
    assert resp.json()["ok"] is True

def test_submit_review_invalid_tag():
    resp = client.post("/place/review", json={
        "place_name": "비자림",
        "tags": ["없는태그"],
        "device_id": "test-device-002"
    })
    assert resp.status_code == 400

def test_submit_review_note_too_long():
    resp = client.post("/place/review", json={
        "place_name": "비자림",
        "tags": ["감동이에요"],
        "note": "a" * 201,
        "device_id": "test-device-003"
    })
    assert resp.status_code == 400

def test_get_reviews_returns_counts():
    client.post("/place/review", json={
        "place_name": "test_place_unique_xyz",
        "tags": ["소름 돋아요"],
        "device_id": "test-device-get-001"
    })
    resp = client.get("/place/reviews/test_place_unique_xyz")
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] >= 1
    assert data["tag_counts"]["소름 돋아요"] >= 1
    assert "recent_notes" in data

def test_get_reviews_empty_place():
    resp = client.get("/place/reviews/존재하지않는장소99999")
    assert resp.status_code == 200
    assert resp.json()["total"] == 0
