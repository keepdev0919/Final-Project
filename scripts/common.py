from __future__ import annotations

import json
import os
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


ROOT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT_DIR / "data"
RAW_DIR = DATA_DIR / "raw"
PROCESSED_DIR = DATA_DIR / "processed"
EXTRACTED_DIR = DATA_DIR / "extracted"
NORMALIZED_DIR = DATA_DIR / "normalized"
STORAGE_DIR = ROOT_DIR / "storage"
REPORTS_DIR = ROOT_DIR / "reports"
EVALUATIONS_DIR = REPORTS_DIR / "evaluations"
VECTOR_DB_DIR = STORAGE_DIR / "vector_db"
DB_PATH = STORAGE_DIR / "metadata.db"
EMBEDDING_MODEL = "text-embedding-3-small"
DEFAULT_COLLECTION_NAME = "jeju_folklore_chunks"
ENV_PATH = ROOT_DIR / ".env"


@dataclass(frozen=True)
class SourceConfig:
    source_type: str
    api_service: str
    endpoint: str


SOURCE_CONFIGS = {
    "legend": SourceConfig(
        source_type="legend",
        api_service="E07",
        endpoint="http://www.jeju.go.kr/rest/JejuMythContents/getJejuMythContentsList",
    ),
    "folktale": SourceConfig(
        source_type="folktale",
        api_service="E08",
        endpoint="http://www.jeju.go.kr/rest/JejuFolktaleContents/getJejuFolktaleContentsList",
    ),
}


def ensure_directories() -> None:
    for path in (
        DATA_DIR,
        RAW_DIR,
        RAW_DIR / "api",
        RAW_DIR / "documents",
        PROCESSED_DIR,
        EXTRACTED_DIR,
        NORMALIZED_DIR,
        STORAGE_DIR,
        REPORTS_DIR,
        EVALUATIONS_DIR,
        VECTOR_DB_DIR,
    ):
        path.mkdir(parents=True, exist_ok=True)

    for source_type in SOURCE_CONFIGS:
        (RAW_DIR / "api" / source_type).mkdir(parents=True, exist_ok=True)
        (RAW_DIR / "documents" / source_type).mkdir(parents=True, exist_ok=True)
        (EXTRACTED_DIR / source_type).mkdir(parents=True, exist_ok=True)
        (NORMALIZED_DIR / source_type).mkdir(parents=True, exist_ok=True)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def write_jsonl(path: Path, rows: Iterable[dict]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def load_jsonl(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def get_db_connection() -> sqlite3.Connection:
    ensure_directories()
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS metadata (
            source_type TEXT NOT NULL,
            api_service TEXT NOT NULL,
            code_no TEXT NOT NULL,
            type TEXT,
            category TEXT,
            category2 TEXT,
            title TEXT NOT NULL,
            tags TEXT,
            ebook_folder TEXT,
            ebook_url TEXT,
            pdf_filename TEXT,
            pdf_url TEXT,
            collected_at TEXT NOT NULL,
            download_status TEXT NOT NULL DEFAULT 'pending',
            extract_status TEXT NOT NULL DEFAULT 'pending',
            raw_api_page INTEGER,
            PRIMARY KEY (source_type, code_no)
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS documents (
            doc_id TEXT PRIMARY KEY,
            source_type TEXT NOT NULL,
            code_no TEXT NOT NULL,
            title TEXT NOT NULL,
            category TEXT,
            category2 TEXT,
            tags TEXT,
            source_url TEXT,
            raw_text TEXT,
            clean_text TEXT,
            language TEXT NOT NULL DEFAULT 'ko',
            extracted_at TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS chunks (
            chunk_id TEXT PRIMARY KEY,
            doc_id TEXT NOT NULL,
            source_type TEXT NOT NULL,
            code_no TEXT NOT NULL,
            title TEXT NOT NULL,
            category TEXT,
            category2 TEXT,
            tags TEXT,
            chunk_index INTEGER NOT NULL,
            text TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """
    )
    ensure_column_exists(conn, "documents", "normalized_text", "TEXT")
    ensure_column_exists(conn, "documents", "normalized_at", "TEXT")
    conn.commit()
    return conn


def ensure_column_exists(conn: sqlite3.Connection, table_name: str, column_name: str, column_type: str) -> None:
    columns = {row[1] for row in conn.execute(f"PRAGMA table_info({table_name})").fetchall()}
    if column_name not in columns:
        conn.execute(f"ALTER TABLE {table_name} ADD COLUMN {column_name} {column_type}")


def upsert_metadata_rows(rows: Iterable[dict]) -> None:
    with get_db_connection() as conn:
        conn.executemany(
            """
            INSERT INTO metadata (
                source_type,
                api_service,
                code_no,
                type,
                category,
                category2,
                title,
                tags,
                ebook_folder,
                ebook_url,
                pdf_filename,
                pdf_url,
                collected_at,
                raw_api_page
            ) VALUES (
                :source_type,
                :api_service,
                :code_no,
                :type,
                :category,
                :category2,
                :title,
                :tags,
                :ebook_folder,
                :ebook_url,
                :pdf_filename,
                :pdf_url,
                :collected_at,
                :raw_api_page
            )
            ON CONFLICT(source_type, code_no) DO UPDATE SET
                api_service = excluded.api_service,
                type = excluded.type,
                category = excluded.category,
                category2 = excluded.category2,
                title = excluded.title,
                tags = excluded.tags,
                ebook_folder = excluded.ebook_folder,
                ebook_url = excluded.ebook_url,
                pdf_filename = excluded.pdf_filename,
                pdf_url = excluded.pdf_url,
                collected_at = excluded.collected_at,
                raw_api_page = excluded.raw_api_page
            """
            ,
            rows,
        )
        conn.commit()


def update_metadata_status(
    source_type: str,
    code_no: str,
    *,
    download_status: str | None = None,
    extract_status: str | None = None,
) -> None:
    assignments = []
    values: list[str] = []
    if download_status is not None:
        assignments.append("download_status = ?")
        values.append(download_status)
    if extract_status is not None:
        assignments.append("extract_status = ?")
        values.append(extract_status)
    if not assignments:
        return

    values.extend([source_type, code_no])
    with get_db_connection() as conn:
        conn.execute(
            f"UPDATE metadata SET {', '.join(assignments)} WHERE source_type = ? AND code_no = ?",
            values,
        )
        conn.commit()


def slugify_code(filename: str) -> str:
    return filename.strip().replace("/", "_")


def load_env_file() -> None:
    if not ENV_PATH.exists():
        return

    for raw_line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value
