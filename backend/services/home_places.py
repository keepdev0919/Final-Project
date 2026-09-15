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

## 한 장소의 해설을 다 담는다

오디는 **장소가 아니라 해설 단위**로 데이터를 준다. 관음사는 일주문·사천왕문·대웅전…
**10개의 해설이 각각 좌표를 갖고 따로** 온다. 그래서 300m로 묶어 한 장소로 본다.

⚠️ **묶을 때 대표 하나만 남기고 버리면 안 된다.** 관음사 10개 중 9개가 사라지면
그 절을 눌렀을 때 들을 것이 하나로 줄고, 나중에 지점·미션을 만들 재료도 없어진다
(2026-08-26 조익준님 지적 — 실제로 그렇게 동작하고 있었다).

그래서 `stories`에 그 묶음의 해설을 **전부** 담는다. `story_seconds`는 **합계**이고,
`stid`·`story_title`은 목록에서 가장 가까운 것(대표)이다.

## 계산을 저장해 두는 이유

비짓제주 지점 146,357건 × 오디 178건을 매 요청마다 재계산할 수 없다.
`home_places` 테이블에 한 번 계산해 두고, 비면 채운다(`ensure_built`).
오디 연동은 2026-09-11 에 걷어냈다. 이 표는 그 전에 계산해 둔 값을 그대로 쓴다.

## 카드 사진을 테이블에 넣어 두는 이유

카드마다 KTO를 부르면 홈 한 번 열 때 호출이 10건 나가고, `/place/detail`의
분당 한도(30)에 스크롤 몇 번으로 걸린다. 캐시가 만료되는 1시간마다 첫 로딩이
3초씩 걸리기도 한다.

그래서 **고른 사진 주소를 `thumbnail`에 박아 둔다.** 채우는 것은
`warm_thumbnails()`이고 `scripts/warm_home_thumbnails.py`로 돌린다.
`build()`는 이 값을 **이름으로 이어받는다** — 순위를 다시 계산해도 사진이 날아가지 않는다.
"""
from __future__ import annotations

import json
import logging
import math
import os
import re
import time
from pathlib import Path

from services.db import get_db_connection

# 저장소 뿌리. `backend/services/home_places.py` → 두 단계 위.
BASE_DIR = Path(__file__).resolve().parents[2]

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

# 오디 제목에서 이름이 자동으로 안 뽑히는 곳을 손으로 적는 파일.
# 왼쪽이 `place_name_from_stories`가 뽑아낸 값, 오른쪽이 화면에 쓸 이름이다.
NAME_FILE = BASE_DIR / "data" / "place_names.json"


def name_overrides() -> dict[str, str]:
    """`data/place_names.json`의 손질 목록. 파일이 없으면 빈 채로 간다.

    키는 두 가지를 다 받는다.

    - **자동으로 뽑힌 이름** — 읽기 쉬워서 대부분 이걸로 적는다
    - **대표 해설 번호(stid)** — 자동 이름이 겹칠 때 쓴다. 오디에 감성 제목 시리즈가
      12건 따로 있어서 「가파도」와 「낭만적인 힐링의 섬, 가파도」가 **둘 다 「가파도」로**
      뽑히는 일이 생긴다. 이름으로 고치면 둘 다 바뀌므로 번호로 짚어야 한다.

    파일이 깨져도 앱은 돌아야 한다 — 이름이 조금 이상할 뿐 화면은 뜬다.
    """
    try:
        with open(NAME_FILE, encoding="utf-8") as f:
            return json.load(f).get("overrides", {})
    except FileNotFoundError:
        return {}
    except (OSError, ValueError):
        logger.exception("place_names.json을 읽지 못했다 — 자동으로 뽑은 이름을 쓴다")
        return {}

# 장소 이름과 KTO 이름이 다른 곳. 사진을 찾을 때만 쓴다 — 화면에는 비짓제주 이름이 뜬다.
#
# 자동으로 맞출 방법이 없어서 손으로 적는다. 띄어쓰기 하나 차이로 KTO 이름 검색이
# 빈 결과를 준다(`오설록티뮤지엄` → 0건, `오설록 티뮤지엄` → 1건). 상위권만 채워도 충분하다.
NAME_ALIASES = {
    "오설록티뮤지엄": "오설록 티뮤지엄",
    "에코랜드 테마파크": "에코랜드테마파크",
    "이호테우말등대": "이호테우해변",
    "세화해변": "세화해수욕장",
    "한라산국립공원": "한라산",
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


def place_name_from_stories(titles: list[str]) -> str:
    """오디 해설 제목에서 **장소 이름**을 뽑는다.

    오디 제목은 장소 이름이 아니라 **해설 제목**이다. 그래서 세 가지 손질이 필요하다.

    ① **여러 해설의 공통 접두어** — 관음사 10건이 「관음사 일주문」·「관음사 대웅전」…
       이므로 공통 부분이 곧 장소 이름이다. 실측으로 잘 맞는다:
       관음사 · 약천사 · 성읍민속마을 · 정방폭포 · 오설록 티 뮤지엄.

    ② **`수식어, 실제이름` 꼴** — 「낭만적인 힐링의 섬, 가파도」처럼 쉼표 뒤가 장소다.
       오디에 이런 감성 제목이 25건쯤 있다.

    ③ **분류 접두어** — 「열린관광지 - 제주도 ○○」, 「안도 코스 - ○○」의 앞부분.
       단, 접두어가 곧 장소인 경우(안도 코스 4건 묶음)는 ①이 먼저 잡는다.

    그래도 이상한 것은 `NAME_OVERRIDES`에 손으로 적는다. 자동으로 다 맞출 수 없고,
    **틀린 이름이 지도에 뜨는 것보다 손으로 몇 개 적는 편이 싸다.**
    """
    cleaned = [t.strip() for t in titles if t and t.strip()]
    if not cleaned:
        return ""

    if len(cleaned) > 1:
        prefix = os.path.commonprefix(cleaned).strip()
        prefix = re.sub(r"[\s\-–—·,]+$", "", prefix).strip()
        # 접두어가 너무 짧으면 장소 이름이 아니다(「제주」·「산방」처럼).
        if len(prefix) >= 3:
            return _strip_category_prefix(prefix)

    name = cleaned[0]
    # 「수식어, 실제이름」 — 쉼표가 하나뿐이고 뒤쪽이 짧을 때만 장소로 본다.
    if name.count(",") == 1:
        head, tail = (part.strip() for part in name.split(","))
        if tail and len(tail) <= len(head):
            name = tail
    return _strip_category_prefix(name)


# 오디가 제목 앞에 붙이는 분류 딱지. 장소 이름이 아니다.
_CATEGORY_PREFIXES = ("열린관광지 - 제주도", "열린관광지 -", "열린관광지")


def _strip_category_prefix(name: str) -> str:
    for prefix in _CATEGORY_PREFIXES:
        if name.startswith(prefix):
            return name[len(prefix):].strip(" -–—·") or name
    return name


def compute(conn) -> list[dict]:
    """장소 목록을 만든다 (저장하지 않는다).

    ## 오디가 전부다

    **묶음 하나 = 장소 하나**이고, 오디에 해설이 있는 곳은 하나도 빠지지 않는다.

    예전에는 비짓제주 장소 이름 목록을 훑으며 이름이 오디 묶음을 "차지"하게 했다.
    그러면 두 가지가 동시에 망가진다(2026-08-26 조익준님 지적) —
    ① 비짓제주에 이름이 없는 묶음 18곳(사려니숲길·가파도·알뜨르비행장…)이 **통째로 사라지고**
    ② 아무도 안 가져간 묶음을 근처 **식당이 가져간다**(자리돔횟집이 456m 떨어진
      「서귀포 기적의 도서관」 해설을 선점했다).

    ## 인기 점수를 계산하지 않는다

    한때 비짓제주 일정에서 "이 장소가 몇 번 담겼나"를 뽑아 순위를 매겼다. **걷어냈다.**

    그 숫자가 필요했던 이유는 **홈에 띄울 6곳을 고르는 것** 하나뿐이었는데, 그건
    손으로 고르면 되는 일이다(`data/home_stage.json`). 계산으로 하려니 오히려
    문제만 생겼다 — 좌표로 세면 도심이 부풀어 제주목관아가 성산일출봉을 이기고,
    가장 큰 이웃 값을 쓰면 목관아가 동문시장의 인기를 빌려온다.

    **정확하지도 않은 숫자를 계산하느라 146,357건을 훑을 이유가 없다.**
    유명한 곳이 어디인지는 사람이 안다.

    순서는 **해설이 많은 곳부터**다. 콘텐츠가 두꺼운 곳이 위로 온다는 뜻이고,
    바깥 데이터가 필요 없다.
    """
    stories = _load_stories(conn)
    if not stories:
        return []
    clusters = _cluster_ids(stories)

    stories_by_cluster: dict[int, list[dict]] = {}
    for idx, story in enumerate(stories):
        stories_by_cluster.setdefault(clusters[idx], []).append(story)

    overrides = name_overrides()
    places: list[dict] = []
    for group in stories_by_cluster.values():
        center_lat = sum(st["lat"] for st in group) / len(group)
        center_lng = sum(st["lng"] for st in group) / len(group)

        # 묶음 안에서는 중심에 가까운 순. 지점 순서를 정할 때의 출발점이 된다
        # (실제 걷는 순서는 콘텐츠를 만들 때 사람이 정한다).
        group = sorted(
            group,
            key=lambda st: _distance_m(center_lat, center_lng, st["lat"], st["lng"]),
        )
        auto_name = place_name_from_stories([st["title"] for st in group])
        # 번호로 짚은 것이 이름으로 짚은 것보다 우선한다 — 이름이 겹칠 때 쓰라고 둔 것이다.
        name = overrides.get(group[0]["stid"]) or overrides.get(auto_name) or auto_name

        places.append({
            "name": name,
            "lat": center_lat,
            "lng": center_lng,
            "stid": group[0]["stid"],
            "story_title": group[0]["title"],
            # ⚠️ 대표 하나가 아니라 **묶음 전체의 합계**다. 관음사는 10개를 더한 값이다.
            "story_seconds": sum(st["play_time"] or 0 for st in group),
            "story_count": len(group),
            "stories": [
                {
                    "stid": st["stid"],
                    "title": st["title"],
                    "seconds": st["play_time"] or 0,
                    "lat": st["lat"],
                    "lng": st["lng"],
                }
                for st in group
            ],
            # 묶음이 얼마나 퍼져 있나(가장 먼 해설까지). 값이 크면 서로 다른 곳이
            # 한 묶음이 됐을 수 있다 — 콘텐츠를 만들 때 사람이 갈라야 한다.
            "story_distance_m": round(max(
                _distance_m(center_lat, center_lng, st["lat"], st["lng"]) for st in group
            )),
        })

    places.sort(key=lambda p: (-p["story_count"], p["name"]))

    # 이름이 겹치면 어느 쪽이 홈에 연결될지 알 수 없다. 조용히 두지 않고 알린다.
    # 고치는 곳은 `data/place_names.json`이고, 겹칠 때는 stid로 짚는다.
    seen: dict[str, str] = {}
    for place in places:
        if place["name"] in seen:
            logger.error(
                "장소 이름이 겹친다: %r (stid %s ↔ %s). data/place_names.json에서 "
                "stid로 짚어 고칠 것", place["name"], seen[place["name"]], place["stid"],
            )
        seen[place["name"]] = place["stid"]
    return places


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
        "(rank, name, lat, lng, stid, story_title, story_seconds, "
        " story_count, stories, story_distance_m, thumbnail, built_at) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        [
            (i, p["name"], p["lat"], p["lng"], p["stid"],
             p["story_title"], p["story_seconds"], p["story_count"],
             json.dumps(p["stories"], ensure_ascii=False),
             p["story_distance_m"], p.get("thumbnail"), time.time())
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


def _row_to_place(row) -> dict:
    """DB 한 줄을 응답 모양으로. `stories`는 JSON 문자열이라 풀어서 내보낸다."""
    place = dict(row)
    try:
        place["stories"] = json.loads(place.get("stories") or "[]")
    except (TypeError, ValueError):
        logger.warning("home_places.stories 파싱 실패: %s", place.get("name"))
        place["stories"] = []
    return place


def top(limit: int = 10) -> list[dict]:
    """홈 카드용 상위 목록.

    ⚠️ 연결을 닫지 않는다. `get_db_connection()`은 스레드마다 하나를 만들어 **재사용**하므로,
    닫으면 닫힌 연결이 캐시에 남아 다음 요청이 전부 실패한다.
    """
    conn = get_db_connection()
    ensure_built(conn)
    rows = conn.execute(
        "SELECT name, lat, lng, stid, story_title, story_seconds, "
        "       story_count, stories, story_distance_m, thumbnail "
        "FROM home_places ORDER BY rank LIMIT ?",
        (limit,),
    ).fetchall()
    return [_row_to_place(r) for r in rows]


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
    사진 고르기는 사람이 해야 한다. 그래서 후보 전부를
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
