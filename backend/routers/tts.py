"""TTS — 오디 대본을 곱닥이 목소리로 들려준다.

## 흐름 (안 D · 2026-08-20 결정)

    재생 버튼 → GET /odii/story?stid=   KTO 실시간 호출 (호출 이력 남음)
                                        대본을 받아 화면에 자막으로 뿌린다
              → GET /tts/odii?stid=     대본 해시로 캐시를 찾는다
                                        있으면 파일 그대로 스트리밍 (Typecast 0회)
                                        없으면 생성해서 저장한 뒤 스트리밍

**대본을 클라이언트가 다시 보내지 않는다.** stid만 주면 서버가 오디에서 다시
받아온다. 클라이언트가 긴 텍스트를 업로드하게 만들면 중간에서 바꿔치기할 수
있고(우리 크레딧으로 아무 문장이나 읽게 된다), 목소리 통제도 클라이언트로 넘어간다.

## 오디 음성 파일을 쓰지 않는 이유 (2026-08-20 조익준님 결정)

오디가 주는 `audioUrl`은 189곳 중 47곳(21%)에만 있다. 섞어 쓰면 장소마다
목소리가 바뀐다. 전부 우리 TTS로 통일한다.
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
