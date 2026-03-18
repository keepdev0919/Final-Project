from __future__ import annotations

import argparse
import re
import sqlite3
import unicodedata

from common import NORMALIZED_DIR, get_db_connection, utc_now_iso


# Conservative replacements only. Keep raw text intact and normalize only
# characters that are highly likely to hurt retrieval quality.
CHAR_REPLACEMENTS = {
    "\x0c": "\n",
    "\ue390": "닭",
    "\ue38a": "다",
    "\ue38b": "닥",
    "\ue38e": "던",
    "\ue38f": "달",
    "\ue3e5": "딱",
    "\ue3e8": "딸",
    "\ue566": "말",
    "\ue560": "마",
    "\ue563": "만",
    "\ue64a": "바",
    "\ue64f": "발",
    "\ue650": "밭",
    "\ue97d": "사",
    "\ue982": "살",
    "\ue991": "샛",
    "\uebd8": "쌀",
    "\uedae": "었",
    "\uedd0": "왕",
    "\ueeae": "여",
    "\ueeaf": "여",
    "\ue1a7": "가",
    "\ue1ab": "같",
    "\ue1ad": "갈",
    "\ue1ba": "감",
    "\ue1bf": "갓",
    "\ue1c8": "같",
    "\ue202": "까",
    "\ue283": "나",
    "\ue288": "날",
    "\uefe7": "어",
    "\uf537": "하",
    "\uf53a": "한",
    "\uf53c": "할",
    "\uf492": "팔",
    "\uf498": "팥",
    "\uf1fc": "자",
    "\uf204": "잠",
    "\uf341": "차",
    "\uf345": "차",
    "\uf34b": "참",
    "\uf351": "찾",
    "\uf43d": "쳐",
    "\uf546": "해",
    "\uf000": "",
}

STRING_REPLACEMENTS = {
    "／": "/",
    "질르믈": "기르면",
    "질르는디": "기르는데",
    "질른": "기른",
    "질르완": "기르다 보니",
    "기르면하면은": "기르면은",
    "기르면 허믄": "기르면",
    "한 대여섯해 기른 닭도 잇곡": "한 대여섯 해 기른 닭도 있고",
    "여남은 해 기른 개도 잇주": "여남은 해 기른 개도 있지",
}

WHITESPACE_RE = re.compile(r"[ \t]+")
MULTI_NEWLINE_RE = re.compile(r"\n{3,}")
TARGET_CHAR_RE = re.compile(r"[\u1100-\u11FF\uA960-\uA97F\uD7B0-\uD7FF\uE000-\uF8FF\uF900-\uFAFF\uFF61-\uFFDC]")


def fetch_documents(source_type: str | None, limit: int | None) -> list[sqlite3.Row]:
    query = """
        SELECT doc_id, source_type, code_no, clean_text
        FROM documents
        WHERE clean_text IS NOT NULL
          AND clean_text != ''
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


def normalize_text(text: str) -> tuple[str, dict[str, int]]:
    normalized = unicodedata.normalize("NFKC", text)
    replacement_counts: dict[str, int] = {}

    for old, new in CHAR_REPLACEMENTS.items():
        count = normalized.count(old)
        if count:
            normalized = normalized.replace(old, new)
            replacement_counts[f"char:{old.encode('unicode_escape').decode()}"] = count

    for old, new in STRING_REPLACEMENTS.items():
        count = normalized.count(old)
        if count:
            normalized = normalized.replace(old, new)
            replacement_counts[f"str:{old}"] = count

    unresolved = TARGET_CHAR_RE.findall(normalized)
    if unresolved:
        replacement_counts["dropped_unresolved_special_chars"] = len(unresolved)
        normalized = TARGET_CHAR_RE.sub("", normalized)

    normalized = normalized.replace("\r\n", "\n").replace("\r", "\n")
    normalized = WHITESPACE_RE.sub(" ", normalized)
    normalized = MULTI_NEWLINE_RE.sub("\n\n", normalized)
    return normalized.strip(), replacement_counts


def save_normalized(doc_id: str, source_type: str, code_no: str, normalized_text: str) -> None:
    output_path = NORMALIZED_DIR / source_type / f"{code_no}.txt"
    output_path.write_text(normalized_text, encoding="utf-8")

    with get_db_connection() as conn:
        conn.execute(
            """
            UPDATE documents
            SET normalized_text = ?, normalized_at = ?
            WHERE doc_id = ?
            """,
            (normalized_text, utc_now_iso(), doc_id),
        )
        conn.commit()


def main() -> None:
    parser = argparse.ArgumentParser(description="원문 텍스트를 검색용 정규화본으로 변환")
    parser.add_argument("--source", choices=["legend", "folktale"], default=None)
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    rows = fetch_documents(args.source, args.limit)
    print(f"normalize candidates={len(rows)}")

    for row in rows:
        normalized, replacement_counts = normalize_text(row["clean_text"])
        save_normalized(row["doc_id"], row["source_type"], row["code_no"], normalized)
        if replacement_counts:
            summary = ", ".join(f"{key}={value}" for key, value in sorted(replacement_counts.items()))
            print(f"[ok] normalized {row['source_type']} {row['code_no']} ({summary})")
        else:
            print(f"[ok] normalized {row['source_type']} {row['code_no']}")


if __name__ == "__main__":
    main()
