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


def test_course_places_are_looked_up_by_id_not_title():
    """코스 장소는 반드시 `course_id`로 조회해야 한다.

    `curated_courses.origin_title`은 비짓제주 사용자가 쓴 개인 메모다 —
    "여행", "^^", "제주도". **유일하지 않다.** 이 값으로 `courses`를 역조회하면
    남의 코스 장소가 통째로 딸려온다.

        id=19670 "전체 3일 · 천왕사 외 10곳"
          course_id로 조회        →  12곳  ← 정답
          origin_title로 역조회   → 891곳  ← 74배

    화면에는 코스가 그럴듯하게 뜨고 장소만 수백 개가 된다. 크래시가 아니라
    조용히 틀린 데이터라 눈으로 못 잡는다. 탐험 화면을 만들며 제목으로 조회하는
    코드가 들어오면 여기서 걸린다.

    되살릴 일이 있으면 이 테스트를 먼저 지우면서 "왜"를 남길 것.
    """
    import sqlite3
    from pathlib import Path

    db = Path(__file__).parent.parent / "storage" / "metadata.db"
    if not db.exists():
        import pytest
        pytest.skip("metadata.db 없음 (CI 등)")

    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row

    # 1) origin_title이 유일하지 않다는 사실 자체를 못 박는다.
    dup = conn.execute(
        "SELECT origin_title, COUNT(*) n FROM curated_courses "
        "WHERE origin_title IS NOT NULL AND TRIM(origin_title) != '' "
        "GROUP BY origin_title HAVING n > 1 ORDER BY n DESC LIMIT 1"
    ).fetchone()
    assert dup is not None, (
        "origin_title이 유일해졌다면 이 테스트의 전제가 바뀐 것이다. "
        "데이터 재빌드 여부를 확인하고 이 테스트를 갱신할 것."
    )

    # 2) id 조회와 title 조회가 실제로 다른 결과를 낸다.
    row = conn.execute(
        "SELECT id, origin_title FROM curated_courses WHERE origin_title = ? LIMIT 1",
        (dup["origin_title"],),
    ).fetchone()

    by_id = conn.execute(
        "SELECT COUNT(*) n FROM course_places WHERE course_id = ?", (row["id"],)
    ).fetchone()["n"]
    by_title = conn.execute(
        "SELECT COUNT(*) n FROM course_places "
        "WHERE course_id IN (SELECT id FROM courses WHERE title = ?)",
        (row["origin_title"],),
    ).fetchone()["n"]

    assert by_title > by_id, "전제가 바뀌었다 — 이 테스트를 재검토할 것"

    # 3) 실제 코드 경로가 id 기반인지 확인한다. 이게 본 검사다.
    from agents.course_detail_agent import get_places_for_course

    places = get_places_for_course(str(row["id"]))
    assert len(places) <= by_id, (
        f"코스 {row['id']}의 장소가 {len(places)}곳으로 나왔다. "
        f"course_id 기준은 {by_id}곳이다 — 제목으로 조회하고 있다."
    )
