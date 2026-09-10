"""코스 상세 에이전트.

course_id로 장소 목록과 코스 제목을 조회해 Course 딕셔너리를 만든다.
LLM 없이 DB 조회만으로 동작한다.

## 설화 의존 제거 (2026-08-13 → 2026-08-14 완료)

이전에는 `place_folklore_mapping`에서 장소별 설화를 가져와 붙이고, 그 설화를 엮어
LLM으로 여행 내러티브를 생성했다. 2026-08-13에 코스 추천에서 설화를 분리하며 둘 다
제거했고, 스키마 호환을 위해 남겨뒀던 `folklore_pins`·`narrative` 빈 필드도
2026-08-14에 없앴다. 근거는 설계 문서 §5:

- 코스는 "어디를 갈지", 설화는 "그 장소의 이야기"다. 추천 기준으로 쓸 근거가 없다
- 장소에 강하게 얽힌 설화가 실제로 거의 없다 (설화-장소 매핑 작업에서 확인)
- 설화는 로컬 파일 데이터라 공모전 데이터 활용 점수에 기여하지 않는다
  (공지 FAQ: "OpenAPI 형태만 인정")

따라서 이 모듈은 더 이상 LLM을 쓰지 않는다.
"""
from __future__ import annotations

from services.db import get_db_connection
from services.place_display_names import display_names


def get_places_for_course(course_id: str) -> list[dict]:
    """SQLite에서 코스 장소 목록 조회."""
    conn = get_db_connection()
    rows = conn.execute(
        """
        SELECT place_name, lat, lng, day
        FROM course_places
        WHERE course_id = ? AND in_jeju = 1
        ORDER BY day, start_time
        """,
        (course_id,),
    ).fetchall()
    names = display_names()
    seen: set[tuple] = set()
    result = []
    for r in rows:
        if r["lat"] is None or r["lng"] is None:
            continue
        key = (r["place_name"], r["day"])
        if key in seen:
            continue
        seen.add(key)
        result.append({
            # 원본 이름은 identity라 그대로 두고, 화면에는 정리된 이름을 보낸다
            # (`backend/scripts/build_place_display_names.py`).
            "place_name": names.get(r["place_name"], r["place_name"]),
            "lat": r["lat"],
            "lng": r["lng"],
            "day": r["day"],
        })
    return result


def get_course_title(course_id: str) -> tuple[str, int]:
    """코스 제목·일수 조회.

    **`curated_courses`를 먼저 본다.** 원본 `courses.title`은 비짓제주 사용자가 쓴
    개인 메모라 그대로 노출할 수 없다 — "^^", "z", "우리의 첫 비행기 여행♥".
    `build_curated_courses.py`가 `{지역} {일수}일 · {대표장소} 외 N곳` 형태로 생성해
    저장해 두므로 그것을 쓴다.

    이 조회가 원본을 보면 목록과 상세의 제목이 달라진다 — 목록은 curated 제목을,
    상세는 원본 제목을 보여주는 불일치가 실제로 발생했다(2026-08-13 수정).

    큐레이션에 없는 코스(직접 저장 등)는 원본으로 폴백한다.
    """
    conn = get_db_connection()
    row = conn.execute(
        "SELECT title, duration_days FROM curated_courses WHERE id = ?",
        (course_id,),
    ).fetchone()
    if row:
        return (row["title"], row["duration_days"] or 1)

    row = conn.execute(
        "SELECT title, duration_days FROM courses WHERE id = ?",
        (course_id,),
    ).fetchone()
    return (row["title"] if row else "", row["duration_days"] if row else 1)


def run_detail_agent(course_id: str) -> dict:
    """Detail 에이전트 진입점. Course 딕셔너리 반환."""
    course_title, duration_days = get_course_title(course_id)
    if not course_title:
        return {"error": f"코스를 찾을 수 없습니다: {course_id}"}

    places = get_places_for_course(course_id)
    if not places:
        return {"error": f"코스 장소 데이터가 없습니다: {course_id}"}

    return {
        "id": course_id,
        "title": course_title,
        "duration_days": duration_days,
        "places": places,
        "error": "",
    }

# eager init — FastAPI worker 시작 시점에 DB 커넥션 확보
get_db_connection()
