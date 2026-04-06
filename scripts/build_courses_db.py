"""
Visit Jeju 여행세부일정 + 지오코딩 결과 → courses DB 구축

사용법:
    python scripts/build_courses_db.py

기능:
    - VISIT JEJU_여행세부일정.CSV + visitjeju_places_geocoded.json 조인
    - storage/metadata.db에 courses, course_places 테이블 생성
"""

from __future__ import annotations

import csv
import json
import sqlite3
from pathlib import Path

BASE_DIR = Path(__file__).parent.parent
CSV_PATH = BASE_DIR / "VISIT JEJU_여행세부일정.CSV"
GEOCODED_PATH = BASE_DIR / "data" / "processed" / "visitjeju_places_geocoded.json"
DB_PATH = BASE_DIR / "storage" / "metadata.db"


# ─── 스키마 ───────────────────────────────────────────────────────────────────

CREATE_COURSES = """
CREATE TABLE IF NOT EXISTS courses (
    id              TEXT PRIMARY KEY,
    title           TEXT,
    duration_days   INTEGER,
    place_count     INTEGER,
    geocoded_count  INTEGER
);
"""

CREATE_COURSE_PLACES = """
CREATE TABLE IF NOT EXISTS course_places (
    seq_no          INTEGER,
    course_id       TEXT,
    place_name      TEXT,
    day             INTEGER,
    start_time      TEXT,
    end_time        TEXT,
    place_type      TEXT,
    lat             REAL,
    lng             REAL,
    in_jeju         INTEGER,
    FOREIGN KEY (course_id) REFERENCES courses(id)
);
"""

CREATE_IDX_COURSE_ID = "CREATE INDEX IF NOT EXISTS idx_cp_course_id ON course_places(course_id);"
CREATE_IDX_LATLONG  = "CREATE INDEX IF NOT EXISTS idx_cp_latlng ON course_places(lat, lng);"


# ─── 메인 ─────────────────────────────────────────────────────────────────────

def main() -> None:
    # 1. 지오코딩 결과 로드 (장소명 → 좌표 딕셔너리)
    with open(GEOCODED_PATH, encoding="utf-8") as f:
        geocoded_list = json.load(f)
    geo_map: dict[str, dict] = {item["place_name"]: item for item in geocoded_list}
    print(f"지오코딩 장소: {len(geo_map)}개")

    # 2. CSV 로드
    with open(CSV_PATH, encoding="cp949") as f:
        rows = list(csv.DictReader(f))
    print(f"CSV 행 수: {len(rows)}개")

    # 3. 일정별 그룹화
    courses: dict[str, dict] = {}
    for row in rows:
        cid = row["여행일정아이디"].strip()
        if cid not in courses:
            courses[cid] = {
                "id": cid,
                "title": row["여행일정타이틀"].strip(),
                "places": [],
            }
        courses[cid]["places"].append(row)

    print(f"고유 일정: {len(courses)}개")

    # 4. DB 저장
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute(CREATE_COURSES)
    cur.execute(CREATE_COURSE_PLACES)
    cur.execute(CREATE_IDX_COURSE_ID)
    cur.execute(CREATE_IDX_LATLONG)

    # 기존 데이터 초기화 (재실행 시 중복 방지)
    cur.execute("DELETE FROM course_places")
    cur.execute("DELETE FROM courses")

    course_rows = []
    place_rows = []
    geocoded_total = 0
    place_total = 0

    for cid, course in courses.items():
        places = course["places"]
        geocoded_count = 0

        for p in places:
            name = p["콘텐츠명"].strip()
            geo = geo_map.get(name)

            lat = geo["lat"] if geo and geo.get("status") == "OK" else None
            lng = geo["lng"] if geo and geo.get("status") == "OK" else None
            in_jeju = 1 if geo and geo.get("in_jeju") else 0

            if lat is not None:
                geocoded_count += 1

            place_rows.append((
                int(p["일련번호"]),
                cid,
                name,
                int(p["여행일수"]) if p["여행일수"].strip().isdigit() else 0,
                p["시작시간"].strip(),
                p["종료시간"].strip(),
                p["장소구분"].strip(),
                lat,
                lng,
                in_jeju,
            ))

        place_total += len(places)
        geocoded_total += geocoded_count

        duration_days = max(
            (int(p["여행일수"]) for p in places if p["여행일수"].strip().isdigit()),
            default=0,
        )
        course_rows.append((
            cid,
            course["title"],
            duration_days,
            len(places),
            geocoded_count,
        ))

    cur.executemany(
        "INSERT INTO courses VALUES (?,?,?,?,?)",
        course_rows,
    )
    cur.executemany(
        "INSERT INTO course_places VALUES (?,?,?,?,?,?,?,?,?,?)",
        place_rows,
    )
    conn.commit()
    conn.close()

    print("\n=== 완료 ===")
    print(f"courses 테이블: {len(course_rows)}개 일정")
    print(f"course_places 테이블: {len(place_rows)}개 장소 행")
    print(f"GPS 좌표 있는 장소: {geocoded_total}/{place_total} ({geocoded_total/place_total*100:.1f}%)")
    print(f"저장 위치: {DB_PATH}")


if __name__ == "__main__":
    main()
