"""SQLite + ChromaDB 연결 싱글톤."""
import os
import sqlite3
import threading
from pathlib import Path
from functools import lru_cache

import chromadb

BASE_DIR = Path(__file__).parent.parent.parent
DB_PATH = BASE_DIR / "storage" / "metadata.db"
CHROMA_PATH = BASE_DIR / "storage" / "vector_db"
COLLECTION_NAME = "jeju_folklore_chunks"
EMBEDDING_MODEL = "text-embedding-3-small"

# PersistentClient를 모듈 레벨에 보관해 GC 방지
# (lru_cache만으로는 client 로컬 변수가 GC되어 ChromaDB 내부 시스템이 해제됨)
_chroma_client: chromadb.PersistentClient | None = None
_chroma_collection = None
_chroma_lock = threading.Lock()


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
    _review_cols = {
        row[1] for row in conn.execute("PRAGMA table_info(place_reviews)").fetchall()
    }
    if "user_id" not in _review_cols:
        conn.execute("ALTER TABLE place_reviews ADD COLUMN user_id TEXT")

    _metadata_cols = {
        row[1] for row in conn.execute("PRAGMA table_info(metadata)").fetchall()
    }
    if _metadata_cols and "hook" not in _metadata_cols:
        conn.execute("ALTER TABLE metadata ADD COLUMN hook TEXT")

    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS folklore_connection_cache (
            code_no    TEXT NOT NULL,
            place      TEXT NOT NULL,
            connection TEXT NOT NULL,
            cached_at  REAL,
            PRIMARY KEY (code_no, place)
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS folklore_story_cache (
            code_no    TEXT NOT NULL,
            place      TEXT NOT NULL,
            pages_json TEXT NOT NULL,
            cached_at  REAL,
            PRIMARY KEY (code_no, place)
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
    # ⚠️ 이 표는 **다시 만들지 않는다(append-only).** `home_places`는
    # `home_places.build()`가 통째로 갈아엎지만, 여기 id는 PLAY가 FK로
    # 물고 있어서 한 번 발급하면 끝까지 같아야 한다.
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS places (
            id           TEXT PRIMARY KEY,   -- uuid7. 놀멍봅서가 발급하고 절대 안 바꾼다
            display_name TEXT NOT NULL,      -- 화면·검색용. identity 로 쓰지 않는다
            lat          REAL NOT NULL,
            lng          REAL NOT NULL,
            created_at   REAL NOT NULL
        )
        """
    )
    # 외부 식별자. **한 Place에 여러 개가 붙을 수 있다** — 성읍 하나에 Odii stid가
    # 8개 달리는 식이다. 반대로 한 외부 ID가 두 Place에 붙는 것은 막는다(PK).
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


def get_chroma_collection():
    global _chroma_client, _chroma_collection
    if _chroma_collection is None:
        with _chroma_lock:
            if _chroma_collection is None:
                _chroma_client = chromadb.PersistentClient(path=str(CHROMA_PATH))
                _chroma_collection = _chroma_client.get_collection(COLLECTION_NAME)
    return _chroma_collection


def embed_query(text: str) -> list[float]:
    """OpenAI API로 텍스트를 1536-dim 벡터로 임베딩."""
    import urllib.request
    import json

    api_key = os.environ.get("OPENAI_API_KEY", "")
    payload = json.dumps({"input": text, "model": EMBEDDING_MODEL}).encode("utf-8")
    req = urllib.request.Request(
        "https://api.openai.com/v1/embeddings",
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.loads(resp.read().decode("utf-8"))
    return body["data"][0]["embedding"]
