"""코스 리스트 에이전트.

`curated_courses`에서 지역×기간 조건으로 후보를 가져와 **코스 품질 점수**
(`composite_score`) 상위 풀에서 무작위로 top_n개를 반환한다. LLM 없이 DB 조회만으로
동작한다.

## 설화 의존 제거 (2026-08-13)

이전 버전은 `place_folklore_mapping`을 조회해 **사용자의 설화 카테고리 취향 점수**로
코스를 정렬했다(`_score_course`). 취향 퀴즈에서 받은 5종 카테고리 순위가 입력이었다.

제거한 이유:
- 코스는 "어디를 갈지", 설화는 "그 장소의 이야기"다. 추천 기준으로 쓸 근거가 없다
- 장소에 강하게 얽힌 설화가 실제로 거의 없다 (설화-장소 매핑 작업에서 확인)
- 설화는 로컬 파일 데이터라 공모전 데이터 활용 점수에 기여하지 않는다
  (공지 FAQ: "OpenAPI 형태만 인정, 파일데이터 활용은 인정되지 않음")

코스 품질 기준은 `backend/scripts/build_curated_courses.py`가 미리 계산해
`composite_score`에 담아둔다 — 경로 효율 40% + 하루 장소 수 적정성 35% +
관광지 비율 25%.

⚠️ `category_scores` 파라미터는 **호출부 호환을 위해 남아 있지만 무시된다.**
취향 퀴즈 제거(단계 1)와 함께 API 스키마에서 없앨 예정이다.
"""
from __future__ import annotations

import math
import random
from typing import Any

from services.db import get_db_connection


# ─── 유틸 (테스트에서도 사용) ──────────────────────────────────────────────────

def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6_371_000
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ─── 퍼블릭 API ───────────────────────────────────────────────────────────────

# 상위 몇 개를 무작위 추출 풀로 쓸지. 매번 같은 코스만 나오지 않게 하되
# 품질이 낮은 코스가 섞이지 않을 만큼만.
CANDIDATE_POOL_SIZE = 12


def run_course_list(
    region: str,
    duration_days: int,
    category_scores: dict[str, int] | None = None,
    top_n: int = 3,
) -> dict[str, Any]:
    """curated_courses에서 조건에 맞는 코스를 품질 순으로 가져와 반환.

    Args:
        region: 동부 | 서부 | 남부 | 북부 | 전체
        duration_days: 여행 일수
        category_scores: **무시된다.** 설화 취향 기반 정렬을 제거했다(위 모듈 문서 참조).
            호출부 호환을 위해 시그니처만 유지한다.
        top_n: 반환할 코스 수

    Returns:
        {"result_courses": [...], "error": ""}  — router와 동일한 인터페이스
    """
    conn = get_db_connection()

    duration_min = max(1, duration_days - 1)
    duration_max = duration_days + 1

    # 부실 코스 필터: place_count >= 3 AND >= duration_days
    # (1박 2일에 갈 곳이 1~2곳인 일정을 배제)
    if region == "전체":
        rows = conn.execute(
            """
            SELECT id, title, duration_days, region
            FROM curated_courses
            WHERE duration_days BETWEEN ? AND ?
              AND place_count >= 3
              AND place_count >= ?
            ORDER BY composite_score DESC
            LIMIT ?
            """,
            (duration_min, duration_max, duration_days, CANDIDATE_POOL_SIZE),
        ).fetchall()
    else:
        # 요청 지역 코스 우선, 부족하면 "전체"로 분류된 코스로 보완
        rows = conn.execute(
            """
            SELECT id, title, duration_days, region
            FROM curated_courses
            WHERE region IN (?, '전체')
              AND duration_days BETWEEN ? AND ?
              AND place_count >= 3
              AND place_count >= ?
            ORDER BY CASE WHEN region = ? THEN 0 ELSE 1 END, composite_score DESC
            LIMIT ?
            """,
            (region, duration_min, duration_max, duration_days, region, CANDIDATE_POOL_SIZE),
        ).fetchall()

    if not rows:
        return {"result_courses": [], "error": "조건에 맞는 코스를 찾지 못했습니다."}

    # 품질 상위 풀에서 무작위 추출 — 같은 조건으로 다시 받으면 다른 코스를 보여준다.
    # 정렬은 SQL의 composite_score DESC가 이미 했다.
    sample_size = min(top_n, len(rows))
    top_rows = random.sample(rows, sample_size)

    return {"result_courses": _with_places(conn, top_rows), "error": ""}


def _with_places(conn, rows: list) -> list[dict[str, Any]]:
    """코스 행에 장소 목록을 붙인다. 코스 하나씩 조회하지 않고 한 번에 가져온다."""
    course_ids = [r["id"] for r in rows]
    if not course_ids:
        return []

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

    return [
        {
            "id": row["id"],
            "title": row["title"],
            "duration_days": row["duration_days"],
            # 권역은 DB에 이미 있었는데 앱까지 내려보내지 않고 있었다. 코스 카드가
            # 권역색 배지를 달면서 필요해졌다 — 제목 앞의 「서부 」를 글자로 파싱하는
            # 대신 데이터를 그대로 쓴다 (2026-09-09).
            "region": row["region"],
            "places": places_by_course.get(row["id"], []),
        }
        for row in rows
    ]


# ─── 「이런 코스는 어때요?」 ───────────────────────────────────────────────────
#
# 권역·기간을 고르기 전에, 코스 탭 첫 화면에서 그냥 둘러보라고 깔아 두는 목록이다.
# 「추천」이 아니라 「이런 것도 있어요」다 — 사용자 취향을 반영하지 않는다.

# 품질 하한. curated_courses 는 이미 한 번 걸러진 목록이지만 점수 편차가 있다.
# 1,255개 중 0.7 미만이 105개(8%)라, 하한 없이 뽑으면 열두 장에 한 장꼴로
# 「하루에 섬을 왕복하는」 코스가 첫 화면에 올라온다.
FEATURED_MIN_SCORE = 0.8


def run_featured_courses(limit: int = 5) -> dict[str, Any]:
    """조건 없이 둘러볼 코스를 무작위로 뽑는다. 부를 때마다 다른 코스가 나온다.

    ## 제목이 지저분한 코스를 왜 거르나

    코스 제목은 원본 여행 일정의 장소 이름으로 자동 생성되는데
    (`build_curated_courses.py::_make_title`), 비짓제주 원본에 이런 게 섞여 있다:

        북부 1일 · 수목원테마파크_2025.11.11 영업종료(리모델링공사) / 2026.03.01 재오픈 예정 외 2곳
        북부 3일 · 이호테우해수욕장_old 외 7곳

    0.8점 이상 687개 중 89개(13%)가 이 상태다. 거르지 않으면 다섯 장 중 한 장꼴로
    깨진 카드가 첫 화면에 뜬다. **근본 해결은 대표 장소를 고를 때 이런 이름을
    건너뛰도록 빌드 스크립트를 고치는 것**이고, 여기 필터는 그때까지의 방어선이다.
    걸러내도 590개가 남아 매번 다른 다섯 장을 보여주기에 충분하다.
    """
    conn = get_db_connection()

    rows = conn.execute(
        r"""
        SELECT id, title, duration_days, region
        FROM curated_courses
        WHERE composite_score >= ?
          AND place_count >= 3
          AND LENGTH(title) <= 40
          AND title NOT LIKE '%(%'      -- 「(리모델링공사)」 같은 안내문
          AND title NOT LIKE '%/%'      -- 「영업종료 / 재오픈 예정」
          AND title NOT LIKE '%20%'     -- 「2025.11.11」 같은 날짜
          AND title NOT LIKE '%\_%' ESCAPE '\'   -- 「이호테우해수욕장_old」
        ORDER BY RANDOM()
        LIMIT ?
        """,
        (FEATURED_MIN_SCORE, limit),
    ).fetchall()

    if not rows:
        return {"result_courses": [], "error": "보여줄 코스를 찾지 못했습니다."}

    return {"result_courses": _with_places(conn, rows), "error": ""}


# ─── 라우터 호환 래퍼 ─────────────────────────────────────────────────────────

class _FakeGraph:
    """routers/course.py가 course_list_graph.invoke(state)를 호출하므로 인터페이스 유지."""

    def invoke(self, state: dict) -> dict:
        result = run_course_list(
            region=state.get("region", "전체"),
            duration_days=state.get("duration_days", 3),
        )
        return {**state, **result}


course_list_graph = _FakeGraph()
