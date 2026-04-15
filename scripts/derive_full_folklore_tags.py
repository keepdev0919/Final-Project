"""Derive first-pass tags for the full folklore corpus.

This script scans the normalized legend/folktale corpus and produces a
first-pass tagging table for all usable normalized texts. It is intended to
support category derivation from the full 505-item corpus before narrowing the
results back down to GPS-usable stories.
"""

from __future__ import annotations

import csv
import json
from collections import Counter
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent.parent
LEGEND_DIR = BASE_DIR / "data" / "normalized" / "legend"
FOLKTALE_DIR = BASE_DIR / "data" / "normalized" / "folktale"
LEGEND_META = BASE_DIR / "data" / "processed" / "metadata_legend.jsonl"
FOLKTALE_META = BASE_DIR / "data" / "processed" / "metadata_folktale.jsonl"
OUT_CSV = BASE_DIR / "docs" / "experiments" / "006-full-folklore-tagging-v1.csv"


CORE_RULES = {
    "무속신화·신격 전승": [
        "본풀이",
        "당본풀이",
        "본향당",
        "당의 내력",
        "당신으로 좌정",
        "좌정",
        "심방",
        "굿",
        "조상신",
        "수호신",
        "신화",
        "신격",
        "적강",
        "옥황상제",
        "용왕국",
    ],
    "마을 공동체 전승": [
        "본향당",
        "본향",
        "마을 사람들이",
        "함께 모시는",
        "문중",
        "집안",
        "향당",
        "당제",
        "마을의 당",
        "동네",
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
        "어부",
        "고기잡이",
        "풍어",
        "영등",
        "해신",
        "바당",
        "난파",
        "파선",
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
        "원귀",
        "빙의",
        "저승",
    ],
    "가족·인간사 서사": [
        "계모",
        "혼인",
        "신랑",
        "신부",
        "부부",
        "인연",
        "팔자",
        "원한",
        "효자",
        "처녀",
        "총각",
        "콩데기",
        "사랑",
        "이별",
        "서러운",
        "설운",
        "한이 맺",
        "못살게",
        "학대",
        "눈물",
    ],
    "생활민담·교훈담": [
        "민담",
        "교훈",
        "권선징악",
        "지혜",
        "재치",
        "꾀",
        "웃음",
        "하르방",
        "선비",
        "공서방",
        "배서방",
        "토끼",
        "까마귀",
        "욕심",
        "벌을 받",
    ],
    "지명·지형 유래": [
        "지명유래",
        "지명의 유래",
        "유래",
        "생겨나",
        "형성",
        "연못",
        "동굴",
        "폭포",
        "바위",
        "산천",
        "오름",
        "한라산",
        "백록담",
        "명당",
        "지세",
        "설촌",
        "봉우리",
    ],
}

MOOD_RULES = {
    "신성": ["본풀이", "당본풀이", "좌정", "심방", "굿", "제사", "신격"],
    "신비": ["전설", "용왕", "귀신", "도깨비", "도체비", "기이", "신비"],
    "공포": ["귀신", "도깨비", "도체비", "괴물", "삼두구미", "그슨새", "원귀"],
    "슬픔": ["원한", "이별", "서러운", "설운", "한이", "눈물", "비극"],
    "따뜻함": ["효자", "도와주", "가족", "부부", "정성", "공동체"],
    "익살": ["웃음", "우스운", "하르방", "똥", "재치", "꾀"],
    "경외": ["옥황상제", "신화", "신격", "용왕", "산신"],
}

ENTITY_RULES = {
    "신": ["옥황상제", "신격", "산신", "당신", "신령"],
    "조상신": ["조상신"],
    "마을신": ["본향당", "본향신", "당신"],
    "도체비/요괴": ["도깨비", "도체비", "요괴", "괴물", "삼두구미"],
    "혼령/귀신": ["귀신", "혼령", "원귀"],
    "동물": ["토끼", "까마귀", "호랑이", "구렁이", "여우", "개", "닭"],
    "용왕/해신": ["용왕", "해신"],
    "심방": ["심방"],
    "왕/관원/선비": ["왕", "목사", "현감", "관원", "선비"],
    "인간": ["사람", "하르방", "부부", "처녀", "총각", "며느리"],
}

SPACE_RULES = {
    "바다": ["바다", "바닷가", "바당", "난파", "파선", "포구"],
    "해안 마을": ["해안", "해변", "포구", "어촌"],
    "산/오름": ["한라산", "오름", "산", "봉우리", "산신"],
    "동굴/연못/폭포": ["동굴", "연못", "폭포"],
    "마을": ["마을", "동네", "마을회관", "경로당", "본향"],
    "당/사당": ["당", "사당", "본향당"],
    "섬": ["마라도", "우도", "섬"],
    "한라산 권역": ["한라산", "백록담"],
}

FUNCTION_RULES = {
    "기원 설명": ["유래", "생겨나", "형성", "기원"],
    "금기 설명": ["금기", "안 된다", "삼가", "조심"],
    "장소 신성화": ["당의 내력", "좌정", "본향당", "수호신"],
    "인물 전승": ["내력", "전승", "이야기이다"],
    "교훈 전달": ["교훈", "권선징악", "지혜", "경고", "벌을 받"],
    "공동체 기억": ["함께 모시는", "집안", "문중", "마을 사람들이"],
    "비극 기억": ["원한", "비극", "이별", "학대", "죽음"],
}


def load_metadata(path: Path) -> dict[str, dict[str, str]]:
    items: dict[str, dict[str, str]] = {}
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            row = json.loads(line)
            items[row["code_no"]] = row
    return items


def count_hits(text: str, keywords: list[str]) -> int:
    return sum(1 for keyword in keywords if keyword in text)


def sorted_labels(score_map: dict[str, int], *, min_score: int = 1) -> list[str]:
    labels = [(label, score) for label, score in score_map.items() if score >= min_score]
    labels.sort(key=lambda item: (-item[1], item[0]))
    return [label for label, _ in labels]


def join_labels(labels: list[str]) -> str:
    return " | ".join(labels)


def infer_narrative_type(source_type: str, text: str) -> str:
    if source_type == "legend":
        if any(keyword in text for keyword in ["본풀이", "신화", "심방", "굿", "당본풀이"]):
            return "무속신화"
        return "전설"
    if any(keyword in text for keyword in ["귀신", "도깨비", "도체비", "그슨새"]):
        return "민담 | 전설"
    return "민담"


def choose_representative_category(source_type: str, core_scores: dict[str, int]) -> str:
    legend_priority = [
        "해양·어촌 전승",
        "초자연 존재담",
        "지명·지형 유래",
        "마을 공동체 전승",
        "가족·인간사 서사",
        "생활민담·교훈담",
    ]
    folktale_priority = [
        "생활민담·교훈담",
        "초자연 존재담",
        "가족·인간사 서사",
        "해양·어촌 전승",
        "지명·지형 유래",
        "마을 공동체 전승",
        "무속신화·신격 전승",
    ]

    if source_type == "legend":
        myth_score = core_scores["무속신화·신격 전승"]
        for label in legend_priority:
            score = core_scores[label]
            if label in {"해양·어촌 전승", "초자연 존재담", "지명·지형 유래", "마을 공동체 전승"}:
                if score >= 2 and score >= myth_score:
                    return label
            elif label in {"가족·인간사 서사", "생활민담·교훈담"}:
                if score >= myth_score + 2:
                    return label
        return "무속신화·신격 전승"

    ranked = sorted(folktale_priority, key=lambda label: (-core_scores[label], folktale_priority.index(label)))
    if core_scores[ranked[0]] > 0:
        return ranked[0]
    return "생활민담·교훈담"


def extract_hint(text: str) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    filtered = [
        line
        for line in lines[1:12]
        if not line.startswith(("1 ", "2 ", "3 ", "4 ", "5 ", "6 ", "•줄거리", "∙ 핵심어"))
    ]
    hint = " ".join(filtered)[:240].strip()
    return hint


def iter_corpus_files() -> list[tuple[str, Path]]:
    items: list[tuple[str, Path]] = []
    items.extend(("legend", path) for path in sorted(LEGEND_DIR.glob("*.txt")))
    items.extend(("folktale", path) for path in sorted(FOLKTALE_DIR.glob("*.txt")))
    return items


def main() -> None:
    legend_meta = load_metadata(LEGEND_META)
    folktale_meta = load_metadata(FOLKTALE_META)
    metadata_map = {**legend_meta, **folktale_meta}

    rows: list[dict[str, str]] = []
    core_counter: Counter[str] = Counter()
    representative_counter: Counter[str] = Counter()
    mood_counter: Counter[str] = Counter()
    entity_counter: Counter[str] = Counter()
    space_counter: Counter[str] = Counter()
    function_counter: Counter[str] = Counter()
    source_counter: Counter[str] = Counter()

    for source_type, path in iter_corpus_files():
        code_no = path.stem
        metadata = metadata_map.get(code_no, {})
        normalized_text = path.read_text(encoding="utf-8")
        title = metadata.get("title") or normalized_text.splitlines()[0].strip()
        analysis_text = " ".join(
            [
                title,
                metadata.get("tags", ""),
                metadata.get("category", ""),
                normalized_text,
            ]
        )

        narrative_type = infer_narrative_type(source_type, analysis_text)
        core_scores = {label: count_hits(analysis_text, keywords) for label, keywords in CORE_RULES.items()}

        if source_type == "legend":
            core_scores["무속신화·신격 전승"] += 2
        if source_type == "folktale":
            core_scores["생활민담·교훈담"] += 1

        core_topics = sorted_labels(core_scores, min_score=2)
        if not core_topics:
            core_topics = ["생활민담·교훈담" if source_type == "folktale" else "무속신화·신격 전승"]
        representative_category = choose_representative_category(source_type, core_scores)

        mood_scores = {label: count_hits(analysis_text, keywords) for label, keywords in MOOD_RULES.items()}
        if "무속신화·신격 전승" in core_topics:
            mood_scores["신성"] += 1
            mood_scores["경외"] += 1
        if "생활민담·교훈담" in core_topics:
            mood_scores["익살"] += 1
        moods = sorted_labels(mood_scores, min_score=1) or ["신비"]

        entity_scores = {label: count_hits(analysis_text, keywords) for label, keywords in ENTITY_RULES.items()}
        if source_type == "folktale":
            entity_scores["인간"] += 1
        if "무속신화·신격 전승" in core_topics:
            entity_scores["신"] += 1
        entities = sorted_labels(entity_scores, min_score=1) or ["인간"]

        space_scores = {label: count_hits(analysis_text, keywords) for label, keywords in SPACE_RULES.items()}
        if "마을 공동체 전승" in core_topics:
            space_scores["마을"] += 1
        spaces = sorted_labels(space_scores, min_score=1) or ["마을"]

        function_scores = {label: count_hits(analysis_text, keywords) for label, keywords in FUNCTION_RULES.items()}
        if "지명·지형 유래" in core_topics:
            function_scores["기원 설명"] += 1
        if "마을 공동체 전승" in core_topics or "무속신화·신격 전승" in core_topics:
            function_scores["공동체 기억"] += 1
        if source_type == "folktale":
            function_scores["교훈 전달"] += 1
        else:
            function_scores["인물 전승"] += 1
        functions = sorted_labels(function_scores, min_score=1) or ["인물 전승"]

        source_counter[source_type] += 1
        representative_counter[representative_category] += 1
        for label in core_topics:
            core_counter[label] += 1
        for label in moods:
            mood_counter[label] += 1
        for label in entities:
            entity_counter[label] += 1
        for label in spaces:
            space_counter[label] += 1
        for label in functions:
            function_counter[label] += 1

        rows.append(
            {
                "code_no": code_no,
                "title": title,
                "source_type": source_type,
                "api_category": metadata.get("category", ""),
                "api_tags": metadata.get("tags", ""),
                "source_path": str(path.relative_to(BASE_DIR)),
                "text_hint": extract_hint(normalized_text),
                "narrative_type": narrative_type,
                "representative_category": representative_category,
                "core_topics": join_labels(core_topics),
                "moods": join_labels(moods),
                "entities": join_labels(entities),
                "spaces": join_labels(spaces),
                "functions": join_labels(functions),
            }
        )

    with OUT_CSV.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    summary = {
        "total_items": len(rows),
        "source_counts": dict(source_counter.most_common()),
        "representative_category_counts": dict(representative_counter.most_common()),
        "core_topic_counts": dict(core_counter.most_common()),
        "mood_counts": dict(mood_counter.most_common()),
        "entity_counts": dict(entity_counter.most_common()),
        "space_counts": dict(space_counter.most_common()),
        "function_counts": dict(function_counter.most_common()),
    }
    print(OUT_CSV)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
