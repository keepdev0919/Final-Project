"""curated_courses 테이블 빌드 — 설화 없는 코스 품질 기준 (2026-08-13 재작성).

실행:
    .venv/bin/python backend/scripts/build_curated_courses.py

## 왜 다시 썼나

이전 버전은 코스를 **설화 밀도**로 골랐다 — "모든 day에 설화 매핑된 장소가 최소 1개"로
필터하고, 점수를 `설화 텍스트 커버리지 50% + 설화 특이성 30% + 경로 압축도 20%`로
계산했다.

방향 재정립(2026-07-20)으로 설화는 '재료 후보 하나'로 강등됐고, 2026-08-13에
**코스 추천에서 설화를 완전히 분리**하기로 결정했다. 이유:

- 코스는 "어디를 갈지", 설화는 "그 장소의 이야기"다. 추천 기준으로 쓸 근거가 없다
- 장소에 강하게 얽힌 설화가 실제로 거의 없다 (설화-장소 매핑 작업에서 확인)
- 설화는 **로컬 파일 데이터**라 공모전 데이터 활용 점수에 기여하지 않는다
  (공지 FAQ: "OpenAPI 형태만 인정, 파일데이터 활용은 인정되지 않음")

## 새 점수 기준

| 기준 | 무엇을 재나 | 비중 |
|---|---|---|
| 경로 효율 | 이동 거리 대비 장소 수. 하루에 섬을 왕복하는 코스를 걸러낸다 | 40% |
| 하루 장소 수 적정성 | 하루 3~4곳이 최적. 1곳은 허전하고 7곳은 빡빡하다 | 35% |
| 관광지 비율 | is_attraction 비율. 숙소·맛집만인 코스를 걸러낸다 | 25% |

**"장소 다양성"은 채택하지 않았다.** `visitjeju_places_final.json`의 `category`가
3,284개 중 1,424개(43%)가 `unclear`여서, 다양성 점수가 "정보가 많은 장소를 포함한
코스"에 유리하게 편향된다. 대신 이진값이라 편향이 없는 `is_attraction`을 썼다.

## 원본 데이터의 함정 (필터 근거)

비짓제주 코스는 **실제 사용자가 만든 개인 여행 계획**이라 그대로 쓸 수 없는 것이 섞여 있다.
실측:

- **같은 장소를 여러 번 추가한 코스 1,556개** — 예: "우도피아"만 7번. 좌표가 동일해
  이동 거리 0km가 되고, 장소 수도 부풀려져 **세 점수 기준을 모두 속인다.**
  실제로 첫 빌드에서 이 코스가 만점(1.000)으로 1위였다.
- **일부 day가 비어 있는 코스 761개** — 2일 코스인데 day1에 장소가 없는 식.

그래서 고유 장소로 중복을 제거하고, 모든 day에 장소가 있는 코스만 남긴다.

## 제목 생성

원본 `courses.title`은 비짓제주 사용자가 쓴 개인 메모다 — "^^", "z",
"엄마 환갑기념", "김승열어르신생일기념제주도여행". 그대로 노출할 수 없으므로
`{지역} {일수}일 · {대표장소} 외 N곳` 형태로 생성한다. 원본은 `origin_title`에 보존.
"""
from __future__ import annotations

import json
import math
import sqlite3
import sys
from collections import Counter
from pathlib import Path

# ─── 설정 ──────────────────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).parent.parent.parent
DB_PATH = BASE_DIR / "storage" / "metadata.db"
PLACES_JSON = BASE_DIR / "data" / "processed" / "visitjeju_places_final.json"

TOP_PER_BUCKET = 50       # region × duration 조합당 최대 코스 수
MAX_DURATION = 7          # 7일 초과는 7일 버킷으로 묶음
MIN_PLACES_PER_DAY = 2    # 하루 평균 2곳 미만은 코스로 부적합
MIN_ATTRACTION_RATIO = 0.15  # 관광지가 15% 미만이면 여행 코스로 부적합
MIN_UNIQUE_KM_PER_DAY = 1.0  # 고유 장소가 2곳 이상인데 이동이 이보다 적으면 좌표 중복 의심

# 점수 비중
W_ROUTE = 0.40            # 경로 효율
W_DENSITY = 0.35          # 하루 장소 수 적정성
W_ATTRACTION = 0.25       # 관광지 비율

IDEAL_PLACES_PER_DAY = 3.5   # 하루 장소 수의 최적점
DENSITY_TOLERANCE = 2.5      # 최적점에서 이만큼 벗어나면 점수 0

# 경로 효율: 하루 이동 거리가 이 값 이하면 만점, 이상이면 0점
ROUTE_BEST_KM = 20.0
ROUTE_WORST_KM = 90.0

# 교통 시설은 지역 판정·경로 계산에서 제외 (공항이 코스 지역을 왜곡한다)
TRANSIT_KEYWORDS = ["공항", "항구", "터미널", "버스정류장"]

MMR_LAMBDA = 0.7          # 관련성 vs 다양성 (높으면 점수 우선)
MMR_SIM_THRESHOLD = 0.6   # 장소 겹침 비율이 이 이상이면 중복으로 간주


# ─── 유틸 ──────────────────────────────────────────────────────────────────────
def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _classify_place_region(lat: float, lng: float) -> str:
    """제주를 4개 권역으로 나눈다. 제주시 기준 남북, 애월~성산 기준 동서."""
    if lng < 126.40:
        return "서부"
    if lng > 126.75:
        return "동부"
    return "북부" if lat > 33.40 else "남부"


def _is_transit(name: str) -> bool:
    return any(k in name for k in TRANSIT_KEYWORDS)


def _clamp01(x: float) -> float:
    return max(0.0, min(1.0, x))


def _dedupe_places(places: list[dict]) -> list[dict]:
    """같은 장소의 중복 방문을 제거한다 (day별로 최초 1회만 남긴다).

    비짓제주 사용자가 같은 장소를 여러 번 추가한 코스가 1,556개 있다. 중복을 그대로
    두면 이동 거리가 0에 가까워지고 장소 수가 부풀려져 점수를 속인다.
    day를 넘나드는 재방문은 정상일 수 있으므로 (day, place_name)을 키로 쓴다.
    """
    seen: set[tuple[int, str]] = set()
    out: list[dict] = []
    for p in sorted(places, key=lambda x: (x["day"], x["seq_no"])):
        key = (p["day"], p["place_name"])
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


# ─── 점수 ──────────────────────────────────────────────────────────────────────
def _route_score(places: list[dict], duration_days: int) -> tuple[float, float]:
    """경로 효율. (점수, 하루평균이동km)를 반환한다.

    day별로 방문 순서대로 이동 거리를 더한 뒤 일수로 나눈다. 하루에 섬 반대편을
    왕복하는 코스는 이동만 하다 끝나므로 낮은 점수를 준다.
    """
    by_day: dict[int, list[dict]] = {}
    for p in places:
        if _is_transit(p["place_name"]):
            continue
        by_day.setdefault(p["day"], []).append(p)

    total_km = 0.0
    for day_places in by_day.values():
        day_places.sort(key=lambda x: x["seq_no"])
        for a, b in zip(day_places, day_places[1:]):
            total_km += _haversine_km(a["lat"], a["lng"], b["lat"], b["lng"])

    per_day = total_km / max(duration_days, 1)
    # ROUTE_BEST_KM 이하 = 1.0, ROUTE_WORST_KM 이상 = 0.0
    score = 1.0 - (per_day - ROUTE_BEST_KM) / (ROUTE_WORST_KM - ROUTE_BEST_KM)
    return _clamp01(score), per_day


def _density_score(place_count: int, duration_days: int) -> tuple[float, float]:
    """하루 장소 수 적정성. (점수, 하루평균장소수)를 반환한다.

    IDEAL_PLACES_PER_DAY에서 멀어질수록 선형으로 감점한다. 하루 1곳은 허전하고
    7곳은 이동에 쫓긴다.
    """
    per_day = place_count / max(duration_days, 1)
    score = 1.0 - abs(per_day - IDEAL_PLACES_PER_DAY) / DENSITY_TOLERANCE
    return _clamp01(score), per_day


def _attraction_ratio(places: list[dict], place_meta: dict) -> float:
    """관광지 비율. 숙소·맛집·카페만으로 구성된 코스를 걸러낸다."""
    non_transit = [p for p in places if not _is_transit(p["place_name"])]
    if not non_transit:
        return 0.0
    n = sum(1 for p in non_transit if place_meta.get(p["place_name"], {}).get("is_attraction"))
    return n / len(non_transit)


def _make_title(region: str, duration_days: int, places: list[dict], place_meta: dict) -> str:
    """원본 제목이 개인 메모라 쓸 수 없으므로 생성한다."""
    non_transit = [p for p in places if not _is_transit(p["place_name"])]
    if not non_transit:
        return f"{region} {duration_days}일 코스"

    # 대표 장소: 관광지 우선, 없으면 첫 방문지
    attractions = [p for p in non_transit
                   if place_meta.get(p["place_name"], {}).get("is_attraction")]
    lead = (attractions or non_transit)[0]["place_name"]

    rest = len(non_transit) - 1
    if rest <= 0:
        return f"{region} {duration_days}일 · {lead}"
    return f"{region} {duration_days}일 · {lead} 외 {rest}곳"


# ─── 메인 ──────────────────────────────────────────────────────────────────────
def main() -> None:
    if not DB_PATH.exists():
        sys.exit(f"❌ DB 없음: {DB_PATH}")
    if not PLACES_JSON.exists():
        sys.exit(f"❌ 장소 메타 없음: {PLACES_JSON}")

    place_meta = {p["place_name"]: p for p in json.loads(PLACES_JSON.read_text(encoding="utf-8"))}
    print(f"장소 메타 {len(place_meta)}개 로드")

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    courses = conn.execute(
        "SELECT id, title, duration_days, place_count FROM courses"
    ).fetchall()
    print(f"원본 코스 {len(courses)}개")

    rows = conn.execute(
        "SELECT course_id, seq_no, place_name, day, lat, lng FROM course_places "
        "WHERE lat IS NOT NULL AND lng IS NOT NULL AND in_jeju = 1"
    ).fetchall()
    places_by_course: dict[str, list[dict]] = {}
    for r in rows:
        places_by_course.setdefault(str(r["course_id"]), []).append(dict(r))
    print(f"지오코딩된 장소 {len(rows)}개")

    # ── 후보 평가 ──────────────────────────────────────────────────────────────
    candidates: list[dict] = []
    skipped = Counter()

    for course in courses:
        cid = str(course["id"])
        places = places_by_course.get(cid, [])
        duration = course["duration_days"] or 1

        if not places:
            skipped["장소 없음"] += 1
            continue
        if duration > 30:
            skipped["기간 비정상"] += 1
            continue

        places = _dedupe_places(places)
        non_transit = [p for p in places if not _is_transit(p["place_name"])]

        # 모든 day에 장소가 있어야 한다 (day가 빈 코스 761개 존재)
        days_used = {p["day"] for p in non_transit}
        if len(days_used) < duration:
            skipped["빈 day 있음"] += 1
            continue

        if len(non_transit) / duration < MIN_PLACES_PER_DAY:
            skipped["하루 장소 부족"] += 1
            continue

        # 고유 장소가 여럿인데 이동이 사실상 0이면 좌표가 같은 것 — 지오코딩 실패 의심
        unique_names = {p["place_name"] for p in non_transit}
        if len(unique_names) >= 2:
            _, probe_km = _route_score(places, duration)
            if probe_km < MIN_UNIQUE_KM_PER_DAY:
                skipped["좌표 중복 의심"] += 1
                continue

        attraction = _attraction_ratio(places, place_meta)
        if attraction < MIN_ATTRACTION_RATIO:
            skipped["관광지 없음"] += 1
            continue

        # 지역: 교통 시설 제외 다수결. 과반이 아니면 "전체"
        votes = Counter(_classify_place_region(p["lat"], p["lng"]) for p in non_transit)
        top_region, top_n = votes.most_common(1)[0]
        region = top_region if top_n / len(non_transit) >= 0.5 else "전체"

        route, km_per_day = _route_score(places, duration)
        density, places_per_day = _density_score(len(non_transit), duration)

        composite = W_ROUTE * route + W_DENSITY * density + W_ATTRACTION * attraction

        candidates.append({
            "id": cid,
            "title": _make_title(region, duration, places, place_meta),
            "origin_title": course["title"],
            "duration_days": duration,
            "region": region,
            "place_count": len(non_transit),
            "attraction_ratio": round(attraction, 3),
            "km_per_day": round(km_per_day, 1),
            "places_per_day": round(places_per_day, 2),
            "route_score": round(route, 3),
            "density_score": round(density, 3),
            "composite_score": round(composite, 4),
            "place_names": {p["place_name"] for p in non_transit},
        })

    print(f"\n후보 {len(candidates)}개 (제외 {sum(skipped.values())}개)")
    for reason, n in skipped.most_common():
        print(f"  - {reason}: {n}")

    # ── 버킷별 MMR 선별 ────────────────────────────────────────────────────────
    buckets: dict[tuple[str, int], list[dict]] = {}
    for c in candidates:
        buckets.setdefault((c["region"], min(c["duration_days"], MAX_DURATION)), []).append(c)

    selected: list[dict] = []
    for (region, dur), items in buckets.items():
        items.sort(key=lambda x: -x["composite_score"])
        picked: list[dict] = []
        for cand in items:
            if len(picked) >= TOP_PER_BUCKET:
                break
            # 이미 뽑힌 코스와 장소가 많이 겹치면 건너뛴다
            too_similar = False
            for p in picked:
                inter = len(cand["place_names"] & p["place_names"])
                union = len(cand["place_names"] | p["place_names"]) or 1
                if inter / union >= MMR_SIM_THRESHOLD:
                    too_similar = True
                    break
            if not too_similar:
                picked.append(cand)
        selected.extend(picked)

    print(f"선별 {len(selected)}개")

    # ── 저장 ───────────────────────────────────────────────────────────────────
    conn.execute("DROP TABLE IF EXISTS curated_courses")
    conn.execute("""
        CREATE TABLE curated_courses (
            id                TEXT PRIMARY KEY,
            title             TEXT,
            origin_title      TEXT,
            duration_days     INTEGER,
            region            TEXT,
            place_count       INTEGER,
            attraction_ratio  REAL,
            km_per_day        REAL,
            places_per_day    REAL,
            route_score       REAL,
            density_score     REAL,
            composite_score   REAL
        )
    """)
    conn.executemany(
        """INSERT INTO curated_courses
           (id, title, origin_title, duration_days, region, place_count,
            attraction_ratio, km_per_day, places_per_day,
            route_score, density_score, composite_score)
           VALUES (:id, :title, :origin_title, :duration_days, :region, :place_count,
                   :attraction_ratio, :km_per_day, :places_per_day,
                   :route_score, :density_score, :composite_score)""",
        [{k: v for k, v in s.items() if k != "place_names"} for s in selected],
    )
    conn.execute("CREATE INDEX idx_curated_region_dur ON curated_courses(region, duration_days)")
    conn.commit()

    print("\n=== 지역 × 일수 분포 ===")
    for row in conn.execute(
        "SELECT region, duration_days, COUNT(*) cnt, ROUND(AVG(composite_score),3) avg_s "
        "FROM curated_courses GROUP BY region, duration_days ORDER BY region, duration_days"
    ):
        print(f"  {row['region']:4} {row['duration_days']}일: {row['cnt']:>3}개 (평균 {row['avg_s']})")

    print("\n=== 상위 5개 ===")
    for row in conn.execute(
        "SELECT title, composite_score, km_per_day, places_per_day, attraction_ratio "
        "FROM curated_courses ORDER BY composite_score DESC LIMIT 5"
    ):
        print(f"  {row['composite_score']:.3f} | {row['title']}")
        print(f"          이동 {row['km_per_day']}km/일 · {row['places_per_day']}곳/일 · 관광지 {row['attraction_ratio']:.0%}")

    conn.close()
    print("\n✅ curated_courses 빌드 완료")


if __name__ == "__main__":
    main()
