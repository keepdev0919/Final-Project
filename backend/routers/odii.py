"""오디(Odii) 오디오 가이드 — 한국관광공사 오디오 해설 OpenAPI.

## 두 가지를 나눠서 다룬다 (2026-08-19 조익준님 결정)

| 로컬에 저장 | 실시간 호출 |
|---|---|
| 어떤 장소에 해설이 있는지 (제목·좌표·stid) | **대본·음성** |

지도에 핀을 찍고 "이 장소엔 들을 게 있다" 배지를 띄우려면 목록이 즉시 있어야
한다. 그래서 목록만 로컬에 둔다. 반면 **대본(`script`)은 저장하지 않는다.**
두 가지 이유다.

1. 관광공사 콘텐츠를 쟁여두고 재배포하는 모양이 되지 않는다. 사용자가 재생을
   누를 때 관광공사에서 받아온다.
2. 공모전 공지가 *"로컬 DB 저장 방식이 아닌 실시간 호출 방식으로 활용할 것을
   강력히 권고"* 하고, *"개발 기간 내 API 호출 이력이 확인되지 않을 경우 심사에서
   불이익"* 을 명시했다. 재생이 곧 호출이 되게 만든다.

## 오디에는 ID 단건 조회가 없다

`storyBasedList?tid=969`는 필터가 먹지 않고 전체(6,547건)를 돌려준다(실측).
그래서 단건은 **저장해둔 좌표 + 좁은 반경**으로 가져온다. `radius=100`이면
정확히 그 지점 1건이 오고 0.3초면 끝난다.

## 주의

- `langCode`가 **필수**다. 빠뜨리면 `NO_MANDATORY_REQUEST_PARAMETERS_ERROR1`.
- 응답 형태가 두 가지다 — `{"response":{"body":{"items":{"item":[...]}}}}` 와
  `{"items":[...]}`. 둘 다 처리한다.
- 제주 226건 중 **대본 없음 36건**은 목록에서 뺀다. 눌러도 나올 게 없다.
- **음성 파일은 47건(21%)뿐**이다. 나머지는 대본만 있어 TTS로 읽어야 하는데,
  그건 "오디 음성을 트는 것"이 아니라 "오디 대본을 우리가 읽는 것"이라
  저작권 판단이 달라진다 → 주최측 확인 대기 항목.
"""
from __future__ import annotations

import logging
import time

from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from routers.tourist import CACHE_TTL, KtoApiError, _kto_get
from services.db import get_db_connection

# 공지가 지정한 출처 표기. 텍스트만 허용되며 공사 CI/BI 로고는 금지.
ATTRIBUTION = "출처: ⓒ한국관광공사"

router = APIRouter(prefix="/odii", tags=["odii"])
limiter = Limiter(key_func=get_remote_address)
logger = logging.getLogger(__name__)

# 제주 전역을 한 번에 덮는 좌표와 반경. 실측으로 226건이 모두 들어온다.
JEJU_CENTER = (126.55, 33.38)
JEJU_RADIUS = 50000

# 단건 조회용 반경. 100m면 그 지점 하나만 잡힌다(실측).
STORY_RADIUS = 100

# 목록 갱신 주기 7일. 관광공사가 지점을 추가·삭제하는 빈도가 낮다.
# 대본과 달리 목록은 저장물이므로 신선도보다 안정성을 택한다.
SYNC_TTL = 7 * 24 * 3600


def _items(data: dict) -> list[dict]:
    """오디의 두 가지 응답 형태를 모두 리스트로 편다."""
    body = data.get("response", {}).get("body", data)
    raw = body.get("items")
    if not raw or raw == "":
        return []
    if isinstance(raw, dict):
        raw = raw.get("item")
    if not raw:
        return []
    return raw if isinstance(raw, list) else [raw]


def _fetch_jeju_stories(lang: str = "ko") -> list[dict]:
    data = _kto_get("Odii", "storyLocationBasedList", {
        "langCode": lang,
        "mapX": JEJU_CENTER[0],
        "mapY": JEJU_CENTER[1],
        "radius": JEJU_RADIUS,
        "numOfRows": 300,
        "pageNo": 1,
    })
    return _items(data)


def sync_places(lang: str = "ko") -> int:
    """제주 오디 목록을 받아 로컬에 저장한다. 저장한 건수를 돌려준다.

    ⚠️ `script`는 저장하지 않는다. 있는지 여부(`has_script`)만 기록한다.
    이 함수를 고쳐 대본을 넣지 말 것 — 위 모듈 설명의 두 이유가 무너진다.
    """
    stories = _fetch_jeju_stories(lang)
    conn = get_db_connection()
    now = time.time()
    saved = 0
    for s in stories:
        if not (s.get("mapX") and s.get("mapY")):
            continue
        conn.execute(
            """INSERT OR REPLACE INTO odii_places
               (stid, lang, title, audio_title, lat, lng, play_time,
                has_script, has_audio, synced_at)
               VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (
                str(s.get("stid") or ""),
                lang,
                s.get("title") or "",
                s.get("audioTitle") or "",
                float(s["mapY"]),
                float(s["mapX"]),
                int(s.get("playTime") or 0),
                1 if (s.get("script") or "").strip() else 0,
                1 if (s.get("audioUrl") or "").strip() else 0,
                now,
            ),
        )
        saved += 1
    conn.commit()
    logger.info("오디 목록 갱신: %d건 저장 (lang=%s)", saved, lang)
    return saved


def _ensure_synced(lang: str = "ko") -> None:
    """목록이 없거나 오래됐으면 갱신한다."""
    conn = get_db_connection()
    row = conn.execute(
        "SELECT MAX(synced_at) AS last FROM odii_places WHERE lang = ?", (lang,)
    ).fetchone()
    last = (row["last"] if row else None) or 0
    if time.time() - last < SYNC_TTL:
        return
    try:
        sync_places(lang)
    except (KtoApiError, Exception) as e:  # noqa: BLE001
        # 갱신에 실패해도 기존 목록으로 계속 서비스한다. 목록이 아예 없을 때만
        # 호출부가 빈 배열을 받는다.
        logger.error("오디 목록 갱신 실패 (기존 목록 유지): %s", e)


@router.get("/places")
@limiter.limit("60/minute")
def list_places(request: Request, lang: str = "ko") -> dict:
    """지도·홈에 쓸 오디 장소 목록. 로컬 저장분이라 즉시 응답한다.

    대본 없는 건은 제외한다 — 눌러도 나올 게 없는 핀을 지도에 찍지 않는다.
    """
    _ensure_synced(lang)
    conn = get_db_connection()
    rows = conn.execute(
        """SELECT stid, title, audio_title, lat, lng, play_time, has_audio
           FROM odii_places WHERE lang = ? AND has_script = 1
           ORDER BY title""",
        (lang,),
    ).fetchall()
    return {
        "count": len(rows),
        "places": [dict(r) for r in rows],
        "attribution": ATTRIBUTION,
    }


@router.get("/story")
@limiter.limit("60/minute")
def get_story(request: Request, stid: str, lang: str = "ko") -> dict:
    """`GET /odii/story` — 얇은 껍데기. 실제 일은 `fetch_story`가 한다."""
    return fetch_story(stid, lang)


def fetch_story(stid: str, lang: str = "ko") -> dict:
    """재생 버튼을 눌렀을 때 대본·음성을 실시간으로 가져온다.

    **라우트와 분리해 둔 이유.** 레이트 리미터(`@limiter.limit`)가 실제
    `starlette.Request`를 요구하기 때문에, 라우트 함수를 서버 안에서 직접
    부르면 터진다(배치 스크립트에서 실제로 겪음). 내부 호출자는 이 함수를
    쓴다 — `routers/tts.py`, `scripts/warm_tts_cache.py`.

    **좌표를 파라미터로 받지 않는다.** 오디 API 자체는 좌표로만 조회되지만,
    그 좌표는 서버가 저장된 목록에서 꺼내 쓴다. 클라이언트가 좌표를 보내게
    만들면 나중에 누군가 "내 주변 해설 듣기"를 붙이면서 **사용자 위치**를
    넘기게 되고, 그 순간 위치기반서비스사업자 신고 대상이 된다
    (공지 FAQ: 위치를 사업자 서버로 전송하면 DB 저장 여부와 무관하게 해당).

    구조로 막는다. `tests/test_folklore_removed.py`가 이 불변식을 감시한다.
    """
    conn = get_db_connection()
    place = conn.execute(
        "SELECT lat, lng, title FROM odii_places WHERE stid = ? AND lang = ?",
        (stid, lang),
    ).fetchone()
    if place is None:
        _ensure_synced(lang)
        place = conn.execute(
            "SELECT lat, lng, title FROM odii_places WHERE stid = ? AND lang = ?",
            (stid, lang),
        ).fetchone()
    if place is None:
        raise HTTPException(status_code=404, detail="모르는 오디 장소입니다")

    key = f"{lang}:{stid}"
    cached = conn.execute(
        "SELECT * FROM odii_story_cache WHERE cache_key = ?", (key,)
    ).fetchone()
    if cached and (time.time() - cached["cached_at"]) < CACHE_TTL:
        return {
            "stid": stid,
            "title": cached["title"],
            "audio_title": cached["audio_title"],
            "script": cached["script"],
            "audio_url": cached["audio_url"],
            "play_time": cached["play_time"],
            "attribution": ATTRIBUTION,
        }

    try:
        data = _kto_get("Odii", "storyLocationBasedList", {
            "langCode": lang,
            "mapX": place["lng"],
            "mapY": place["lat"],
            "radius": STORY_RADIUS,
            "numOfRows": 5,
            "pageNo": 1,
        })
    except KtoApiError as e:
        raise HTTPException(status_code=502, detail=f"오디 API 오류: {e}")
    except Exception as e:
        raise HTTPException(status_code=502, detail="오디 API에 연결하지 못했습니다") from e

    stories = [s for s in _items(data) if (s.get("script") or "").strip()]
    # 좁은 반경 안에 여러 건이 잡히면 요청받은 stid를 우선한다.
    exact = [s for s in stories if str(s.get("stid") or "") == stid]
    stories = exact or stories
    if not stories:
        raise HTTPException(status_code=404, detail="이 장소에는 오디오 해설이 없습니다")

    s = stories[0]
    result = {
        "stid": stid,
        "title": s.get("title") or "",
        "audio_title": s.get("audioTitle") or "",
        "script": s.get("script") or "",
        "audio_url": s.get("audioUrl") or "",
        "play_time": int(s.get("playTime") or 0),
        "attribution": ATTRIBUTION,
    }

    # 캐시는 1시간. 대본을 쟁여두는 게 아니라 연타·재방문을 흡수하는 용도다.
    conn.execute(
        """INSERT OR REPLACE INTO odii_story_cache
           (cache_key, title, audio_title, script, audio_url, play_time, cached_at)
           VALUES (?,?,?,?,?,?,?)""",
        (key, result["title"], result["audio_title"], result["script"],
         result["audio_url"], result["play_time"], time.time()),
    )
    conn.commit()
    return result


@router.post("/sync")
def force_sync(lang: str = "ko") -> dict:
    """목록을 지금 갱신한다. 운영·개발용."""
    try:
        return {"saved": sync_places(lang)}
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"갱신 실패: {e}")
