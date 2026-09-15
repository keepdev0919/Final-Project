"""Typecast TTS — 대본을 곱닥이 목소리로 읽는다.

## 왜 Typecast인가 (2026-08-20 결정)

OpenAI `tts-1`을 쓰고 있었지만 범용 목소리 11개뿐이라 픽셀아트 가이드 캐릭터에
맞는 목소리가 없었다. Typecast는 캐릭터 목소리 590종에 감정 프리셋 7종을 준다.

## 왜 해시로 캐시하나 — 안 D (2026-08-20 결정)

같은 대본·같은 목소리면 결과가 **항상 같다.** 그런데 재생할 때마다 생성하면
사용자 수에 비례해 돈이 나간다. 실측 계산:

    안 C (매 재생마다 생성)  하루 20명 × 5곳 → 월 228만 크레딧 ≈ $202
    안 D (장소당 1번)        189곳 전체 1회  →    14만 크레딧 ≈ $15 한 번

**대본 텍스트는 저장하지 않는다.** 해시만 저장한다. 오디 대본을 쟁여두지
않겠다는 결정(설계 v2 §2)을 문자 그대로 지키면서 생성 비용만 줄인다.
대본이 바뀌면 해시가 달라져 자동으로 다시 만들어진다.

## 주의

- 글자당 1 크레딧. 무료 플랜은 월 15,000(대본 20개분)이라 개발용으로만 쓴다.
- 한 번에 2,000자 제한. 우리 대본은 최대 246초(≈1,600자)라 전부 한 번에 된다.
- 무료 플랜 동시 호출 2. 배치 생성 시 동시성을 올리지 않는다.
"""
from __future__ import annotations

import hashlib
import logging
import os
import time
from pathlib import Path

import requests

logger = logging.getLogger(__name__)

API_URL = "https://api.typecast.ai/v1/text-to-speech"

# 곱닥이 목소리 — Toby. 2026-09-11 조익준님 선택.
#
# 곱딱이가 말하는 모든 대사(길안내·미션 질문·발견·이야기)를 자동으로 읽게 되면서
# 목소리를 다시 골랐다. Moru·Toby 두 후보와 이전 목소리 Jinseo 를 성읍 실제 대사
# 네 줄로 비교해 Toby 로 정했다. ssfm-v30 에서 감정 7종(whisper 포함)을 지원한다.
#
# 이전: Jinseo (tc_65bb3a1976b69213594357fc, 2026-08-20 선택). 그 목소리로 만든
# 캐시 파일은 storage/tts_cache 에 그대로 남아 있다 — 캐시 키에 목소리 id 가
# 들어가 있어 새 목소리와 섞이지 않는다.
#
# 바꾸려면 tests/test_tts.py도 함께 고친다. 목소리가 조용히 바뀌면
# 앱 전체의 인격이 바뀌는데 화면은 멀쩡해서 아무도 모른다.
VOICE_ID = "tc_6080369d3211aa112ab131db"
MODEL = "ssfm-v30"

# 한 번에 보낼 수 있는 글자 수. Typecast 제한.
MAX_CHARS = 2000

CACHE_DIR = Path(__file__).parent.parent.parent / "storage" / "tts_cache"

# 배포 이미지에 함께 싣는 **미리 만든 음성** (2026-09-11). 운영 서버의 CACHE_DIR 은
# Railway 볼륨이라 처음엔 비어 있고, 그 첫 합성에 Typecast 크레딧이 든다. 개발 기기에서
# 이미 만든 파일을 여기 두면 크레딧 없이 바로 나간다 — 첫 배포 날 크레딧이 바닥나
# 운영 서버가 「CREDIT_INSUFFICIENT」로 음성을 못 만든 일이 있었다.
SEED_DIR = Path(__file__).parent.parent.parent / "storage" / "tts_seed"


class TtsError(RuntimeError):
    """TTS 생성 실패. 호출부가 조용히 넘기지 않도록 예외로 올린다."""


def _api_key() -> str:
    key = os.getenv("TYPECAST_API_KEY", "").strip()
    if not key:
        raise TtsError("TYPECAST_API_KEY가 없습니다")
    return key


def cache_key(text: str, *, emotion: str, lang: str,
              voice_id: str = VOICE_ID, model: str = MODEL) -> str:
    """대본과 생성 조건으로 만든 키. **대본 자체는 어디에도 저장하지 않는다.**

    목소리·모델·감정·언어를 모두 넣는 이유: 이 중 하나만 바뀌어도 결과 음성이
    달라진다. 키에서 빠뜨리면 옛 목소리가 계속 나온다.
    """
    raw = "\x1f".join([model, voice_id, emotion, lang, text])
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _ensure_schema(conn) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS tts_cache (
            hash       TEXT PRIMARY KEY,
            voice_id   TEXT NOT NULL,
            model      TEXT NOT NULL,
            emotion    TEXT NOT NULL,
            lang       TEXT NOT NULL,
            bytes      INTEGER NOT NULL,
            created_at REAL NOT NULL
        )
        """
    )
    conn.commit()


def _path_for(key: str) -> Path:
    return CACHE_DIR / f"{key}.mp3"


def synth(text: str, *, emotion: str = "normal", intensity: float = 1.0,
          lang: str = "kor", conn=None) -> tuple[bytes, bool]:
    """대본을 음성으로. `(mp3 bytes, 캐시에서 나왔는지)` 를 돌려준다.

    캐시에 있으면 Typecast를 부르지 않는다 — 이게 안 D의 핵심이다.
    """
    text = (text or "").strip()
    if not text:
        raise TtsError("대본이 비어 있습니다")
    if len(text) > MAX_CHARS:
        # 잘라서 조용히 반쪽 음성을 내보내지 않는다. 쪼개기는 호출부의 몫이다.
        raise TtsError(f"대본이 {len(text)}자로 한 번에 보낼 수 있는 {MAX_CHARS}자를 넘습니다")

    key = cache_key(text, emotion=emotion, lang=lang)
    path = _path_for(key)
    if path.exists():
        return path.read_bytes(), True
    seed = SEED_DIR / f"{key}.mp3"
    if seed.exists():
        return seed.read_bytes(), True

    body = {
        "text": text,
        "model": MODEL,
        "voice_id": VOICE_ID,
        "language": lang,
        "prompt": {"emotion_type": "preset", "emotion_preset": emotion,
                   "emotion_intensity": intensity},
        "output": {"audio_format": "mp3"},
    }
    try:
        res = requests.post(
            API_URL,
            headers={"X-API-KEY": _api_key(), "Content-Type": "application/json"},
            json=body, timeout=120,
        )
    except requests.RequestException as e:
        raise TtsError(f"Typecast에 연결하지 못했습니다: {e}") from e

    if res.status_code != 200:
        # 403은 플랜 문제가 대부분이다 — 웹 서비스 플랜과 API 플랜은 별개이고,
        # Starter 플랜 키는 ssfm 모델과 호환되지 않는다.
        raise TtsError(f"Typecast {res.status_code}: {res.text[:200]}")

    audio = res.content
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    path.write_bytes(audio)

    if conn is not None:
        _ensure_schema(conn)
        conn.execute(
            """INSERT OR REPLACE INTO tts_cache
               (hash, voice_id, model, emotion, lang, bytes, created_at)
               VALUES (?,?,?,?,?,?,?)""",
            (key, VOICE_ID, MODEL, emotion, lang, len(audio), time.time()),
        )
        conn.commit()

    logger.info("tts 생성 %s (%d자 → %.0fKB)", key[:12], len(text), len(audio) / 1024)
    return audio, False
