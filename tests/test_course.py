"""POST /course/recommend 엔드포인트 테스트 (LangGraph mock)."""
import pytest
from unittest.mock import patch, MagicMock


MOCK_STATE = {
    "course_title": "제주 신화 탐험 코스",
    "enriched_route": [
        {
            "place": "성산일출봉",
            "lat": 33.458,
            "lng": 126.942,
            "day": 1,
            "code_no": "L_001",
            "title": "설문대할망 전설",
            "text": "설문대할망이 제주를 창조했다는 전설이 전해지는 곳.",
        },
        {
            "place": "한라산",
            "lat": 33.362,
            "lng": 126.534,
            "day": 1,
        },
    ],
    "error": "",
}

PAYLOAD = {
    "theme": "신화",
    "duration_days": 1,
    "transport": "도보",
}


@pytest.fixture()
def mock_course_graph():
    with patch("routers.course.course_graph") as mock_graph:
        mock_graph.invoke.return_value = MOCK_STATE
        yield mock_graph


def test_course_recommend_returns_200(client, mock_course_graph):
    """정상 요청 → 200."""
    res = client.post("/course/recommend", json=PAYLOAD)
    assert res.status_code == 200


def test_course_recommend_structure(client, mock_course_graph):
    """응답에 필수 필드 존재."""
    res = client.post("/course/recommend", json=PAYLOAD)
    body = res.json()
    assert "id" in body
    assert "title" in body
    assert "duration_days" in body
    assert "places" in body
    assert isinstance(body["places"], list)


def test_course_recommend_places_structure(client, mock_course_graph):
    """places 항목에 name/lat/lng/day 포함."""
    res = client.post("/course/recommend", json=PAYLOAD)
    places = res.json()["places"]
    assert len(places) == 2
    for p in places:
        assert "name" in p
        assert "lat" in p
        assert "lng" in p
        assert "day" in p


def test_course_recommend_folklore_pins(client, mock_course_graph):
    """설화 코드가 있는 장소에 folklore_pins 존재."""
    res = client.post("/course/recommend", json=PAYLOAD)
    places = res.json()["places"]
    first = places[0]
    assert len(first["folklore_pins"]) == 1
    assert first["folklore_pins"][0]["code_no"] == "L_001"


def test_course_recommend_error_state(client):
    """agent error → 404 반환."""
    with patch("routers.course.course_graph") as mock_graph:
        mock_graph.invoke.return_value = {
            **MOCK_STATE,
            "error": "관련 설화를 찾지 못했습니다.",
            "enriched_route": [],
        }
        res = client.post("/course/recommend", json=PAYLOAD)
    assert res.status_code == 404


def test_course_recommend_missing_theme(client):
    """theme 없으면 422."""
    res = client.post("/course/recommend", json={"duration_days": 1, "transport": "도보"})
    assert res.status_code == 422
