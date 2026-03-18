from __future__ import annotations

import argparse
import sqlite3

from common import get_db_connection, utc_now_iso


def fetch_documents(source_type: str | None, limit: int | None) -> list[sqlite3.Row]:
    query = """
        SELECT
            doc_id,
            source_type,
            code_no,
            title,
            category,
            category2,
            tags,
            COALESCE(NULLIF(normalized_text, ''), clean_text) AS chunk_text
        FROM documents
        WHERE COALESCE(NULLIF(normalized_text, ''), clean_text) IS NOT NULL
          AND COALESCE(NULLIF(normalized_text, ''), clean_text) != ''
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
        return conn.execute(query, params).fetchall()


def chunk_text(text: str, chunk_size: int, overlap: int) -> list[str]:
    if overlap >= chunk_size:
        raise ValueError("overlap must be smaller than chunk_size")

    normalized = text.strip()
    if not normalized:
        return []

    chunks = []
    start = 0
    length = len(normalized)

    while start < length:
        end = min(length, start + chunk_size)
        chunk = normalized[start:end].strip()
        if chunk:
            chunks.append(chunk)
        if end >= length:
            break
        start = end - overlap

    return chunks


def rebuild_chunks(rows: list[sqlite3.Row], chunk_size: int, overlap: int) -> int:
    created = 0
    with get_db_connection() as conn:
        if rows:
            placeholders = ",".join("?" for _ in rows)
            conn.execute(
                f"DELETE FROM chunks WHERE doc_id IN ({placeholders})",
                [row["doc_id"] for row in rows],
            )

        for row in rows:
            pieces = chunk_text(row["chunk_text"], chunk_size, overlap)
            for idx, piece in enumerate(pieces):
                conn.execute(
                    """
                    INSERT INTO chunks (
                        chunk_id,
                        doc_id,
                        source_type,
                        code_no,
                        title,
                        category,
                        category2,
                        tags,
                        chunk_index,
                        text,
                        created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        f"{row['doc_id']}:{idx}",
                        row["doc_id"],
                        row["source_type"],
                        row["code_no"],
                        row["title"],
                        row["category"],
                        row["category2"],
                        row["tags"],
                        idx,
                        piece,
                        utc_now_iso(),
                    ),
                )
                created += 1
        conn.commit()
    return created


def main() -> None:
    parser = argparse.ArgumentParser(description="추출된 문서를 청킹해 SQLite에 저장")
    parser.add_argument("--source", choices=["legend", "folktale"], default=None)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--chunk-size", type=int, default=900)
    parser.add_argument("--overlap", type=int, default=120)
    args = parser.parse_args()

    rows = fetch_documents(args.source, args.limit)
    total = rebuild_chunks(rows, args.chunk_size, args.overlap)
    print(f"chunked documents={len(rows)} chunks={total}")


if __name__ == "__main__":
    main()
