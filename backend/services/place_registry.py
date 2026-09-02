"""Place 레지스트리 — 놀멍봅서가 스스로 발급하는 장소 신분증.

## 왜 있나 (2026-09-02 조익준님 결정)

    "놀멍봅서 Place의 정체성이 Odii/KTO/VisitJeju 어느 한 공급자에도 종속되지 않는다."

전에는 장소를 **이름 문자열**로 가리켰다. `CoursePlace.id = "이름-day"`,
`/place/detail?name=`, `home_stage.json`의 `name`이 `home_places.name`과 정확히
같아야 카드가 뜨는 식이었다. 이름이 바뀌면 연결이 조용히 끊긴다.

Odii `stid`를 PK로 쓰는 안도 검토했으나 채택하지 않았다. Odii는 이제 Place의 주
공급원이 아니라 **여러 Source 중 하나**다. 특정 공급자의 ID를 내부 PK로 쓰면
공급자를 바꾸거나 늘릴 때 Place가 통째로 흔들린다.

그래서:

    Place.id          놀멍봅서가 발급하는 불변 ID (uuid7)
    external_ids      stid · KTO contentId · VisitJeju ID · 국가유산 ID …
    display_name      화면·검색용. **identity 가 아니다**

## 왜 uuid7인가

Python 3.14 표준 라이브러리에 `uuid.uuid7()`이 있다. 의존성이 늘지 않고,
ULID의 장점인 **시간순 정렬**이 되며(`str` 비교로 발급 순서가 나온다),
형식이 표준 UUID라 나중에 다른 DB로 옮겨도 그대로 통한다.

## ⚠️ 이 표는 다시 만들지 않는다

`home_places`는 `home_places.build()`가 통째로 갈아엎는다. 하지만 `places.id`는
PLAY가 FK로 물고 있어서 한 번 발급하면 끝까지 같아야 한다. 그래서 `sync()`는
**외부 ID로 기존 Place를 찾아 재사용**하고, 없을 때만 새로 발급한다.
몇 번을 돌려도 결과가 같다.
"""
from __future__ import annotations

import json
import time
import uuid

# 외부 식별자 공급원. 새 Source를 붙일 때 여기에 추가한다.
SOURCE_ODII = "odii"
SOURCE_KTO = "kto"
SOURCE_VISITJEJU = "visitjeju"
SOURCE_HERITAGE = "heritage"

KNOWN_SOURCES = frozenset({SOURCE_ODII, SOURCE_KTO, SOURCE_VISITJEJU, SOURCE_HERITAGE})


def new_place_id() -> str:
    """새 Place ID. 시간순으로 정렬되는 uuid7."""
    return str(uuid.uuid7())


# ── 조회 ──────────────────────────────────────────────────────────────────────

def find_by_external(conn, source: str, external_id: str) -> str | None:
    """외부 ID로 place_id를 찾는다. 없으면 None."""
    row = conn.execute(
        "SELECT place_id FROM place_external_ids WHERE source = ? AND external_id = ?",
        (source, str(external_id)),
    ).fetchone()
    return row["place_id"] if row else None


def get(conn, place_id: str) -> dict | None:
    """Place 하나. 붙어 있는 외부 ID를 전부 함께 돌려준다."""
    row = conn.execute("SELECT * FROM places WHERE id = ?", (place_id,)).fetchone()
    if row is None:
        return None
    externals = conn.execute(
        "SELECT source, external_id, is_primary FROM place_external_ids "
        "WHERE place_id = ? ORDER BY is_primary DESC, source, external_id",
        (place_id,),
    ).fetchall()
    return {
        "id": row["id"],
        "display_name": row["display_name"],
        "lat": row["lat"],
        "lng": row["lng"],
        "external_ids": [
            {"source": e["source"], "external_id": e["external_id"],
             "is_primary": bool(e["is_primary"])}
            for e in externals
        ],
    }


def external_ids(conn, place_id: str, source: str) -> list[str]:
    """이 Place에 붙은 특정 공급원의 외부 ID 전부.

    한 Place에 여러 개가 붙는다 — 성읍민속마을 하나에 Odii stid가 8개다.
    """
    rows = conn.execute(
        "SELECT external_id FROM place_external_ids WHERE place_id = ? AND source = ? "
        "ORDER BY is_primary DESC, external_id",
        (place_id, source),
    ).fetchall()
    return [r["external_id"] for r in rows]


# ── 발급 · 연결 ───────────────────────────────────────────────────────────────

def link_external(conn, place_id: str, source: str, external_id: str,
                  is_primary: bool = False) -> None:
    """외부 ID를 Place에 붙인다.

    같은 (source, external_id)가 **다른** Place에 이미 붙어 있으면 조용히
    옮기지 않고 막는다. 한 외부 ID가 두 Place를 오가면 PLAY 연결이 흔들린다.
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
        "(source, external_id, place_id, is_primary, linked_at) VALUES (?,?,?,?,?)",
        (source, str(external_id), place_id, 1 if is_primary else 0, time.time()),
    )


def ensure(conn, *, source: str, external_id: str, display_name: str,
           lat: float, lng: float) -> str:
    """외부 ID로 Place를 찾고, 없으면 새로 발급한다. **몇 번 불러도 같은 id.**

    이미 있으면 `display_name`·좌표만 최신으로 맞춘다 — 이름은 identity가
    아니므로 바뀌어도 Place는 그대로다.
    """
    place_id = find_by_external(conn, source, external_id)
    if place_id is not None:
        conn.execute(
            "UPDATE places SET display_name = ?, lat = ?, lng = ? WHERE id = ?",
            (display_name, lat, lng, place_id),
        )
        return place_id

    place_id = new_place_id()
    conn.execute(
        "INSERT INTO places (id, display_name, lat, lng, created_at) VALUES (?,?,?,?,?)",
        (place_id, display_name, lat, lng, time.time()),
    )
    link_external(conn, place_id, source, external_id, is_primary=True)
    return place_id


# ── 마이그레이션 ──────────────────────────────────────────────────────────────

def sync_from_home_places(conn) -> dict[str, int]:
    """기존 121곳에 Place ID를 발급하고 Odii stid를 전부 연결한다.

    `home_places`는 오디 해설을 300m로 묶은 **파생물**이라 다시 만들 때마다
    행이 바뀔 수 있다. 여기서는 그 묶음의 **대표 stid**를 기준으로 Place를 찾아
    재사용하므로, 몇 번을 돌려도 이미 발급된 id는 그대로다.

    묶음에 딸린 나머지 stid도 같은 Place에 연결한다 — 성읍 하나에 8개가 붙는다.
    """
    rows = conn.execute(
        "SELECT name, lat, lng, stid, stories FROM home_places"
    ).fetchall()

    created = reused = linked = 0
    for row in rows:
        place_id = find_by_external(conn, SOURCE_ODII, row["stid"])
        if place_id is None:
            created += 1
        else:
            reused += 1
        place_id = ensure(
            conn,
            source=SOURCE_ODII,
            external_id=row["stid"],
            display_name=row["name"],
            lat=row["lat"],
            lng=row["lng"],
        )

        # 같은 묶음의 나머지 해설도 이 Place에 붙인다.
        try:
            stories = json.loads(row["stories"] or "[]")
        except (json.JSONDecodeError, TypeError):
            stories = []
        for s in stories:
            sid = str(s.get("stid") or "")
            if not sid or sid == row["stid"]:
                continue
            # 이미 다른 Place가 가져간 stid는 건너뛴다. 300m 묶음이 다시 계산되면
            # 경계에 있는 해설이 옆 장소로 옮겨갈 수 있는데, 그때 조용히 뺏어오면
            # 그쪽 PLAY의 Story 연결이 끊긴다.
            if find_by_external(conn, SOURCE_ODII, sid) is not None:
                continue
            link_external(conn, place_id, SOURCE_ODII, sid)
            linked += 1

    conn.commit()
    return {"created": created, "reused": reused, "extra_stids_linked": linked}


def ensure_synced(conn) -> None:
    """Place 레지스트리가 비어 있으면 한 번 채운다."""
    n = conn.execute("SELECT COUNT(*) n FROM places").fetchone()["n"]
    if n == 0:
        sync_from_home_places(conn)
