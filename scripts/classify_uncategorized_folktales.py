"""미분류 설화 212개를 5개 정식 카테고리로 분류.

방식:
  1. 키워드 기반 1차 분류 (도체비/심방/바당 등 명확한 신호)
  2. unclear 케이스는 별도 표시 → 수동 검토 대상
  3. 결과를 docs/experiments/folktale_categorized_212.csv에 저장
"""
from __future__ import annotations

import csv
import json
import re
from collections import Counter
from pathlib import Path

BASE = Path(__file__).parent.parent
INPUT_PATH = BASE / "docs" / "experiments" / "folktale_uncategorized_212.json"
OUTPUT_CSV = BASE / "docs" / "experiments" / "folktale_categorized_212.csv"

CATEGORIES = {
    "MUSOK": "무속신화·신격 전승",
    "FOLKTALE": "생활민담·교훈담",
    "VILLAGE": "마을 공동체 전승",
    "MARINE": "해양·어촌 전승",
    "SUPERNATURAL": "초자연 존재담",
}

# 키워드 점수 기반 분류 (점수 합산 → 가장 높은 카테고리)

KEYWORD_SCORES: dict[str, list[tuple[str, int]]] = {
    "SUPERNATURAL": [
        ("도체비", 5), ("도깨비", 5), ("도채비", 5),
        ("헛게", 4), ("헛불", 4), ("도체빗불", 5), ("도채빗불", 5),
        ("귀신", 3), ("구신", 3), ("혼령", 3), ("기신세", 3),
        ("저승", 2), ("저싱", 2), ("산신", 2), ("호랑이 눈썹", 2),
        ("여우누이", 3), ("둔갑", 2), ("홀려", 2), ("홀린", 2), ("홀리", 2),
        ("벡발노인", 2), ("그슨대", 4), ("그슨새", 4),
    ],
    "MUSOK": [
        ("본풀이", 6), ("당본풀이", 7), ("본향", 4), ("당신", 4),
        ("심방", 5), ("신앙", 2), ("신령", 3), ("좌정", 4),
        ("당제", 4), ("당오백", 3), ("절오백", 3),
        ("천지왕", 4), ("자청비", 4), ("문전제", 3), ("조왕", 3),
        ("영감본", 4), ("애기씨", 2),
    ],
    "MARINE": [
        ("해녀", 5), ("물질", 5), ("테왁", 4), ("불턱", 4), ("숨비", 4),
        ("바당", 2), ("바다", 2), ("어부", 4), ("어선", 3), ("어업", 3),
        ("용왕", 5), ("영등", 5), ("멸치", 3), ("멜", 2), ("갈치", 2),
        ("전복", 3), ("문어", 2), ("배 침몰", 3), ("풍어", 4),
        ("선원", 3), ("뱃사람", 3), ("포구", 2), ("갯것", 2),
    ],
    "VILLAGE": [
        ("마을 유래", 5), ("지명 유래", 5), ("마을신", 4),
        ("당오백절오백", 4), ("향토", 2), ("당집", 3),
        ("동네 시작", 3), ("마을 시작", 3),
    ],
    "FOLKTALE": [
        ("효자", 4), ("효녀", 4), ("효성", 3),
        ("권선징악", 5), ("교훈", 3),
        ("과거", 3), ("선비", 3), ("스승", 3), ("제자", 3),
        ("계모", 4), ("부부", 2), ("형제", 2), ("삼형제", 3),
        ("백정", 3), ("양반", 2), ("진정한", 2),
        ("말 한 마디", 4), ("우스갯", 4), ("욕", 2),
        ("지혜", 3), ("재치", 3), ("위기를 면", 4),
        ("거짓말", 2), ("게으름", 2), ("부지런", 2),
    ],
}


def classify(title: str, context: str) -> tuple[str, dict[str, int], str]:
    """카테고리 + 점수 분포 + 결정 사유 반환."""
    text = (title + " " + context)

    scores: dict[str, int] = {k: 0 for k in CATEGORIES}
    hits: dict[str, list[str]] = {k: [] for k in CATEGORIES}

    for cat, kw_list in KEYWORD_SCORES.items():
        for kw, w in kw_list:
            count = text.count(kw)
            if count > 0:
                scores[cat] += w * count
                hits[cat].append(f"{kw}×{count}")

    # 후처리: 도체비인데 어업 맥락 → MARINE 우선
    if scores["SUPERNATURAL"] > 0 and scores["MARINE"] > 0:
        if any(k in text for k in ["멸치", "멜잡", "풍어", "어부", "포구", "어업"]):
            scores["MARINE"] += 3

    # 최고 점수
    if max(scores.values()) == 0:
        return "FOLKTALE", scores, "default(권선징악·일상)"

    best = max(scores.items(), key=lambda x: x[1])
    return best[0], scores, ", ".join(hits[best[0]][:3])


def main() -> None:
    with open(INPUT_PATH) as f:
        data = json.load(f)

    rows = []
    cat_counter: Counter = Counter()
    confidence_buckets = {"high": 0, "med": 0, "low": 0}

    for d in data:
        cat_key, scores, reason = classify(d["title"], d["context"])
        cat_label = CATEGORIES[cat_key]

        # 신뢰도: 1등 점수 vs 2등 점수 격차
        sorted_scores = sorted(scores.values(), reverse=True)
        top, second = sorted_scores[0], sorted_scores[1] if len(sorted_scores) > 1 else 0
        if top == 0:
            conf = "low"
        elif top >= 6 and (top - second) >= 3:
            conf = "high"
        elif top >= 3:
            conf = "med"
        else:
            conf = "low"

        confidence_buckets[conf] += 1
        cat_counter[cat_label] += 1

        rows.append({
            "code_no": d["code_no"],
            "title": d["title"],
            "final_category": cat_label,
            "confidence": conf,
            "top_score": top,
            "reason": reason,
            "context_excerpt": d["context"][:120],
        })

    # CSV 저장
    OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["code_no", "title", "final_category", "confidence",
                        "top_score", "reason", "context_excerpt"],
        )
        writer.writeheader()
        writer.writerows(rows)

    # 출력
    print(f"총 {len(rows)}개 분류 완료\n")
    print("카테고리 분포:")
    for cat, cnt in cat_counter.most_common():
        print(f"  {cat:25s} {cnt:4d} ({cnt/len(rows)*100:.1f}%)")
    print(f"\n신뢰도:")
    for level, cnt in confidence_buckets.items():
        print(f"  {level:6s} {cnt:4d} ({cnt/len(rows)*100:.1f}%)")
    print(f"\n💾 저장: {OUTPUT_CSV}")


if __name__ == "__main__":
    main()
