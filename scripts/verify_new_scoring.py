"""새 점수 계산 방식 검증.

같은 시나리오를 (a) 기존 DISTINCT 방식 vs (b) 새 점유율 방식으로 비교.
DB는 현재 (설화 재분류 적용된) 것만 사용.
"""
from __future__ import annotations

import sqlite3
from pathlib import Path

BASE = Path(__file__).parent.parent
DB = BASE / "storage" / "metadata.db"


def score_old(conn: sqlite3.Connection, course_id: str, cat_scores: dict[str, int]) -> int:
    """기존: DISTINCT 카테고리만 1번씩 카운트."""
    rows = conn.execute("""
        SELECT DISTINCT pfm.final_category
        FROM course_places cp
        JOIN place_folklore_mapping pfm ON pfm.place_name = cp.place_name
        WHERE cp.course_id = ? AND pfm.specificity >= 5
    """, (course_id,)).fetchall()
    return sum(cat_scores.get(r[0], 0) for r in rows)


def score_new(conn: sqlite3.Connection, course_id: str, cat_scores: dict[str, int]) -> float:
    """새: 점유율 × specificity 가중."""
    rows = conn.execute("""
        SELECT pfm.final_category, pfm.specificity
        FROM course_places cp
        JOIN place_folklore_mapping pfm ON pfm.place_name = cp.place_name
        WHERE cp.course_id = ? AND pfm.specificity >= 5
    """, (course_id,)).fetchall()
    if not rows:
        return 0.0
    cat_weighted: dict[str, float] = {}
    total = 0.0
    for cat, spec in rows:
        w = spec / 5.0
        cat_weighted[cat] = cat_weighted.get(cat, 0.0) + w
        total += w
    if total == 0:
        return 0.0
    score = 0.0
    for cat, w in cat_weighted.items():
        score += cat_scores.get(cat, 0) * (w / total)
    return score * 10


def get_category_dist(conn: sqlite3.Connection, course_id: str) -> dict[str, int]:
    rows = conn.execute("""
        SELECT pfm.final_category, COUNT(*)
        FROM course_places cp
        JOIN place_folklore_mapping pfm ON pfm.place_name = cp.place_name
        WHERE cp.course_id = ? AND pfm.specificity >= 5
        GROUP BY pfm.final_category
    """, (course_id,)).fetchall()
    return {r[0]: r[1] for r in rows}


def run_scenario(name: str, region: str, cat_scores: dict[str, int], days: int) -> None:
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row

    duration_min = max(1, days - 1)
    duration_max = days + 1

    candidates = conn.execute("""
        SELECT id, title, duration_days
        FROM curated_courses
        WHERE region IN (?, '전체') AND duration_days BETWEEN ? AND ?
        ORDER BY CASE WHEN region = ? THEN 0 ELSE 1 END, composite_score DESC
        LIMIT 50
    """, (region, duration_min, duration_max, region)).fetchall()

    scored = []
    for c in candidates:
        cid = c["id"]
        scored.append({
            "id": cid,
            "title": c["title"],
            "score_old": score_old(conn, cid, cat_scores),
            "score_new": score_new(conn, cid, cat_scores),
            "dist": get_category_dist(conn, cid),
        })

    # 두 방식별 Top 5
    old_top = sorted(scored, key=lambda x: -x["score_old"])[:5]
    new_top = sorted(scored, key=lambda x: -x["score_new"])[:5]

    # 변별력 분석
    old_unique_scores = len({s["score_old"] for s in scored[:10]})
    new_unique_scores = len({round(s["score_new"], 2) for s in scored[:10]})

    print(f"\n{'#'*100}")
    print(f"# {name}")
    print(f"# 입력 점수: {cat_scores}")
    print(f"{'#'*100}\n")

    print(f"[OLD 방식 — DISTINCT 카테고리 합산]")
    print(f"  Top 10 중 고유 점수 개수: {old_unique_scores}  ← 변별력 지표 (높을수록 좋음)")
    for s in old_top:
        print(f"  {s['score_old']:3d}점  {s['id']:6s}  {s['title'][:35]}")

    print(f"\n[NEW 방식 — 점유율 × specificity 가중]")
    print(f"  Top 10 중 고유 점수 개수: {new_unique_scores}")
    for s in new_top:
        # 사용자 입력 카테고리만 강조
        focus_cats = {c: s["dist"].get(c, 0) for c in cat_scores}
        print(f"  {s['score_new']:5.1f}점  {s['id']:6s}  {s['title'][:30]:30s}  focus={focus_cats}")

    # 새 Top3에 들어왔는데 OLD Top3에 없던 코스
    old_top3 = {s["id"] for s in old_top[:3]}
    new_top3 = {s["id"] for s in new_top[:3]}
    newly_promoted = new_top3 - old_top3
    if newly_promoted:
        print(f"\n  🆕 NEW Top3에 새로 진입: {sorted(newly_promoted)}")
        for cid in newly_promoted:
            s = next(x for x in scored if x["id"] == cid)
            print(f"     {cid}: {s['title']}")
            print(f"        OLD 순위 = {scored.index(s)+1 if False else '동점 다수'}, NEW 점수 = {s['score_new']:.1f}")
            print(f"        매핑 분포: {s['dist']}")

    conn.close()


SCENARIOS = [
    {
        "name": "동부 + 으스스한 이야기(supernatural) + 바다(ocean) + 3일",
        "region": "동부",
        "cat_scores": {
            "초자연 존재담": 4, "생활민담·교훈담": 1, "해양·어촌 전승": 3,
        },
        "days": 3,
    },
    {
        "name": "서부 + 신이 마을에 내려오는 이야기(mythology) + 마을과 당(village) + 2일",
        "region": "서부",
        "cat_scores": {
            "무속신화·신격 전승": 4, "마을 공동체 전승": 3,
        },
        "days": 2,
    },
    {
        "name": "전체 + 재치있고 교훈적인 이야기(folktale) + any + 1일",
        "region": "전체",
        "cat_scores": {
            "생활민담·교훈담": 3, "마을 공동체 전승": 1,
        },
        "days": 1,
    },
]


def main():
    for s in SCENARIOS:
        run_scenario(s["name"], s["region"], s["cat_scores"], s["days"])


if __name__ == "__main__":
    main()
