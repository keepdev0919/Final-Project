"""SQLite 연결 싱글톤.

ChromaDB(벡터 검색)와 OpenAI 임베딩은 2026-09-10에 걷어냈다. 제거된 설화 검색
기능의 잔재로, 호출부가 하나도 없었다. 인덱스 자체는 `storage/vector_db`에
남아 있다 — git에 없는 빌드 산출물이라 지우려면 손으로 지운다.
"""
import os
import sqlite3
import threading
from pathlib import Path


BASE_DIR = Path(__file__).parent.parent.parent
DB_PATH = BASE_DIR / "storage" / "metadata.db"


def _load_env() -> None:
    env_path = BASE_DIR / ".env"
    if not env_path.exists():
        return
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


_load_env()


def _ensure_schema(conn: sqlite3.Connection) -> None:
    """스키마 보장. IF NOT EXISTS + PRAGMA로 idempotent. 매 스레드 첫 연결 시 호출."""
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS tourist_info_cache (
            content_id TEXT PRIMARY KEY,
            name       TEXT,
            address    TEXT,
            phone      TEXT,
            category   TEXT,
            cached_at  REAL
        )
        """
    )
    _existing_cols = {
        row[1] for row in conn.execute("PRAGMA table_info(place_detail_cache)").fetchall()
    }
    if "images" not in _existing_cols:
        conn.execute("DROP TABLE IF EXISTS place_detail_cache")
        conn.execute(
            """
            CREATE TABLE place_detail_cache (
                name             TEXT,
                lat              REAL,
                lng              REAL,
                overview         TEXT,
                images           TEXT,
                address          TEXT,
                tel              TEXT,
                open_time        TEXT,
                rest_date        TEXT,
                use_fee          TEXT,
                parking          TEXT,
                content_type_id  TEXT,
                cached_at        REAL,
                PRIMARY KEY (name, lat, lng)
            )
            """
        )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS place_reviews (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            place_name TEXT    NOT NULL,
            tags       TEXT    NOT NULL,
            note       TEXT,
            device_id  TEXT    NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(place_name, device_id) ON CONFLICT REPLACE
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS kto_call_log (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            service   TEXT NOT NULL,
            operation TEXT NOT NULL,
            ok        INTEGER NOT NULL,
            detail    TEXT,
            called_at REAL NOT NULL
        )
        """
    )
    conn.execute("CREATE INDEX IF NOT EXISTS idx_kto_call_log_at ON kto_call_log(called_at)")

    # 오디 장소 목록. **대본(script)은 저장하지 않는다** — 있는지 여부만 둔다.
    # 이유는 routers/odii.py 모듈 설명 참조 (재배포 회피 + 실시간 호출 요건).
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS odii_places (
            stid        TEXT NOT NULL,
            lang        TEXT NOT NULL,
            title       TEXT,
            audio_title TEXT,
            lat         REAL,
            lng         REAL,
            play_time   INTEGER,
            has_script  INTEGER,
            has_audio   INTEGER,
            synced_at   REAL,
            PRIMARY KEY (stid, lang)
        )
        """
    )
    # 홈 장소 카드 순위. 비짓제주 등장 빈도 × 오디 해설 유무를 미리 계산해 둔 것이다
    # (146,357 × 178 거리 계산을 매 요청마다 할 수 없다). 계산 규칙은
    # services/home_places.py 모듈 설명 참조.
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS home_places (
            rank          INTEGER PRIMARY KEY,
            name          TEXT NOT NULL,
            lat           REAL NOT NULL,
            lng           REAL NOT NULL,
            stid          TEXT NOT NULL,
            story_title   TEXT,
            story_seconds INTEGER,
            story_count   INTEGER,
            stories       TEXT,
            story_distance_m INTEGER,
            thumbnail     TEXT,
            thumbnail_candidates TEXT,
            built_at      REAL
        )
        """
    )
    # 재생 시 받아온 대본의 1시간 캐시. 연타·재방문 흡수용이며 영구 저장이 아니다.
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS odii_story_cache (
            cache_key   TEXT PRIMARY KEY,
            title       TEXT,
            audio_title TEXT,
            script      TEXT,
            audio_url   TEXT,
            play_time   INTEGER,
            cached_at   REAL
        )
        """
    )
    # ── Place 레지스트리 ────────────────────────────────────────────────
    #
    # **놀멍봅서 Place의 정체성은 어느 외부 공급자에도 종속되지 않는다**
    # (2026-09-02 조익준님 결정).
    #
    # Odii는 이제 Place의 주 공급원이 아니라 여러 Source 중 하나다. 그래서
    # Odii `stid`나 KTO `contentId`를 PK로 쓰지 않는다. 공급자를 바꾸거나
    # 늘릴 때 Place가 통째로 흔들리기 때문이다.
    #
    # `place_key`는 놀멍봅서가 정한 **자체 불변 키**다(`data/places.json`).
    # 이름도 좌표도 외부 ID도 아니다 — 그래야 이름이 바뀌거나 오디를 안 쓰게 돼도
    # Place 가 그대로 남는다.
    #
    # ⚠️ 이 표는 **다시 만들지 않는다(append-only).** 여기 id는 PLAY 와 진행 기록이
    # FK로 물고 있어서 한 번 발급하면 끝까지 같아야 한다.
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS places (
            id           TEXT PRIMARY KEY,   -- uuid7. 놀멍봅서가 발급하고 절대 안 바꾼다
            place_key    TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,      -- 화면·검색용. identity 로 쓰지 않는다
            lat          REAL NOT NULL,
            lng          REAL NOT NULL,
            status       TEXT NOT NULL DEFAULT 'CANDIDATE',
            home_visible INTEGER NOT NULL DEFAULT 1,  -- 홈 「수행 가능한 퀘스트」 노출 여부
            created_at   REAL NOT NULL
        )
        """
    )
    _places_cols = {
        row[1] for row in conn.execute("PRAGMA table_info(places)").fetchall()
    }
    if "home_visible" not in _places_cols:
        conn.execute("ALTER TABLE places ADD COLUMN home_visible INTEGER NOT NULL DEFAULT 1")
    # 외부 식별자 = **Place 의 정체성이 아니라 바깥 자료로 가는 다리**다(데이터.md §3).
    # 한 Place 에 여러 개가 붙을 수 있고(KTO contentId + Odii stid + 국가유산 ID …),
    # 한 외부 ID 가 두 Place 에 붙는 것은 막는다(PK).
    #
    # ⚠️ **Place 를 찾는 열쇠로 쓰지 않는다.** 그건 `places.place_key` 가 한다.
    # 여기에 의존하면 특정 공급자를 끊는 순간 Place 를 못 찾게 된다.
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS place_external_ids (
            source      TEXT NOT NULL,   -- odii | kto | visitjeju | heritage
            external_id TEXT NOT NULL,
            place_id    TEXT NOT NULL,
            is_primary  INTEGER NOT NULL DEFAULT 0,
            linked_at   REAL NOT NULL,
            PRIMARY KEY (source, external_id)
        )
        """
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_place_ext_place ON place_external_ids(place_id)"
    )

    # ── 미션 신고 ───────────────────────────────────────────────────────
    #
    # 현장 답사를 하지 않기로 했으므로(2026-09-02) 웹으로 시야까지 확정 못 한
    # 미션이 있다(성읍 M04·M07). "출시 후 사용자 리뷰로 잡는다"는 전략은
    # **이 표가 채워져야 성립한다.** 안 채워지면 그냥 「검증 안 함」이다.
    #
    # ⚠️ **사용자를 식별하는 값을 담지 않는다.** 기기 ID·위치·사진 없음.
    # 신고 화면이 "위치나 사진은 함께 보내지 않습니다"라고 약속하고 있어서,
    # 여기에 무엇을 더하려면 그 문구부터 고쳐야 한다.
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS mission_reports (
            id          TEXT PRIMARY KEY,
            play_id     TEXT NOT NULL,
            mission_id  TEXT,
            reason      TEXT NOT NULL,
            note        TEXT,
            reported_at REAL NOT NULL
        )
        """
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_mission_reports_play "
        "ON mission_reports(play_id, mission_id)"
    )

    conn.commit()


# Thread-local connection: FastAPI 의 ThreadPool 워커마다 자기 connection 보유.
# 같은 connection 객체를 여러 스레드가 동시에 execute() 하면
# Python 3.14 sqlite3 에서 InterfaceError(SQLITE_MISUSE) 발생하므로 격리한다.
_thread_local = threading.local()


def get_db_connection() -> sqlite3.Connection:
    conn = getattr(_thread_local, "conn", None)
    if conn is not None:
        return conn
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    _ensure_schema(conn)
    _thread_local.conn = conn
    return conn
