from __future__ import annotations

import argparse
import re
import sqlite3
import subprocess
from pathlib import Path

from common import EXTRACTED_DIR, get_db_connection, update_metadata_status, utc_now_iso


WHITESPACE_RE = re.compile(r"[ \t]+")
MULTI_NEWLINE_RE = re.compile(r"\n{3,}")
PAGE_NUMBER_RE = re.compile(r"^\s*\d+\s*$", re.MULTILINE)
VIEWER_NOISE_RE = re.compile(r"(?im)^\s*(synap|convert\.jsp|http://www\.jeju\.go\.kr).*$")


def fetch_rows(source_type: str | None, limit: int | None) -> list[sqlite3.Row]:
    query = """
        SELECT source_type, code_no, title, category, category2, tags, pdf_url, ebook_url, pdf_filename
        FROM metadata
        WHERE download_status = 'downloaded'
          AND extract_status IN ('pending', 'failed')
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


def locate_document(row: sqlite3.Row) -> Path | None:
    source_dir = Path("data/raw/documents") / row["source_type"]
    if row["pdf_filename"]:
        candidate = source_dir / row["pdf_filename"]
        if candidate.exists():
            return candidate

    pdf_candidates = list(source_dir.glob(f"{row['code_no']}*.pdf"))
    if pdf_candidates:
        return pdf_candidates[0]

    html_candidate = source_dir / f"{row['code_no']}.html"
    if html_candidate.exists():
        return html_candidate
    return None


def extract_pdf_text(path: Path) -> str:
    result = subprocess.run(
        ["pdftotext", "-layout", str(path), "-"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def extract_html_text(path: Path) -> str:
    text = path.read_text(encoding="utf-8", errors="ignore")
    text = re.sub(r"(?is)<script.*?</script>", " ", text)
    text = re.sub(r"(?is)<style.*?</style>", " ", text)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    return text


def clean_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("\f", "\n")
    text = VIEWER_NOISE_RE.sub("", text)
    text = PAGE_NUMBER_RE.sub("", text)
    text = WHITESPACE_RE.sub(" ", text)
    text = MULTI_NEWLINE_RE.sub("\n\n", text)
    return text.strip()


def save_document(row: sqlite3.Row, raw_text: str, cleaned_text: str, source_url: str) -> None:
    doc_id = f"{row['source_type']}:{row['code_no']}"
    extracted_path = EXTRACTED_DIR / row["source_type"] / f"{row['code_no']}.txt"
    extracted_path.write_text(cleaned_text, encoding="utf-8")

    with get_db_connection() as conn:
        conn.execute(
            """
            INSERT INTO documents (
                doc_id,
                source_type,
                code_no,
                title,
                category,
                category2,
                tags,
                source_url,
                raw_text,
                clean_text,
                language,
                extracted_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ko', ?)
            ON CONFLICT(doc_id) DO UPDATE SET
                title = excluded.title,
                category = excluded.category,
                category2 = excluded.category2,
                tags = excluded.tags,
                source_url = excluded.source_url,
                raw_text = excluded.raw_text,
                clean_text = excluded.clean_text,
                extracted_at = excluded.extracted_at
            """,
            (
                doc_id,
                row["source_type"],
                row["code_no"],
                row["title"],
                row["category"],
                row["category2"],
                row["tags"],
                source_url,
                raw_text,
                cleaned_text,
                utc_now_iso(),
            ),
        )
        conn.commit()


def main() -> None:
    parser = argparse.ArgumentParser(description="다운로드된 원문에서 텍스트 추출")
    parser.add_argument("--source", choices=["legend", "folktale"], default=None)
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    rows = fetch_rows(args.source, args.limit)
    print(f"extract candidates={len(rows)}")

    for row in rows:
        path = locate_document(row)
        if path is None:
            update_metadata_status(row["source_type"], row["code_no"], extract_status="failed")
            print(f"[skip] missing file source={row['source_type']} code={row['code_no']}")
            continue

        try:
            if path.suffix.lower() == ".pdf":
                raw_text = extract_pdf_text(path)
            else:
                raw_text = extract_html_text(path)
            cleaned_text = clean_text(raw_text)
            source_url = row["pdf_url"] or row["ebook_url"] or ""
            save_document(row, raw_text, cleaned_text, source_url)
            update_metadata_status(row["source_type"], row["code_no"], extract_status="extracted")
            print(f"[ok] extracted {row['source_type']} {row['code_no']}")
        except Exception as exc:
            update_metadata_status(row["source_type"], row["code_no"], extract_status="failed")
            print(f"[fail] extract {row['source_type']} {row['code_no']} ({exc})")


if __name__ == "__main__":
    main()
