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
    """곱닥이 목소리를 고정한다 — Toby (2026-09-11 조익준님 선택).

    곱딱이의 모든 대사를 자동으로 읽게 되면서 다시 골랐다. Moru·Toby 와 이전
    목소리 Jinseo 를 성읍 실제 대사 네 줄(길안내·미션·발견·이야기)로 비교했다.

    이전: Jinseo `tc_65bb3a1976b69213594357fc` (2026-08-20, 후보 11명 5초 샘플 비교).

    목소리가 **모르는 사이에 바뀌면 앱 전체의 인격이 바뀌는데 화면은 멀쩡하다.**
    바꿀 때는 이 테스트를 같이 고치면서 누가 왜 정했는지를 남긴다.
    """
    assert typecast.VOICE_ID == "tc_6080369d3211aa112ab131db"
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


def test_line_resolver_speaks_exactly_what_the_screen_shows():
    """곱딱이가 말하는 모든 말을 음성으로 읽는다 (2026-09-11 조익준님 결정).

    음성은 화면 자막과 같은 문장이어야 한다. iOS 는 첫 Step 에서 미션 prompt 와
    Step prompt 를 빈 줄로 이어 보여주므로 서버도 같은 규칙으로 문장을 만든다.
    클라이언트가 보낸 문장은 절대 읽지 않으므로 열쇠로만 문장을 찾는다.
    """
    from routers.tts import resolve_line
    from models.play import Play

    play = Play.model_validate({
        "id": "p", "place_key": "k", "title": "t",
        "estimated_minutes_min": 10, "estimated_minutes_max": 20,
        "distance_meters": 100, "difficulty": "쉬움",
        "points": [{
            "id": "pt1", "title": "대장간집", "objective": "경계의 흔적",
            "navigation_text": "주차장에서 마을 안쪽으로",
            "missions": [{
                "id": "m1", "title": "정낭", "prompt": "대문 자리를 봐.",
                "steps": [
                    {"input_type": "NUMBER", "prompt": "막대가 몇 개야?", "answer": 3,
                     "success_feedback": "맞아, 세 개!"},
                    {"input_type": "CONFIRM", "prompt": "걸린 개수를 확인해 봐.", "answer": True},
                ],
                "discovery": {"title": "정낭", "body": "정낭은 집주인의 부재를 알리는 신호였어."},
            }],
        }],
        "stories": [{"id": "s1", "script": "정낭 이야기", "unlock_after_mission": "m1"}],
        "final": {"title": "복원", "prompt": "순서대로 이어봐.",
                  "step": {"input_type": "CONFIRM", "prompt": "", "answer": True}},
        "clear": {"title": "완료", "body": "집이 그냥 건물이 아니란 걸 알게 됐지?"},
    })

    assert resolve_line(play, "point:pt1") == "주차장에서 마을 안쪽으로"
    assert resolve_line(play, "mission:m1:0") == "대문 자리를 봐.\n\n막대가 몇 개야?"
    assert resolve_line(play, "mission:m1:1") == "걸린 개수를 확인해 봐."
    assert resolve_line(play, "feedback:m1:0") == "맞아, 세 개!"
    assert resolve_line(play, "discovery:m1") == "정낭은 집주인의 부재를 알리는 신호였어."
    assert resolve_line(play, "story:s1") == "정낭 이야기"
    assert resolve_line(play, "final") == "순서대로 이어봐."
    assert resolve_line(play, "clear") == "집이 그냥 건물이 아니란 걸 알게 됐지?"

    import pytest as _pytest
    for bad in ("mission:m1:9", "story:none", "feedback:m1:1", "tell:me:anything", "point:x"):
        with _pytest.raises(ValueError):
            resolve_line(play, bad)


def test_seed_audio_is_served_without_calling_typecast(tmp_path, monkeypatch):
    """배포 이미지에 실은 미리 만든 음성은 Typecast 를 부르지 않고 나간다.

    운영 서버 첫 배포 날 Typecast 크레딧이 바닥나 음성이 전부 502 가 났다
    (2026-09-11). 개발 기기에서 만든 파일을 SEED_DIR 로 실어 보내 해결했다 —
    이 길이 막히면 크레딧이 없는 날 앱이 조용히 소리를 잃는다.
    """
    monkeypatch.setattr(typecast, "CACHE_DIR", tmp_path / "cache")
    monkeypatch.setattr(typecast, "SEED_DIR", tmp_path / "seed")
    (tmp_path / "seed").mkdir()
    key = typecast.cache_key("곱딱이 인사", emotion="normal", lang="kor")
    (tmp_path / "seed" / f"{key}.mp3").write_bytes(b"ID3seed")

    def boom(*a, **k):
        raise AssertionError("Typecast 를 부르면 안 된다")
    monkeypatch.setattr(typecast.requests, "post", boom)

    audio, from_cache = typecast.synth("곱딱이 인사")
    assert audio == b"ID3seed" and from_cache is True
