from __future__ import annotations

import csv
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
INPUT_CSV = ROOT / "docs" / "experiments" / "004-gps-folklore-tagging-v1.csv"
OUTPUT_CSV = ROOT / "docs" / "experiments" / "gps-folklore-final.csv"
OUTPUT_MD = ROOT / "docs" / "experiments" / "gps-folklore-final.md"


def normalize_category(row: dict[str, str]) -> str:
    code = row["code_no"]
    category = row["representative_category"]

    # Final cleanup after human review of rare categories.
    if code == "T_M_072":
        return "무속신화·신격 전승"
    if code == "W-F-258":
        return "초자연 존재담"
    if category == "지명·지형 유래":
        return "마을 공동체 전승"
    if category == "가족·인간사 서사":
        return "초자연 존재담"
    return category


def spatial_focus(spaces: str) -> str:
    values = [v.strip() for v in spaces.split("|") if v.strip()]
    joined = " ".join(values)
    if "바다" in joined or "해안 마을" in joined or "섬" in joined:
        return "바다·해안"
    if "당/사당" in joined:
        return "당·사당"
    if "한라산 권역" in joined or "산/오름" in joined:
        return "산·오름"
    if "동굴/연못/폭포" in joined:
        return "자연지형"
    if "마을" in joined:
        return "마을"
    return values[0] if values else ""


def category_sort_key(category: str) -> tuple[int, str]:
    order = {
        "무속신화·신격 전승": 0,
        "마을 공동체 전승": 1,
        "해양·어촌 전승": 2,
        "생활민담·교훈담": 3,
        "초자연 존재담": 4,
    }
    return (order.get(category, 99), category)


def build() -> None:
    rows = list(csv.DictReader(INPUT_CSV.open(encoding="utf-8-sig")))
    final_rows: list[dict[str, str]] = []
    for row in rows:
        final_rows.append(
            {
                "code_no": row["code_no"],
                "title": row["title"],
                "source_type": row["source_type"],
                "primary_place": row["primary_place"],
                "final_category": normalize_category(row),
                "spatial_focus": spatial_focus(row["spaces"]),
                "summary_hint": row["summary_hint"],
            }
        )

    final_rows.sort(
        key=lambda r: (
            category_sort_key(r["final_category"]),
            r["primary_place"],
            r["title"],
        )
    )

    fieldnames = [
        "code_no",
        "title",
        "source_type",
        "primary_place",
        "final_category",
        "spatial_focus",
        "summary_hint",
    ]
    with OUTPUT_CSV.open("w", encoding="utf-8-sig", newline="") as fp:
        writer = csv.DictWriter(fp, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(final_rows)

    counts = Counter(r["final_category"] for r in final_rows)
    samples: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in final_rows:
        if len(samples[row["final_category"]]) < 5:
            samples[row["final_category"]].append(row)

    lines = [
        "# GPS 설화 최종본",
        "",
        "228개 GPS 설화를 마지막으로 정리한 최종 분류본입니다.",
        "",
        "정리 원칙:",
        "- 사람이 읽기 쉬운 최종본만 남기기 위해 컬럼을 줄였습니다.",
        "- 희소 카테고리였던 `지명·지형 유래`와 `가족·인간사 서사`는 마지막 검토 후 인접 범주로 통합했습니다.",
        "- `차사본풀이(T_M_072)`는 무속신화 계열로, `죽은 혼사 거부한 언니 영혼(W-F-258)`은 초자연 존재담으로 직접 보정했습니다.",
        "",
        "최종 카테고리 분포:",
    ]
    for category, count in sorted(counts.items(), key=lambda item: category_sort_key(item[0])):
        lines.append(f"- {category}: {count}개")

    for category, items in sorted(samples.items(), key=lambda item: category_sort_key(item[0])):
        lines.extend(
            [
                "",
                f"## {category}",
            ]
        )
        for row in items:
            lines.append(
                f"- {row['title']} ({row['primary_place']}, {row['source_type']}, {row['spatial_focus']})"
            )

    OUTPUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build()
