"""코스 카드 대표 사진이 **제목의 그 장소**를 가리키는지 못 박는다.

## 왜 테스트인가

대표 장소는 코스를 만들 때(`_make_title`) 정해져 제목에 박히고, 서빙할 때
(`course_thumbnail.lead_place_name`) 제목에서 되뽑힌다. **두 함수가 같은 형식을
알고 있어야만** 맞는 사진이 붙는다.

한쪽만 바꾸면 사진이 사라지는 게 아니라 **엉뚱한 장소의 사진이 붙는다.** 화면은
멀쩡하고 앱도 안 죽는다 — 「곽지해수욕장 외 5곳」 카드에 다른 데 사진이 붙어 있을
뿐이라, 사람이 사진을 알아보기 전까지 아무도 모른다. 그래서 테스트로 잡는다.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "backend"))

from services.course_thumbnail import lead_place_name  # noqa: E402


def test_reads_lead_from_the_usual_title():
    """`{권역} {일수}일 · {대표장소} 외 {N}곳` 이 기본 형식이다."""
    assert lead_place_name("서부 3일 · 곽지해수욕장 외 5곳") == "곽지해수욕장"


def test_reads_lead_when_there_is_only_one_place():
    """장소가 하나뿐이면 「외 N곳」이 안 붙는다."""
    assert lead_place_name("동부 1일 · 성산일출봉") == "성산일출봉"


def test_place_name_containing_digits_survives():
    """「9.81 파크」처럼 숫자가 든 이름이 잘려나가면 안 된다."""
    assert lead_place_name("서부 2일 · 9.81 파크 외 3곳") == "9.81 파크"


def test_place_name_containing_the_word_gos():
    """이름 안의 「곳」은 접미사가 아니다 — 「외 N곳」만 떼야 한다."""
    assert lead_place_name("남부 2일 · 쇠소깍 외 2곳") == "쇠소깍"


def test_no_lead_when_title_has_no_place():
    """대표 장소를 못 고른 코스는 `{권역} {일수}일 코스` 다. 사진도 없다."""
    assert lead_place_name("전체 3일 코스") is None


def test_matches_the_titles_the_builder_actually_makes():
    """빌드 스크립트가 만드는 형식과 **같은 형식**을 읽는지 직접 맞춰본다.

    여기가 두 파일을 묶는 자리다. `_make_title` 의 형식이 바뀌면 이 테스트가 깨진다.
    """
    sys.path.insert(0, str(Path(__file__).parent.parent / "backend" / "scripts"))
    from build_curated_courses import _make_title

    places = [
        {"place_name": "제주국제공항"},   # 교통시설 — 대표에서 빠진다
        {"place_name": "곽지해수욕장"},
        {"place_name": "협재해수욕장"},
    ]
    meta = {"곽지해수욕장": {"is_attraction": True},
            "협재해수욕장": {"is_attraction": True}}
    title = _make_title("서부", 2, places, meta, {}, set())
    assert lead_place_name(title) == "곽지해수욕장", title


def test_title_uses_the_display_name():
    """제목에는 정리된 표시 이름이 들어간다.

    원본은 `성산일출봉(UNESCO 세계자연유산)`인데 그대로 제목에 넣으면 카드가
    깨져 보인다(`build_place_display_names.py`). 썸네일은 제목에서 이름을 되뽑아
    사진을 찾으므로, **여기서 쓰는 이름과 `thumbnail_for` 가 찾는 이름이 어긋나면
    사진이 조용히 사라진다.** 그 연결을 지키는 자리다.
    """
    sys.path.insert(0, str(Path(__file__).parent.parent / "backend" / "scripts"))
    from build_curated_courses import _make_title

    places = [{"place_name": "성산일출봉(UNESCO 세계자연유산)"}, {"place_name": "우도(해양도립공원)"}]
    meta = {"성산일출봉(UNESCO 세계자연유산)": {"is_attraction": True}}
    display = {"성산일출봉(UNESCO 세계자연유산)": "성산일출봉", "우도(해양도립공원)": "우도"}

    title = _make_title("동부", 2, places, meta, display, set())
    assert lead_place_name(title) == "성산일출봉", title


def test_closed_place_is_not_the_lead():
    """폐업한 곳은 코스를 대표하지 않는다.

    원본에 `명월국민학교(폐업)` 같은 게 있다. 없어진 곳이 카드 제목이 되면
    사용자가 헛걸음한다.
    """
    sys.path.insert(0, str(Path(__file__).parent.parent / "backend" / "scripts"))
    from build_curated_courses import _make_title

    places = [{"place_name": "명월국민학교(폐업)"}, {"place_name": "협재해수욕장"}]
    meta = {"명월국민학교(폐업)": {"is_attraction": True},
            "협재해수욕장": {"is_attraction": True}}
    display = {"명월국민학교(폐업)": "명월국민학교"}

    title = _make_title("서부", 2, places, meta, display, {"명월국민학교"})
    assert lead_place_name(title) == "협재해수욕장", title
