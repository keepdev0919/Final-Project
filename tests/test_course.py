"""코스 추천/리스트/상세 엔드포인트 테스트."""
import pytest
from unittest.mock import patch, MagicMock


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
    "category_scores": {
        "무속신화·신격 전승": 3,
        "생활민담·교훈담": 1,
        "마을 공동체 전승": 2,
        "해양·어촌 전승": 4,
        "초자연 존재담": 0,
    },
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
        {"place_name": "성산일출봉", "lat": 33.458, "lng": 126.942, "day": 1},
        {"place_name": "섭지코지", "lat": 33.430, "lng": 126.930, "day": 1},
    ],
    "error": "",
}

DETAIL_PAYLOAD = {
    "course_id": "course-101",
    "category_scores": {
        "무속신화·신격 전승": 3,
        "생활민담·교훈담": 1,
        "마을 공동체 전승": 2,
        "해양·어촌 전승": 4,
        "초자연 존재담": 0,
    },
}


@pytest.fixture()
def mock_detail_agent():
    with patch("routers.course.run_detail_agent") as mock_fn:
        mock_fn.return_value = DETAIL_MOCK_RESULT
        yield mock_fn


def test_course_detail_returns_200(client, mock_detail_agent):
    """정상 요청 → 200."""
    res = client.post("/course/detail", json=DETAIL_PAYLOAD)
    assert res.status_code == 200


def test_course_detail_returns_places_in_order(client, mock_detail_agent):
    """장소가 순서대로 나와야 한다.

    설화 필드(folklore_pins·narrative)를 확인하던 테스트 3건은 2026-08-14에
    필드와 함께 제거했다. 근거는 tests/test_folklore_removed.py 참조.
    """
    places = client.post("/course/detail", json=DETAIL_PAYLOAD).json()["places"]
    assert [p["name"] for p in places] == ["성산일출봉", "섭지코지"]


def test_course_detail_not_found(client):
    """없는 course_id → 404.

    routers/course.py의 detail_course는 에러 문구에 "찾을 수 없습니다"가
    있으면 404, 그 밖의 에러는 500으로 나눈다. 없는 리소스에 500을 주면
    클라이언트가 재시도할지 포기할지 구분할 수 없다.
    """
    with patch("routers.course.run_detail_agent") as mock_fn:
        mock_fn.return_value = {"error": "코스를 찾을 수 없습니다: bad-id"}
        res = client.post(
            "/course/detail",
            json={**DETAIL_PAYLOAD, "course_id": "bad-id"},
        )
    assert res.status_code == 404


def test_course_detail_other_error_is_500(client):
    """'찾을 수 없습니다'가 아닌 에러 → 500."""
    with patch("routers.course.run_detail_agent") as mock_fn:
        mock_fn.return_value = {"error": "내러티브 생성에 실패했습니다"}
        res = client.post("/course/detail", json=DETAIL_PAYLOAD)
    assert res.status_code == 500


def test_course_detail_missing_course_id(client):
    """course_id 누락 → 422."""
    res = client.post("/course/detail", json={"style": "ocean"})
    assert res.status_code == 422
