"""Derive first-pass tags for GPS-enabled folklore entries.

This script builds a reusable first-pass tagging dataset from the folklore
metadata and GPS-usable folklore list. The output is intended to support:

1. data-driven internal category derivation
2. user-question redesign based on real folklore content
3. later agent candidate selection
"""

from __future__ import annotations

import csv
import json
import sqlite3
from collections import Counter
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent.parent
GPS_PATH = BASE_DIR / "data" / "processed" / "folklore_gps.json"
DB_PATH = BASE_DIR / "storage" / "metadata.db"
OUT_CSV = BASE_DIR / "docs" / "experiments" / "004-gps-folklore-tagging-v1.csv"
OUT_JSON = BASE_DIR / "docs" / "experiments" / "004-gps-folklore-tagging-v1-summary.json"


CORE_RULES = {
    "무속신화·신격 전승": [
        "본풀이",
        "당본풀이",
        "본향당",
        "본향신",
        "당의 내력",
        "당신",
        "좌정",
        "심방",
        "굿",
        "수호신",
        "조상신",
        "신격",
        "신화",
        "제사",
        "산신대왕",
        "당주",
    ],
    "마을 공동체 전승": [
        "본향당",
        "본향",
        "함께 모시는",
        "집안",
        "문중",
        "향당",
        "수호신",
        "마을의 당",
        "마을 사람들이",
        "동네 사람들",
    ],
    "해양·어촌 전승": [
        "바다",
        "바닷가",
        "용왕",
        "해녀",
        "잠수",
        "물질",
        "전복",
        "소라",
        "바당",
        "해신",
        "어부",
        "난파",
        "파선",
        "풍어",
        "고기잡이",
        "멜",
        "선박",
    ],
    "초자연 존재담": [
        "도깨비",
        "도체비",
        "도깨빗불",
        "귀신",
        "혼령",
        "요괴",
        "괴물",
        "삼두구미",
        "그슨새",
        "둔갑",
        "변신",
        "빙의",
        "원귀",
        "저승",
    ],
    "가족·인간사 서사": [
        "며느리",
        "계모",
        "혼인",
        "신랑",
        "신부",
        "인연",
        "팔자",
        "원한",
        "효자",
        "처녀",
        "총각",
        "콩데기",
        "본처",
        "버려진",
        "학대",
        "사랑",
        "이별",
        "부부",
        "서러운",
        "설운",
    ],
    "생활민담·교훈담": [
        "민담",
        "지혜",
        "교훈",
        "권선징악",
        "과거시험",
        "선비",
        "제자",
        "하르방",
        "토끼",
        "까마귀",
        "꾀",
        "웃음",
        "재치",
        "공서방",
        "배서방",
    ],
    "지명·지형 유래": [
        "유래",
        "오름",
        "연못",
        "동굴",
        "폭포",
        "바위",
        "지명",
        "설촌",
        "지세",
        "명당",
        "봉우리",
        "형성",
        "생겨",
        "산천",
        "경계",
        "갈랐다",
        "차지할 땅",
    ],
}

MOOD_RULES = {
    "신성": ["본풀이", "당본풀이", "당신", "좌정", "심방", "굿", "신화", "신격", "제사", "수호신"],
    "신비": ["용왕", "바다", "도깨비", "도체비", "귀신", "괴물", "빙의", "저승", "전설"],
    "공포": ["귀신", "괴물", "도깨비", "도체비", "삼두구미", "그슨새", "원귀", "시체"],
    "슬픔": ["원한", "이별", "서러운", "설운", "비극", "못살게", "학대"],
    "따뜻함": ["가족", "부부", "효자", "도와준", "집안", "아기"],
    "익살": ["하르방", "익살", "똥", "토끼", "재치", "꾀", "웃음"],
    "경외": ["신화", "신격", "산신", "용왕", "본향당"],
}

ENTITY_RULES = {
    "신": ["옥황상제", "신화", "신격", "신"],
    "조상신": ["조상신"],
    "마을신": ["본향당", "당신", "본향신"],
    "도체비/요괴": ["도깨비", "도체비", "도깨빗불", "요괴", "괴물", "삼두구미"],
    "혼령/귀신": ["귀신", "혼령", "원귀", "저승"],
    "동물": ["토끼", "까마귀", "개", "닭", "호랑이", "구렁이", "여우", "생이"],
    "용왕/해신": ["용왕", "해신"],
    "심방": ["심방"],
    "왕/관원/선비": ["목사", "현감", "관원", "선비", "왕", "옥황상제"],
    "인간": ["사람", "부부", "아들", "딸", "며느리", "하르방", "아기", "처녀", "총각"],
}

SPACE_RULES = {
    "바다": ["바다", "바닷가", "용왕", "해녀", "잠수", "물질", "난파", "파선", "해신", "어부"],
    "해안 마을": ["해안", "해변", "포구", "바닷가"],
    "산/오름": ["한라산", "오름", "산", "산신"],
    "동굴/연못/폭포": ["동굴", "연못", "폭포"],
    "당/사당": ["당", "사당", "본향당"],
    "섬": ["마라도", "우도", "섬"],
    "한라산 권역": ["한라산", "백록담"],
}

FUNCTION_RULES = {
    "기원 설명": ["유래", "생겨", "형성", "기원"],
    "금기 설명": ["안 된다", "금기", "경고"],
    "장소 신성화": ["당의 내력", "본향당", "좌정", "수호신"],
    "인물 전승": ["내력", "전승", "이야기이다"],
    "교훈 전달": ["교훈", "지혜", "경고", "밝혀낸", "도와준"],
    "공동체 기억": ["함께 모시는", "집안", "문중", "마을 사람들이"],
    "비극 기억": ["원한", "비극", "못살게", "학대"],
}


def count_hits(text: str, keywords: list[str]) -> int:
    return sum(1 for keyword in keywords if keyword in text)


def join_labels(labels: list[str]) -> str:
    return " | ".join(labels)


def sorted_labels(score_map: dict[str, int], *, min_score: int = 1) -> list[str]:
    labels = [(label, score) for label, score in score_map.items() if score >= min_score]
    labels.sort(key=lambda item: (-item[1], item[0]))
    return [label for label, _ in labels]


def infer_narrative_type(source_type: str, text: str) -> str:
    if source_type == "legend":
        if any(keyword in text for keyword in ["본풀이", "신화", "심방", "굿", "당본풀이"]):
            return "무속신화"
        return "전설"
    if any(keyword in text for keyword in ["귀신", "도깨비", "도체비", "그슨새"]):
        return "민담 | 전설"
    return "민담"


def choose_representative_category(source_type: str, core_scores: dict[str, int]) -> str:
    """Choose a more user-facing representative category.

    The broad myth bucket is useful as a tag, but it dominates primary scores for
    legend items. For UX/question design we also want a more specific focus
    category when available.
    """

    priority = [
        "해양·어촌 전승",
        "초자연 존재담",
        "지명·지형 유래",
        "마을 공동체 전승",
        "가족·인간사 서사",
        "생활민담·교훈담",
        "무속신화·신격 전승",
    ]

    if source_type == "legend":
        for label in priority[:-1]:
            if core_scores[label] >= 2:
                return label
        return "무속신화·신격 전승"

    ranked = sorted(priority, key=lambda label: (-core_scores[label], priority.index(label)))
    if core_scores[ranked[0]] > 0:
        return ranked[0]
    return "생활민담·교훈담"


def main() -> None:
    gps_items = json.loads(GPS_PATH.read_text(encoding="utf-8"))
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    out_rows: list[dict[str, str]] = []
    core_counter: Counter[str] = Counter()
    primary_counter: Counter[str] = Counter()
    representative_counter: Counter[str] = Counter()
    mood_counter: Counter[str] = Counter()
    entity_counter: Counter[str] = Counter()
    space_counter: Counter[str] = Counter()
    function_counter: Counter[str] = Counter()

    for item in gps_items:
        row = conn.execute(
            """
            SELECT title, source_type, category, category2, tags, summary
            FROM metadata
            WHERE code_no=?
            LIMIT 1
            """,
            (item["code_no"],),
        ).fetchone()
        if row is None:
            continue

        text = " ".join(
            [
                row["title"] or "",
                row["tags"] or "",
                row["summary"] or "",
                item["primary_place"],
                " ".join(item.get("all_places", [])),
            ]
        )

        narrative_type = infer_narrative_type(row["source_type"], text)

        core_scores = {label: count_hits(text, keywords) for label, keywords in CORE_RULES.items()}
        if row["source_type"] == "legend":
            core_scores["무속신화·신격 전승"] += 2
        if row["source_type"] == "folktale":
            core_scores["생활민담·교훈담"] += 2
            core_scores["가족·인간사 서사"] += 1
        core_topics = sorted_labels(core_scores, min_score=1)
        if not core_topics:
            core_topics = ["생활민담·교훈담" if row["source_type"] == "folktale" else "무속신화·신격 전승"]
        primary_category = core_topics[0]
        representative_category = choose_representative_category(row["source_type"], core_scores)

        mood_scores = {label: count_hits(text, keywords) for label, keywords in MOOD_RULES.items()}
        if row["source_type"] == "legend":
            mood_scores["신비"] += 1
        if "무속신화·신격 전승" in core_topics:
            mood_scores["신성"] += 1
            mood_scores["경외"] += 1
        if "생활민담·교훈담" in core_topics:
            mood_scores["익살"] += 1
        moods = sorted_labels(mood_scores, min_score=1) or ["신비"]

        entity_scores = {label: count_hits(text, keywords) for label, keywords in ENTITY_RULES.items()}
        if row["source_type"] == "folktale":
            entity_scores["인간"] += 1
        if "무속신화·신격 전승" in core_topics:
            entity_scores["신"] += 1
        entities = sorted_labels(entity_scores, min_score=1) or ["인간"]

        space_scores = {label: count_hits(text, keywords) for label, keywords in SPACE_RULES.items()}
        primary_place = item["primary_place"]
        if primary_place.endswith(("리", "읍", "면", "동")):
            space_scores["마을"] = space_scores.get("마을", 0) + 1
        if primary_place in {"한라산", "백록담"}:
            space_scores["산/오름"] += 1
            space_scores["한라산 권역"] += 1
        spaces = sorted_labels(space_scores, min_score=1) or ["마을"]

        function_scores = {label: count_hits(text, keywords) for label, keywords in FUNCTION_RULES.items()}
        if "지명·지형 유래" in core_topics:
            function_scores["기원 설명"] += 1
        if "마을 공동체 전승" in core_topics or "무속신화·신격 전승" in core_topics:
            function_scores["공동체 기억"] += 1
        if row["source_type"] == "folktale":
            function_scores["교훈 전달"] += 1
        else:
            function_scores["인물 전승"] += 1
        functions = sorted_labels(function_scores, min_score=1) or ["인물 전승"]

        for label in core_topics:
            core_counter[label] += 1
        primary_counter[primary_category] += 1
        representative_counter[representative_category] += 1
        for label in moods:
            mood_counter[label] += 1
        for label in entities:
            entity_counter[label] += 1
        for label in spaces:
            space_counter[label] += 1
        for label in functions:
            function_counter[label] += 1

        out_rows.append(
            {
                "code_no": item["code_no"],
                "title": row["title"],
                "source_type": row["source_type"],
                "primary_place": item["primary_place"],
                "lat": str(item["lat"]),
                "lng": str(item["lng"]),
                "all_places": join_labels(item.get("all_places", [])),
                "summary_hint": (row["summary"] or "").replace("\r", " ").replace("\n", " ").strip(),
                "api_category": row["category"] or "",
                "api_category2": row["category2"] or "",
                "api_tags": row["tags"] or "",
                "narrative_type": narrative_type,
                "primary_category": primary_category,
                "representative_category": representative_category,
                "core_topics": join_labels(core_topics),
                "entities": join_labels(entities),
                "spaces": join_labels(spaces),
                "moods": join_labels(moods),
                "functions": join_labels(functions),
            }
        )

    with OUT_CSV.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(out_rows[0].keys()))
        writer.writeheader()
        writer.writerows(out_rows)

    summary = {
        "total_items": len(out_rows),
        "core_topic_counts": dict(core_counter.most_common()),
        "primary_category_counts": dict(primary_counter.most_common()),
        "representative_category_counts": dict(representative_counter.most_common()),
        "mood_counts": dict(mood_counter.most_common()),
        "entity_counts": dict(entity_counter.most_common()),
        "space_counts": dict(space_counter.most_common()),
        "function_counts": dict(function_counter.most_common()),
    }
    OUT_JSON.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    print(OUT_CSV)
    print(OUT_JSON)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
