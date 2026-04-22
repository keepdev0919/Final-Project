"""장소 상세 정보 — KTO API로 사진·설명 조회 (GPS 기반 contentId 탐색)."""
from __future__ import annotations

import difflib
import time
from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from services.db import get_db_connection
from routers.tourist import _kto_get  # tourist.py와 중복 방지

router = APIRouter(prefix="/place", tags=["place"])
limiter = Limiter(key_func=get_remote_address)

CACHE_TTL = 7 * 24 * 3600  # 7일


def _find_content_id(name: str, lat: float, lng: float) -> str | None:
    """GPS 반경 검색으로 가장 이름이 비슷한 장소의 contentId를 반환."""
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
        if not matches:
            return item_list[0]["contentid"] if item_list else None
        best = next(it for it in item_list if it["title"] == matches[0])
        return best["contentid"]
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


def _fetch_image(content_id: str) -> str:
    """contentId로 대표 사진 URL 조회."""
    try:
        data = _kto_get("KorService2", "detailImage2", {
            "contentId": content_id,
            "imageYN": "Y",
            "numOfRows": 1,
        })
        items = data["response"]["body"]["items"]
        if not items or items == "":
            return ""
        item_list = items["item"] if isinstance(items["item"], list) else [items["item"]]
        return item_list[0].get("originimgurl", "") if item_list else ""
    except Exception:
        return ""


@router.get("/detail")
@limiter.limit("30/minute")
def get_place_detail(request: Request, name: str, lat: float, lng: float):
    """장소명 + GPS로 KTO 사진·설명 조회 (7일 캐시)."""
    conn = get_db_connection()

    cached = conn.execute(
        "SELECT * FROM place_detail_cache WHERE name = ? AND ABS(lat - ?) < 0.001 AND ABS(lng - ?) < 0.001",
        (name, lat, lng),
    ).fetchone()
    if cached and (time.time() - cached["cached_at"]) < CACHE_TTL:
        return {
            "name": cached["name"],
            "overview": cached["overview"],
            "image_url": cached["image_url"],
            "address": cached["address"],
        }

    content_id = _find_content_id(name, lat, lng)
    if not content_id:
        raise HTTPException(status_code=404, detail="KTO에서 해당 장소를 찾을 수 없습니다.")

    detail = _fetch_detail(content_id)
    image_url = detail.get("firstimage") or _fetch_image(content_id)
    overview = detail.get("overview", "")
    address = detail.get("addr1", "")

    conn.execute(
        """INSERT OR REPLACE INTO place_detail_cache
           (name, lat, lng, overview, image_url, address, cached_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (name, lat, lng, overview, image_url, address, time.time()),
    )
    conn.commit()

    return {
        "name": name,
        "overview": overview,
        "image_url": image_url,
        "address": address,
    }
