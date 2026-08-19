"""오디(Odii) 연동에서 지켜야 할 결정을 고정한다.

핵심 결정은 하나다 — **대본은 로컬에 저장하지 않는다.**
목록(제목·좌표·stid)만 저장하고, 대본과 음성은 사용자가 재생을 누를 때
관광공사에서 실시간으로 받는다. 편해 보인다고 대본을 저장하면 두 가지가
동시에 무너지므로 테스트로 막는다.
"""

import json
import sys
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "backend"))

from routers import odii  # noqa: E402

ODII_SRC = (PROJECT_ROOT / "backend" / "routers" / "odii.py").read_text(encoding="utf-8")
DB_SRC = (PROJECT_ROOT / "backend" / "services" / "db.py").read_text(encoding="utf-8")


def test_script_is_not_stored_in_the_place_list():
    """`odii_places` 테이블에 대본 칸을 만들지 않는다.

    이유 둘.
    ① 관광공사 콘텐츠를 통째로 쟁여두고 우리 앱에서 재배포하는 모양이 된다.
       오디오 파일이 21%뿐이라 나머지는 우리가 TTS로 읽어야 하는데, 그 저작권
       판단은 아직 주최측 답을 못 받았다. 저장까지 하면 더 무거워진다.
    ② 공지: "로컬 DB 저장 방식이 아닌 실시간 호출 방식으로 활용할 것을 강력히
       권고. 개발 기간 내 API 호출 이력이 확인되지 않을 경우 심사에서 불이익."
       재생이 곧 호출이어야 이력이 쌓인다.

    있는지 여부(`has_script`)만 저장한다 — 지도에 찍을지 말지 판단하려면 필요하다.
    """
    table = DB_SRC.split("CREATE TABLE IF NOT EXISTS odii_places")[1].split(")")[0]
    assert "has_script" in table
    assert "script  " not in table.replace("has_script", ""), "대본 칸이 생겼다"


def test_place_list_excludes_stories_without_script():
    """대본 없는 건(제주 35건)은 지도·목록에 내보내지 않는다.

    눌러도 나올 게 없는 핀을 찍으면 사용자는 20번 눌러 19번 실망한다.
    심사위원도 같은 경험을 한다.
    """
    assert "has_script = 1" in ODII_SRC


def test_langcode_is_always_sent():
    """`langCode`는 오디의 필수 파라미터다.

    빠뜨리면 `NO_MANDATORY_REQUEST_PARAMETERS_ERROR1(langCode)`로 실패한다.
    KorService2에는 없는 파라미터라 습관적으로 빠뜨리기 쉽다.
    """
    for call in ODII_SRC.split('_kto_get("Odii"')[1:]:
        assert '"langCode"' in call.split("})")[0], "langCode 없는 오디 호출이 있다"


@pytest.mark.parametrize("payload,expected", [
    ({"response": {"body": {"items": {"item": [{"stid": "1"}, {"stid": "2"}]}}}}, 2),
    ({"items": [{"stid": "1"}]}, 1),                       # 두 번째 응답 형태
    ({"response": {"body": {"items": {"item": {"stid": "1"}}}}}, 1),  # 1건일 때 dict
    ({"response": {"body": {"items": ""}}}, 0),            # 결과 없음
])
def test_both_response_shapes_are_parsed(payload, expected):
    """오디는 같은 오퍼레이션이 두 가지 형태로 응답한다.

    `{"response":{"body":{"items":{"item":[...]}}}}` 와 `{"items":[...]}`.
    게다가 1건일 때는 리스트가 아니라 객체로 온다. 한쪽만 처리하면 어떤
    장소에서는 조용히 "해설 없음"이 된다.
    """
    assert len(odii._items(payload)) == expected


def test_single_story_lookup_uses_a_tight_radius():
    """단건은 좌표 + 좁은 반경으로 가져온다.

    오디에는 ID 단건 조회가 없다 — `storyBasedList?tid=969`는 필터를 무시하고
    전체 6,547건을 돌려준다(2026-08-19 실측). 반경을 넓히면 옆 장소 해설이
    딸려와 엉뚱한 걸 재생하게 된다.
    """
    assert odii.STORY_RADIUS <= 300


def test_story_endpoint_never_accepts_coordinates():
    """`/odii/story`는 좌표를 받지 않고 `stid`만 받는다.

    오디 API 자체는 좌표로만 조회되지만, 그 좌표는 **서버가 저장된 목록에서
    꺼내 쓴다.** 클라이언트가 좌표를 보내는 구조로 두면 나중에 누가
    "내 주변 해설 듣기"를 붙이면서 사용자 위치를 넘기게 되고, 그 순간
    위치기반서비스사업자 신고 대상이 된다(공지 FAQ: 위치를 사업자 서버로
    전송하면 DB 저장 여부와 무관하게 해당).

    문서로 부탁하지 않고 파라미터로 막는다.
    """
    import inspect
    params = set(inspect.signature(odii.get_story).parameters)
    assert "stid" in params
    assert not ({"lat", "lng", "mapX", "mapY"} & params), "좌표 파라미터가 생겼다"
