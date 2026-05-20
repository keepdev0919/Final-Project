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


@lru_cache(maxsize=1)
def get_db_connection():
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    # 관광지 정보 캐시 테이블 (없으면 최초 연결 시 한 번만 생성)
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
    # place_detail_cache: 스키마 변경 감지 시 DROP + 재생성 (캐시라 데이터 손실 무방)
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

    # ── 설화 LLM 가공 결과 캐시 ─────────────────────────────────────────────
    # 1) metadata.hook : 설화별 영구 후크 (한 줄, 30~50자). NULL이면 lazy 생성 대상.
    _metadata_cols = {
        row[1] for row in conn.execute("PRAGMA table_info(metadata)").fetchall()
    }
    if _metadata_cols and "hook" not in _metadata_cols:
        conn.execute("ALTER TABLE metadata ADD COLUMN hook TEXT")

    # 2) 장소×설화 한 줄 연결 캐시
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

    # 3) 장소×설화 스토리북(페이지 JSON) 캐시
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
