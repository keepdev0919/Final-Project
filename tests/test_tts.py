"""곱닥이 목소리와 TTS 캐시 규칙을 못 박는다.

## 왜 테스트하나

목소리가 조용히 바뀌면 **앱 전체의 인격이 바뀌는데 아무도 모른다.** 화면은
멀쩡하고 소리만 다른 사람이 된다. 그리고 캐시 키에서 조건 하나를 빠뜨리면
옛 목소리가 계속 나온다 — 이것도 조용히 틀린다.

## 안 D (2026-08-20 결정)

같은 대본·같은 목소리면 결과가 항상 같다. 그래서 **장소당 한 번만 생성**하고
해시로 찾아 쓴다. 실측 계산이 이 결정을 정했다.

    안 C (매 재생마다 생성)  하루 20명 × 5곳 → 월 228만 크레딧 ≈ $202
    안 D (장소당 1번)        189곳 전체 1회  →    14만 크레딧 ≈ $15 한 번

**대본 텍스트는 어디에도 저장하지 않는다.** 해시만 저장한다 — 오디 대본을
쟁여두지 않겠다는 결정(설계 v2 §2)을 지키면서 생성 비용만 줄이기 위해서다.
"""
import pytest

from services import typecast


def test_voice_is_pinned():
    """곱닥이 목소리를 고정한다 (2026-08-20 조익준님 선택).

    Mirei Kato / ssfm-v30. 바꾸려면 이 테스트를 같이 고치면서
    "왜 바꾸는지"를 남길 것. 목소리는 콘텐츠 품질 영역이라
    조익준님 결정 없이 바뀌어선 안 된다.
    """
    assert typecast.VOICE_ID == "tc_63edf3ccd8e2eb7338999376"
    assert typecast.MODEL == "ssfm-v30"


def test_cache_key_covers_every_condition_that_changes_the_audio():
    """음성을 달라지게 하는 조건이 전부 키에 들어가야 한다.

    하나라도 빠지면 조건을 바꿔도 옛 캐시가 나온다. 목소리를 바꿨는데
    그대로인 상황이 생기고, 원인을 찾기 어렵다.
    """
    base = typecast.cache_key("성산일출봉", emotion="normal", lang="kor")

    assert base != typecast.cache_key("섭지코지", emotion="normal", lang="kor"), "대본"
    assert base != typecast.cache_key("성산일출봉", emotion="whisper", lang="kor"), "감정"
    assert base != typecast.cache_key("성산일출봉", emotion="normal", lang="eng"), "언어"
    assert base != typecast.cache_key("성산일출봉", emotion="normal", lang="kor",
                                      voice_id="tc_other"), "목소리"
    assert base != typecast.cache_key("성산일출봉", emotion="normal", lang="kor",
                                      model="ssfm-v21"), "모델"

    # 같은 조건이면 항상 같아야 한다 — 그래야 캐시가 맞는다.
    assert base == typecast.cache_key("성산일출봉", emotion="normal", lang="kor")


def test_cache_key_does_not_leak_the_script():
    """키는 해시다. 대본이 그대로 들어가 있으면 저장 안 하겠다는 결정이 무의미해진다."""
    script = "약 5천년 전, 지하에 있던 마그마가 물과 만나 격렬하게 터지면서"
    key = typecast.cache_key(script, emotion="normal", lang="kor")
    assert script not in key
    assert len(key) == 64 and all(c in "0123456789abcdef" for c in key)


def test_cache_table_has_no_text_column():
    """`tts_cache` 테이블에 대본을 담는 칸이 있으면 안 된다.

    칸이 있으면 누군가 채운다. 구조로 막는다.
    """
    import sqlite3

    conn = sqlite3.connect(":memory:")
    typecast._ensure_schema(conn)
    cols = {row[1] for row in conn.execute("PRAGMA table_info(tts_cache)")}
    for banned in ("text", "script", "content", "body"):
        assert banned not in cols, f"tts_cache에 '{banned}' 칸이 있다"
    assert "hash" in cols


def test_overlong_script_raises_instead_of_truncating():
    """2,000자를 넘으면 잘라서 반쪽 음성을 내보내지 않고 예외를 올린다.

    조용히 자르면 사용자는 이야기가 중간에 끊긴 걸 '원래 그런 것'으로 받아들인다.
    (현재 오디 대본은 최대 246초 ≈ 1,600자라 여기 걸리지 않는다. 나중에 우리가
    쓴 긴 대본이 들어올 때를 위한 방어다.)
    """
    with pytest.raises(typecast.TtsError):
        typecast.synth("가" * (typecast.MAX_CHARS + 1))


def test_empty_script_raises():
    with pytest.raises(typecast.TtsError):
        typecast.synth("   ")
