from __future__ import annotations

import argparse
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

from common import (
    RAW_DIR,
    SOURCE_CONFIGS,
    ensure_directories,
    upsert_metadata_rows,
    utc_now_iso,
    write_jsonl,
)


USER_AGENT = "jeju-folklore-rag/0.1"


def request_xml(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as response:
        return response.read()


def text_or_empty(parent: ET.Element, tag: str) -> str:
    node = parent.find(tag)
    return node.text.strip() if node is not None and node.text else ""


def parse_query_total(root: ET.Element) -> int | None:
    query = root.find("query")
    if query is None:
        return None

    rows_nodes = query.findall("rows")
    if not rows_nodes:
        return None

    raw_text = rows_nodes[-1].text.strip() if rows_nodes[-1].text else ""
    return int(raw_text) if raw_text.isdigit() else None


def parse_items(source_type: str, page: int, raw_xml: bytes) -> tuple[list[dict], int | None]:
    root = ET.fromstring(raw_xml)
    total_count = parse_query_total(root)
    items = []

    for item in root.findall("./items/item"):
        code_no = text_or_empty(item, "codeNo")
        items.append(
            {
                "source_type": source_type,
                "api_service": SOURCE_CONFIGS[source_type].api_service,
                "code_no": code_no,
                "type": text_or_empty(item, "type"),
                "category": text_or_empty(item, "category"),
                "category2": text_or_empty(item, "category2"),
                "title": text_or_empty(item, "title"),
                "tags": text_or_empty(item, "tag"),
                "ebook_folder": text_or_empty(item, "ebook"),
                "ebook_url": text_or_empty(item, "ebookUrl"),
                "pdf_filename": text_or_empty(item, "pdf"),
                "pdf_url": text_or_empty(item, "pdfUrl"),
                "collected_at": utc_now_iso(),
                "raw_api_page": page,
            }
        )

    return items, total_count


def save_raw_page(source_type: str, page: int, raw_xml: bytes) -> Path:
    path = RAW_DIR / "api" / source_type / f"page_{page:04d}.xml"
    path.write_bytes(raw_xml)
    return path


def build_url(source_type: str, page: int, page_size: int) -> str:
    endpoint = SOURCE_CONFIGS[source_type].endpoint
    query = urllib.parse.urlencode({"page": page, "pageSize": page_size})
    return f"{endpoint}?{query}"


def fetch_source(source_type: str, page_size: int, delay_seconds: float) -> list[dict]:
    page = 1
    all_rows: list[dict] = []
    expected_total: int | None = None

    while True:
        url = build_url(source_type, page, page_size)
        raw_xml = request_xml(url)
        save_raw_page(source_type, page, raw_xml)
        rows, total_count = parse_items(source_type, page, raw_xml)

        if expected_total is None:
            expected_total = total_count

        if not rows:
            break

        all_rows.extend(rows)
        print(
            f"[{source_type}] fetched page={page} page_rows={len(rows)} "
            f"accumulated={len(all_rows)} expected_total={expected_total}"
        )

        if expected_total is not None and len(all_rows) >= expected_total:
            break

        page += 1
        time.sleep(delay_seconds)

    return all_rows


def main() -> None:
    parser = argparse.ArgumentParser(description="제주 설화/민담 메타데이터 수집")
    parser.add_argument(
        "--source",
        choices=["legend", "folktale", "all"],
        default="all",
        help="수집 대상",
    )
    parser.add_argument("--page-size", type=int, default=100, help="페이지당 요청 건수")
    parser.add_argument("--delay", type=float, default=0.2, help="요청 간 대기 시간(초)")
    args = parser.parse_args()

    ensure_directories()
    targets = list(SOURCE_CONFIGS) if args.source == "all" else [args.source]

    for source_type in targets:
        rows = fetch_source(source_type, args.page_size, args.delay)
        output_path = Path("data/processed") / f"metadata_{source_type}.jsonl"
        write_jsonl(output_path, rows)
        upsert_metadata_rows(rows)
        print(f"[{source_type}] wrote {len(rows)} rows to {output_path}")


if __name__ == "__main__":
    main()
