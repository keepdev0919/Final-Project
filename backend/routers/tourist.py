"""KTO OpenAPI 프록시 — `_kto_get`은 place.py에서도 공유."""
import os
import time
import urllib.parse
import urllib.request
import json
from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from services.db import get_db_connection

router = APIRouter(prefix="/tourist", tags=["tourist"])
limiter = Limiter(key_func=get_remote_address)

KTO_BASE = "https://apis.data.go.kr/B551011"
KTO_KEY = os.getenv("KTO_API_KEY", "")
CACHE_TTL = 7 * 24 * 3600  # 7일


def _kto_get(service: str, operation: str, params: dict) -> dict:
    params.update({"serviceKey": KTO_KEY, "MobileOS": "ETC", "MobileApp": "JejuFolklore", "_type": "json"})
    url = f"{KTO_BASE}/{service}/{operation}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read())


@router.get("/info")
@limiter.limit("30/minute")
def get_tourist_info(request: Request, content_id: str):
    """contentId로 관광정보 조회 (7일 캐시)."""
    conn = get_db_connection()
    cached = conn.execute(
        "SELECT * FROM tourist_info_cache WHERE content_id=?", (content_id,)
    ).fetchone()

    if cached and (time.time() - cached["cached_at"]) < CACHE_TTL:
        return dict(cached)

    try:
        data = _kto_get("KorService2", "detailCommon2", {"contentId": content_id, "defaultYN": "Y", "addrinfoYN": "Y"})
        item = data["response"]["body"]["items"]["item"][0]
    except Exception:
        raise HTTPException(status_code=502, detail="KTO API 오류")

    conn.execute(
        "INSERT OR REPLACE INTO tourist_info_cache VALUES (?,?,?,?,?,?)",
        (content_id, item.get("title"), item.get("addr1"), item.get("tel"), item.get("cat1"), time.time()),
    )
    conn.commit()
    return item
