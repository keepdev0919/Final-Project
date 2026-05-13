"""설화 재분류 효과 검증: before(백업) vs after(현재) 추천 결과 비교.

같은 입력으로 두 DB에 코스 추천을 돌려서:
  1. Top 3 코스가 어떻게 바뀌었는지
  2. 각 코스의 카테고리 점수가 어떻게 변했는지
  3. 어떤 도체비/심방 풍부한 코스가 새로 올라왔는지
"""
from __future__ import annotations

import sqlite3
from pathlib import Path

BASE = Path(__file__).parent.parent
DB_AFTER = BASE / "storage" / "metadata.db"
DB_BEFORE = BASE / "storage" / "metadata.db.bak_before_folktale_recategorize"


def get_course_categories(conn: sqlite3.Connection, course_id: str) -> dict[str, int]:
    """코스에 매핑된 카테고리별 매핑 row 수."""
    rows = conn.execute("""
        SELECT pfm.final_category, COUNT(*) AS cnt
        FROM course_places cp
        JOIN place_folklore_mapping pfm ON pfm.place_name = cp.place_name
        WHERE cp.course_id = ? AND pfm.specificity >= 5
        GROUP BY pfm.final_category
    """, (course_id,)).fetchall()
    return {r[0]: r[1] for r in rows}


def get_course_distinct_categories(conn: sqlite3.Connection, course_id: str) -> set[str]:
    """현재 점수 계산 방식: distinct 카테고리만."""
    rows = conn.execute("""
        SELECT DISTINCT pfm.final_category
        FROM course_places cp
        JOIN place_folklore_mapping pfm ON pfm.place_name = cp.place_name
        WHERE cp.course_id = ? AND pfm.specificity >= 5
    """, (course_id,)).fetchall()
    return {r[0] for r in rows}


def score_courses(db_path: Path, region: str, category_scores: dict[str, int],
                  duration_days: int, top_n: int = 5) -> list[dict]:
    """course_list_agent.py와 동일한 로직."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    duration_min = max(1, duration_days - 1)
    duration_max = duration_days + 1

    rows = conn.execute("""
        SELECT id, title, duration_days, region
        FROM curated_courses
        WHERE region IN (?, '전체') AND duration_days BETWEEN ? AND ?
        ORDER BY CASE WHEN region = ? THEN 0 ELSE 1 END, composite_score DESC
        LIMIT 50
    """, (region, duration_min, duration_max, region)).fetchall()

    scored = []
    for row in rows:
        cats = get_course_distinct_categories(conn, row["id"])
        score = sum(category_scores.get(c, 0) for c in cats)
        cat_counts = get_course_categories(conn, row["id"])
        scored.append({
            "id": row["id"], "title": row["title"], "region": row["region"],
            "score": score, "categories": cats, "category_counts": cat_counts,
        })

    scored.sort(key=lambda x: -x["score"])
    conn.close()
    return scored[:top_n]


def print_results(label: str, scenarios: list[dict]) -> None:
    print(f"\n{'='*100}")
    print(f"  {label}")
    print(f"{'='*100}")
    for s in scenarios:
        title_str = s["title"][:35]
        cats_str = "/".join(sorted(s["categories"]))[:60]
        print(f"  [{s['score']:2d}점] {s['id']:6s} {title_str:35s}")
        print(f"        매핑: {s['category_counts']}")


# 시나리오 정의 (TasteDiscoveryView의 q1Map/q2Map과 동일)
SCENARIOS = [
    {
        "name": "동부 + 으스스한 이야기 + 바다 + 3일",
        "region": "동부",
        "category_scores": {  # supernatural + ocean
            "초자연 존재담": 3 + 1,
            "생활민담·교훈담": 1,
            "해양·어촌 전승": 3,
        },
        "duration_days": 3,
    },
    {
        "name": "서부 + 신이 마을에 내려오는 이야기 + 마을과 당 + 2일",
        "region": "서부",
        "category_scores": {  # mythology + village
            "무속신화·신격 전승": 3 + 1,
            "마을 공동체 전승": 1 + 2,
        },
        "duration_days": 2,
    },
    {
        "name": "전체 + 재치있고 교훈적인 이야기 + 상관없음 + 1일",
        "region": "전체",
        "category_scores": {  # folktale + any
            "생활민담·교훈담": 3,
            "마을 공동체 전승": 1,
        },
        "duration_days": 1,
    },
]


def main() -> None:
    for scenario in SCENARIOS:
        print(f"\n{'#'*100}")
        print(f"# 시나리오: {scenario['name']}")
        print(f"# category_scores: {scenario['category_scores']}")
        print(f"{'#'*100}")

        before = score_courses(DB_BEFORE, scenario["region"],
                               scenario["category_scores"], scenario["duration_days"])
        after = score_courses(DB_AFTER, scenario["region"],
                              scenario["category_scores"], scenario["duration_days"])

        print_results("BEFORE (설화 미분류 상태)", before)
        print_results("AFTER (설화 재분류 후)", after)

        # 변화 요약
        before_top3 = [(s["id"], s["score"]) for s in before[:3]]
        after_top3 = [(s["id"], s["score"]) for s in after[:3]]

        before_ids = {s["id"] for s in before[:3]}
        after_ids = {s["id"] for s in after[:3]}

        new = after_ids - before_ids
        removed = before_ids - after_ids

        print(f"\n{'─'*100}")
        print(f"  Top 3 변화")
        print(f"{'─'*100}")
        if new:
            print(f"  🆕 새로 들어옴: {sorted(new)}")
        if removed:
            print(f"  ❌ 빠짐: {sorted(removed)}")
        if not new and not removed:
            print(f"  ➖ Top 3 멤버 동일")
        print(f"  Before Top 3 점수: {[s for _, s in before_top3]}")
        print(f"  After  Top 3 점수: {[s for _, s in after_top3]}")


if __name__ == "__main__":
    main()
