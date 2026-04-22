"""장소 상세 정보 — KTO API로 사진·설명 조회 (GPS 기반 contentId 탐색)."""
from __future__ import annotations

import difflib
import json as _json
import time
from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from services.db import get_db_connection
from routers.tourist import _kto_get  # tourist.py와 중복 방지

router = APIRouter(prefix="/place", tags=["place"])
limiter = Limiter(key_func=get_remote_address)

CACHE_TTL = 7 * 24 * 3600  # 7일


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
        item_list = items["item"] if isinstance(items["item"], list) else [items["item"]]
        titles = [it["title"] for it in item_list]
        matches = difflib.get_close_matches(name, titles, n=1, cutoff=0.3)
        best = next(
            (it for it in item_list if it["title"] == matches[0]),
            item_list[0]
        ) if matches else item_list[0]
        return best["contentid"], str(best.get("contenttypeid", "12"))
    except Exception:
        return None


def _fetch_detail(content_id: str) -> dict:
    """contentId로 상세 정보(overview, 사진, 주소) 조회."""
    try:
        data = _kto_get("KorService2", "detailCommon2", {
            "contentId": content_id,
            "overviewYN": "Y",
            "defaultYN": "Y",
        })
        item = data["response"]["body"]["items"]["item"]
        if isinstance(item, list):
            item = item[0]
        return item
    except Exception:
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
        item_list = items["item"] if isinstance(items["item"], list) else [items["item"]]
        return [it["originimgurl"] for it in item_list if it.get("originimgurl")]
    except Exception:
        return []


def _fetch_intro(content_id: str, content_type_id: str) -> dict:
    """운영시간·휴무·입장료·주차 조회. 없는 필드는 빈 문자열."""
    try:
        data = _kto_get("KorService2", "detailIntro2", {
            "contentId": content_id,
            "contentTypeId": content_type_id,
        })
        item = data["response"]["body"]["items"]["item"]
        if isinstance(item, list):
            item = item[0]
        return {
            "open_time": item.get("opentime") or item.get("usetimefestival") or item.get("opentimefood") or "",
            "rest_date": item.get("restdate") or item.get("restdatefood") or "",
            "use_fee":   item.get("usefee") or "",
            "parking":   item.get("parking") or item.get("parkingfood") or "",
        }
    except Exception:
        return {"open_time": "", "rest_date": "", "use_fee": "", "parking": ""}


@router.get("/detail")
@limiter.limit("30/minute")
def get_place_detail(request: Request, name: str, lat: float, lng: float):
    """장소명 + GPS로 KTO 사진·설명·이용팁 조회 (7일 캐시)."""
    conn = get_db_connection()

    cached = conn.execute(
        "SELECT * FROM place_detail_cache WHERE name = ? AND ABS(lat - ?) < 0.001 AND ABS(lng - ?) < 0.001",
        (name, lat, lng),
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
        raise HTTPException(status_code=404, detail="KTO에서 해당 장소를 찾을 수 없습니다.")
    content_id, content_type_id = result

    detail  = _fetch_detail(content_id)
    images  = _fetch_images(content_id)
    first   = detail.get("firstimage", "")
    if first and first not in images:
        images = [first] + images
    intro   = _fetch_intro(content_id, content_type_id)

    overview = detail.get("overview", "")
    address  = detail.get("addr1", "")
    tel      = detail.get("tel", "")

    conn.execute(
        """INSERT OR REPLACE INTO place_detail_cache
           (name, lat, lng, overview, images, address, tel,
            open_time, rest_date, use_fee, parking, content_type_id, cached_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (name, lat, lng, overview, _json.dumps(images, ensure_ascii=False),
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
