"""코스 리스트 에이전트.

curated_courses 테이블에서 지역×기간 조건으로 풀을 가져온 뒤,
place_folklore_mapping 기반 카테고리 점수로 상위 3개를 반환한다.
LLM 없이 DB 조회만으로 동작한다.
"""
from __future__ import annotations

import math
from typing import Any

from services.db import get_db_connection


# ─── 유틸 (테스트에서도 사용) ──────────────────────────────────────────────────

CATEGORY_QUERIES = {
    "무속신화·신격 전승": "제주 무속신화 본풀이 신격 전승",
    "생활민담·교훈담": "제주 생활민담 교훈담 해학 이야기",
    "마을 공동체 전승": "제주 마을 공동체 전승 본향당 마을신",
    "해양·어촌 전승": "제주 바다 해녀 어촌 해양 전승",
    "초자연 존재담": "제주 도체비 귀신 초자연 존재 이야기",
}


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6_371_000
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _scores_to_theme_text(scores: dict[str, int]) -> str:
    sorted_cats = sorted(scores.items(), key=lambda x: -x[1])
    lines = []
    for cat, score in sorted_cats:
        if score > 0:
            query = CATEGORY_QUERIES.get(cat, cat)
            lines.append(f"- {cat} ({score}점): {query}")
    return "\n".join(lines) if lines else "특별한 취향 없음 (다양한 설화 포함)"


# ─── 코스 스코어링 ─────────────────────────────────────────────────────────────

def _score_course(
    course_id: str,
    category_scores: dict[str, int],
    conn,
) -> int:
    """place_folklore_mapping 기반 카테고리 점수 합산."""
    rows = conn.execute(
        """
        SELECT DISTINCT pfm.final_category
        FROM course_places cp
        JOIN place_folklore_mapping pfm ON pfm.place_name = cp.place_name
        WHERE cp.course_id = ? AND pfm.specificity >= 5
        """,
        (course_id,),
    ).fetchall()
    return sum(category_scores.get(r["final_category"], 0) for r in rows)


# ─── 퍼블릭 API ───────────────────────────────────────────────────────────────

def run_course_list(
    region: str,
    duration_days: int,
    category_scores: dict[str, int],
    top_n: int = 3,
) -> dict[str, Any]:
    """curated_courses에서 조건에 맞는 코스를 가져와 취향 점수로 정렬 후 반환.

    Returns:
        {"result_courses": [...], "error": ""}  — router와 동일한 인터페이스
    """
    conn = get_db_connection()

    duration_min = max(1, duration_days - 1)
    duration_max = duration_days + 1

    # 요청 지역 코스 우선 + 부족하면 "전체" 코스로 보완
    rows = conn.execute(
        """
        SELECT id, title, duration_days
        FROM curated_courses
        WHERE region IN (?, '전체') AND duration_days BETWEEN ? AND ?
        ORDER BY CASE WHEN region = ? THEN 0 ELSE 1 END, composite_score DESC
        LIMIT 50
        """,
        (region, duration_min, duration_max, region),
    ).fetchall()

    if not rows:
        return {"result_courses": [], "error": "조건에 맞는 코스를 찾지 못했습니다."}

    scored: list[tuple[int, dict]] = []
    for row in rows:
        folklore_score = _score_course(row["id"], category_scores, conn)
        scored.append((folklore_score, dict(row)))

    scored.sort(key=lambda x: -x[0])
    top_rows = [item[1] for item in scored[:top_n]]

    # 장소 목록 배치 조회
    course_ids = [r["id"] for r in top_rows]
    placeholders = ",".join("?" * len(course_ids))
    place_rows = conn.execute(
        f"""
        SELECT course_id, place_name, lat, lng, day
        FROM course_places
        WHERE course_id IN ({placeholders}) AND in_jeju = 1
          AND lat IS NOT NULL AND lng IS NOT NULL
        ORDER BY course_id, day, seq_no
        """,
        course_ids,
    ).fetchall()

    places_by_course: dict[str, list[dict]] = {cid: [] for cid in course_ids}
    seen: set[tuple] = set()
    for p in place_rows:
        key = (p["course_id"], p["place_name"], p["day"])
        if key in seen:
            continue
        seen.add(key)
        places_by_course[p["course_id"]].append({
            "place_name": p["place_name"],
            "lat": p["lat"],
            "lng": p["lng"],
            "day": p["day"],
        })

    result_courses = []
    for row in top_rows:
        result_courses.append({
            "id": row["id"],
            "title": row["title"],
            "duration_days": row["duration_days"],
            "places": places_by_course.get(row["id"], []),
        })

    return {"result_courses": result_courses, "error": ""}


# ─── 라우터 호환 래퍼 ─────────────────────────────────────────────────────────

class _FakeGraph:
    """routers/course.py가 course_list_graph.invoke(state)를 호출하므로 인터페이스 유지."""

    def invoke(self, state: dict) -> dict:
        result = run_course_list(
            region=state.get("region", "전체"),
            duration_days=state.get("duration_days", 3),
            category_scores=state.get("category_scores", {}),
        )
        return {**state, **result}


course_list_graph = _FakeGraph()
