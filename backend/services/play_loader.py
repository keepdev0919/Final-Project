"""PLAY 콘텐츠 로더 — `data/plays/*.json` 을 읽어 검증하고 Place 에 연결한다.

## 왜 파일인가

PLAY 는 사람이 손으로 쓰는 원고다. 다섯 개뿐이고, 문구 한 줄을 고치는 일이
자주 생긴다. DB 에 넣으면 고칠 때마다 마이그레이션이 필요하고 git 에서
무엇이 바뀌었는지 안 보인다. 파일이면 정본 문서
(`docs/기획/콘텐츠/성읍민속마을.md`)와 나란히 두고 볼 수 있다.

## place_ref → place_id

파일에는 사람이 읽을 수 있는 외부 ID(`odii:2166`)로 적고, 불러올 때
레지스트리가 **놀멍봅서 place_id 로 바꾼다.** 원고에 uuid 를 손으로 적게
하지 않으면서도, 메모리에 올라온 PLAY 는 `place_id` 를 물고 있다.

Place 의 정체성이 오디에 종속되는 것이 아니다 — 오디 stid 는 **찾아가는 열쇠**일
뿐이고, 연결된 뒤에는 place_id 가 주인이다. 나중에 오디를 안 쓰게 되면
`place_ref` 만 다른 공급원으로 바꾸면 된다.

## ⚠️ 캐시하지 않는다

원고를 고치고 서버를 안 껐다 켜도 바로 반영돼야 한다. 파일 다섯 개를 읽는
비용은 무시할 수 있다.
"""
from __future__ import annotations

import json
import logging
from pathlib import Path

from models.play import MapPin, Play, PlaySummary
from services import place_registry as registry

logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).parent.parent.parent
PLAY_DIR = BASE_DIR / "data" / "plays"


def _strip_notes(data: dict) -> dict:
    """`_읽어보세요` 처럼 사람에게 남긴 메모는 모델에 넣지 않는다."""
    return {k: v for k, v in data.items() if not k.startswith("_")}


def load_all(conn) -> list[Play]:
    """PLAY 원고를 전부 읽는다.

    한 파일이 깨져도 나머지는 살린다 — 원고 하나의 오타 때문에 앱 전체가
    빈 화면이 되면 안 된다. 대신 **조용히 넘기지 않고 로그로 크게 남긴다.**
    """
    plays: list[Play] = []
    if not PLAY_DIR.exists():
        return plays

    for path in sorted(PLAY_DIR.glob("*.json")):
        try:
            raw = _strip_notes(json.loads(path.read_text(encoding="utf-8")))
            play = Play(**raw)
        except Exception as exc:  # noqa: BLE001
            logger.error("[PLAY] %s 를 읽지 못했습니다: %s", path.name, exc)
            continue

        if not _attach_place(conn, play, path.name):
            continue
        plays.append(play)

    return plays


def _attach_place(conn, play: Play, filename: str) -> bool:
    """`place_ref` 를 놀멍봅서 place_id 로 바꾼다. 못 찾으면 그 PLAY 를 버린다."""
    if play.place_id:
        return True
    if play.place_ref is None:
        logger.error("[PLAY] %s 에 place_ref 도 place_id 도 없습니다", filename)
        return False

    place_id = registry.find_by_external(
        conn, play.place_ref.source, play.place_ref.external_id
    )
    if place_id is None:
        logger.error(
            "[PLAY] %s 가 가리키는 장소(%s:%s)를 레지스트리에서 못 찾았습니다. "
            "place_registry.sync_from_home_places() 를 먼저 돌리세요",
            filename, play.place_ref.source, play.place_ref.external_id,
        )
        return False

    play.place_id = place_id
    if not play.place_name:
        place = registry.get(conn, place_id)
        play.place_name = place["display_name"] if place else ""
    return True


def get(conn, play_id: str) -> Play | None:
    for play in load_all(conn):
        if play.id == play_id:
            return play
    return None


def for_place(conn, place_id: str) -> list[Play]:
    """이 장소에서 할 수 있는 PLAY 전부.

    **Place 1 : N PLAY** 다. 제주돌문화공원처럼 큰 곳은 나중에 야외전시장·
    신화의 정원·초가마을이 각각 PLAY 가 된다.
    """
    return [p for p in load_all(conn) if p.place_id == place_id]


# ── 요약 · 지도 ───────────────────────────────────────────────────────────────

def _thumbnail(conn, place_id: str) -> str | None:
    """대표 사진. KTO 가 채워 둔 것을 재사용한다.

    `home_places` 를 이름으로 뒤지지 않고 place_id → 대표 stid → 사진 순으로 간다.
    이름으로 뒤지면 이름이 바뀌는 순간 사진이 조용히 사라진다.
    """
    stids = registry.external_ids(conn, place_id, registry.SOURCE_ODII)
    if not stids:
        return None
    placeholders = ",".join("?" * len(stids))
    row = conn.execute(
        f"SELECT thumbnail FROM home_places WHERE stid IN ({placeholders}) "
        "AND thumbnail IS NOT NULL AND thumbnail != '' LIMIT 1",
        stids,
    ).fetchone()
    return row["thumbnail"] if row else None


def summarize(conn, play: Play) -> PlaySummary:
    return PlaySummary(
        id=play.id,
        place_id=play.place_id,
        place_name=play.place_name,
        title=play.title,
        objective=play.objective,
        estimated_minutes_min=play.estimated_minutes_min,
        estimated_minutes_max=play.estimated_minutes_max,
        distance_meters=play.distance_meters,
        difficulty=play.difficulty,
        mission_count=play.mission_count,
        thumbnail=_thumbnail(conn, play.place_id),
    )


# 준비 중 핀으로 띄울 후보. `docs/기획/Odii_원본기준_전수분류.md` §3 의
# 🟢 가능 27개에서 이미 PLAY 가 있는 곳을 뺀 목록이다.
#
# ⚠️ 여기 이름은 `home_places.name` 과 정확히 같아야 찾아진다. 이름은 identity 가
# 아니므로, 못 찾은 것은 **조용히 빠지지 않고** 로그로 알린다.
PREPARING_PLACE_NAMES = (
    "관음사", "제주목관아", "제주돌문화공원", "항파두리 항몽유적지",
    "약천사", "제주추사관", "수월봉", "제주항일기념관", "대정향교",
    "제주민속자연사박물관", "국립제주박물관", "제주세계자연유산센터",
    "제주해녀박물관", "제주민속촌", "제주감귤박물관",
    "알뜨르비행장 지하벙커", "송악산 일제 동굴진지", "남제주 비행기 격납고",
    "서귀포 이중섭 미술관", "왈종미술관", "오설록 티 뮤지엄", "성산일출봉",
)


def map_pins(conn) -> list[MapPin]:
    """PLAY 지도 핀.

    답하는 질문이 바뀌었다 (2026-09-02).
      전: "제주에 오디 해설이 몇 개 있나" → 121 핀
      후: "제주 어디서 놀멍봅서를 할 수 있고, 앞으로 어디에 생기나"

    오디 121곳은 **내부 콘텐츠 후보 Pool 로만** 남는다. 사용자에게는
    플레이할 수 있는 곳과 준비 중인 곳만 보인다.
    """
    pins: list[MapPin] = []
    active_place_ids: set[str] = set()

    for play in load_all(conn):
        place = registry.get(conn, play.place_id)
        if place is None:
            continue
        active_place_ids.add(play.place_id)
        pins.append(MapPin(
            place_id=place["id"],
            place_name=place["display_name"],
            lat=place["lat"],
            lng=place["lng"],
            status="active",
            play=summarize(conn, play),
        ))

    for name in PREPARING_PLACE_NAMES:
        row = conn.execute(
            "SELECT stid FROM home_places WHERE name = ?", (name,)
        ).fetchone()
        if row is None:
            logger.warning("[PLAY] 준비 중 후보 '%s' 를 home_places 에서 못 찾았습니다", name)
            continue
        place_id = registry.find_by_external(conn, registry.SOURCE_ODII, row["stid"])
        if place_id is None or place_id in active_place_ids:
            continue
        place = registry.get(conn, place_id)
        if place is None:
            continue
        active_place_ids.add(place_id)
        pins.append(MapPin(
            place_id=place["id"],
            place_name=place["display_name"],
            lat=place["lat"],
            lng=place["lng"],
            status="preparing",
        ))

    return pins
