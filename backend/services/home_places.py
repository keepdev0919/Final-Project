"""홈 장소 카드 — 실제 여행자가 많이 담은 곳 중 해설이 있는 곳.

## 왜 두 데이터를 겹치나

홈 카드는 **눌러서 해설을 들을 수 있는 곳**이어야 한다. 그런데 "유명한 곳"의 순위는
오디 데이터에 없다. 오디는 해설이 있는지만 알려준다. 반대로 비짓제주 일정 9,134개는
"사람들이 실제로 어디를 갔나"를 알려주지만 해설이 있는지는 모른다.

그래서 **비짓제주 등장 빈도로 순위를 매기고, 오디 해설이 있는 곳만 남긴다.**
결과가 성산일출봉·섭지코지·천지연폭포처럼 우리가 아는 이름으로 나온다.

## 왜 이름을 비짓제주 쪽에서 가져오나

오디 제목은 대본 제목이라 장소 이름이 아니다 — 동문시장이 `"동문시장의 맛있는 이야기"`,
섭지코지가 `"안도 코스 - 방두포등대"`, 오설록이 `"티스톤"`으로 온다. 카드에 그대로 쓰면
어디인지 알 수 없다. **여행자가 부르는 이름(비짓제주)을 쓰고, 오디는 해설로만 쓴다.**

## 반경 700m

성산일출봉이 551m다 — 오디 좌표는 정상 부근이고 비짓제주 좌표는 주차장 쪽이다.
500m로 끊으면 **1위 장소가 목록에서 사라진다**(실측). 넉넉히 700m로 잡는다.
줄이면 유명한 곳이 빠지는지 먼저 확인할 것.

**대가가 있다.** 넓게 잡으면 옆 장소의 해설이 붙는다 — `에코랜드 테마파크`에
350m 떨어진 `교래자연휴양림` 해설이 붙었다(실측). 다른 곳이다.
그래서 `story_distance_m`를 같이 저장한다. **이 값이 큰 항목은 사람이 봐야 한다** —
콘텐츠를 채울 때 목록을 훑으며 어긋난 짝을 걷어낸다.

## 계산을 저장해 두는 이유

비짓제주 지점 146,357건 × 오디 178건을 매 요청마다 재계산할 수 없다.
`home_places` 테이블에 한 번 계산해 두고, 비면 채운다(`ensure_built`).
오디 목록이 갱신되면(`POST /odii/sync`) 같이 다시 계산한다.

## 카드 사진을 테이블에 넣어 두는 이유

카드마다 KTO를 부르면 홈 한 번 열 때 호출이 10건 나가고, `/place/detail`의
분당 한도(30)에 스크롤 몇 번으로 걸린다. 캐시가 만료되는 1시간마다 첫 로딩이
3초씩 걸리기도 한다.

그래서 **고른 사진 주소를 `thumbnail`에 박아 둔다.** 채우는 것은
`warm_thumbnails()`이고 `scripts/warm_home_thumbnails.py`로 돌린다.
`build()`는 이 값을 **이름으로 이어받는다** — 순위를 다시 계산해도 사진이 날아가지 않는다.
"""
from __future__ import annotations

import logging
import math
import re
import time

from services.db import get_db_connection

logger = logging.getLogger(__name__)

# 장소와 해설을 같은 곳으로 볼 최대 거리. 위 모듈 설명 참조.
STORY_RADIUS_M = 700.0

# 오디 해설을 여러 건 가진 한 장소를 한 카드로 묶을 거리.
CLUSTER_RADIUS_M = 300.0

# 관광지가 아닌 것. 등장 빈도 1위가 `제주국제공항`(4,621개 코스)이라 안 걸러내면
# 홈 첫 칸이 공항이 된다.
EXCLUDE_KEYWORDS = (
    "공항", "터미널", "렌터카", "버스", "정류장", "주차장", "휴게소", "면세점",
)

# 비짓제주 데이터에 남아 있는 옛 항목. 같은 장소가 두 번 보인다.
OLD_SUFFIX = "_old"

# 비짓제주 이름과 KTO 이름이 다른 곳. 사진을 찾을 때만 쓴다 — 화면에는 비짓제주 이름이 뜬다.
#
# 자동으로 맞출 방법이 없어서 손으로 적는다. 띄어쓰기 하나 차이로 KTO 이름 검색이
# 빈 결과를 준다(`오설록티뮤지엄` → 0건, `오설록 티뮤지엄` → 1건). 상위권만 채워도 충분하다.
NAME_ALIASES = {
    "오설록티뮤지엄": "오설록 티뮤지엄",
}


def clean_name(raw: str) -> str:
    """카드에 쓸 이름으로 다듬는다.

    비짓제주 이름에는 괄호 부가설명이 붙어 있다 —
    `성산일출봉(UNESCO 세계자연유산)` · `만장굴(안전점검 및 내부공사로 운영중단)`.
    카드에 그대로 넣으면 두 줄이 되고, 운영 상태 같은 건 시간이 지나면 거짓이 된다.
    """
    name = raw.strip()
    if name.endswith(OLD_SUFFIX):
        name = name[: -len(OLD_SUFFIX)]
    name = re.sub(r"\s*[（(][^)）]*[)）]\s*$", "", name).strip()
    return name or raw.strip()


def is_excluded(raw: str) -> bool:
    """관광지가 아니면 True."""
    return any(k in raw for k in EXCLUDE_KEYWORDS)


def _distance_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371000.0
    p1, l1, p2, l2 = map(math.radians, (lat1, lng1, lat2, lng2))
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin((l2 - l1) / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def _load_stories(conn) -> list[dict]:
    """대본 있는 한국어 오디 해설. 「초등 교과연계」는 뺀다.

    교과연계는 같은 장소의 어린이용 별도 대본이라, 두면 한 장소가 두 지점으로 보인다.
    """
    rows = conn.execute(
        "SELECT stid, title, lat, lng, play_time FROM odii_places "
        "WHERE has_script = 1 AND lang = 'ko' AND title NOT LIKE '%교과연계%' "
        "AND lat IS NOT NULL AND lng IS NOT NULL"
    ).fetchall()
    return [dict(r) for r in rows]


def _cluster_ids(stories: list[dict]) -> list[int]:
    """가까운 해설끼리 같은 묶음 번호를 준다 (union-find).

    관음사 10건처럼 한 장소를 여러 지점으로 쪼개 놓은 곳이 있다. 묶지 않으면
    같은 절이 카드 10개로 나온다.
    """
    parent = list(range(len(stories)))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for i in range(len(stories)):
        for j in range(i + 1, len(stories)):
            if _distance_m(stories[i]["lat"], stories[i]["lng"],
                           stories[j]["lat"], stories[j]["lng"]) <= CLUSTER_RADIUS_M:
                a, b = find(i), find(j)
                if a != b:
                    parent[a] = b
    return [find(i) for i in range(len(stories))]


def compute(conn) -> list[dict]:
    """순위표를 계산해서 돌려준다 (저장하지 않는다)."""
    stories = _load_stories(conn)
    if not stories:
        return []
    clusters = _cluster_ids(stories)

    places = conn.execute(
        "SELECT place_name, COUNT(DISTINCT course_id) AS course_count, "
        "       AVG(lat) AS lat, AVG(lng) AS lng "
        "FROM course_places "
        "WHERE in_jeju = 1 AND lat IS NOT NULL AND lng IS NOT NULL "
        "GROUP BY place_name ORDER BY course_count DESC"
    ).fetchall()

    # 한 묶음(같은 장소)에는 등장 빈도가 가장 높은 이름 하나만 남긴다.
    # 이호테우말등대·이호테우해수욕장·이호테우해수욕장_old가 다 같은 해설을 가리킨다.
    best_by_cluster: dict[int, dict] = {}
    for row in places:
        raw = row["place_name"]
        if is_excluded(raw):
            continue
        nearest, nearest_dist = None, STORY_RADIUS_M
        for idx, story in enumerate(stories):
            dist = _distance_m(row["lat"], row["lng"], story["lat"], story["lng"])
            if dist <= nearest_dist:
                nearest, nearest_dist = idx, dist
        if nearest is None:
            continue
        cluster = clusters[nearest]
        if cluster in best_by_cluster:
            continue  # 이미 더 인기 있는 이름이 이 묶음을 차지했다
        story = stories[nearest]
        best_by_cluster[cluster] = {
            "name": clean_name(raw),
            "lat": row["lat"],
            "lng": row["lng"],
            "course_count": row["course_count"],
            "stid": story["stid"],
            "story_title": story["title"],
            "story_seconds": story["play_time"] or 0,
            "story_distance_m": round(nearest_dist),
        }

    ranked = sorted(best_by_cluster.values(), key=lambda p: -p["course_count"])
    return ranked


def build(conn) -> int:
    """계산해서 `home_places`에 저장한다. 저장한 개수를 돌려준다.

    이미 받아둔 카드 사진은 이름을 기준으로 이어받는다. 순위를 다시 계산할 때마다
    KTO를 103번 다시 부르는 일을 막는다.
    """
    kept_thumbnails = {
        r["name"]: r["thumbnail"]
        for r in conn.execute(
            "SELECT name, thumbnail FROM home_places WHERE thumbnail IS NOT NULL"
        ).fetchall()
    }
    ranked = compute(conn)
    for place in ranked:
        place["thumbnail"] = kept_thumbnails.get(place["name"])
    conn.execute("DELETE FROM home_places")
    conn.executemany(
        "INSERT INTO home_places "
        "(rank, name, lat, lng, course_count, stid, story_title, story_seconds, "
        " story_distance_m, thumbnail, built_at) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        [
            (i, p["name"], p["lat"], p["lng"], p["course_count"], p["stid"],
             p["story_title"], p["story_seconds"], p["story_distance_m"],
             p.get("thumbnail"), time.time())
            for i, p in enumerate(ranked)
        ],
    )
    conn.commit()
    logger.info("home_places rebuilt: %d places", len(ranked))
    return len(ranked)


def ensure_built(conn) -> None:
    """비어 있으면 채운다."""
    count = conn.execute("SELECT COUNT(*) FROM home_places").fetchone()[0]
    if count == 0:
        build(conn)


def top(limit: int = 10) -> list[dict]:
    """홈 카드용 상위 목록.

    ⚠️ 연결을 닫지 않는다. `get_db_connection()`은 스레드마다 하나를 만들어 **재사용**하므로,
    닫으면 닫힌 연결이 캐시에 남아 다음 요청이 전부 실패한다.
    """
    conn = get_db_connection()
    ensure_built(conn)
    rows = conn.execute(
        "SELECT name, lat, lng, course_count, stid, story_title, story_seconds, "
        "       story_distance_m, thumbnail "
        "FROM home_places ORDER BY rank LIMIT ?",
        (limit,),
    ).fetchall()
    return [dict(r) for r in rows]


def warm_thumbnails(conn, limit: int = 20) -> dict[str, int]:
    """상위 `limit`곳의 카드 사진을 KTO에서 받아 저장한다.

    사진이 이미 있는 항목은 건너뛴다. 실패한 항목은 비워 두고 넘어간다 —
    한 곳이 안 나온다고 나머지를 못 받으면 안 된다.

    ## 어떤 곳인지 찾는 일은 `find_sight_content_id`가 한다

    이름 검색과 좌표 검색을 둘 다 쓰고 거리로 검증한다. 이유는 그 함수 설명 참조 —
    한쪽만 쓰면 천지연폭포가 빠지거나 성산일출봉에 식당 사진이 붙는다.

    ## 고른 사진이 최선은 아니다

    KTO 대표 사진(`firstimage`)을 먼저 쓰고 없으면 갤러리 첫 장을 쓴다.
    그런데 성산일출봉은 대표 사진도 **표석과 안내판이 앞을 가린 사진**이다.
    사진 고르기는 사람이 해야 한다(`DESIGN.md` §10). 그래서 후보 전부를
    `thumbnail_candidates`에 함께 저장해 둔다 — 나중에 골라 바꿀 수 있게.
    """
    import json

    from routers.place import _fetch_detail, _fetch_images, find_sight_content_id

    # ⚠️ `rank < limit`이다. `LIMIT ?`만 쓰면 "빈 칸 N개"가 되어 30위권 사진을 받는 동안
    # 상위 10곳이 비어 있는 일이 생긴다. 우리가 원하는 건 **상위 N곳**이다.
    rows = conn.execute(
        "SELECT rank, name, lat, lng FROM home_places "
        "WHERE thumbnail IS NULL AND rank < ? ORDER BY rank",
        (limit,),
    ).fetchall()

    filled = 0
    for row in rows:
        try:
            search_name = NAME_ALIASES.get(row["name"], row["name"])
            found = find_sight_content_id(search_name, row["lat"], row["lng"])
            if not found:
                continue

            candidates: list[str] = []
            representative = (_fetch_detail(found[0]) or {}).get("firstimage") or ""
            if representative:
                candidates.append(representative)
            for url in _fetch_images(found[0]):
                if url not in candidates:
                    candidates.append(url)
            if not candidates:
                continue

            conn.execute(
                "UPDATE home_places SET thumbnail = ?, thumbnail_candidates = ? "
                "WHERE rank = ?",
                (candidates[0], json.dumps(candidates, ensure_ascii=False), row["rank"]),
            )
            filled += 1
        except Exception:  # noqa: BLE001
            logger.warning("home_places 썸네일 실패: %s", row["name"], exc_info=True)
    conn.commit()
    return {"tried": len(rows), "filled": filled}
