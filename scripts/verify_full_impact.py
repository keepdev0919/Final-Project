"""전체 변경(설화 재분류 + 매핑 재빌드 + 점수 계산 개선) 효과 종합 검증.

원본(아무 변경 없음) vs 현재(전 작업 적용) 추천 결과 비교.
"""
from __future__ import annotations

import sqlite3
from pathlib import Path

BASE = Path(__file__).parent.parent
DB_ORIGINAL = BASE / "storage" / "metadata.db.bak_before_folktale_recategorize"  # 처음 상태
DB_FINAL = BASE / "storage" / "metadata.db"


def score_old(conn, course_id, cat_scores):
    """원래 알고리즘: DISTINCT 카테고리 합산."""
    rows = conn.execute("""
        SELECT DISTINCT pfm.final_category
        FROM course_places cp
        JOIN place_folklore_mapping pfm ON pfm.place_name = cp.place_name
        WHERE cp.course_id = ? AND pfm.specificity >= 5
    """, (course_id,)).fetchall()
    return sum(cat_scores.get(r[0], 0) for r in rows)


def score_new(conn, course_id, cat_scores):
    """새 알고리즘: 점유율 × specificity 가중."""
    rows = conn.execute("""
        SELECT pfm.final_category, pfm.specificity
        FROM course_places cp
        JOIN place_folklore_mapping pfm ON pfm.place_name = cp.place_name
        WHERE cp.course_id = ? AND pfm.specificity >= 5
    """, (course_id,)).fetchall()
    if not rows:
        return 0.0
    cat_w = {}
    total = 0.0
    for cat, spec in rows:
        w = spec / 5.0
        cat_w[cat] = cat_w.get(cat, 0.0) + w
        total += w
    if total == 0:
        return 0.0
    return sum(cat_scores.get(c, 0) * (w / total) for c, w in cat_w.items()) * 10


def get_dist(conn, course_id):
    rows = conn.execute("""
        SELECT pfm.final_category, COUNT(*)
        FROM course_places cp
        JOIN place_folklore_mapping pfm ON pfm.place_name = cp.place_name
        WHERE cp.course_id = ? AND pfm.specificity >= 5
        GROUP BY pfm.final_category
    """, (course_id,)).fetchall()
    return {r[0]: r[1] for r in rows}


def run(db_path, scoring_fn, region, cat_scores, days, top_n=5):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    dmin, dmax = max(1, days - 1), days + 1

    rows = conn.execute("""
        SELECT id, title FROM curated_courses
        WHERE region IN (?, '전체') AND duration_days BETWEEN ? AND ?
        ORDER BY CASE WHEN region = ? THEN 0 ELSE 1 END, composite_score DESC
        LIMIT 50
    """, (region, dmin, dmax, region)).fetchall()

    scored = []
    for r in rows:
        s = scoring_fn(conn, r["id"], cat_scores)
        scored.append({"id": r["id"], "title": r["title"], "score": s,
                       "dist": get_dist(conn, r["id"])})
    scored.sort(key=lambda x: -x["score"])
    conn.close()
    return scored[:top_n]


SCENARIOS = [
    {
        "name": "동부 + 으스스한 이야기(supernatural) + 바다(ocean) + 3일",
        "region": "동부",
        "cat_scores": {"초자연 존재담": 4, "생활민담·교훈담": 1, "해양·어촌 전승": 3},
        "days": 3,
    },
    {
        "name": "서부 + 신이 마을에 내려오는 이야기(mythology) + 마을과 당(village) + 2일",
        "region": "서부",
        "cat_scores": {"무속신화·신격 전승": 4, "마을 공동체 전승": 3},
        "days": 2,
    },
]


for sc in SCENARIOS:
    print(f"\n{'='*100}")
    print(f"  📍 {sc['name']}")
    print(f"  입력: {sc['cat_scores']}")
    print(f"{'='*100}")

    print(f"\n[BEFORE 모든 작업 — 원본 DB + OLD 알고리즘]")
    before = run(DB_ORIGINAL, score_old, sc["region"], sc["cat_scores"], sc["days"])
    unique_b = len({s["score"] for s in before})
    print(f"  Top5 변별력: {unique_b}/5 고유 점수")
    for s in before:
        print(f"  {s['score']:5d}점  {s['id']:6s}  {s['title'][:35]}")
        print(f"            {s['dist']}")

    print(f"\n[AFTER 모든 작업 — 정리된 DB + NEW 알고리즘]")
    after = run(DB_FINAL, score_new, sc["region"], sc["cat_scores"], sc["days"])
    unique_a = len({round(s["score"], 1) for s in after})
    print(f"  Top5 변별력: {unique_a}/5 고유 점수")
    for s in after:
        focus = {c: s["dist"].get(c, 0) for c in sc["cat_scores"]}
        print(f"  {s['score']:5.1f}점  {s['id']:6s}  {s['title'][:30]:30s}  focus={focus}")

    # 변화
    before_ids = {s["id"] for s in before[:3]}
    after_ids = {s["id"] for s in after[:3]}
    new = after_ids - before_ids
    gone = before_ids - after_ids
    print(f"\n  Top3 변화: 🆕 {sorted(new) if new else '없음'} / ❌ 빠짐 {sorted(gone) if gone else '없음'}")
