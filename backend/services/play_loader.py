"""PLAY 콘텐츠 로더 — `data/plays/*.json` 을 읽어 검증하고 Place 에 연결한다.

## 왜 파일인가

PLAY 는 사람이 손으로 쓰는 원고다. 다섯 개뿐이고, 문구 한 줄을 고치는 일이
자주 생긴다. DB 에 넣으면 고칠 때마다 마이그레이션이 필요하고 git 에서
무엇이 바뀌었는지 안 보인다. 파일이면 정본 문서
(`docs/기획/콘텐츠/성읍민속마을.md`)와 나란히 두고 볼 수 있다.

## place_key → place_id

원고에는 `data/places.json` 의 **자체 키**(`seongeup-folk-village`)로 적고,
불러올 때 레지스트리가 놀멍봅서 place_id 로 바꾼다. 원고에 uuid 를 손으로
적게 하지 않으면서도, 메모리에 올라온 PLAY 는 `place_id` 를 물고 있다.

⚠️ 오디 `stid` 로 가리키지 않는다. 오디는 콘텐츠 조사 Source 중 하나일
뿐인데 그것으로 Place 를 찾게 만들면 **오디를 안 쓰는 순간 장소를 못 찾는다**
(2026-09-02 결정).

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
    """`place_key` 를 놀멍봅서 place_id 로 바꾼다. 못 찾으면 그 PLAY 를 버린다."""
    place = registry.by_key(conn, play.place_key)
    if place is None:
        logger.error(
            "[PLAY] %s 가 가리키는 장소 '%s' 가 data/places.json 에 없습니다",
            filename, play.place_key,
        )
        return False
    play.place_id = place["id"]
    if not play.place_name:
        play.place_name = place["display_name"]
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

    이름으로 뒤지지 않는다 — 이름이 바뀌면 사진이 조용히 사라진다.
    지금은 오디 stid 를 임시 열쇠로 쓴다. **KTO contentId 를 장소마다 확보하면
    그쪽으로 옮긴다** (`data/places.json` 참조).
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
        place_key=play.place_key,
        place_name=play.place_name,
        title=play.title,
        objective=play.objective,
        card_summary=play.card_summary,
        estimated_minutes_min=play.estimated_minutes_min,
        estimated_minutes_max=play.estimated_minutes_max,
        distance_meters=play.distance_meters,
        difficulty=play.difficulty,
        difficulty_stars=play.difficulty_stars,
        mission_count=play.mission_count,
        thumbnail=_thumbnail(conn, play.place_id),
    )


def map_pins(conn) -> list[MapPin]:
    """PLAY 지도 핀.

    답하는 질문이 바뀌었다 (2026-09-02).
      전: "제주에 오디 해설이 몇 개 있나" → 121 핀
      후: "제주 어디서 놀멍봅서를 할 수 있고, 앞으로 어디에 생기나"

    오디 121곳은 **내부 콘텐츠 후보 Pool 로만** 남는다. 사용자에게는
    플레이할 수 있는 곳과 준비 중인 곳만 보인다.
    """
    plays_by_place: dict[str, list] = {}
    for play in load_all(conn):
        plays_by_place.setdefault(play.place_id, []).append(play)

    pins: list[MapPin] = []
    for place in registry.all_places(conn):
        # CANDIDATE 는 띄우지 않는다 (데이터.md §11).
        if place["status"] == registry.STATUS_CANDIDATE:
            continue

        plays = plays_by_place.get(place["id"], [])
        if place["status"] == registry.STATUS_LIVE and not plays:
            # LIVE 라고 적혀 있는데 원고가 없으면 눌러도 아무것도 없다.
            logger.error("[PLAY] '%s' 가 LIVE 인데 PLAY 원고가 없습니다", place["place_key"])
            continue

        pins.append(MapPin(
            place_id=place["id"],
            place_key=place["place_key"],
            place_name=place["display_name"],
            lat=place["lat"],
            lng=place["lng"],
            status="active" if plays else "preparing",
            thumbnail=_thumbnail(conn, place["id"]),
            # 한 Place 에 PLAY 가 여럿이면 핀에는 첫 번째만 붙인다.
            # 전부 보려면 장소 상세의 「이 장소에서 할 수 있는 PLAY」 로 간다.
            play=summarize(conn, plays[0]) if plays else None,
        ))

    return pins
