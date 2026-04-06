"""SQLite + ChromaDB 연결 싱글톤."""
import sqlite3
from pathlib import Path
from functools import lru_cache

import chromadb

BASE_DIR = Path(__file__).parent.parent.parent
DB_PATH = BASE_DIR / "storage" / "metadata.db"
CHROMA_PATH = BASE_DIR / "storage" / "vector_db"
COLLECTION_NAME = "jeju_folklore_chunks"


@lru_cache(maxsize=1)
def get_db_connection():
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


@lru_cache(maxsize=1)
def get_chroma_collection():
    client = chromadb.PersistentClient(path=str(CHROMA_PATH))
    return client.get_collection(COLLECTION_NAME)
