from __future__ import annotations

import argparse
import json
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

from common import NORMALIZED_DIR, REPORTS_DIR, SOURCE_CONFIGS, ensure_directories


CONTEXT_WINDOW = 28
MAX_EXAMPLES_PER_CHAR = 8


def is_target_char(ch: str) -> bool:
    codepoint = ord(ch)
    return (
        codepoint >= 0xE000
        or 0x1100 <= codepoint <= 0x11FF
        or 0xA960 <= codepoint <= 0xA97F
        or 0xD7B0 <= codepoint <= 0xD7FF
        or 0xF900 <= codepoint <= 0xFAFF
        or 0xFF61 <= codepoint <= 0xFFDC
    )


def unicode_name(ch: str) -> str:
    try:
        return unicodedata.name(ch)
    except ValueError:
        return "UNKNOWN"


def scan_paths(paths: list[Path]) -> tuple[Counter[str], dict[str, list[dict[str, str]]], int]:
    counts: Counter[str] = Counter()
    examples: dict[str, list[dict[str, str]]] = defaultdict(list)
    files_with_target = 0

    for path in paths:
        text = path.read_text(encoding="utf-8", errors="ignore")
        found_in_file = False

        for idx, ch in enumerate(text):
            if not is_target_char(ch):
                continue

            counts[ch] += 1
            found_in_file = True

            if len(examples[ch]) >= MAX_EXAMPLES_PER_CHAR:
                continue

            start = max(0, idx - CONTEXT_WINDOW)
            end = min(len(text), idx + CONTEXT_WINDOW + 1)
            snippet = text[start:end].replace("\n", " ")
            examples[ch].append(
                {
                    "file": str(path),
                    "context": snippet,
                }
            )

        if found_in_file:
            files_with_target += 1

    return counts, examples, files_with_target


def build_markdown(
    source_label: str,
    total_files: int,
    files_with_target: int,
    counts: Counter[str],
    examples: dict[str, list[dict[str, str]]],
) -> str:
    lines = [
        f"# 2차 정규화 감사 리포트 ({source_label})",
        "",
        f"- 전체 파일 수: {total_files}",
        f"- 특수/옛표기 포함 파일 수: {files_with_target}",
        f"- 서로 다른 문제 문자 수: {len(counts)}",
        "",
        "## 빈도 상위 문자",
        "",
        "| 문자 | 코드포인트 | 빈도 | 유니코드 이름 |",
        "| --- | --- | ---: | --- |",
    ]

    for ch, count in counts.most_common(40):
        rendered = ch
        if ch == "|":
            rendered = "\\|"
        lines.append(f"| {rendered} | `U+{ord(ch):04X}` | {count} | {unicode_name(ch)} |")

    lines.extend(["", "## 문자별 문맥 예문", ""])

    for ch, count in counts.most_common(20):
        lines.append(f"### `{ch}` (`U+{ord(ch):04X}`) x {count}")
        lines.append("")
        for item in examples[ch]:
            lines.append(f"- [{Path(item['file']).name}]({Path(item['file']).resolve()}): `{item['context']}`")
        lines.append("")

    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="정규화 후 남은 특수문자와 문맥 예문 감사")
    parser.add_argument("--source", choices=["legend", "folktale", "all"], default="all")
    args = parser.parse_args()

    ensure_directories()
    targets = list(SOURCE_CONFIGS) if args.source == "all" else [args.source]

    for source_type in targets:
        paths = sorted((NORMALIZED_DIR / source_type).glob("*.txt"))
        counts, examples, files_with_target = scan_paths(paths)

        records = []
        for ch, count in counts.most_common():
            records.append(
                {
                    "char": ch,
                    "codepoint": f"U+{ord(ch):04X}",
                    "count": count,
                    "unicode_name": unicode_name(ch),
                    "examples": examples[ch],
                }
            )

        json_path = REPORTS_DIR / f"normalization_audit_{source_type}.json"
        json_path.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")

        markdown = build_markdown(source_type, len(paths), files_with_target, counts, examples)
        md_path = REPORTS_DIR / f"normalization_audit_{source_type}.md"
        md_path.write_text(markdown, encoding="utf-8")

        print(
            f"[{source_type}] files={len(paths)} files_with_target={files_with_target} "
            f"chars={len(counts)} -> {md_path}"
        )


if __name__ == "__main__":
    main()
