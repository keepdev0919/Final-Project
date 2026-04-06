"""GET /pins 엔드포인트 테스트."""
import pytest


def test_pins_requires_lat_lng(client):
    """lat/lng 없으면 422 반환."""
    res = client.get("/pins")
    assert res.status_code == 422


def test_pins_returns_list(client):
    """성산일출봉 좌표로 조회 — 리스트 반환."""
    res = client.get("/pins", params={"lat": 33.458, "lng": 126.942, "radius_m": 5000})
    assert res.status_code == 200
    assert isinstance(res.json(), list)


def test_pins_result_structure(client):
    """반환된 핀에 필수 필드 존재."""
    res = client.get("/pins", params={"lat": 33.458, "lng": 126.942, "radius_m": 5000})
    pins = res.json()
    if pins:
        pin = pins[0]
        assert "code_no" in pin
        assert "title" in pin
        assert "lat" in pin
        assert "lng" in pin
        assert "source_type" in pin


def test_pins_sorted_by_distance(client):
    """결과가 distance_m 오름차순 정렬."""
    res = client.get("/pins", params={"lat": 33.458, "lng": 126.942, "radius_m": 10000})
    pins = res.json()
    if len(pins) >= 2:
        distances = [p["distance_m"] for p in pins if p.get("distance_m") is not None]
        assert distances == sorted(distances)


def test_pins_all_within_radius(client):
    """반환된 핀이 모두 요청 반경 이내."""
    radius = 3000
    res = client.get("/pins", params={"lat": 33.458, "lng": 126.942, "radius_m": radius})
    for pin in res.json():
        assert pin["distance_m"] <= radius


def test_pins_small_radius_returns_fewer(client):
    """반경이 작을수록 결과가 적거나 같음."""
    res_large = client.get("/pins", params={"lat": 33.458, "lng": 126.942, "radius_m": 10000})
    res_small = client.get("/pins", params={"lat": 33.458, "lng": 126.942, "radius_m": 500})
    assert len(res_small.json()) <= len(res_large.json())
