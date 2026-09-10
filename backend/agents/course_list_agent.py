"""코스 리스트 에이전트.

`curated_courses`에서 지역×기간 조건에 맞는 코스를 **무작위로** top_n개 반환한다.
LLM 없이 DB 조회만으로 동작한다.

## 설화 의존 제거 (2026-08-13)

이전 버전은 `place_folklore_mapping`을 조회해 **사용자의 설화 카테고리 취향 점수**로
코스를 정렬했다(`_score_course`). 취향 퀴즈에서 받은 5종 카테고리 순위가 입력이었다.

제거한 이유:
- 코스는 "어디를 갈지", 설화는 "그 장소의 이야기"다. 추천 기준으로 쓸 근거가 없다
- 장소에 강하게 얽힌 설화가 실제로 거의 없다 (설화-장소 매핑 작업에서 확인)
- 설화는 로컬 파일 데이터라 공모전 데이터 활용 점수에 기여하지 않는다
  (공지 FAQ: "OpenAPI 형태만 인정, 파일데이터 활용은 인정되지 않음")

## 점수제 제거 (2026-09-10)

이전에는 `composite_score`(경로 효율·하루 장소 수·관광지 비율의 가중합) 상위 12개를
뽑아 그중 일부를 보여줬다. 점수제를 통째로 없앤 이유는 **잘려나가던 것이 못 쓸
데이터가 아니라 정상 여행이었기 때문**이다 — 숙소·식당이 낀 보통 일정은 이동이
길고 관광지 비율이 낮아 자동으로 낮은 점수를 받았다. 그렇게 1,793개가 버려지고
있었다.

지금은 `build_curated_courses.py`가 하드필터로 「일정이 아닌 데이터」만 걷어내고,
여기서는 조건에 맞는 것 중 무작위로 뽑는다. 목록이 1,255개 → 6,339개로 늘었다.

코스 사이에 우열은 없다. 화면이 「추천 TOP N」이라 부르며 번호를 붙이지만 그대로
두기로 했다 (2026-09-10 조익준님 결정) — 번호는 순위가 아니라 목록의 자리 표시다.

설화 취향 점수를 받던 `category_scores` 파라미터는 2026-09-10에 없앴다. API 스키마와
앱에서 이미 빠져 있어 아무도 넘기지 않고 있었다.
"""
from __future__ import annotations

import math
from typing import Any

from services.db import get_db_connection
from services.place_display_names import display_names



# ─── 유틸 (테스트에서도 사용) ──────────────────────────────────────────────────

def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6_371_000
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ─── 퍼블릭 API ───────────────────────────────────────────────────────────────

# 제목 중복을 걸러낼 여유분. 필요한 개수의 몇 배를 뽑아 두고 추린다
# (`_dedupe_by_title`). 4배면 5장을 채우는 데 실패한 적이 없다.
OVERFETCH = 4

# 추천 목록이 한 번에 보여주는 코스 수. 화면 제목 「추천 TOP N」이 이 숫자다
# (2026-09-10 조익준님 결정, 3 → 5). 라우터도 이 값으로 자른다.
RESULT_COUNT = 5


def run_course_list(
    region: str,
    duration_days: int,
    top_n: int = RESULT_COUNT,
) -> dict[str, Any]:
    """curated_courses에서 조건에 맞는 코스를 무작위로 가져와 반환.

    Args:
        region: 동부 | 서부 | 남부 | 북부 | 전체
        duration_days: 여행 일수
        top_n: 반환할 코스 수

    Returns:
        {"result_courses": [...], "error": ""}  — router와 동일한 인터페이스
    """
    conn = get_db_connection()

    # 고른 일수와 **정확히 같은** 코스만 준다 (2026-09-10).
    #
    # 예전에는 ±1일이었다. 목록이 1,255개뿐이라 후보가 모자랄까 봐 넓혀둔 것인데,
    # 그 탓에 「2박3일」을 고른 사람에게 1박2일 코스가 뜨고 「당일치기」의 절반이
    # 1박2일로 왔다. 사용자는 이미 자기 여행에 맞는 일수를 고른 것이므로 그대로
    # 주는 게 맞다. 점수제를 없애면서 목록이 6,339개가 되어 정확히 맞춰도
    # 권역당 79~354개가 남는다.
    #
    # 예외는 앱의 마지막 선택지 「3박4일 이상」뿐이다. 이 옵션은 라벨 자체가
    # 「이상」이라 5일·6일 여행자도 여기를 고른다. 정확 매칭하면 5일 이상 코스
    # 692개가 영영 안 보이므로 위로 열어 둔다.
    #
    # 다만 일주일에서 끊는다. 원본에는 28일·21일짜리 일정도 있는데 그건 여행이
    # 아니라 한 달 살기다 — 4일 여행자에게 보여줄 것이 아니다. 8일 이상은
    # 4일 이상 코스 2,154개 중 48개(2%)뿐이라 잃는 것도 거의 없다.
    OPEN_ENDED_FROM = 4   # 앱의 마지막 선택지가 보내는 값 (TasteDiscoveryView)
    OPEN_ENDED_TO = 7     # 보통 여행의 상한. 그 위는 장기 체류라 성격이 다르다

    duration_min = duration_days
    duration_max = OPEN_ENDED_TO if duration_days >= OPEN_ENDED_FROM else duration_days

    # 부실 코스 걸러내기는 여기서 하지 않는다. 「이건 일정이 아니다」 판정은
    # 전부 빌드 단계(`build_curated_courses.py`)에 모여 있고, curated_courses에
    # 들어온 것은 이미 통과한 것이다. 같은 규칙을 두 곳에서 관리하지 않는다.
    if region == "전체":
        rows = conn.execute(
            """
            SELECT id, title, duration_days, region
            FROM curated_courses
            WHERE duration_days BETWEEN ? AND ?
            ORDER BY RANDOM()
            LIMIT ?
            """,
            (duration_min, duration_max, top_n * OVERFETCH),
        ).fetchall()
    else:
        # 요청 지역 코스 우선, 부족하면 "전체"로 분류된 코스로 보완.
        # 지역 우선순위 안에서는 무작위다.
        rows = conn.execute(
            """
            SELECT id, title, duration_days, region
            FROM curated_courses
            WHERE region IN (?, '전체')
              AND duration_days BETWEEN ? AND ?
            ORDER BY CASE WHEN region = ? THEN 0 ELSE 1 END, RANDOM()
            LIMIT ?
            """,
            (region, duration_min, duration_max, region, top_n * OVERFETCH),
        ).fetchall()

    if not rows:
        return {"result_courses": [], "error": "조건에 맞는 코스를 찾지 못했습니다."}

    # 순서도 무작위다. 점수제를 없앤 뒤로 코스 사이에 우열이 없어서, 화면의
    # 번호는 순위가 아니라 목록의 자리 표시다 (2026-09-10 결정).
    return {"result_courses": _with_places(conn, _dedupe_by_title(rows, top_n)), "error": ""}


def _dedupe_by_title(rows: list, limit: int) -> list:
    """제목이 같은 코스가 한 화면에 두 번 나오지 않게 한다.

    제목은 `{지역} {일수}일 · {대표장소} 외 N곳`으로 자동 생성되는데, 대표 장소와
    개수만 쓰다 보니 **6,339개 중 47%가 다른 코스와 제목이 겹친다.** 「북부 4일 ·
    산굼부리 외 10곳」은 70개나 된다. 내용은 서로 다르지만(장소 겹침 11~23%)
    사용자 눈에는 같은 카드 두 장으로 보인다.

    근본 해결은 제목에 장소를 하나 더 넣는 것인데, 그러면 40자를 넘어가
    첫 화면의 `LENGTH(title) <= 40` 필터에 걸린다. 제목 형식을 다시 잡기 전까지
    여기서 막는다.
    """
    seen: set[str] = set()
    out = []
    for row in rows:
        if row["title"] in seen:
            continue
        seen.add(row["title"])
        out.append(row)
        if len(out) >= limit:
            break
    return out


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

    names = display_names()
    places_by_course: dict[str, list[dict]] = {cid: [] for cid in course_ids}
    seen: set[tuple] = set()
    for p in place_rows:
        key = (p["course_id"], p["place_name"], p["day"])
        if key in seen:
            continue
        seen.add(key)
        places_by_course[p["course_id"]].append({
            "place_name": names.get(p["place_name"], p["place_name"]),
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

def run_featured_courses(limit: int = 5) -> dict[str, Any]:
    """조건 없이 둘러볼 코스를 무작위로 뽑는다. 부를 때마다 다른 코스가 나온다.

    ## 품질 하한이 없어졌다 (2026-09-10)

    예전에는 `composite_score >= 0.8`으로 한 번 더 걸렀다. 점수제를 없애면서
    이 하한도 사라졌다 — 「하루에 섬을 왕복하는」 코스는 이제 빌드 단계의
    이동거리 하드필터(`MAX_KM_PER_DAY`)가 막는다.

    ## 제목 필터도 걷어냈다 (2026-09-10)

    예전에는 제목에 괄호·언더바·날짜가 있으면 통째로 걸렀다. 원본 장소 이름이
    이랬기 때문이다:

        북부 1일 · 수목원테마파크_2025.11.11 영업종료(리모델링공사) / … 외 2곳
        북부 3일 · 이호테우해수욕장_old 외 7곳

    그런데 **제목만 깨진 것이지 코스는 멀쩡했다.** 그 필터에 1,200개가 같이
    빠지고 있었다. 지금은 장소 이름 자체를 정리해서 제목이 깨지지 않는다
    (`backend/scripts/build_place_display_names.py`).
    """
    conn = get_db_connection()

    rows = conn.execute(
        """
        SELECT id, title, duration_days, region
        FROM curated_courses
        ORDER BY RANDOM()
        LIMIT ?
        """,
        (limit * OVERFETCH,),
    ).fetchall()

    if not rows:
        return {"result_courses": [], "error": "보여줄 코스를 찾지 못했습니다."}

    return {"result_courses": _with_places(conn, _dedupe_by_title(rows, limit)), "error": ""}


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
