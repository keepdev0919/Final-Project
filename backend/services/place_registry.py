"""Place 레지스트리 — 놀멍봅서가 스스로 발급하는 장소 신분증.

## 원칙 (2026-09-02 조익준님 결정)

    "놀멍봅서 Place 의 정체성이 Odii/KTO/VisitJeju 어느 한 공급자에도 종속되지 않는다."

전에는 장소를 **이름 문자열**로 가리켰다. `CoursePlace.id = "이름-day"`,
`/place/detail?name=`, `home_stage.json` 의 name 이 `home_places.name` 과 한
글자만 달라도 카드가 조용히 사라졌다.

Odii `stid` 를 열쇠로 쓰는 안도 잠깐 썼다가 걷어냈다. **오디는 이제 콘텐츠
조사 Source 중 하나일 뿐인데, 그것으로 Place 를 찾게 만들면 오디를 안 쓰는
순간 장소를 못 찾는다.** 열쇠는 우리가 쥔다.

    places.place_key      놀멍봅서가 정한 자체 불변 키 (`data/places.json`)
                          화면에 안 보이고 검색에도 안 쓴다. 오직 재현용 열쇠다
    places.id             uuid7. PLAY·진행기록이 FK 로 무는 값
    place_external_ids    KTO contentId · Odii stid · 국가유산 ID …
                          **바깥 자료로 가는 다리이지 열쇠가 아니다**
    display_name          화면·검색용. identity 가 아니다

## 왜 uuid7 인가

의존성이 늘지 않고(`services/ids.py` — 표준 `uuid.uuid7()` 은 3.14 부터라 서버 3.12 에 없다),
ULID 의 장점인 **시간순 정렬**이 되며, 형식이 표준 UUID 라 나중에 다른 DB 로
옮겨도 통한다.

## 왜 121곳을 다 넣지 않나

오디에 해설이 있다는 것과 놀멍봅서가 Place 로 관리한다는 것은 다른 얘기다.
Place 가 필요한 곳은 **PLAY 가 있거나 지도에 「준비 중」으로 알리는 곳**뿐이다
(데이터.md §11). 나머지는 콘텐츠 조사용 후보 Pool 로만 남는다.

## ⚠️ append-only

`sync_from_file()` 은 `place_key` 로 기존 Place 를 찾아 **재사용**하고 없을
때만 발급한다. 몇 번을 돌려도 id 가 그대로다 — 재발급되면 이미 만든 PLAY 와
사용자의 진행 기록이 전부 미아가 된다.
"""
from __future__ import annotations

import json
import time
from pathlib import Path

from services.ids import uuid7

BASE_DIR = Path(__file__).parent.parent.parent
PLACES_FILE = BASE_DIR / "data" / "places.json"

# 외부 식별자 공급원.
SOURCE_ODII = "odii"
SOURCE_KTO = "kto"
SOURCE_VISITJEJU = "visitjeju"
SOURCE_HERITAGE = "heritage"

KNOWN_SOURCES = frozenset({SOURCE_ODII, SOURCE_KTO, SOURCE_VISITJEJU, SOURCE_HERITAGE})

# 지도 공개 상태. 정본은 `docs/기획/콘텐츠후보지.md`.
STATUS_LIVE = "LIVE"            # 플레이할 수 있다 → 활성 핀
STATUS_PLANNED = "PLANNED"      # 제작 대상 → 「준비 중」 핀
STATUS_CANDIDATE = "CANDIDATE"  # 후속 검토 → **지도에 띄우지 않는다**

KNOWN_STATUSES = frozenset({STATUS_LIVE, STATUS_PLANNED, STATUS_CANDIDATE})


def new_place_id() -> str:
    """새 Place ID. 시간순으로 정렬되는 uuid7."""
    return uuid7()


# ── 조회 ──────────────────────────────────────────────────────────────────────

def _row_to_place(conn, row) -> dict:
    externals = conn.execute(
        "SELECT source, external_id FROM place_external_ids WHERE place_id = ? "
        "ORDER BY source, external_id",
        (row["id"],),
    ).fetchall()
    return {
        "id": row["id"],
        "place_key": row["place_key"],
        "display_name": row["display_name"],
        "lat": row["lat"],
        "lng": row["lng"],
        "status": row["status"],
        "home_visible": bool(row["home_visible"]),
        "external_ids": [
            {"source": e["source"], "external_id": e["external_id"]} for e in externals
        ],
    }


def get(conn, place_id: str) -> dict | None:
    row = conn.execute("SELECT * FROM places WHERE id = ?", (place_id,)).fetchone()
    return _row_to_place(conn, row) if row else None


def by_key(conn, place_key: str) -> dict | None:
    """자체 키로 찾는다. **PLAY 원고와 코드가 Place 를 가리키는 정식 방법이다.**"""
    row = conn.execute(
        "SELECT * FROM places WHERE place_key = ?", (place_key,)
    ).fetchone()
    return _row_to_place(conn, row) if row else None


def all_places(conn, status: str | None = None) -> list[dict]:
    if status:
        rows = conn.execute(
            "SELECT * FROM places WHERE status = ? ORDER BY place_key", (status,)
        ).fetchall()
    else:
        rows = conn.execute("SELECT * FROM places ORDER BY place_key").fetchall()
    return [_row_to_place(conn, r) for r in rows]


def find_by_external(conn, source: str, external_id: str) -> str | None:
    """외부 ID 로 place_id 를 찾는다.

    ⚠️ **Place 를 가리키는 정식 방법이 아니다.** 그건 `by_key()` 다.
    이건 바깥에서 들어온 데이터를 우리 Place 에 붙일 때만 쓴다.
    """
    row = conn.execute(
        "SELECT place_id FROM place_external_ids WHERE source = ? AND external_id = ?",
        (source, str(external_id)),
    ).fetchone()
    return row["place_id"] if row else None


def external_ids(conn, place_id: str, source: str) -> list[str]:
    rows = conn.execute(
        "SELECT external_id FROM place_external_ids WHERE place_id = ? AND source = ? "
        "ORDER BY external_id",
        (place_id, source),
    ).fetchall()
    return [r["external_id"] for r in rows]


# ── 발급 · 연결 ───────────────────────────────────────────────────────────────

def link_external(conn, place_id: str, source: str, external_id: str) -> None:
    """외부 자료로 가는 다리를 놓는다.

    같은 (source, external_id) 가 **다른** Place 에 이미 붙어 있으면 조용히
    옮기지 않고 막는다.
    """
    if source not in KNOWN_SOURCES:
        raise ValueError(f"모르는 공급원: {source}")
    owner = find_by_external(conn, source, external_id)
    if owner is not None and owner != place_id:
        raise ValueError(
            f"{source}:{external_id} 는 이미 다른 Place({owner})에 연결돼 있습니다"
        )
    conn.execute(
        "INSERT OR REPLACE INTO place_external_ids "
        "(source, external_id, place_id, is_primary, linked_at) VALUES (?,?,?,0,?)",
        (source, str(external_id), place_id, time.time()),
    )


def ensure_by_key(conn, *, place_key: str, display_name: str, lat: float, lng: float,
                  status: str = STATUS_CANDIDATE, home_visible: bool = True) -> str:
    """자체 키로 Place 를 찾고, 없으면 발급한다. **몇 번 불러도 같은 id.**

    이미 있으면 이름·좌표·상태만 최신으로 맞춘다. 이름은 identity 가 아니므로
    바뀌어도 Place 는 그대로다.
    """
    if status not in KNOWN_STATUSES:
        raise ValueError(f"모르는 상태: {status}")

    row = conn.execute(
        "SELECT id FROM places WHERE place_key = ?", (place_key,)
    ).fetchone()
    if row is not None:
        conn.execute(
            "UPDATE places SET display_name = ?, lat = ?, lng = ?, status = ?, "
            "home_visible = ? WHERE id = ?",
            (display_name, lat, lng, status, int(home_visible), row["id"]),
        )
        return row["id"]

    place_id = new_place_id()
    conn.execute(
        "INSERT INTO places (id, place_key, display_name, lat, lng, status, "
        "home_visible, created_at) VALUES (?,?,?,?,?,?,?,?)",
        (place_id, place_key, display_name, lat, lng, status,
         int(home_visible), time.time()),
    )
    return place_id


# ── 선언 파일에서 동기화 ──────────────────────────────────────────────────────

def sync_from_file(conn) -> dict[str, int]:
    """`data/places.json` 을 읽어 Place 를 맞춘다.

    선언에서 빠진 Place 는 **지우지 않는다.** PLAY 나 사용자 진행 기록이 물고
    있을 수 있고, 파일에서 한 줄 지웠다고 사용자 기록이 사라지면 안 된다.
    상태만 CANDIDATE 로 내려 지도에서 빠지게 한다.
    """
    if not PLACES_FILE.exists():
        return {"created": 0, "updated": 0, "retired": 0}

    data = json.loads(PLACES_FILE.read_text(encoding="utf-8"))
    declared = data.get("places", [])

    before = {r["place_key"] for r in conn.execute("SELECT place_key FROM places")}
    seen: set[str] = set()
    created = updated = 0

    for entry in declared:
        key = entry["key"]
        seen.add(key)
        if key in before:
            updated += 1
        else:
            created += 1
        place_id = ensure_by_key(
            conn,
            place_key=key,
            display_name=entry["name"],
            lat=entry["lat"],
            lng=entry["lng"],
            status=entry.get("status", STATUS_CANDIDATE),
            home_visible=entry.get("home_visible", True),
        )
        for ext in entry.get("external_ids", []):
            link_external(conn, place_id, ext["source"], ext["external_id"])

    retired = 0
    for key in before - seen:
        conn.execute(
            "UPDATE places SET status = ? WHERE place_key = ?", (STATUS_CANDIDATE, key)
        )
        retired += 1

    conn.commit()
    return {"created": created, "updated": updated, "retired": retired}


def ensure_synced(conn) -> None:
    """Place 레지스트리가 비어 있으면 한 번 채운다."""
    n = conn.execute("SELECT COUNT(*) n FROM places").fetchone()["n"]
    if n == 0:
        sync_from_file(conn)
