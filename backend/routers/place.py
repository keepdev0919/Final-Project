"""장소 상세 정보 — KTO API로 사진·설명 조회 (GPS 기반 contentId 탐색)."""
from __future__ import annotations

import math
import difflib
import json as _json
import logging
import time
from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
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


def _find_content_id(
    name: str,
    lat: float,
    lng: float,
    radius: int = 500,
    require_name_match: bool = False,
    allowed_types: frozenset[str] | None = None,
) -> tuple[str, str] | None:
    """GPS 반경 검색으로 (contentId, contentTypeId) 반환.

    ## 반경을 넓힐 때 함께 조여야 하는 것

    `radius`를 넓히면 못 찾던 장소가 잡히지만 **엉뚱한 곳이 잡힌다.**
    성산일출봉 좌표에서 반경 2km를 부르면 후보 10개 중 9개가 식당·펜션이고,
    이름 유사도로 고르면 `성산흑돼지두루치기 성산일출봉점`(음식점)이
    `성산일출봉 [유네스코 세계자연유산]`(관광지)을 **이긴다** — 뒤에 붙은
    `[유네스코 세계자연유산]`이 길어서 유사도가 떨어지기 때문이다(2026-08-22 실측).

    그래서 두 개를 같이 준다.

    - `allowed_types` — 관광지·문화시설만 받는다(`SIGHT_CONTENT_TYPES`).
      ⚠️ **기본값은 None(제한 없음)이다.** 코스에는 식당·카페가 들어 있고
      `/place/detail`은 그것들도 보여줘야 한다. 제한하면 코스 장소 상세가 빈다.
    - `require_name_match` — 이름이 안 맞으면 아무것도 돌려주지 않는다.
      틀린 사진이 붙는 것보다 없는 게 낫다.

    ## 이름 고르는 순서

    유사도보다 **포함 관계를 먼저 본다.** `성산일출봉`으로 찾을 때
    `성산일출봉 [유네스코 세계자연유산]`은 이름으로 시작하므로 유사도와 무관하게 이긴다.
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
            if not item_list:
                return None

        best = _pick_by_name(name, item_list)
        if best is None:
            if require_name_match:
                return None
            best = item_list[0]
        return best["contentid"], str(best.get("contenttypeid", "12"))
    except Exception as e:
        logger.warning("KTO _find_content_id failed for %s: %s", name, e)
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
        return {name: _pick(item, prefixes) for name, prefixes in _INTRO_FIELDS.items()}
    except Exception as e:
        logger.error("KTO _fetch_intro 실패 content_id=%s type=%s: %s", content_id, content_type_id, e)
        return empty


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
            "images":           _json.loads(cached["images"] or "[]"),
            "address":          cached["address"] or "",
            "tel":              cached["tel"] or "",
            "open_time":        cached["open_time"] or "",
            "rest_date":        cached["rest_date"] or "",
            "use_fee":          cached["use_fee"] or "",
            "parking":          cached["parking"] or "",
        }

    result = _find_content_id(name, lat, lng)
    if not result:
        # KTO DB에 없는 장소(공항 등)는 빈 필드로 200 반환 — iOS는 있는 정보만 표시
        return {"name": name, "overview": "", "images": [], "address": "",
                "tel": "", "open_time": "", "rest_date": "", "use_fee": "", "parking": ""}
    content_id, content_type_id = result

    detail  = _fetch_detail(content_id)
    images  = _fetch_images(content_id)
    first   = detail.get("firstimage", "")
    if first and first not in images:
        images = [first] + images
    intro   = _fetch_intro(content_id, content_type_id)

    overview = detail.get("overview", "")
    address  = detail.get("addr1", "")
    # 성산일출봉처럼 detailCommon2의 tel이 비고 detailIntro2의 infocenter에만
    # 번호가 있는 장소가 많다. 둘 중 있는 쪽을 쓴다.
    tel      = detail.get("tel", "") or intro.get("tel", "")

    conn.execute(
        """INSERT OR REPLACE INTO place_detail_cache
           (name, lat, lng, overview, images, address, tel,
            open_time, rest_date, use_fee, parking, content_type_id, cached_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (name, _lat, _lng, overview, _json.dumps(images, ensure_ascii=False),
         address, tel,
         intro["open_time"], intro["rest_date"], intro["use_fee"], intro["parking"],
         content_type_id, time.time()),
    )
    conn.commit()

    return {
        "name":      name,
        "overview":  overview,
        "images":    images,
        "address":   address,
        "tel":       tel,
        "open_time": intro["open_time"],
        "rest_date": intro["rest_date"],
        "use_fee":   intro["use_fee"],
        "parking":   intro["parking"],
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


def find_sight_content_id(name: str, lat: float, lng: float) -> tuple[str, str] | None:
    """관광지 하나의 (contentId, contentTypeId). 못 찾으면 None.

    좌표 검색만으로는 부족하고 이름 검색만으로도 부족하다. **둘 다 쓴다.**

    | 방식 | 잘 되는 것 | 안 되는 것 |
    |---|---|---|
    | 이름 검색 | 천지연폭포·카멜리아힐 — 좌표 검색에 아예 안 잡히는 곳 | `우도`→`가우도`(전남), `주상절리대`→`무등산 주상절리대`(광주) |
    | 좌표 검색 | 이름이 데이터와 다른 곳(`오설록티뮤지엄`↔`오설록 티뮤지엄`) | 주변에 식당이 많으면 관광지가 10개 안에 안 들어온다 |

    그래서 **이름으로 먼저 찾고 거리로 검증**하고, 없으면 좌표로 찾는다.
    둘 다 관광지 계열(`SIGHT_CONTENT_TYPES`)만 받는다 — 안 그러면 성산일출봉 카드에
    `성산흑돼지두루치기 성산일출봉점` 사진이 붙는다.
    """
    for item in _search_by_keyword(name):
        if str(item.get("contenttypeid", "")) not in SIGHT_CONTENT_TYPES:
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
        found = _find_content_id(
            name, lat, lng, radius=radius,
            require_name_match=True, allowed_types=SIGHT_CONTENT_TYPES,
        )
        if found:
            return found
    return None
