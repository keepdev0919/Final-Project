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
