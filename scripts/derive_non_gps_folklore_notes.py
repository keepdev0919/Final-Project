"""Build a lean documentation sheet for folklore entries without GPS.

The output intentionally keeps only three analysis fields per story:

1. core_category
2. spatial_clue
3. service_use

This helps treat non-GPS folklore as a reusable content asset without mixing it
into the location-confirmed route generation pool.
"""

from __future__ import annotations

import csv
import json
from collections import Counter
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent.parent
FULL_TAGGING_CSV = BASE_DIR / "docs" / "experiments" / "006-full-folklore-tagging-v1.csv"
GPS_JSON = BASE_DIR / "data" / "processed" / "folklore_gps.json"
OUT_CSV = BASE_DIR / "docs" / "experiments" / "007-non-gps-folklore-notes-v1.csv"


def top_space(raw_spaces: str) -> str:
    spaces = [item.strip() for item in raw_spaces.split("|") if item.strip()]
    priority = [
        "바다",
        "해안 마을",
        "섬",
        "당/사당",
        "한라산 권역",
        "산/오름",
        "동굴/연못/폭포",
        "마을",
    ]
    for item in priority:
        if item in spaces:
            return item
    return spaces[0] if spaces else "단서 약함"


def choose_service_use(source_type: str, core_category: str, spatial_clue: str) -> str:
    if source_type == "legend":
        if spatial_clue in {"바다", "해안 마을", "섬", "당/사당", "한라산 권역", "산/오름"}:
            return "GPS 복원 후보"
        return "장소 상세/코스 설명 보강"

    if core_category in {"초자연 존재담", "해양·어촌 전승", "가족·인간사 서사"}:
        if spatial_clue in {"바다", "해안 마을", "섬", "마을"}:
            return "GPS 복원 후보"
        return "장소 상세/코스 설명 보강"

    return "챗봇·RAG 보강"


def main() -> None:
    full_rows = list(csv.DictReader(FULL_TAGGING_CSV.open(encoding="utf-8-sig")))
    gps_codes = {item["code_no"] for item in json.loads(GPS_JSON.read_text(encoding="utf-8"))}
    non_gps_rows = [row for row in full_rows if row["code_no"] not in gps_codes]

    output_rows: list[dict[str, str]] = []
    source_counter: Counter[str] = Counter()
    category_counter: Counter[str] = Counter()
    spatial_counter: Counter[str] = Counter()
    use_counter: Counter[str] = Counter()

    for row in non_gps_rows:
        core_category = row["representative_category"]
        spatial_clue = top_space(row["spaces"])
        service_use = choose_service_use(row["source_type"], core_category, spatial_clue)

        source_counter[row["source_type"]] += 1
        category_counter[core_category] += 1
        spatial_counter[spatial_clue] += 1
        use_counter[service_use] += 1

        output_rows.append(
            {
                "code_no": row["code_no"],
                "title": row["title"],
                "source_type": row["source_type"],
                "core_category": core_category,
                "spatial_clue": spatial_clue,
                "service_use": service_use,
                "text_hint": row["text_hint"],
            }
        )

    with OUT_CSV.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(output_rows[0].keys()))
        writer.writeheader()
        writer.writerows(output_rows)

    summary = {
        "total_items": len(output_rows),
        "source_counts": dict(source_counter.most_common()),
        "core_category_counts": dict(category_counter.most_common()),
        "spatial_clue_counts": dict(spatial_counter.most_common()),
        "service_use_counts": dict(use_counter.most_common()),
    }

    print(OUT_CSV)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
