"""KTO OpenAPI 프록시 (국문관광정보 / 연관관광지 / 집중률 예측)."""
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
    """국문 관광정보 조회 (7일 캐시)."""
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


@router.get("/related")
@limiter.limit("30/minute")
def get_related_tourist(request: Request, area_cd: str, signgu_cd: str, base_ym: str):
    """연관 관광지 조회."""
    try:
        data = _kto_get("TarRlteTarService1", "AreaBasedList1",
                        {"areaCd": area_cd, "signguCd": signgu_cd, "baseYm": base_ym})
        return data["response"]["body"]["items"]
    except Exception:
        raise HTTPException(status_code=502, detail="KTO API 오류")


@router.get("/congestion")
@limiter.limit("30/minute")
def get_congestion(request: Request, area_cd: str, signgu_cd: str, date: str, tats_nm: str = ""):
    """집중률 예측 조회 (캐시 없음, 실시간)."""
    params = {"areaCd": area_cd, "signguCd": signgu_cd, "baseYmd": date}
    if tats_nm:
        params["tAtsNm"] = tats_nm
    try:
        data = _kto_get("TatsCntrRateService", "tatsCntrRateList", params)
        return data["response"]["body"]["items"]
    except Exception:
        raise HTTPException(status_code=502, detail="KTO API 오류")
