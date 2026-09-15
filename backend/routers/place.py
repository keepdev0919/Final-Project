"""장소 상세 정보 — KTO API로 사진·설명 조회 (GPS 기반 contentId 탐색)."""
from __future__ import annotations

import math
import re
import difflib
import json as _json
import logging
import os
import time
import urllib.parse
import urllib.request
from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from services.image_url import all_to_https
from services.db import get_db_connection
from routers.tourist import _kto_get, CACHE_TTL  # tourist.py와 중복 방지

router = APIRouter(prefix="/place", tags=["place"])
limiter = Limiter(key_func=get_remote_address)
logger = logging.getLogger(__name__)


# 장소 종류(contentTypeId). 실측 값이다.
#   12 관광지 · 14 문화시설 · 15 축제행사 · 25 여행코스 · 28 레포츠
#   32 숙박 · 38 쇼핑 · 39 음식점
#
# 38(쇼핑)을 넣는다 — 동문재래시장·서귀포매일올레시장은 제주 관광의 축이고 오디 해설도 있다.
# 면세점 같은 것은 이름 규칙(`home_places.EXCLUDE_KEYWORDS`)이 먼저 걸러낸다.
# 32(숙박)·39(음식점)은 넣지 않는다 — 관광지 근처에 널려서 이름이 비슷하면 이겨버린다.
SIGHT_CONTENT_TYPES = frozenset({"12", "14", "25", "28", "38"})


def _nearby_content_id(
    name: str,
    lat: float,
    lng: float,
    radius: int,
    allowed_types: frozenset[str] | None,
) -> tuple[str, str] | None:
    """좌표 반경 검색으로 (contentId, contentTypeId). **이름이 맞는 것만** 준다.

    전에는 이름이 하나도 안 맞으면 **가장 가까운 것을 대신 썼다.** 그래서
    `해녀의부엌 종달점`을 물으면 KTO 에 없으니 바로 옆 `종달리해변` 사진과 설명이
    붙었다 (2026-09-10 실측). 화면은 멀쩡해 보여서 눌러봐도 안 잡힌다.
    **틀린 정보가 붙는 것보다 없는 게 낫다** — 그 폴백은 없앴다.

    ## 반경을 넓힐 때 종류도 같이 조여야 하는 이유

    성산일출봉 좌표에서 반경 2km를 부르면 후보 10개 중 9개가 식당·펜션이고,
    `성산흑돼지두루치기 성산일출봉점`(음식점)이 이름 포함으로 잡힐 수 있다.
    관광지를 찾는 자리(홈·PLAY)는 `allowed_types=SIGHT_CONTENT_TYPES` 로 막는다.
    코스 장소 상세는 식당·카페도 보여줘야 하므로 `None`(제한 없음)으로 부른다.
    """
    try:
        data = _kto_get("KorService2", "locationBasedList2", {
            "mapX": lng,
            "mapY": lat,
            "radius": radius,
            "numOfRows": 10,
        })
        items = data["response"]["body"]["items"]
        if not items or items == "":
            return None
        raw_items = items.get("item")
        if not raw_items:
            return None
        item_list = raw_items if isinstance(raw_items, list) else [raw_items]

        if allowed_types is not None:
            item_list = [
                it for it in item_list
                if str(it.get("contenttypeid", "")) in allowed_types
            ]
        best = _pick_by_name(name, item_list)
        if best is None:
            return None
        return best["contentid"], str(best.get("contenttypeid", "12"))
    except Exception as e:
        logger.warning("KTO _nearby_content_id failed for %s: %s", name, e)
        return None


def _pick_by_name(name: str, item_list: list[dict]) -> dict | None:
    """이름이 가장 잘 맞는 후보. 없으면 None.

    ① 완전히 같음 → ② 이름으로 시작함 → ③ 이름을 품고 있음 → ④ 유사도(0.6 이상).

    ④의 문턱을 0.6으로 잡는다. 예전 값 0.3은 너무 느슨해서 `성산일출봉`이
    `성산해촌`(식당)에도 걸렸다.
    """
    titles = {it["title"]: it for it in item_list if it.get("title")}
    if name in titles:
        return titles[name]
    for title, it in titles.items():
        if title.startswith(name):
            return it
    for title, it in titles.items():
        if name in title:
            return it
    close = difflib.get_close_matches(name, list(titles), n=1, cutoff=0.6)
    return titles[close[0]] if close else None


def _fetch_detail(content_id: str) -> dict:
    """contentId로 상세 정보(overview, 사진, 주소) 조회.

    ⚠️ 파라미터를 추가하지 말 것. `overviewYN`·`defaultYN`·`addrinfoYN`은
    KorService1 것이며, KorService2에 보내면 INVALID_REQUEST_PARAMETER_ERROR로
    **호출 전체가 실패한다.** 2026-08-19까지 이 상태였고, 실패해도 빈 값으로
    200을 반환해서 "설명 없는 장소"처럼 보였다.
    """
    try:
        data = _kto_get("KorService2", "detailCommon2", {
            "contentId": content_id,
        })
        item = data["response"]["body"]["items"]["item"]
        if isinstance(item, list):
            item = item[0]
        return item
    except Exception as e:
        logger.warning("KTO _fetch_detail failed for content_id=%s: %s", content_id, e)
        return {}


def _fetch_images(content_id: str) -> list[str]:
    """contentId로 사진 URL 최대 5장 조회."""
    try:
        data = _kto_get("KorService2", "detailImage2", {
            "contentId": content_id,
            "imageYN": "Y",
            "numOfRows": 5,
        })
        items = data["response"]["body"]["items"]
        if not items or items == "":
            return []
        raw_items = items.get("item")
        if not raw_items:
            return []
        item_list = raw_items if isinstance(raw_items, list) else [raw_items]
        return [it["originimgurl"] for it in item_list if it.get("originimgurl")]
    except Exception as e:
        logger.error("KTO _fetch_images 실패 content_id=%s: %s", content_id, e)
        return []


# detailIntro2는 **장소 종류마다 칸 이름이 다르다.** 실측(2026-08-19):
#
#   12 관광지   usetime          restdate           parking          infocenter
#   14 문화시설  usetimeculture   restdateculture    parkingculture   infocenterculture  usefee
#   15 축제행사  usetimefestival  (playtime)         —                sponsor1tel
#   32 숙박     checkintime      —                  parkinglodging   infocenterlodging
#   38 쇼핑     opentime         restdateshopping   parkingshopping  infocentershopping
#   39 음식점   opentimefood     restdatefood       parkingfood      infocenterfood
#
# 종류별로 일일이 적으면 새 종류가 나올 때마다 조용히 빈 값이 된다
# (기존 코드가 `opentime`만 봐서 관광지 운영시간이 항상 비어 있었다).
# 그래서 이름을 정확히 맞추지 않고 **앞부분이 같은 칸을 찾는다.**
_INTRO_FIELDS = {
    "open_time": ("usetime", "opentime", "checkintime"),
    "rest_date": ("restdate",),
    "use_fee":   ("usefee",),
    "parking":   ("parking",),
    "tel":       ("infocenter", "sponsor1tel"),
}
# "parking"으로 시작하지만 주차 가능 여부가 아닌 칸.
_INTRO_EXCLUDE = {"parkingfee"}


def _pick(item: dict, prefixes: tuple[str, ...]) -> str:
    """앞부분이 일치하는 칸 중 값이 있는 첫 번째를 돌려준다."""
    for prefix in prefixes:
        for key, value in item.items():
            if key in _INTRO_EXCLUDE or not key.startswith(prefix):
                continue
            text = str(value).strip()
            if text:
                return text
    return ""


def _fetch_intro(content_id: str, content_type_id: str) -> dict:
    """운영시간·휴무·입장료·주차·전화 조회. 없는 칸은 빈 문자열."""
    empty = {k: "" for k in _INTRO_FIELDS}
    try:
        data = _kto_get("KorService2", "detailIntro2", {
            "contentId": content_id,
            "contentTypeId": content_type_id,
        })
        item = data["response"]["body"]["items"]["item"]
        if isinstance(item, list):
            item = item[0]
        # 반복정보·무장애와 같은 정리를 거친다. 전에는 이 네 칸만 빠져 있어서
        # 성산일출봉 운영시간에 `<br>` 이 글자로 찍혔다 (2026-09-10 발견).
        return {name: _clean_text(_pick(item, prefixes)) for name, prefixes in _INTRO_FIELDS.items()}
    except Exception as e:
        logger.error("KTO _fetch_intro 실패 content_id=%s type=%s: %s", content_id, content_type_id, e)
        return empty


def _clean_text(value) -> str:
    """KTO 값의 `<br>`·줄바꿈을 정리하고, **붙어서 온 줄을 다시 끊는다.**

    KTO 는 같은 칸을 장소마다 다르게 준다 (2026-09-10 실측):

    - 성산일출봉 운영시간: `- 1~2월 …<br>- 3~4월 …` — `<br>` 로 줄이 나뉜다.
    - 카멜리아힐 운영시간: `[하절기]- 08:30~18:30- 입장 마감 17:30[동절기]- …`
      — 줄바꿈이 **아예 없다.** 원래 줄이었던 것이 붙어서 온다.

    그래서 `<br>` 만 바꾸지 않고 `[머리]` 앞과 `- 항목` 앞에서도 줄을 끊는다.
    `10:00 - 18:00` 처럼 앞에 공백이 있는 `-` 는 범위 표시라 건드리지 않는다.
    """
    text = str(value or "")
    for br in ("<br>", "<br/>", "<br />", "<BR>"):
        text = text.replace(br, "\n")
    # 줄이 **하나도 없는** 값만 되살린다. `<br>` 로 이미 나뉜 값은 그대로 둔다 —
    # 거기서 `- ` 를 다시 끊으면 「안내 가능- 시간 : …」 같은 문장이 반만 갈라진다.
    if "\n" not in text:
        # `17:30[동절기]- ` · `17:00 [3월/…] - ` → 머리 앞에서 끊는다.
        # 뒤에 항목 표시 `-` 나 끝이 올 때만 머리다 — `성산일출봉입구[서] 정류장` 의
        # `[서]` 는 방향 표기라 두어야 한다.
        text = re.sub(r"(?<=\S)\s*(\[[^\]\n]{1,24}\])(?=\s*-|\s*$)", r"\n\1", text)
        # `]- 08:30` · `17:30- 입장 마감` · `가능- 시간` → 항목 앞에서 끊는다.
        # `09:00- 18:00` 처럼 숫자 사이에 낀 것은 범위 표시라 둔다.
        text = re.sub(r"(?<=[^\s\d])\s*- (?=\S)", "\n- ", text)
        text = re.sub(r"(?<=\d)\s*- (?=[^\s\d])", "\n- ", text)
    return "\n".join(line.strip() for line in text.split("\n") if line.strip())


def _reclean_rows(rows: list[dict]) -> list[dict]:
    """캐시에 원문 그대로 남은 반복정보·무장애 줄도 지금 규칙으로 다시 정리한다."""
    return [{**row, "value": _clean_text(row.get("value", ""))} for row in rows]


def _fetch_info(content_id: str, content_type_id: str) -> list[dict]:
    """반복정보(detailInfo2) — 화장실·주차요금·해설 안내처럼 장소마다 다른 항목.

    관광지(12)는 `입 장 료`·`화장실`·`주차요금`·`한국어안내서비스` 같은 것이 오고,
    시장·카페는 대개 비어 있다 (2026-09-10 실측). 이름표는 KTO 가 띄어 쓴 그대로
    (`입 장 료`)라 공백을 지운다.
    """
    try:
        data = _kto_get("KorService2", "detailInfo2", {
            "contentId": content_id,
            "contentTypeId": content_type_id,
            "numOfRows": 20,
        })
        items = data["response"]["body"].get("items") or {}
        raw = items.get("item") if isinstance(items, dict) else None
        if not raw:
            return []
        rows = raw if isinstance(raw, list) else [raw]
        out = []
        for it in rows:
            label = str(it.get("infoname", "")).replace(" ", "").strip()
            value = _clean_text(it.get("infotext", ""))
            if label and value:
                out.append({"label": label, "value": value})
        return out
    except Exception as e:
        logger.warning("KTO _fetch_info failed for content_id=%s: %s", content_id, e)
        return []


# 무장애 여행정보(KorWithService2 detailWithTour2)의 칸 이름 → 화면 이름표.
# contentId 는 일반 관광정보와 **같은 번호**를 쓴다 (2026-09-10 실측: 협재 127490).
# 값은 자유 서술이고 뒤에 `_무장애 편의시설` 같은 꼬리가 붙는다 — 떼고 보여준다.
_ACCESSIBILITY_FIELDS = (
    ("parking",            "장애인 주차"),
    ("route",              "접근로"),
    ("publictransport",    "대중교통"),
    ("ticketoffice",       "매표소"),
    ("exit",               "출입구"),
    ("elevator",           "엘리베이터"),
    ("restroom",           "장애인 화장실"),
    ("wheelchair",         "휠체어 대여"),
    ("stroller",           "유모차 대여"),
    ("braileblock",        "점자블록"),
    ("brailepromotion",    "점자 안내물"),
    ("audioguide",         "음성 안내"),
    ("videoguide",         "수어·영상 안내"),
    ("guidehuman",         "안내 인력"),
    ("helpdog",            "안내견 동반"),
    ("lactationroom",      "수유실"),
    ("infantsfamilyetc",   "유아 편의"),
    ("blindhandicapetc",   "시각장애 편의"),
    ("hearinghandicapetc", "청각장애 편의"),
    ("handicapetc",        "기타 편의"),
)


def _fetch_accessibility(content_id: str) -> list[dict]:
    """무장애 정보. 등록 안 된 장소는 빈 목록 — 제주는 181곳이 등록돼 있다 (2026-09-10)."""
    try:
        data = _kto_get("KorWithService2", "detailWithTour2", {"contentId": content_id})
        items = data["response"]["body"].get("items") or {}
        raw = items.get("item") if isinstance(items, dict) else None
        if not raw:
            return []
        item = raw[0] if isinstance(raw, list) else raw
        out = []
        for key, label in _ACCESSIBILITY_FIELDS:
            value = _clean_text(item.get(key, ""))
            if "_" in value:
                value = value.split("_", 1)[0].strip()
            if value:
                out.append({"label": label, "value": value})
        return out
    except Exception as e:
        logger.warning("KTO _fetch_accessibility failed for content_id=%s: %s", content_id, e)
        return []


@router.get("/detail")
@limiter.limit("30/minute")
def get_place_detail(request: Request, name: str, lat: float, lng: float):
    """장소명 + 관광지 좌표로 KTO 사진·설명·이용팁 조회 (1시간 캐시).

    받는 lat/lng는 **관광지 자체의 좌표**다(호출부: PlaceDetailView가
    place.lat/place.lng를 넘긴다). 사용자 위치가 아니므로 개인위치정보에
    해당하지 않는다. 이 성질을 깨뜨리지 말 것.
    """
    conn = get_db_connection()

    _lat = round(lat, 5)
    _lng = round(lng, 5)
    cached = conn.execute(
        "SELECT * FROM place_detail_cache WHERE name = ? AND lat = ? AND lng = ?",
        (name, _lat, _lng),
    ).fetchone()
    if cached and (time.time() - cached["cached_at"]) < CACHE_TTL:
        return {
            "name":             cached["name"],
            "overview":         cached["overview"] or "",
            # KTO 는 http 로 준다 — iOS 가 막으므로 나갈 때 https 로 올린다.
            "images":           all_to_https(_json.loads(cached["images"] or "[]")),
            "address":          cached["address"] or "",
            "tel":              cached["tel"] or "",
            # 정리 규칙이 바뀌기 전에 캐시된 줄도 있어, 나갈 때 한 번 더 정리한다.
            "open_time":        _clean_text(cached["open_time"]),
            "rest_date":        _clean_text(cached["rest_date"]),
            "use_fee":          _clean_text(cached["use_fee"]),
            "parking":          _clean_text(cached["parking"]),
            "info":             _reclean_rows(_json.loads(cached["info"] or "[]")),
            "accessibility":    _reclean_rows(_json.loads(cached["accessibility"] or "[]")),
        }

    # 종류 제한 없음 — 코스에는 식당·카페가 들어 있다. 이름이 안 맞으면 None 이다.
    result = find_content_id(name, lat, lng)
    if not result:
        # KTO 에 없는 장소(공항·작은 가게 등)는 빈 필드로 200 반환 — iOS 는 있는 정보만
        # 표시한다. 옆 관광지 정보를 대신 붙이지 않는다.
        return {"name": name, "overview": "", "images": [], "address": "",
                "tel": "", "open_time": "", "rest_date": "", "use_fee": "", "parking": "",
                "info": [], "accessibility": []}
    content_id, content_type_id = result

    detail  = _fetch_detail(content_id)
    images  = _fetch_images(content_id)
    first   = detail.get("firstimage", "")
    if first and first not in images:
        images = [first] + images
    intro   = _fetch_intro(content_id, content_type_id)
    info    = _fetch_info(content_id, content_type_id)
    access  = _fetch_accessibility(content_id)

    overview = detail.get("overview", "")
    address  = detail.get("addr1", "")
    # 성산일출봉처럼 detailCommon2의 tel이 비고 detailIntro2의 infocenter에만
    # 번호가 있는 장소가 많다. 둘 중 있는 쪽을 쓴다.
    tel      = detail.get("tel", "") or intro.get("tel", "")

    conn.execute(
        """INSERT OR REPLACE INTO place_detail_cache
           (name, lat, lng, overview, images, address, tel,
            open_time, rest_date, use_fee, parking, content_type_id, cached_at,
            info, accessibility)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (name, _lat, _lng, overview, _json.dumps(images, ensure_ascii=False),
         address, tel,
         intro["open_time"], intro["rest_date"], intro["use_fee"], intro["parking"],
         content_type_id, time.time(),
         _json.dumps(info, ensure_ascii=False), _json.dumps(access, ensure_ascii=False)),
    )
    conn.commit()

    return {
        "name":      name,
        "overview":  overview,
        "images":    all_to_https(images),
        "address":   address,
        "tel":       tel,
        "open_time": intro["open_time"],
        "rest_date": intro["rest_date"],
        "use_fee":   intro["use_fee"],
        "parking":   intro["parking"],
        "info":      info,
        "accessibility": access,
    }


# 이름으로 찾은 후보가 우리가 아는 좌표에서 이만큼 넘게 떨어져 있으면 다른 곳이다.
# `우도`로 검색하면 전남 강진의 `가우도`가, `주상절리대`로 검색하면 광주 `무등산 주상절리대`가
# 온다(실측). 제주 안이라도 5km를 넘으면 같은 장소로 보기 어렵다.
NAME_SEARCH_MAX_DISTANCE_M = 5000.0


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371000.0
    p1, l1, p2, l2 = map(math.radians, (lat1, lng1, lat2, lng2))
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin((l2 - l1) / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def _search_by_keyword(name: str) -> list[dict]:
    """이름으로 KTO를 검색한다.

    ⚠️ **`areaCode`를 보내지 말 것.** `areaCode=39`(제주)를 붙이면 천지연폭포·카멜리아힐·
    오설록 티뮤지엄이 **빈 결과로 돌아온다**(2026-08-22 실측). 붙이지 않으면 정상이다.
    지역 제한은 아래 거리 검증이 대신한다.
    """
    try:
        data = _kto_get("KorService2", "searchKeyword2", {
            "keyword": name,
            "numOfRows": 10,
        })
        items = data["response"]["body"]["items"]
        if not items or items == "":
            return []
        raw = items.get("item")
        if not raw:
            return []
        return raw if isinstance(raw, list) else [raw]
    except Exception as e:  # noqa: BLE001
        logger.warning("KTO _search_by_keyword failed for %s: %s", name, e)
        return []


def find_content_id(
    name: str,
    lat: float,
    lng: float,
    allowed_types: frozenset[str] | None = None,
) -> tuple[str, str] | None:
    """장소 하나의 (contentId, contentTypeId). 못 찾으면 None.

    좌표 검색만으로는 부족하고 이름 검색만으로도 부족하다. **둘 다 쓴다.**

    | 방식 | 잘 되는 것 | 안 되는 것 |
    |---|---|---|
    | 이름 검색 | 천지연폭포·카멜리아힐 — 좌표 검색에 아예 안 잡히는 곳 | `우도`→`가우도`(전남), `주상절리대`→`무등산 주상절리대`(광주) |
    | 좌표 검색 | 이름이 데이터와 다른 곳(`오설록티뮤지엄`↔`오설록 티뮤지엄`) | 주변에 식당이 많으면 관광지가 10개 안에 안 들어온다 |

    그래서 **이름으로 먼저 찾고 거리로 검증**하고, 없으면 좌표로 찾는다.
    어느 길로 가든 **이름이 맞는 것만** 받는다 — 안 맞으면 None 이다.

    `allowed_types` 로 종류를 좁힌다. 홈·PLAY 처럼 관광지를 찾는 자리는
    `SIGHT_CONTENT_TYPES`(`find_sight_content_id`), 코스 장소 상세처럼 식당·카페도
    보여줘야 하는 자리는 None.
    """
    for item in _search_by_keyword(name):
        if allowed_types is not None and str(item.get("contenttypeid", "")) not in allowed_types:
            continue
        try:
            item_lat, item_lng = float(item["mapy"]), float(item["mapx"])
        except (KeyError, TypeError, ValueError):
            continue
        if _haversine_m(lat, lng, item_lat, item_lng) > NAME_SEARCH_MAX_DISTANCE_M:
            continue
        if _pick_by_name(name, [item]) is None:
            continue
        return item["contentid"], str(item.get("contenttypeid", "12"))

    for radius in (500, 2000):
        found = _nearby_content_id(name, lat, lng, radius, allowed_types)
        if found:
            return found
    return None


def find_sight_content_id(name: str, lat: float, lng: float) -> tuple[str, str] | None:
    """관광지 계열만 받는 `find_content_id`. 홈·PLAY 가 쓴다 — 안 그러면 성산일출봉
    카드에 `성산흑돼지두루치기 성산일출봉점` 사진이 붙는다."""
    return find_content_id(name, lat, lng, allowed_types=SIGHT_CONTENT_TYPES)


# =============================================================================
# 주변 시설 — 공중화장실(제주시) · 버스정류장(국토교통부 TAGO)
# =============================================================================
#
# 젠트립이 관광지 상세에서 보여주는 「주변 화장실·정류장」과 같은 자리
# (2026-09-10 조익준님 결정). 가이드 없이 혼자 다니는 여행자가 현장에서 실제로
# 찾는 것이라 장소 정보 탭에 둔다.
#
# ⚠️ **조회 기준은 관광지 좌표다.** 사용자 위치를 서버로 보내지 않는다 —
# 그 순간 개인위치정보를 다루는 위치기반서비스사업이 되어 신고 대상이 된다.
#
# | 데이터 | 출처 | 방식 |
# |---|---|---|
# | 공중화장실 | 제주특별자치도 제주시 (data.go.kr 15109235) | 반경 조회가 없어 415곳 전체를 하루 한 번 받아 두고 거리로 거른다. **제주시 관할만** 있다 — 서귀포시는 공공데이터포털에 API 가 없다 (2026-09-10) |
# | 버스정류장 | 국토교통부 TAGO (data.go.kr 15098534) | 좌표 기준 근접 정류소(반경 500m). 제주 도시코드 39 |
#
# 전국공중화장실표준데이터는 2025년 2월부터 좌표가 빠져 쓸 수 없다.

PUBLIC_KEY = os.getenv("KTO_API_KEY", "")   # 공공데이터포털 계정 하나로 같은 키를 쓴다
TOILET_URL = "https://apis.data.go.kr/6510000/publicToiletService/getPublicToiletInfoList"
BUS_URL = "https://apis.data.go.kr/1613000/BusSttnInfoInqireService/getCrdntPrxmtSttnList"
NEARBY_RADIUS_M = 1000.0
NEARBY_LIMIT = 5
TOILET_LIST_TTL = 24 * 3600
NEARBY_TTL = 3600

_toilet_cache: dict = {"items": [], "at": 0.0}
_nearby_cache: dict[tuple[float, float], tuple[float, dict]] = {}


def _public_get(url: str, params: dict) -> dict:
    params = dict(params, serviceKey=PUBLIC_KEY)
    with urllib.request.urlopen(f"{url}?{urllib.parse.urlencode(params)}", timeout=15) as r:
        return _json.loads(r.read())


def _float(value) -> float | None:
    """`126..42388329` 처럼 깨진 좌표가 섞여 있다 (2026-09-10 실측 6건). 못 읽으면 None."""
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _jeju_toilets() -> list[dict]:
    """제주시 공중화장실 전체. 하루 한 번만 받는다."""
    now = time.time()
    if _toilet_cache["items"] and now - _toilet_cache["at"] < TOILET_LIST_TTL:
        return _toilet_cache["items"]
    try:
        data = _public_get(TOILET_URL, {"pageNo": 1, "numOfRows": 500, "type": "json"})
        raw = data["response"]["body"]["items"]["item"]
        items = raw if isinstance(raw, list) else [raw]
    except Exception as e:  # noqa: BLE001
        logger.warning("제주시 화장실 목록 실패: %s", e)
        return _toilet_cache["items"]
    _toilet_cache.update(items=items, at=now)
    return items


def _toilets_near(lat: float, lng: float) -> list[dict]:
    out = []
    for it in _jeju_toilets():
        t_lat, t_lng = _float(it.get("laCrdnt")), _float(it.get("loCrdnt"))
        if t_lat is None or t_lng is None:
            continue
        dist = _haversine_m(lat, lng, t_lat, t_lng)
        if dist > NEARBY_RADIUS_M:
            continue
        accessible = any(
            (_float(it.get(k)) or 0) > 0
            for k in ("maleDspsnClosetCnt", "femaleDspsnClosetCnt")
        )
        out.append({
            "name": str(it.get("toiletNm", "")).strip(),
            "distance_m": int(dist),
            "lat": t_lat, "lng": t_lng,
            "open_time": str(it.get("opnTimeInfo", "")).strip(),
            "accessible": accessible,
        })
    return _closest_unique(out)


def _bus_stops_near(lat: float, lng: float) -> list[dict]:
    try:
        data = _public_get(BUS_URL, {"gpsLati": lat, "gpsLong": lng, "numOfRows": 30, "_type": "json"})
        items = data["response"]["body"].get("items") or {}
        raw = items.get("item") if isinstance(items, dict) else None
        if not raw:
            return []
        rows = raw if isinstance(raw, list) else [raw]
    except Exception as e:  # noqa: BLE001
        logger.warning("TAGO 정류장 실패 lat=%s lng=%s: %s", lat, lng, e)
        return []
    out = []
    for it in rows:
        s_lat, s_lng = _float(it.get("gpslati")), _float(it.get("gpslong"))
        if s_lat is None or s_lng is None:
            continue
        out.append({
            "name": str(it.get("nodenm", "")).strip(),
            "distance_m": int(_haversine_m(lat, lng, s_lat, s_lng)),
            "lat": s_lat, "lng": s_lng,
        })
    return _closest_unique(out)


def _closest_unique(rows: list[dict]) -> list[dict]:
    """가까운 순으로, **같은 이름은 하나만**, 최대 `NEARBY_LIMIT`.

    정류장은 길 양쪽에 같은 이름으로 두 개씩 있고(`용마로` ×2), 해수욕장 관리센터
    화장실은 같은 이름으로 세 개가 등록돼 있다. 다 늘어놓으면 다섯 줄이 두 이름이다.
    """
    rows = sorted(rows, key=lambda r: r["distance_m"])
    seen: set[str] = set()
    out = []
    for r in rows:
        if r["name"] in seen:
            continue
        seen.add(r["name"])
        out.append(r)
        if len(out) >= NEARBY_LIMIT:
            break
    return out


@router.get("/nearby")
@limiter.limit("30/minute")
def get_place_nearby(request: Request, lat: float, lng: float):
    """관광지 좌표 주변 1km 의 공중화장실과 정류장. 좌표별 1시간 캐시."""
    key = (round(lat, 4), round(lng, 4))
    now = time.time()
    hit = _nearby_cache.get(key)
    if hit and now - hit[0] < NEARBY_TTL:
        return hit[1]
    result = {
        "toilets": _toilets_near(lat, lng),
        "bus_stops": _bus_stops_near(lat, lng),
    }
    _nearby_cache[key] = (now, result)
    return result
