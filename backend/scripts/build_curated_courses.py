"""curated_courses 테이블 빌드 — 「못 쓸 데이터만 걷어낸다」 (2026-09-10 재작성).

실행:
    .venv/bin/python backend/scripts/build_curated_courses.py

## 왜 점수제를 없앴나

원본은 비짓제주에 올라온 **실제 사용자의 여행 일정**이다. 우리가 코스를 설계하는 게
아니라 남이 짠 일정을 고르는 것이므로, 걸러야 할 것은 「우리 기준에 안 맞는 코스」가
아니라 **「일정이 아닌 데이터」**다.

이전 버전은 경로 효율·하루 장소 수·관광지 비율을 가중합한 `composite_score`로
6,697개를 1,255개로 줄였다. 그런데 잘려나간 것을 실제로 열어보니 이랬다:

    3일 12곳 · 59km/일 · 관광지 33%   (점수 0.4)
    day1: 공항 → 관음사 → 사려니숲길 → 쌍둥이횟집 → 휴애리 → 오션스위츠 호텔
    day2: 호텔 → 비자림 → 섭지코지 → 산방산 → 카멜리아힐

멀쩡한 제주 3박4일이다. 점수가 낮은 이유는 이동이 길고 관광지 비율이 낮아서인데,
그건 **숙소와 식당이 낀 보통 여행이면 당연히 그렇다.** 이런 일정이 1,793개
잘려나가고 있었다. 점수제가 걸러낸 것은 못 쓸 데이터가 아니라 정상 여행이었다.

그래서 점수를 없애고 **하드필터를 통과한 전부를 저장한 뒤, 조회할 때 무작위로
뽑는다.** 목록이 1,255개에서 6천여 개로 늘어 매번 다른 코스를 보여줄 수 있다.

## 하드필터 — 「이건 일정이 아니다」

| 조건 | 왜 |
|---|---|
| 장소 없음 / 기간 30일 초과 | 데이터 파손 |
| 장소 3곳 미만 | 코스라기엔 빈약하다 |
| **8일 이상** | 여행이 아니라 한 달 살기다. 28일·21일짜리도 있다 |
| 일부 day가 비어 있음 | 2일 코스인데 day1에 장소가 없는 식. 761개 |
| 하루 평균 2곳 미만 | 계획하다 만 일정 |
| 고유 장소 2곳 이상인데 이동 1km 미만 | 지오코딩 실패로 좌표가 겹친 것 |
| 관광지 비율 15% 미만 | 여행 일정으로 보기 어렵다 |
| **하루 이동 150km 초과** | 아래 참조 |
| **폐업한 곳이 낀 코스** | 화면 표시 이름이 「(폐업)」을 떼어내 문 닫은 가게가 멀쩡해 보인다. 비짓제주가 폐업 표기를 단 20곳 기준 |

### 이동거리 상한이 찜 목록을 잡는다

원본에는 가고 싶은 곳을 모아둔 **찜 목록**이 섞여 있다:

    1일 17곳 · 612km/일
    성산일출봉 → 협재 → 섭지코지 → 카멜리아힐 → 월정리 → 오설록 → 동문시장 → 비자림 → 용두암 …

제주 일주도로가 약 200km인데 하루 612km면 세 바퀴다. 순서도 무의미하다.
반면 하루 90~120km는 `쇠소깍 → 약천사 → 휴애리 → 산방산 → 천지연폭포`처럼
멀쩡하다. 실측으로 정상 일정의 상한은 130km대였고 찜 목록은 178km부터 나왔다.
그 사이인 150km를 경계로 잡았다 — **하루에 제주를 거의 한 바퀴 도는 일정**이다.

밀도(하루 장소 수)로는 막지 않는다. 하루 5~8곳은 식당·숙소가 섞여 숫자가 커진
정상 일정이고, 찜 목록은 이동거리로 저절로 걸린다.

## 원본 데이터의 함정

- **같은 장소를 여러 번 추가한 코스 1,556개** — 예: "우도피아"만 7번. 좌표가 동일해
  이동 거리가 0이 되어 이동거리 상한을 통과해 버린다. 그래서 먼저 중복을 제거한다.
- **일부 day가 비어 있는 코스 761개** — 2일 코스인데 day1에 장소가 없는 식.

## 제목 생성 — 원본 제목은 쓰지 않는다 (2026-09-10 조익준님 결정)

원본 `courses.title`은 비짓제주 사용자가 자기 일정에 붙인 이름이다. 보존은 하되
(`origin_title`) 화면에는 쓰지 않고 `{지역} {일수}일 · {대표장소} 외 N곳`을 만든다.

이유 두 가지다.

**1. 남의 개인정보가 섞여 있다.** 6,071개 중 477개(8%)에 사람이 드러난다:

    11월 (with유은) · 자윤이와 함께 · 김승열어르신생일기념제주도여행

비짓제주에 자기 일정을 저장한 사람들이지 우리 앱에 공개되는 데 동의한 사람들이
아니다. 걸러내는 규칙을 짤 수는 있지만 규칙이 새는 순간 남의 실명이 앱에 뜬다.

**2. 대부분 코스 내용을 알려주지 않는다.** 가장 흔한 제목이 「가족여행」 230회,
「2박3일」 97회, 「제주여행」 74회, 「여행」 53회다. 생성한 제목은 최소한
권역·일수·대표 장소를 알려준다.

제목이 겹치는 것(「북부 4일 · 산굼부리 외 10곳」이 70개)은 감수한다. 저장은
제목이 아니라 코스 id로 신원을 잡으므로(`SavedCourse.identityKey`) 사용자가
담아둔 코스가 섞이지 않는다. 한 화면에 같은 제목이 두 번 뜨는 것만
`course_list_agent._dedupe_by_title`이 막는다.
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
DISPLAY_NAMES_JSON = BASE_DIR / "data" / "course_place_display_names.json"

MIN_PLACES = 3            # 장소 2곳짜리는 코스라기엔 빈약하다 (전부 당일치기다)
MIN_PLACES_PER_DAY = 2    # 하루 평균 2곳 미만은 계획하다 만 일정
MAX_DURATION = 7          # 보통 여행의 상한. 그 위는 한 달 살기라 성격이 다르다
MIN_ATTRACTION_RATIO = 0.15  # 관광지가 15% 미만이면 여행 일정으로 보기 어렵다
MIN_UNIQUE_KM_PER_DAY = 1.0  # 고유 장소가 2곳 이상인데 이동이 이보다 적으면 좌표 중복 의심
MAX_KM_PER_DAY = 150.0    # 하루에 제주를 거의 한 바퀴. 이 이상은 찜 목록이다

# 교통 시설은 지역 판정·경로 계산에서 제외 (공항이 코스 지역을 왜곡한다)
TRANSIT_KEYWORDS = ["공항", "항구", "터미널", "버스정류장"]


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
def _km_per_day(places: list[dict], duration_days: int) -> float:
    """하루 평균 이동 거리(km). day별로 방문 순서대로 더한 뒤 일수로 나눈다.

    **찜 목록을 걸러내는 유일한 기준이다** (`MAX_KM_PER_DAY`). 예전에는 이 값을
    20~90km 사이에서 점수로 환산해 종합점수의 40%로 썼는데, 하루 60km짜리 정상
    여행까지 감점하고 있었다. 지금은 채점하지 않고 상한만 본다.
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

    return total_km / max(duration_days, 1)


def _places_per_day(place_count: int, duration_days: int) -> float:
    """하루 평균 장소 수. **점수가 아니라 기록용 통계다.**

    예전에는 이 값을 3.5곳 기준으로 채점해 종합점수의 35%로 썼다. 지금은 채점하지
    않는다 (모듈 문서 「하루 장소 수 기준을 뺐다」 참조). 목록을 눈으로 점검할 때
    쓰려고 컬럼에는 계속 남긴다.
    """
    return place_count / max(duration_days, 1)


def _attraction_ratio(places: list[dict], place_meta: dict) -> float:
    """관광지 비율. 숙소·맛집·카페만으로 구성된 코스를 걸러낸다."""
    non_transit = [p for p in places if not _is_transit(p["place_name"])]
    if not non_transit:
        return 0.0
    n = sum(1 for p in non_transit if place_meta.get(p["place_name"], {}).get("is_attraction"))
    return n / len(non_transit)


def _make_title(region: str, duration_days: int, places: list[dict], place_meta: dict,
                display: dict[str, str], closed: set[str]) -> str:
    """원본 제목이 개인 메모라 쓸 수 없으므로 생성한다.

    대표 장소 이름은 **표시용 이름**을 쓴다. 원본에는
    `성산일출봉(UNESCO 세계자연유산)`, `이호테우해수욕장_old` 같은 게 섞여 있어
    그대로 제목에 넣으면 카드가 깨져 보인다
    (`build_place_display_names.py` 참조).

    폐업한 곳은 대표로 쓰지 않는다 — 없어진 가게가 코스를 대표하면 안 된다.
    """
    non_transit = [p for p in places if not _is_transit(p["place_name"])]
    if not non_transit:
        return f"{region} {duration_days}일 코스"

    def shown(p: dict) -> str:
        return display.get(p["place_name"], p["place_name"])

    # 대표 장소: 「폐업 아닌 관광지」 → 「폐업 아닌 아무 곳」 → 첫 방문지
    open_places = [p for p in non_transit if shown(p) not in closed]
    attractions = [p for p in open_places
                   if place_meta.get(p["place_name"], {}).get("is_attraction")]
    lead = shown((attractions or open_places or non_transit)[0])

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

    if not DISPLAY_NAMES_JSON.exists():
        sys.exit(f"❌ 표시 이름 없음: {DISPLAY_NAMES_JSON}\n"
                 "   .venv/bin/python backend/scripts/build_place_display_names.py 를 먼저 실행하라")
    names = json.loads(DISPLAY_NAMES_JSON.read_text(encoding="utf-8"))
    display, closed = names["display_names"], set(names["closed"])
    print(f"표시 이름 {len(display)}개 · 폐업 {len(closed)}곳")

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
        if duration > MAX_DURATION:
            # 「전체 28일 · 세화해변 외 63곳」 같은 것. 4일 여행자에게 보여줄 게 아니다.
            skipped["8일 이상 (장기 체류)"] += 1
            continue

        places = _dedupe_places(places)

        # 폐업한 곳이 하나라도 낀 코스는 뺀다. 화면에서는 표시 이름이 「(폐업)」을
        # 떼어내므로(`build_place_display_names.py`) 문 닫은 가게가 멀쩡한 곳처럼
        # 보이고, 코스를 믿고 간 여행자가 헛걸음한다. 표시 이름으로 비교하므로
        # 폐업 표기가 붙기 전에 등록된 같은 가게(「북촌에가면」)도 함께 걸린다.
        if any(display.get(p["place_name"], p["place_name"]) in closed for p in places):
            skipped["폐업 장소 포함"] += 1
            continue
        non_transit = [p for p in places if not _is_transit(p["place_name"])]

        # 모든 day에 장소가 있어야 한다 (day가 빈 코스 761개 존재)
        days_used = {p["day"] for p in non_transit}
        if len(days_used) < duration:
            skipped["빈 day 있음"] += 1
            continue

        if len(non_transit) < MIN_PLACES:
            skipped["장소 3곳 미만"] += 1
            continue

        if len(non_transit) / duration < MIN_PLACES_PER_DAY:
            skipped["하루 장소 부족"] += 1
            continue

        # 고유 장소가 여럿인데 이동이 사실상 0이면 좌표가 같은 것 — 지오코딩 실패 의심
        km_per_day = _km_per_day(places, duration)

        unique_names = {p["place_name"] for p in non_transit}
        if len(unique_names) >= 2 and km_per_day < MIN_UNIQUE_KM_PER_DAY:
            skipped["좌표 중복 의심"] += 1
            continue

        # 찜 목록 컷 — 하루에 제주를 거의 한 바퀴 도는 일정은 여행이 아니다
        if km_per_day > MAX_KM_PER_DAY:
            skipped["찜 목록 (이동 과다)"] += 1
            continue

        attraction = _attraction_ratio(places, place_meta)
        if attraction < MIN_ATTRACTION_RATIO:
            skipped["관광지 없음"] += 1
            continue

        # 지역: 교통 시설 제외 다수결. 과반이 아니면 "전체"
        votes = Counter(_classify_place_region(p["lat"], p["lng"]) for p in non_transit)
        top_region, top_n = votes.most_common(1)[0]
        region = top_region if top_n / len(non_transit) >= 0.5 else "전체"

        places_per_day = _places_per_day(len(non_transit), duration)

        candidates.append({
            "id": cid,
            "title": _make_title(region, duration, places, place_meta, display, closed),
            "origin_title": course["title"],
            "duration_days": duration,
            "region": region,
            "place_count": len(non_transit),
            "attraction_ratio": round(attraction, 3),
            "km_per_day": round(km_per_day, 1),
            "places_per_day": round(places_per_day, 2),
        })

    print(f"\n후보 {len(candidates)}개 (제외 {sum(skipped.values())}개)")
    for reason, n in skipped.most_common():
        print(f"  - {reason}: {n}")

    # ── 저장 ───────────────────────────────────────────────────────────────────
    #
    # 예전에는 여기서 점수 상위 50개씩만 골라 1,255개로 줄였다. 지금은 하드필터를
    # 통과한 전부를 넣는다 — 무엇을 보여줄지는 조회할 때 무작위로 정한다
    # (`agents/course_list_agent.py`).
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
            places_per_day    REAL
        )
    """)
    conn.executemany(
        """INSERT INTO curated_courses
           (id, title, origin_title, duration_days, region, place_count,
            attraction_ratio, km_per_day, places_per_day)
           VALUES (:id, :title, :origin_title, :duration_days, :region, :place_count,
                   :attraction_ratio, :km_per_day, :places_per_day)""",
        candidates,
    )
    conn.execute("CREATE INDEX idx_curated_region_dur ON curated_courses(region, duration_days)")
    conn.commit()

    print("\n=== 지역 × 일수 분포 ===")
    for row in conn.execute(
        "SELECT region, duration_days, COUNT(*) cnt FROM curated_courses "
        "GROUP BY region, duration_days ORDER BY region, duration_days"
    ):
        print(f"  {row['region']:4} {row['duration_days']:>2}일: {row['cnt']:>4}개")

    print("\n=== 무작위 5개 (실제로 사용자가 보게 될 모습) ===")
    for row in conn.execute(
        "SELECT title, km_per_day, places_per_day, attraction_ratio "
        "FROM curated_courses ORDER BY RANDOM() LIMIT 5"
    ):
        print(f"  {row['title']}")
        print(f"    이동 {row['km_per_day']}km/일 · {row['places_per_day']}곳/일 · 관광지 {row['attraction_ratio']:.0%}")

    conn.close()
    print("\n✅ curated_courses 빌드 완료")


if __name__ == "__main__":
    main()
