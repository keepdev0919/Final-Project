"""KTO OpenAPI 프록시 — `_kto_get`은 place.py에서도 공유."""
import logging
import os
import time
import urllib.parse
import urllib.request
import json
from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from services.db import get_db_connection

logger = logging.getLogger(__name__)

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
#
# 표시 위치: iOS ProfileSheet 하단 (2026-08-13 반영). 백엔드는 이 상수를 직접
# 쓰지 않는다 — 값의 단일 출처로서만 존재한다. 문구를 바꿀 일이 생기면 여기와
# ProfileSheet를 함께 고칠 것.
KTO_ATTRIBUTION = "출처: ⓒ한국관광공사"


class KtoApiError(RuntimeError):
    """KTO가 HTTP 200으로 돌려준 실패. 조용히 넘기지 않으려고 예외로 올린다."""


def _log_call(service: str, operation: str, ok: bool, detail: str = "") -> None:
    """호출 한 건을 기록한다.

    공모전 공지가 "개발 기간 내 API 호출 이력이 확인되지 않을 경우 심사 불이익"을
    명시한다. 그 이력이 실제로 쌓이는지를 추측하지 않고 세기 위한 장치다.
    공공데이터포털 마이페이지 수치와 대조해 캐시 TTL을 조정한다.

    기록 실패가 API 호출 자체를 막으면 안 되므로 어떤 예외도 삼킨다.
    """
    try:
        conn = get_db_connection()
        conn.execute(
            "INSERT INTO kto_call_log (service, operation, ok, detail, called_at) VALUES (?,?,?,?,?)",
            (service, operation, 1 if ok else 0, detail[:200], time.time()),
        )
        conn.commit()
    except Exception:  # noqa: BLE001 — 계측이 본 기능을 깨뜨리지 않는다
        pass


def _kto_get(service: str, operation: str, params: dict) -> dict:
    """KTO OpenAPI 호출.

    ⚠️ **KTO는 실패도 HTTP 200으로 돌려준다.** 본문의 resultCode를 봐야 안다.
    예전에는 이걸 확인하지 않아 `detailCommon2`가 파라미터 오류로 계속 실패하는데도
    화면에는 "정보가 원래 없는 장소"처럼 보였다(2026-08-19 발견). 그래서 여기서
    resultCode를 검사해 예외로 올린다. 조용한 실패를 만들지 말 것.
    """
    params.update({
        "serviceKey": KTO_KEY,
        "MobileOS": "ETC",
        "MobileApp": MOBILE_APP,
        "_type": "json",
    })
    url = f"{KTO_BASE}/{service}/{operation}?{urllib.parse.urlencode(params)}"
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            data = json.loads(r.read())
    except Exception as e:
        _log_call(service, operation, False, f"{type(e).__name__}: {e}")
        logger.error("KTO 호출 실패 %s/%s: %s", service, operation, e)
        raise

    code = (data.get("response", {}).get("header", {}).get("resultCode")
            or data.get("resultCode"))
    if code not in (None, "0000", "00"):
        reason = (data.get("response", {}).get("header", {}).get("resultMsg")
                  or data.get("resultMsg") or f"resultCode={code}")
        _log_call(service, operation, False, reason)
        logger.error("KTO 응답 오류 %s/%s: %s", service, operation, reason)
        raise KtoApiError(f"{service}/{operation}: {reason}")

    _log_call(service, operation, True)
    return data


@router.get("/info")
@limiter.limit("30/minute")
def get_tourist_info(request: Request, content_id: str):
    """contentId로 관광정보 조회 (1시간 캐시 — CACHE_TTL 주석 참조)."""
    conn = get_db_connection()
    cached = conn.execute(
        "SELECT * FROM tourist_info_cache WHERE content_id=?", (content_id,)
    ).fetchone()

    if cached and (time.time() - cached["cached_at"]) < CACHE_TTL:
        return dict(cached)

    try:
        # ⚠️ defaultYN·addrinfoYN·overviewYN은 KorService1 파라미터다.
        # KorService2에 보내면 INVALID_REQUEST_PARAMETER_ERROR로 통째로 실패한다.
        data = _kto_get("KorService2", "detailCommon2", {"contentId": content_id})
        item = data["response"]["body"]["items"]["item"][0]
    except Exception:
        raise HTTPException(status_code=502, detail="KTO API 오류")

    conn.execute(
        "INSERT OR REPLACE INTO tourist_info_cache VALUES (?,?,?,?,?,?)",
        (content_id, item.get("title"), item.get("addr1"), item.get("tel"), item.get("cat1"), time.time()),
    )
    conn.commit()
    return item
