"""course_day_concepts 테이블 빌드 스크립트.

실행:
    python backend/scripts/build_course_day_concepts.py

동작:
    1. curated_courses × day 단위로 앵커 장소 선별
    2. 앵커 장소들의 설화 카테고리 다수결로 Day 컨셉 결정
    3. course_day_concepts 테이블 저장

앵커 선별 조건:
    - place_folklore_mapping specificity >= 5
    - matched_place가 place_name 안에 부분 포함 시 제외 (지명 포함 상업시설 가짜매핑 제거)
    - EXCLUDE_KEYWORDS(카페/식당/숙박 등) 포함 장소 제외
    - day당 최대 MAX_ANCHORS_PER_DAY 개
"""
from __future__ import annotations

import json
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path

BASE_DIR = Path(__file__).parent.parent.parent
DB_PATH = BASE_DIR / "storage" / "metadata.db"

MIN_SPECIFICITY = 5
MAX_ANCHORS_PER_DAY = 3

EXCLUDE_KEYWORDS = [
    # 카페·음료
    "카페", "커피", "coffee", "브루어리", "로스터리", "티룸",
    # 식당·음식
    "식당", "레스토랑", "맛집", "짜장", "짬뽕", "돈까스", "스시", "포차",
    "이자카야", "분식", "냉면", "갈비", "삼겹살", "해물짜장", "밥집", "음식점",
    "뷔페", "베이커리", "빵", "브런치", "소주공장",
    # 숙박
    "호텔", "펜션", "게스트하우스", "민박", "리조트", "모텔", "하우스",
    "스테이", "숙소",
    # 쇼핑·상업
    "마트", "편의점", "주유소", "면세점", "아울렛",
    # 교통
    "공항", "항구", "터미널", "버스정류장", "주차장",
    # 기타 시설
    "레일바이크", "짚라인",
]


def _is_excluded(place_name: str) -> bool:
    return any(kw in place_name for kw in EXCLUDE_KEYWORDS)


def _is_fake_mapping(place_name: str, matched_place: str) -> bool:
    """matched_place가 place_name에 부분 포함 && 다른 이름 → 가짜매핑."""
    if place_name == matched_place:
        return False
    return matched_place in place_name


def build(conn: sqlite3.Connection) -> None:
    conn.row_factory = sqlite3.Row

    # ── 1. 앵커 후보 매핑 로드 ───────────────────────────────────────────────
    print("설화 매핑 로딩 중...")
    pfm_rows = conn.execute(
        """
        SELECT place_name, matched_place, specificity, final_category
        FROM place_folklore_mapping
        WHERE specificity >= ?
        """,
        (MIN_SPECIFICITY,),
    ).fetchall()

    # place_name → {category: count, best_spec: int}
    place_info: dict[str, dict] = {}
    for r in pfm_rows:
        pn = r["place_name"]
        mp = r["matched_place"] or ""
        if _is_fake_mapping(pn, mp):
            continue
        if pn not in place_info:
            place_info[pn] = {"category_cnt": Counter(), "best_spec": 0}
        place_info[pn]["category_cnt"][r["final_category"]] += 1
        place_info[pn]["best_spec"] = max(place_info[pn]["best_spec"], r["specificity"])

    print(f"  유효 앵커 후보 장소 {len(place_info)}개")

    # ── 2. curated_courses × day 단위 장소 목록 ─────────────────────────────
    print("코스 장소 로딩 중...")
    place_rows = conn.execute(
        """
        SELECT cp.course_id, cp.place_name, cp.day
        FROM course_places cp
        JOIN curated_courses cc ON cp.course_id = cc.id
        WHERE cp.in_jeju = 1 AND cp.lat IS NOT NULL
        ORDER BY cp.course_id, cp.day, cp.seq_no
        """
    ).fetchall()

    # (course_id, day) → [place_name, ...]
    day_places: dict[tuple, list[str]] = defaultdict(list)
    seen: set[tuple] = set()
    for r in place_rows:
        key = (r["course_id"], r["day"], r["place_name"])
        if key in seen:
            continue
        seen.add(key)
        day_places[(r["course_id"], r["day"])].append(r["place_name"])

    print(f"  총 {len(day_places)}개 (course × day)")

    # ── 3. 각 day별 앵커 + 컨셉 결정 ────────────────────────────────────────
    print("앵커 + 컨셉 계산 중...")
    results: list[dict] = []
    stats = Counter()

    for (course_id, day), places in day_places.items():
        # 앵커 후보: 제외 키워드 없고 + 설화 매핑 있는 장소
        candidates = [
            p for p in places
            if not _is_excluded(p) and p in place_info
        ]

        # 점수 순 정렬: best_spec 우선, 설화 수 보조
        candidates.sort(
            key=lambda p: (
                -place_info[p]["best_spec"],
                -sum(place_info[p]["category_cnt"].values()),
            )
        )
        anchors = candidates[:MAX_ANCHORS_PER_DAY]

        # Day 컨셉: 앵커들의 카테고리 다수결
        # 앵커 없으면 day 내 모든 장소(설화 있는 것) 기준으로 fallback
        category_pool = anchors if anchors else candidates
        cat_counter: Counter = Counter()
        for p in category_pool:
            if p in place_info:
                cat_counter += place_info[p]["category_cnt"]

        concept_category = cat_counter.most_common(1)[0][0] if cat_counter else None

        results.append({
            "course_id": course_id,
            "day": day,
            "concept_category": concept_category,
            "anchor_places": json.dumps(anchors, ensure_ascii=False),
        })

        if anchors:
            stats["with_anchor"] += 1
        else:
            stats["no_anchor"] += 1

    print(f"  앵커 있는 day: {stats['with_anchor']} / 앵커 없는 day: {stats['no_anchor']}")

    # ── 4. 테이블 저장 ────────────────────────────────────────────────────────
    conn.execute("DROP TABLE IF EXISTS course_day_concepts")
    conn.execute(
        """
        CREATE TABLE course_day_concepts (
            course_id        TEXT NOT NULL,
            day              INTEGER NOT NULL,
            concept_category TEXT,
            anchor_places    TEXT,   -- JSON array
            PRIMARY KEY (course_id, day)
        )
        """
    )
    conn.executemany(
        """
        INSERT INTO course_day_concepts (course_id, day, concept_category, anchor_places)
        VALUES (:course_id, :day, :concept_category, :anchor_places)
        """,
        results,
    )
    conn.commit()
    print(f"course_day_concepts 저장 완료 ({len(results)}행)")

    # ── 5. 컨셉 카테고리 분포 출력 ───────────────────────────────────────────
    cat_dist = conn.execute(
        """
        SELECT concept_category, COUNT(*) as cnt
        FROM course_day_concepts
        GROUP BY concept_category
        ORDER BY cnt DESC
        """
    ).fetchall()
    print("\n[컨셉 카테고리 분포]")
    for row in cat_dist:
        print(f"  {row['concept_category'] or '없음'}: {row['cnt']}개")

    # ── 6. 샘플 출력 ─────────────────────────────────────────────────────────
    samples = conn.execute(
        """
        SELECT cdc.course_id, cc.title, cdc.day, cdc.concept_category, cdc.anchor_places
        FROM course_day_concepts cdc
        JOIN curated_courses cc ON cdc.course_id = cc.id
        WHERE cdc.anchor_places != '[]'
        ORDER BY RANDOM()
        LIMIT 5
        """
    ).fetchall()
    print("\n[샘플]")
    for row in samples:
        anchors = json.loads(row["anchor_places"])
        print(f"  [{row['title']} / Day {row['day']}] {row['concept_category']}")
        for a in anchors:
            print(f"    - {a}")


if __name__ == "__main__":
    print(f"DB: {DB_PATH}")
    if not DB_PATH.exists():
        print("ERROR: DB 파일을 찾을 수 없습니다.", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        build(conn)
    finally:
        conn.close()
    print("\n완료!")
