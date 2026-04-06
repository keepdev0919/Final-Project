"""
설화·민담 GPS 좌표 생성 스크립트

사용법:
    python scripts/geocode_folklore.py

기능:
    1. 설화·민담 텍스트에서 제주 지명 추출 (NER 화이트리스트)
    2. 82개 고유 지명 → Google Geocoding API로 GPS 좌표 획득
    3. 각 설화·민담에 GPS 좌표 매핑 (복수 지명 → 가장 구체적인 좌표 1개 선정)
    4. storage/metadata.db의 metadata 테이블에 lat/lng/primary_place 컬럼 추가
    5. data/processed/folklore_place_coords.json 저장 (지명 → GPS 캐시)
"""

from __future__ import annotations

import json
import os
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).parent.parent
load_dotenv(BASE_DIR / ".env")
sys.path.insert(0, str(Path(__file__).parent))

from common import EXTRACTED_DIR
from test_ner import JEJU_PLACES, extract_places

GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY", "")

PLACE_COORDS_PATH = BASE_DIR / "data" / "processed" / "folklore_place_coords.json"
DB_PATH = BASE_DIR / "storage" / "metadata.db"

JEJU_BOUNDS = "33.1,126.1|34.0,127.0"
REQUEST_DELAY = 0.05

# 더 구체적인 지명일수록 높은 우선순위 (행정구역보다 랜드마크가 더 정확)
SPECIFICITY = {
    "한라산": 10, "성산일출봉": 10, "만장굴": 10, "우도": 10,
    "마라도": 10, "가파도": 10, "비양도": 10, "항파두리": 9,
    "새별오름": 9, "다랑쉬오름": 9, "용눈이오름": 9, "산굼부리": 9,
    # 리 단위
    "가시리": 7, "송당리": 7, "선흘리": 7, "김녕리": 7, "세화리": 7,
    "하도리": 7, "종달리": 7, "표선리": 7, "성읍리": 7, "사계리": 7,
    "화순리": 7, "신촌리": 7, "함덕리": 7, "조천리": 7,
    # 읍·면 단위
    "애월읍": 5, "구좌읍": 5, "조천읍": 5, "한림읍": 5, "성산읍": 5,
    "표선읍": 5, "남원읍": 5, "대정읍": 5, "안덕면": 5, "한경면": 5,
    "표선면": 5, "우도면": 5,
    # 동 단위
    "용담동": 4, "건입동": 4, "화북동": 4, "삼양동": 4, "봉개동": 4,
    "아라동": 4, "연동": 4, "노형동": 4, "외도동": 4, "이호동": 4,
    "도두동": 4, "삼도동": 4, "이도동": 4, "송산동": 4, "정방동": 4,
    "중앙동": 4, "천지동": 4, "효돈동": 4, "동홍동": 4, "서홍동": 4,
    "중문동": 4, "예래동": 4, "대륜동": 4, "대천동": 4, "호근동": 4,
    "광령리": 4, "어음리": 4, "봉성리": 4, "장전리": 4,
    # 시 단위
    "제주시": 2, "서귀포시": 2,
    # 역사 지명 (위치 특정 어려움)
    "제주목": 1, "대정현": 1, "정의현": 1, "제주성": 1, "무근성": 1, "남문통": 1,
}


def geocode_place(place_name: str, api_key: str) -> dict:
    query = place_name + " 제주"
    params = urllib.parse.urlencode({
        "address": query,
        "key": api_key,
        "language": "ko",
        "region": "KR",
        "bounds": JEJU_BOUNDS,
    })
    url = f"https://maps.googleapis.com/maps/api/geocode/json?{params}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "jeju-folklore-rag/0.1"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
    except Exception as e:
        return {"place_name": place_name, "status": "REQUEST_ERROR", "error": str(e)}

    status = data.get("status", "UNKNOWN")
    if status != "OK" or not data.get("results"):
        return {"place_name": place_name, "status": status}

    result = data["results"][0]
    loc = result["geometry"]["location"]
    lat, lng = loc["lat"], loc["lng"]
    in_jeju = 33.0 <= lat <= 34.0 and 126.0 <= lng <= 127.0

    return {
        "place_name": place_name,
        "status": "OK",
        "lat": lat,
        "lng": lng,
        "formatted_address": result.get("formatted_address", ""),
        "in_jeju": in_jeju,
    }


def load_place_coords() -> dict[str, dict]:
    if not PLACE_COORDS_PATH.exists():
        return {}
    with open(PLACE_COORDS_PATH, encoding="utf-8") as f:
        items = json.load(f)
    return {item["place_name"]: item for item in items}


def save_place_coords(coords: dict[str, dict]) -> None:
    PLACE_COORDS_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(PLACE_COORDS_PATH, "w", encoding="utf-8") as f:
        json.dump(list(coords.values()), f, ensure_ascii=False, indent=2)


def pick_best_place(places: list[str], coords: dict[str, dict]) -> tuple[str, float, float] | None:
    """복수 지명 중 가장 구체적이고 GPS 있는 지명 선택."""
    candidates = [
        (p, coords[p]) for p in places
        if p in coords and coords[p].get("status") == "OK" and coords[p].get("in_jeju")
    ]
    if not candidates:
        return None
    candidates.sort(key=lambda x: SPECIFICITY.get(x[0], 3), reverse=True)
    best_place, best_coord = candidates[0]
    return best_place, best_coord["lat"], best_coord["lng"]


def update_metadata_db(story_gps: list[dict]) -> None:
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # lat/lng/primary_place 컬럼 없으면 추가
    existing_cols = [row[1] for row in cur.execute("PRAGMA table_info(metadata)").fetchall()]
    for col, col_type in [("lat", "REAL"), ("lng", "REAL"), ("primary_place", "TEXT")]:
        if col not in existing_cols:
            cur.execute(f"ALTER TABLE metadata ADD COLUMN {col} {col_type}")

    for item in story_gps:
        cur.execute(
            "UPDATE metadata SET lat=?, lng=?, primary_place=? WHERE code_no=?",
            (item["lat"], item["lng"], item["primary_place"], item["code_no"]),
        )
    conn.commit()
    conn.close()


def main() -> None:
    if not GOOGLE_MAPS_API_KEY:
        print("❌ GOOGLE_MAPS_API_KEY가 비어 있습니다.")
        return

    # 1. 모든 설화·민담에서 지명 추출
    story_places: dict[str, dict] = {}  # code_no → {source_type, title, places}

    for f in sorted((EXTRACTED_DIR / "legend").glob("*.txt")):
        code_no = f.stem
        text = f.read_text(encoding="utf-8")
        title = text.splitlines()[0].strip()
        places = extract_places(text)
        story_places[code_no] = {"source_type": "legend", "title": title, "places": places}

    for f in sorted((EXTRACTED_DIR / "folktale").glob("W-F-*.txt")):
        code_no = f.stem
        text = f.read_text(encoding="utf-8")
        title = text.splitlines()[0].strip()
        places = extract_places(text)
        story_places[code_no] = {"source_type": "folktale", "title": title, "places": places}

    total_stories = len(story_places)
    stories_with_places = sum(1 for v in story_places.values() if v["places"])
    all_place_names = sorted(set(p for v in story_places.values() for p in v["places"]))

    print(f"설화·민담 총: {total_stories}개")
    print(f"지명 추출 성공: {stories_with_places}개")
    print(f"고유 지명: {len(all_place_names)}개")

    # 2. 지명 지오코딩 (캐시 활용)
    coords = load_place_coords()
    todo = [p for p in all_place_names if p not in coords or coords[p].get("status") == "REQUEST_DENIED"]
    print(f"\n이미 처리됨: {len(coords)}개 | 남은 작업: {len(todo)}개")

    for i, place in enumerate(todo):
        result = geocode_place(place, GOOGLE_MAPS_API_KEY)
        coords[place] = result
        status = "✅" if result.get("in_jeju") else ("⚠️" if result.get("status") == "OK" else "❌")
        print(f"[{i+1}/{len(todo)}] {status} {place}")
        time.sleep(REQUEST_DELAY)

    save_place_coords(coords)

    ok = sum(1 for v in coords.values() if v.get("status") == "OK" and v.get("in_jeju"))
    print(f"\n지오코딩 완료: {ok}/{len(all_place_names)}개 제주 내 좌표 확보")

    # 3. 설화·민담별 대표 GPS 선정
    story_gps = []
    no_gps = []
    for code_no, info in story_places.items():
        best = pick_best_place(info["places"], coords)
        if best:
            story_gps.append({
                "code_no": code_no,
                "source_type": info["source_type"],
                "title": info["title"],
                "primary_place": best[0],
                "lat": best[1],
                "lng": best[2],
                "all_places": info["places"],
            })
        else:
            no_gps.append(code_no)

    print(f"\nGPS 확보된 설화·민담: {len(story_gps)}개")
    print(f"GPS 없음 (지명 미추출 또는 지오코딩 실패): {len(no_gps)}개")

    # 4. SQLite 업데이트
    update_metadata_db(story_gps)
    print(f"metadata.db 업데이트 완료")

    # 5. 결과 저장
    output_path = BASE_DIR / "data" / "processed" / "folklore_gps.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(story_gps, f, ensure_ascii=False, indent=2)
    print(f"저장: {output_path}")

    # 결과 요약
    print("\n=== 지역별 분포 ===")
    from collections import Counter
    from test_ner import REGION_MAP, get_region
    region_count: Counter = Counter()
    for item in story_gps:
        region = get_region(item["primary_place"])
        region_count[region] += 1
    for region, cnt in region_count.most_common():
        print(f"  {region:<18} {cnt}건")


if __name__ == "__main__":
    main()
