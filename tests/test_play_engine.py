"""PLAY 엔진 — 되돌리면 안 되는 결정을 지키는 테스트.

버그를 잡으려는 테스트가 아니다. 세션이 끊기면 다음 세션의 나는 오늘의 결정을
모른다. **"이 값을 함부로 바꾸지 마라, 이유는 이거다"를 코드에 박아두는 장치**다.
그래서 docstring 에 왜 그 값인지를 반드시 적는다 (CLAUDE.md).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

BASE_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(BASE_DIR / "backend"))

from models.play import Play, Step  # noqa: E402
from services import place_registry as registry  # noqa: E402
from services import play_loader  # noqa: E402
from services.db import get_db_connection  # noqa: E402


@pytest.fixture(scope="module")
def conn():
    c = get_db_connection()
    registry.ensure_synced(c)
    return c


@pytest.fixture(scope="module")
def seongeup(conn) -> Play:
    play = play_loader.get(conn, "seongeup-restore")
    assert play is not None, "성읍 PLAY 원고를 못 읽었습니다"
    return play


# ── Place 정체성 ──────────────────────────────────────────────────────────────

class TestPlaceIdentity:
    """**놀멍봅서 Place 의 정체성은 어느 공급자에도 종속되지 않는다** (2026-09-02 결정).

    Odii `stid` 를 Place PK 로 쓰는 안을 검토했으나 채택하지 않았다. Odii 는 이제
    Place 의 주 공급원이 아니라 여러 Source 중 하나이고, 특정 공급자의 ID 를 내부
    PK 로 쓰면 공급자를 바꾸거나 늘릴 때 Place 가 통째로 흔들리기 때문이다.
    """

    def test_place_id_는_외부_id_가_아니다(self, conn):
        """place_id 에 stid 를 그대로 넣지 않는다.

        여기가 무너지면 "Odii 를 안 쓰게 되면 Place 가 사라지는" 구조로 되돌아간다.
        """
        pid = registry.find_by_external(conn, registry.SOURCE_ODII, "2166")
        assert pid is not None
        assert pid != "2166"
        assert len(pid) == 36 and pid.count("-") == 4, "uuid 형식이어야 합니다"

    def test_한_place_에_여러_외부_id_가_붙는다(self, conn):
        """성읍 하나에 Odii 해설이 8건 달린다.

        `Place 1 : N external_id` 가 아니면 "이 장소의 오디 해설 전부"를 못 찾고,
        나중에 KTO contentId·국가유산 ID 를 같이 붙일 수도 없다.
        """
        pid = registry.find_by_external(conn, registry.SOURCE_ODII, "2166")
        stids = registry.external_ids(conn, pid, registry.SOURCE_ODII)
        assert len(stids) >= 8, f"성읍에 붙은 stid 가 {len(stids)}개뿐입니다"
        assert "982" in stids and "2161" in stids

    def test_한_외부_id_는_한_place_에만_붙는다(self, conn):
        """같은 stid 가 두 Place 를 오가면 PLAY 의 Story 연결이 조용히 끊긴다."""
        pid = registry.find_by_external(conn, registry.SOURCE_ODII, "2166")
        other = registry.new_place_id()
        with pytest.raises(ValueError):
            registry.link_external(conn, other, registry.SOURCE_ODII, "2166")

    def test_다시_동기화해도_place_id_가_그대로다(self, conn):
        """`home_places` 는 build() 가 통째로 갈아엎지만 place_id 는 PLAY 가 FK 로
        물고 있다. 재발급되면 이미 만든 PLAY 가 전부 미아가 된다.
        """
        before = registry.find_by_external(conn, registry.SOURCE_ODII, "2166")
        registry.sync_from_home_places(conn)
        after = registry.find_by_external(conn, registry.SOURCE_ODII, "2166")
        assert before == after

    def test_이름은_identity_가_아니다(self, conn):
        """이름이 바뀌어도 Place 는 같아야 한다.

        전에는 이름 문자열이 사실상 키였다 — `home_stage.json` 의 name 이
        `home_places.name` 과 한 글자만 달라도 카드가 조용히 사라졌다.
        """
        pid = registry.find_by_external(conn, registry.SOURCE_ODII, "2166")
        conn.execute("UPDATE places SET display_name = ? WHERE id = ?", ("잠깐다른이름", pid))
        assert registry.find_by_external(conn, registry.SOURCE_ODII, "2166") == pid
        conn.execute("UPDATE places SET display_name = ? WHERE id = ?", ("성읍민속마을", pid))
        conn.commit()


# ── PLAY ↔ Place ──────────────────────────────────────────────────────────────

class TestPlayReferencesPlaceId:
    def test_play_는_place_id_를_fk_로_문다(self, conn, seongeup):
        """PLAY 가 외부 ID 를 직접 물면 공급자 교체가 불가능해진다.

        원고 파일에는 사람이 읽을 수 있는 `place_ref`(odii:2166)로 적고,
        불러올 때 레지스트리가 place_id 로 바꾼다.
        """
        assert seongeup.place_id
        assert seongeup.place_id != seongeup.place_ref.external_id
        assert registry.get(conn, seongeup.place_id) is not None

    def test_place_에서_play_를_찾을_수_있다(self, conn, seongeup):
        """`Place 1 : N PLAY`. 장소 상세의 「이 장소에서 할 수 있는 PLAY」 섹션이 쓴다."""
        plays = play_loader.for_place(conn, seongeup.place_id)
        assert [p.id for p in plays] == ["seongeup-restore"]


# ── 지도 ──────────────────────────────────────────────────────────────────────

class TestMapIsPlayMap:
    """지도가 답하는 질문이 바뀌었다 (2026-09-02).

      전: "제주에 오디 해설이 몇 개 있나"  → 핀 121개
      후: "제주 어디서 놀멍봅서를 할 수 있고 앞으로 어디에 생기나"

    오디 121곳은 **내부 콘텐츠 후보 Pool 로만** 남는다.
    """

    def test_오디_121곳을_사용자에게_뿌리지_않는다(self, conn):
        """여기가 무너지면 "PLAY 5곳"이 "해설 121곳"에 묻혀 안 보인다."""
        pins = play_loader.map_pins(conn)
        assert len(pins) < 60, f"핀이 {len(pins)}개입니다. 오디 전체가 새어 나왔습니다"

    def test_활성_핀에는_play_가_준비중_핀에는_없다(self, conn):
        """핀을 눌렀을 때 보여줄 것이 상태마다 다르다.
        활성이면 PLAY 정보, 준비 중이면 장소 이름과 「준비 중」이다.
        """
        pins = play_loader.map_pins(conn)
        for pin in pins:
            if pin.status == "active":
                assert pin.play is not None and pin.play.mission_count > 0
            else:
                assert pin.play is None

    def test_핀_좌표가_비어_있지_않다(self, conn):
        pins = play_loader.map_pins(conn)
        assert pins
        assert all(p.lat and p.lng for p in pins)


# ── 성읍 콘텐츠 ───────────────────────────────────────────────────────────────

class TestSeongeupContent:
    """`docs/기획/콘텐츠/성읍민속마을.md` 가 정본이다. 여기 숫자는 그 문서의 결정이다."""

    def test_구성이_정본과_같다(self, seongeup):
        """4 Point · 8 Main Mission · 5 Story · 생활기록 6칸.

        Mission 을 9개로 맞추려고 약한 문제를 넣지 않기로 했다 —
        정본 §17 「현재 제외 소재」(돈궤·돌구유·통시 등)가 그 결정의 기록이다.
        """
        assert len(seongeup.points) == 4
        assert seongeup.mission_count == 8
        assert len(seongeup.stories) == 5
        assert len(seongeup.progress_records) == 6

    def test_진행도_6칸이_전부_채워질_수_있다(self, seongeup):
        """끝까지 갔는데 5/6 에서 멈추면 CLEAR 화면의 "6 / 6 RESTORED"가 거짓이 된다."""
        rewards = {m.progress_reward for p in seongeup.points for m in p.missions}
        assert {r.id for r in seongeup.progress_records} <= rewards

    def test_m05_는_방향_정답을_쓰지_않는다(self, seongeup):
        """정본 §M05 「방향 정답 사용 금지」.

        자료마다 안거리·밖거리의 좌/우 설명이 엇갈린다. 방향으로 물으면
        현장에서 맞는 답이 틀린 것으로 처리될 수 있다. 대신 "두 집채가
        마주 보는 구조"를 관찰하게 한다.
        """
        m05 = next(m for p in seongeup.points for m in p.missions if m.id == "m05")
        assert all(s.input_type != "DIRECTION" for s in m05.steps)

    def test_대표_시연_미션은_호령창이다(self, seongeup):
        """심사위원에게 하나만 보여준다면 이것이다.

        "설명을 듣고 호령창을 아는 것"과 "직접 문을 들여다보다 작은 문을 발견한 뒤
        그게 무엇인지 알게 되는 것"의 차이가 제품 차별점을 그대로 보여준다.
        """
        showcase = [m for p in seongeup.points for m in p.missions if m.is_showcase]
        assert [m.id for m in showcase] == ["m08"]
        assert showcase[0].discovery.title == "호령창"

    def test_웹검증_유력_미션에는_힌트가_둘_다_있다(self, seongeup):
        """🟡 은 현장에서 못 찾을 수 있다는 뜻이다. 현장 답사를 하지 않기로 했으므로
        (2026-09-02) 힌트와 건너뛰기가 **없으면 그 미션이 성립하지 않는다.**
        """
        likely = [m for p in seongeup.points for m in p.missions
                  if m.verification == "likely"]
        assert {m.id for m in likely} == {"m04", "m07"}
        for m in likely:
            assert len(m.hints) == 2, f"{m.id} 의 힌트가 {len(m.hints)}개입니다"

    def test_final_은_직접_발견한_것만_묻는다(self, seongeup):
        """정본 §12 「신규 지식 출제: 금지」.

        Final 에서 새 잡학을 물으면 지금까지 현실을 본 경험이 시험으로 바뀐다.
        6쌍 전부가 앞에서 사용자가 직접 발견한 것이어야 한다.
        """
        assert seongeup.final is not None
        step = seongeup.final.step
        assert step.input_type == "MATCH_ORDER"
        assert len(step.answer) == 6
        assert len(step.options) == 6 and len(step.match_targets) == 6

    def test_모든_미션에_힌트가_둘_있다(self, seongeup):
        """Hint 1 은 **어디를 볼지**, Hint 2 는 **무엇을 볼지**.
        하나뿐이면 그 하나가 답을 흘리게 된다.
        """
        for p in seongeup.points:
            for m in p.missions:
                assert len(m.hints) == 2, f"{m.id} 힌트 {len(m.hints)}개"


# ── Story 는 오디 원문이 아니다 ───────────────────────────────────────────────

class TestStoryIsOurs:
    """2026-09-02 결정. `미션 클리어 → 오디 대본 자동재생` 구조를 폐기했다.

    Story 는 오디·국가유산·한국민족문화대백과를 교차검증해 **놀멍봅서가 직접 쓴
    문장**이다. 오디 `stid` 는 출처 메타데이터로만 남는다.
    """

    def test_story_에_우리_문장이_들어_있다(self, seongeup):
        """script 가 비어 있고 stid 만 있으면 예전 구조(오디 자동재생)로 되돌아간 것이다."""
        for s in seongeup.stories:
            assert s.script.strip(), f"{s.id} 에 script 가 없습니다"

    def test_story_길이가_읽어줄_만하다(self, seongeup):
        """기본 15~35초, 중요한 것도 45초 이내 (정본 §5).

        한국어 TTS 는 대략 초당 5~6자다. 45초면 270자 안쪽이다. 길면 사용자가
        현실에서 눈을 떼고 서 있는 시간이 길어진다.
        """
        for s in seongeup.stories:
            assert len(s.script) <= 300, f"{s.id} 가 {len(s.script)}자입니다"

    def test_출처가_붙어_있다(self, seongeup):
        """Story 핵심 주장이 어디서 검증됐는지 추적 가능해야 한다 (정본 §18)."""
        for s in seongeup.stories:
            assert s.sources, f"{s.id} 에 출처가 없습니다"


# ── 모델 방어 ─────────────────────────────────────────────────────────────────

class TestModelGuards:
    """콘텐츠 원고의 실수를 서버가 뜨기 전에 잡는다. 잘못된 PLAY 는 현장에서
    사용자를 막아 세우는데, 그때는 고칠 수 없다.
    """

    def test_짧은_답은_허용_답안을_목록으로_받는다(self):
        """표기가 갈리는 답 때문에 정답을 못 맞히는 일이 제일 흔하다."""
        with pytest.raises(ValueError):
            Step(input_type="SHORT_TEXT", prompt="현판의 글자는?", answer="정의현")
        Step(input_type="SHORT_TEXT", prompt="현판의 글자는?", answer=["정의현", "旌義縣"])

    def test_보기에_없는_답을_막는다(self):
        with pytest.raises(ValueError):
            Step(input_type="CHOICE", prompt="?",
                 options=[{"id": "a", "label": "가"}, {"id": "b", "label": "나"}],
                 answer="c")

    def test_힌트_세_개를_막는다(self):
        """힌트는 '어디를'·'무엇을' 두 단계다. 셋째는 사실상 정답 공개이고,
        그건 `[정답과 이야기 보기]` 가 하는 일이다.
        """
        from models.play import Mission
        with pytest.raises(ValueError):
            Mission(id="x", title="x",
                    steps=[{"input_type": "CONFIRM", "prompt": "?"}],
                    hints=[{"text": "1"}, {"text": "2"}, {"text": "3"}])

    def test_아무도_안_채우는_진행도_칸을_막는다(self):
        """끝까지 가도 100%가 안 되는 PLAY 를 배포하지 않는다."""
        raw = json.loads((BASE_DIR / "data/plays/seongeup.json").read_text(encoding="utf-8"))
        raw = {k: v for k, v in raw.items() if not k.startswith("_")}
        raw["progress_records"].append({"id": "nobody", "label": "아무도"})
        with pytest.raises(ValueError):
            Play(**raw)
