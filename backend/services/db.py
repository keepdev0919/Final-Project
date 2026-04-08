"""SQLite + ChromaDB 연결 싱글톤."""
import os
import sqlite3
from pathlib import Path
from functools import lru_cache

import chromadb

BASE_DIR = Path(__file__).parent.parent.parent
DB_PATH = BASE_DIR / "storage" / "metadata.db"
CHROMA_PATH = BASE_DIR / "storage" / "vector_db"
COLLECTION_NAME = "jeju_folklore_chunks"
EMBEDDING_MODEL = "text-embedding-3-small"


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
    return conn


@lru_cache(maxsize=1)
def get_chroma_collection():
    client = chromadb.PersistentClient(path=str(CHROMA_PATH))
    return client.get_collection(COLLECTION_NAME)


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
