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

# 캐시 TTL 1시간.
#
# 7일로 두지 않는 이유: 성산 1개 장소 기준 개발 기간 전체에 호출 20여 건만
# 남는다. 공지 FAQ가 "개발 기간 내 API 호출 이력이 확인되지 않을 경우 심사에서
# 불이익"을 명시하므로 자격 요건 문제다.
#
# 완전히 없애지 않는 이유: 개발계정 한도가 오퍼레이션당 일 1,000건이라 코스를
# 훑는 사용자 50명 수준에서 차단된다. 차단되면 place.py가 빈 필드로 200을
# 반환해 에러 없이 정보가 사라진다.
#
# 관광 정보는 시간 단위로 바뀌지 않으므로 1시간이면 신선도도 충분하다.
# 공공데이터포털 마이페이지에서 실제 호출 건수를 보고 조정한다.
CACHE_TTL = 3600

# KTO에 전달하는 앱 식별자. 심사 제출 서비스명과 일치시킨다.
MOBILE_APP = "Nolmeongbopseo"

# 공지가 지정한 출처 표기. 텍스트만 허용되며 공사 CI/BI 로고는 사용 금지.
# TourAPI 단독 표기도 지양 대상이다.
KTO_ATTRIBUTION = "출처: ⓒ한국관광공사"


def _kto_get(service: str, operation: str, params: dict) -> dict:
    params.update({
        "serviceKey": KTO_KEY,
        "MobileOS": "ETC",
        "MobileApp": MOBILE_APP,
        "_type": "json",
    })
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
