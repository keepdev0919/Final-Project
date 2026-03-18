from __future__ import annotations

import argparse
import sqlite3
import urllib.request
from pathlib import Path

from common import RAW_DIR, get_db_connection, slugify_code, update_metadata_status


USER_AGENT = "jeju-folklore-rag/0.1"


def fetch_pending_rows(source_type: str | None, limit: int | None) -> list[sqlite3.Row]:
    query = """
        SELECT source_type, code_no, pdf_filename, pdf_url, ebook_url
        FROM metadata
        WHERE download_status IN ('pending', 'failed')
    """
    params: list[object] = []
    if source_type:
        query += " AND source_type = ?"
        params.append(source_type)
    query += " ORDER BY source_type, code_no"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)

    with get_db_connection() as conn:
        rows = conn.execute(query, params).fetchall()
    return rows


def download(url: str, output_path: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as response:
        output_path.write_bytes(response.read())


def resolve_target_path(row: sqlite3.Row) -> tuple[str | None, Path | None]:
    if row["pdf_url"]:
        filename = row["pdf_filename"] or f"{slugify_code(row['code_no'])}.pdf"
        return row["pdf_url"], RAW_DIR / "documents" / row["source_type"] / filename
    if row["ebook_url"]:
        filename = f"{slugify_code(row['code_no'])}.html"
        return row["ebook_url"], RAW_DIR / "documents" / row["source_type"] / filename
    return None, None


def main() -> None:
    parser = argparse.ArgumentParser(description="제주 설화/민담 원문 다운로드")
    parser.add_argument("--source", choices=["legend", "folktale"], default=None)
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    rows = fetch_pending_rows(args.source, args.limit)
    print(f"download candidates={len(rows)}")

    for row in rows:
        url, output_path = resolve_target_path(row)
        if not url or output_path is None:
            update_metadata_status(row["source_type"], row["code_no"], download_status="failed")
            print(f"[skip] missing source url source={row['source_type']} code={row['code_no']}")
            continue

        output_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            download(url, output_path)
            update_metadata_status(row["source_type"], row["code_no"], download_status="downloaded")
            print(f"[ok] {row['source_type']} {row['code_no']} -> {output_path}")
        except Exception as exc:
            update_metadata_status(row["source_type"], row["code_no"], download_status="failed")
            print(f"[fail] {row['source_type']} {row['code_no']} {url} ({exc})")


if __name__ == "__main__":
    main()
