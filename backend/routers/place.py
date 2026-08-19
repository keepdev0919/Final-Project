"""장소 상세 정보 — KTO API로 사진·설명 조회 (GPS 기반 contentId 탐색)."""
from __future__ import annotations

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


def _find_content_id(name: str, lat: float, lng: float) -> tuple[str, str] | None:
    """GPS 반경 검색으로 (contentId, contentTypeId) 반환."""
    try:
        data = _kto_get("KorService2", "locationBasedList2", {
            "mapX": lng,
            "mapY": lat,
            "radius": 500,
            "numOfRows": 10,
        })
        items = data["response"]["body"]["items"]
        if not items or items == "":
            return None
        raw_items = items.get("item")
        if not raw_items:
            return None
        item_list = raw_items if isinstance(raw_items, list) else [raw_items]
        titles = [it["title"] for it in item_list]
        matches = difflib.get_close_matches(name, titles, n=1, cutoff=0.3)
        best = next(
            (it for it in item_list if it["title"] == matches[0]),
            item_list[0]
        ) if matches else item_list[0]
        return best["contentid"], str(best.get("contenttypeid", "12"))
    except Exception as e:
        logger.warning("KTO _find_content_id failed for %s: %s", name, e)
        return None


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
