"""curated_courses 테이블 빌드 스크립트.

실행:
    python backend/scripts/build_curated_courses.py

동작:
    1. courses + place_folklore_mapping 기반으로 텍스트 매핑 비율 계산
    2. 텍스트 매핑 >= TEXT_MAPPING_THRESHOLD % 코스만 필터
    3. 지역 분류 (다수결 방식, 공항 제외)
    4. composite_score 계산 (텍스트 커버리지 + 특이성 + 경로 압축도)
    5. MMR 기반 중복 제거
    6. region × duration_days 조합별 상위 TOP_PER_BUCKET 개 선별
    7. curated_courses 테이블에 저장
"""
from __future__ import annotations

import math
import sqlite3
import sys
from pathlib import Path

# ─── 설정 ──────────────────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).parent.parent.parent
DB_PATH = BASE_DIR / "storage" / "metadata.db"

TEXT_MAPPING_THRESHOLD = 50   # 텍스트 매핑 비율 최소값 (%)
TOP_PER_BUCKET = 30           # region × duration 조합당 최대 코스 수
MMR_SIMILARITY_THRESHOLD = 0.7  # 이 이상 유사한 코스는 중복 제거

TRANSIT_KEYWORDS = ["공항", "항구", "터미널", "버스"]

# 지역 좌표 경계
EAST_LNG = 126.70    # 동부: lng >= EAST_LNG
WEST_LNG = 126.40    # 서부: lng <= WEST_LNG
SOUTH_LAT = 33.38    # 남부: lat < SOUTH_LAT AND lng BETWEEN WEST_LNG AND EAST_LNG
# 북부: lat >= SOUTH_LAT AND lng BETWEEN WEST_LNG AND EAST_LNG


# ─── 유틸 ──────────────────────────────────────────────────────────────────────

def _is_transit(place_name: str) -> bool:
    return any(kw in place_name for kw in TRANSIT_KEYWORDS)


def _classify_place_region(lat: float, lng: float) -> str:
    if lng >= EAST_LNG:
        return "동부"
    if lng <= WEST_LNG:
        return "서부"
    if lat < SOUTH_LAT:
        return "남부"
    return "북부"


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6_371_000
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _route_spread_km(lats: list[float], lngs: list[float]) -> float:
    """바운딩 박스 대각선 거리 (km). 경로가 얼마나 퍼져 있는지."""
    if len(lats) < 2:
        return 0.0
    return _haversine_m(min(lats), min(lngs), max(lats), max(lngs)) / 1000


def _jaccard(set_a: set[str], set_b: set[str]) -> float:
    if not set_a and not set_b:
        return 1.0
    inter = len(set_a & set_b)
    union = len(set_a | set_b)
    return inter / union if union else 0.0


# ─── 메인 로직 ─────────────────────────────────────────────────────────────────

def build(conn: sqlite3.Connection) -> None:
    conn.row_factory = sqlite3.Row

    # ── 1. 모든 코스 기본 정보 로드 ─────────────────────────────────────────
    print("코스 목록 로딩 중...")
    course_rows = conn.execute(
        "SELECT id, title, duration_days FROM courses"
    ).fetchall()
    course_map = {r["id"]: dict(r) for r in course_rows}
    print(f"  총 {len(course_map)}개 코스")

    # ── 2. 모든 코스 장소 로드 ──────────────────────────────────────────────
    print("코스 장소 로딩 중...")
    place_rows = conn.execute(
        """
        SELECT course_id, place_name, lat, lng, day
        FROM course_places
        WHERE in_jeju = 1 AND lat IS NOT NULL AND lng IS NOT NULL
        ORDER BY course_id, day, seq_no
        """
    ).fetchall()

    places_by_course: dict[str, list[dict]] = {}
    seen: set[tuple] = set()
    for p in place_rows:
        cid = p["course_id"]
        key = (cid, p["place_name"], p["day"])
        if key in seen:
            continue
        seen.add(key)
        places_by_course.setdefault(cid, []).append({
            "place_name": p["place_name"],
            "lat": p["lat"],
            "lng": p["lng"],
            "day": p["day"],
        })
    print(f"  {len(places_by_course)}개 코스에 장소 로드 완료")

    # ── 3. place_folklore_mapping으로 텍스트 매핑 비율 + 특이성 계산 ────────
    print("설화 매핑 정보 로딩 중...")
    pfm_rows = conn.execute(
        """
        SELECT DISTINCT place_name, AVG(specificity) as avg_spec
        FROM place_folklore_mapping
        WHERE specificity >= 5
        GROUP BY place_name
        """
    ).fetchall()
    text_mapped_spec: dict[str, float] = {
        r["place_name"]: r["avg_spec"] for r in pfm_rows
    }
    print(f"  텍스트 매핑된 장소 {len(text_mapped_spec)}개")

    # ── 4. 코스별 점수 계산 ──────────────────────────────────────────────────
    print("코스 점수 계산 중...")
    scored_courses: list[dict] = []

    for cid, course in course_map.items():
        places = places_by_course.get(cid, [])
        if not places:
            continue

        non_transit = [p for p in places if not _is_transit(p["place_name"])]
        if not non_transit:
            non_transit = places

        total = len(non_transit)
        text_mapped = [p for p in non_transit if p["place_name"] in text_mapped_spec]
        text_pct = round(100 * len(text_mapped) / total)

        if text_pct < TEXT_MAPPING_THRESHOLD:
            continue

        # 평균 specificity (텍스트 매핑된 장소만, 0~10 → 0~1 정규화)
        avg_spec = (
            sum(text_mapped_spec[p["place_name"]] for p in text_mapped) / len(text_mapped)
            if text_mapped else 0.0
        )
        spec_score = avg_spec / 10.0

        # 경로 압축도 (짧을수록 같은 지역 집중 코스 → 1.0, 제주 전체 span ~80km)
        lats = [p["lat"] for p in non_transit]
        lngs = [p["lng"] for p in non_transit]
        spread_km = _route_spread_km(lats, lngs)
        compactness = max(0.0, 1.0 - spread_km / 80.0)

        # composite_score: 텍스트 커버리지(50%) + 특이성(30%) + 압축도(20%)
        composite = (
            0.50 * text_pct / 100.0
            + 0.30 * spec_score
            + 0.20 * compactness
        )

        # 지역 분류: 다수결 (이동 장소 제외)
        region_votes: dict[str, int] = {}
        for p in non_transit:
            r = _classify_place_region(p["lat"], p["lng"])
            region_votes[r] = region_votes.get(r, 0) + 1

        top_region, top_count = max(region_votes.items(), key=lambda x: x[1])
        region = top_region if top_count / total >= 0.5 else "전체"

        scored_courses.append({
            "id": cid,
            "title": course["title"],
            "duration_days": course["duration_days"],
            "region": region,
            "text_mapping_pct": text_pct,
            "composite_score": composite,
            "place_count": len(places),
            "place_names_set": {p["place_name"] for p in non_transit},
        })

    print(f"  필터 통과: {len(scored_courses)}개 코스")

    # ── 5. region × duration 버킷별 MMR 기반 중복 제거 후 상위 선별 ─────────
    print("버킷별 선별 중...")
    from collections import defaultdict
    buckets: dict[tuple, list[dict]] = defaultdict(list)
    for c in scored_courses:
        key = (c["region"], min(c["duration_days"], 7))  # 7일 초과는 7로 묶음
        buckets[key].append(c)

    final_courses: list[dict] = []
    for (region, dur), candidates in buckets.items():
        candidates.sort(key=lambda x: -x["composite_score"])
        selected: list[dict] = []
        for cand in candidates:
            if len(selected) >= TOP_PER_BUCKET:
                break
            too_similar = any(
                _jaccard(cand["place_names_set"], s["place_names_set"]) >= MMR_SIMILARITY_THRESHOLD
                for s in selected
            )
            if not too_similar:
                selected.append(cand)
        final_courses.extend(selected)

    print(f"  최종 선별: {len(final_courses)}개 코스")

    # ── 6. curated_courses 테이블 저장 ──────────────────────────────────────
    conn.execute("DROP TABLE IF EXISTS curated_courses")
    conn.execute(
        """
        CREATE TABLE curated_courses (
            id                TEXT PRIMARY KEY,
            title             TEXT,
            duration_days     INTEGER,
            region            TEXT,
            text_mapping_pct  INTEGER,
            composite_score   REAL,
            place_count       INTEGER
        )
        """
    )
    conn.executemany(
        """
        INSERT INTO curated_courses
            (id, title, duration_days, region, text_mapping_pct, composite_score, place_count)
        VALUES
            (:id, :title, :duration_days, :region, :text_mapping_pct, :composite_score, :place_count)
        """,
        final_courses,
    )
    conn.commit()
    print("curated_courses 테이블 저장 완료")

    # ── 7. 통계 출력 ────────────────────────────────────────────────────────
    stats = conn.execute(
        """
        SELECT region, duration_days, COUNT(*) as cnt
        FROM curated_courses
        GROUP BY region, duration_days
        ORDER BY region, duration_days
        """
    ).fetchall()
    print("\n[지역 × 기간 분포]")
    for row in stats:
        print(f"  {row['region']} {row['duration_days']}일: {row['cnt']}개")


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
