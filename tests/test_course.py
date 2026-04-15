"""코스 추천/리스트/상세 엔드포인트 테스트."""
import pytest
from unittest.mock import patch, MagicMock


# ─── /course/recommend (레거시, 유지) ──────────────────────────────────────────

RECOMMEND_MOCK_STATE = {
    "course_title": "제주 신화 탐험 코스",
    "final_course": {
        "id": "course-001",
        "title": "성산·한라 1일 코스",
        "places": [
            {
                "place_name": "성산일출봉",
                "lat": 33.458,
                "lng": 126.942,
                "day": 1,
                "folklore_nearby": [
                    {
                        "code_no": "L_001",
                        "title": "설문대할망 전설",
                        "source_type": "legend",
                        "lat": 33.460,
                        "lng": 126.940,
                        "distance_m": 250,
                    }
                ],
            },
            {
                "place_name": "한라산",
                "lat": 33.362,
                "lng": 126.534,
                "day": 1,
                "folklore_nearby": [],
            },
        ],
    },
    "error": "",
}

RECOMMEND_PAYLOAD = {
    "theme": "신화",
    "duration_days": 1,
}


@pytest.fixture()
def mock_course_graph():
    with patch("routers.course.course_graph") as mock_graph:
        mock_graph.invoke.return_value = RECOMMEND_MOCK_STATE
        yield mock_graph


def test_course_recommend_returns_200(client, mock_course_graph):
    """정상 요청 → 200."""
    res = client.post("/course/recommend", json=RECOMMEND_PAYLOAD)
    assert res.status_code == 200


def test_course_recommend_structure(client, mock_course_graph):
    """응답에 필수 필드 존재."""
    res = client.post("/course/recommend", json=RECOMMEND_PAYLOAD)
    body = res.json()
    assert "id" in body
    assert "title" in body
    assert "duration_days" in body
    assert "places" in body
    assert isinstance(body["places"], list)


def test_course_recommend_places_structure(client, mock_course_graph):
    """places 항목에 name/lat/lng/day 포함."""
    res = client.post("/course/recommend", json=RECOMMEND_PAYLOAD)
    places = res.json()["places"]
    assert len(places) == 2
    for p in places:
        assert "name" in p
        assert "lat" in p
        assert "lng" in p
        assert "day" in p


def test_course_recommend_folklore_pins(client, mock_course_graph):
    """설화 코드가 있는 장소에 folklore_pins 존재."""
    res = client.post("/course/recommend", json=RECOMMEND_PAYLOAD)
    places = res.json()["places"]
    first = places[0]
    assert len(first["folklore_pins"]) == 1
    assert first["folklore_pins"][0]["code_no"] == "L_001"


def test_course_recommend_error_state(client):
    """agent error → 500 반환."""
    with patch("routers.course.course_graph") as mock_graph:
        mock_graph.invoke.return_value = {
            **RECOMMEND_MOCK_STATE,
            "error": "코스를 찾지 못했습니다.",
        }
        res = client.post("/course/recommend", json=RECOMMEND_PAYLOAD)
    assert res.status_code == 500


def test_course_recommend_missing_theme(client):
    """theme 없으면 422."""
    res = client.post("/course/recommend", json={"duration_days": 1})
    assert res.status_code == 422


# ─── /course/list ──────────────────────────────────────────────────────────────

LIST_MOCK_STATE = {
    "result_courses": [
        {
            "id": "course-101",
            "title": "동부 해안 1일 코스",
            "duration_days": 1,
            "places": [
                {"place_name": "성산일출봉", "lat": 33.458, "lng": 126.942, "day": 1},
                {"place_name": "섭지코지", "lat": 33.430, "lng": 126.930, "day": 1},
            ],
        },
        {
            "id": "course-102",
            "title": "동부 오름 1일 코스",
            "duration_days": 1,
            "places": [
                {"place_name": "용눈이오름", "lat": 33.440, "lng": 126.800, "day": 1},
            ],
        },
        {
            "id": "course-103",
            "title": "동부 문화 1일 코스",
            "duration_days": 1,
            "places": [
                {"place_name": "제주민속촌", "lat": 33.374, "lng": 126.818, "day": 1},
            ],
        },
    ],
    "error": "",
}

LIST_PAYLOAD = {
    "region": "동부",
    "style": "ocean",
    "duration_days": 1,
}


@pytest.fixture()
def mock_list_graph():
    with patch("routers.course.course_list_graph") as mock_graph:
        mock_graph.invoke.return_value = LIST_MOCK_STATE
        yield mock_graph


def test_course_list_returns_200(client, mock_list_graph):
    """정상 요청 → 200."""
    res = client.post("/course/list", json=LIST_PAYLOAD)
    assert res.status_code == 200


def test_course_list_returns_3_courses(client, mock_list_graph):
    """코스 3개 반환."""
    res = client.post("/course/list", json=LIST_PAYLOAD)
    body = res.json()
    assert isinstance(body, list)
    assert len(body) == 3


def test_course_list_structure(client, mock_list_graph):
    """각 코스에 id/title/duration_days/places 포함."""
    res = client.post("/course/list", json=LIST_PAYLOAD)
    for course in res.json():
        assert "id" in course
        assert "title" in course
        assert "duration_days" in course
        assert "places" in course
        assert isinstance(course["places"], list)


def test_course_list_error_state(client):
    """agent error → 500."""
    with patch("routers.course.course_list_graph") as mock_graph:
        mock_graph.invoke.return_value = {"result_courses": [], "error": "DB 오류"}
        res = client.post("/course/list", json=LIST_PAYLOAD)
    assert res.status_code == 500


def test_course_list_empty_result(client):
    """후보 없음 → 404."""
    with patch("routers.course.course_list_graph") as mock_graph:
        mock_graph.invoke.return_value = {"result_courses": [], "error": ""}
        res = client.post("/course/list", json=LIST_PAYLOAD)
    assert res.status_code == 404


def test_course_list_missing_fields(client):
    """필수 필드 누락 → 422."""
    res = client.post("/course/list", json={"region": "동부"})
    assert res.status_code == 422


# ─── /course/detail ────────────────────────────────────────────────────────────

DETAIL_MOCK_RESULT = {
    "id": "course-101",
    "title": "동부 해안 1일 코스",
    "duration_days": 1,
    "places": [
        {
            "place_name": "성산일출봉",
            "lat": 33.458,
            "lng": 126.942,
            "day": 1,
            "folklore_pins": [
                {
                    "code_no": "L_001",
                    "title": "설문대할망 전설",
                    "source_type": "legend",
                    "summary": "제주를 창조한 할망 이야기",
                    "lat": 33.460,
                    "lng": 126.940,
                    "distance_m": 250,
                }
            ],
        },
        {
            "place_name": "섭지코지",
            "lat": 33.430,
            "lng": 126.930,
            "day": 1,
            "folklore_pins": [],
        },
    ],
    "narrative": "성산의 붉은 일출과 함께 설문대할망의 전설이 깨어납니다...",
    "error": "",
}

DETAIL_PAYLOAD = {"course_id": "course-101", "style": "ocean"}


@pytest.fixture()
def mock_detail_agent():
    with patch("routers.course.run_detail_agent") as mock_fn:
        mock_fn.return_value = DETAIL_MOCK_RESULT
        yield mock_fn


def test_course_detail_returns_200(client, mock_detail_agent):
    """정상 요청 → 200."""
    res = client.post("/course/detail", json=DETAIL_PAYLOAD)
    assert res.status_code == 200


def test_course_detail_has_narrative(client, mock_detail_agent):
    """응답에 narrative 포함."""
    res = client.post("/course/detail", json=DETAIL_PAYLOAD)
    body = res.json()
    assert "narrative" in body
    assert len(body["narrative"]) > 0


def test_course_detail_has_folklore_pins(client, mock_detail_agent):
    """설화 있는 장소에 folklore_pins 포함."""
    res = client.post("/course/detail", json=DETAIL_PAYLOAD)
    places = res.json()["places"]
    first = places[0]
    assert len(first["folklore_pins"]) == 1
    assert first["folklore_pins"][0]["code_no"] == "L_001"


def test_course_detail_empty_folklore_place(client, mock_detail_agent):
    """설화 없는 장소 → folklore_pins=[] (graceful)."""
    res = client.post("/course/detail", json=DETAIL_PAYLOAD)
    places = res.json()["places"]
    second = places[1]
    assert second["folklore_pins"] == []


def test_course_detail_not_found(client):
    """course_id 없음 → 500."""
    with patch("routers.course.run_detail_agent") as mock_fn:
        mock_fn.return_value = {"error": "코스를 찾을 수 없습니다: bad-id"}
        res = client.post("/course/detail", json={"course_id": "bad-id", "style": "ocean"})
    assert res.status_code == 500


def test_course_detail_missing_course_id(client):
    """course_id 누락 → 422."""
    res = client.post("/course/detail", json={"style": "ocean"})
    assert res.status_code == 422
