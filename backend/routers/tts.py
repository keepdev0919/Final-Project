"""TTS — 이야기를 곱닥이 목소리로 들려준다.

## 지금 쓰는 것: `/tts/story`

    발견 → Story 화면 → GET /tts/story?play_id=&story_id=
                        서버가 PLAY 원고에서 script 를 꺼내 읽어 준다
                        대본 해시로 캐시를 찾아 두 번째부터는 Typecast 0회

**Story 는 놀멍봅서가 직접 쓴 문장이다** (2026-09-02 결정). 오디 대본을 그대로
재생하지 않는다 — 오디는 콘텐츠를 만들 때 참고한 여러 Source 중 하나이고,
`story.sources` 에 출처로만 남는다.

`script` 하나가 **화면 자막이자 TTS 원문**이다. 둘이 갈라지면 듣는 말과 보이는
글이 달라진다. 그래서 클라이언트에 자막용·음성용을 따로 주지 않는다.

## ⚠️ 클라이언트가 텍스트를 보내지 않는다

`play_id` 와 `story_id` 만 받는다. 클라이언트가 긴 문자열을 업로드하게 만들면
**우리 Typecast 크레딧으로 아무 문장이나 읽게 되고**, 목소리 통제도 클라이언트로
넘어간다. 읽을 수 있는 것은 우리 원고에 있는 문장뿐이다.

## `/tts/odii` 는 남겨 둔 옛 경로다

오디 대본 자동재생 구조를 폐기하면서(2026-09-02) 앱에서 부르는 곳이 없어졌다.
`scripts/warm_tts_cache.py` 만 쓴다. 정리는 별도 작업.
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response
from slowapi import Limiter
from slowapi.util import get_remote_address

from services import typecast
from services.db import get_db_connection

router = APIRouter(prefix="/tts", tags=["tts"])
limiter = Limiter(key_func=get_remote_address)
logger = logging.getLogger(__name__)

# 감정 프리셋 화이트리스트. 클라이언트가 아무 문자열이나 넣어 Typecast에서
# 400을 받는 대신 여기서 막는다.
ALLOWED_EMOTIONS = {"normal", "happy", "sad", "angry", "whisper", "toneup", "tonedown"}


@router.get("/story")
@limiter.limit("60/minute")
def tts_for_story(request: Request, play_id: str, story_id: str,
                  emotion: str = "normal") -> Response:
    """PLAY 원고의 Story 하나를 음성으로 돌려준다.

    ⚠️ 읽을 문장을 **클라이언트가 보내지 않는다.** id 두 개만 받는다.
    """
    if emotion not in ALLOWED_EMOTIONS:
        raise HTTPException(status_code=400, detail=f"모르는 감정: {emotion}")

    from services import place_registry as registry
    from services import play_loader

    conn = get_db_connection()
    registry.ensure_synced(conn)

    play = play_loader.get(conn, play_id)
    if play is None:
        raise HTTPException(status_code=404, detail="그런 PLAY 가 없습니다")

    # FINAL 뒤에 붙는 Story 도 읽을 수 있어야 한다.
    stories = list(play.stories)
    if play.final is not None and play.final.story is not None:
        stories.append(play.final.story)

    story = next((s for s in stories if s.id == story_id), None)
    if story is None:
        raise HTTPException(status_code=404, detail="그런 이야기가 없습니다")

    script = (story.script or "").strip()
    if not script:
        raise HTTPException(status_code=404, detail="이 이야기에는 읽을 문장이 없습니다")

    try:
        audio, from_cache = typecast.synth(
            script, emotion=emotion, lang="kor", conn=conn
        )
    except typecast.TtsError as e:
        # 조용히 빈 응답을 주지 않는다. 재생이 안 되면 안 되는 이유가 보여야 한다.
        raise HTTPException(status_code=502, detail=str(e))

    # ⚠️ HTTP 헤더는 latin-1 만 담는다. 한글을 넣으면 500 이 난다(2026-08-20 실측).
    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={
            "Cache-Control": "public, max-age=604800",
            "X-Tts-Cache": "hit" if from_cache else "miss",
        },
    )


@router.get("/odii")
@limiter.limit("60/minute")
def tts_for_odii_place(request: Request, stid: str, lang: str = "ko",
                       emotion: str = "normal") -> Response:
    """오디 장소 하나의 대본을 음성으로 돌려준다.

    ⚠️ 좌표를 받지 않는다. `stid`만 받는다 (설계 v2 §2 — 위치정보법).
    """
    if emotion not in ALLOWED_EMOTIONS:
        raise HTTPException(status_code=400, detail=f"모르는 감정: {emotion}")

    # 대본은 오디 라우터를 통해 가져온다. 그래야 KTO 호출 이력이 그쪽에 남고,
    # 대본 획득 규칙(반경·유일성 판정)이 한 곳에만 있게 된다.
    from routers.odii import fetch_story

    story = fetch_story(stid, lang)
    script = (story.get("script") or "").strip()
    if not script:
        raise HTTPException(status_code=404, detail="이 장소에는 대본이 없습니다")

    tc_lang = {"ko": "kor", "en": "eng"}.get(lang, "kor")
    try:
        audio, from_cache = typecast.synth(
            script, emotion=emotion, lang=tc_lang, conn=get_db_connection()
        )
    except typecast.TtsError as e:
        # 조용히 빈 응답을 주지 않는다. 재생이 안 되면 안 되는 이유가 보여야 한다.
        raise HTTPException(status_code=502, detail=str(e))

    # ⚠️ HTTP 헤더는 latin-1만 담을 수 있다. 한글을 넣으면
    # UnicodeEncodeError로 500이 난다(2026-08-20에 실제로 겪음).
    # 출처 표기는 `/odii/story` 응답 본문으로 이미 내려가고 화면이 그걸 쓴다.
    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={
            "Cache-Control": "public, max-age=604800",
            "X-Tts-Cache": "hit" if from_cache else "miss",
        },
    )
