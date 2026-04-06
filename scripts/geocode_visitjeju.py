"""
Visit Jeju 세부일정 장소명 → GPS 좌표 변환 스크립트

사용법:
    python scripts/geocode_visitjeju.py

기능:
    - VISIT JEJU_여행세부일정.CSV에서 고유 장소명 3,284개 추출
    - Google Geocoding API로 GPS 좌표 획득
    - 결과를 data/processed/visitjeju_places_geocoded.json 저장
    - 중단 후 재실행 시 이미 처리된 항목 스킵 (resume 지원)
    - 요청 간 0.05초 딜레이 (무료 티어 제한 고려)
"""

from __future__ import annotations

import csv
import json
import os
import time
import urllib.parse
import urllib.request
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

# ─── 설정 ────────────────────────────────────────────────────────────────────

GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY", "")

CSV_PATH = Path(__file__).parent.parent / "VISIT JEJU_여행세부일정.CSV"
OUTPUT_PATH = Path(__file__).parent.parent / "data" / "processed" / "visitjeju_places_geocoded.json"

# 제주 지역 바이어스 (결과를 제주도 우선으로)
JEJU_REGION = "KR"
JEJU_BOUNDS = "33.1,126.1|34.0,127.0"  # 제주도 바운딩 박스
LANGUAGE = "ko"

REQUEST_DELAY = 0.05  # 초 (Google 무료 티어: 50 req/s)

# ─── 유틸 ─────────────────────────────────────────────────────────────────────


def geocode(place_name: str, api_key: str) -> dict:
    """장소명 → GPS 좌표. 실패 시 status 필드에 오류 코드."""
    query = place_name + " 제주"
    params = urllib.parse.urlencode({
        "address": query,
        "key": api_key,
        "language": LANGUAGE,
        "region": JEJU_REGION,
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
    location_type = result["geometry"].get("location_type", "")
    address = result.get("formatted_address", "")

    # 제주도 범위 내인지 확인
    lat, lng = loc["lat"], loc["lng"]
    in_jeju = 33.0 <= lat <= 34.0 and 126.0 <= lng <= 127.0

    return {
        "place_name": place_name,
        "status": "OK",
        "lat": lat,
        "lng": lng,
        "formatted_address": address,
        "location_type": location_type,
        "in_jeju": in_jeju,
    }


def load_place_names() -> list[str]:
    with open(CSV_PATH, encoding="cp949") as f:
        rows = list(csv.DictReader(f))
    names = sorted(set(r["콘텐츠명"].strip() for r in rows if r["콘텐츠명"].strip()))
    return names


def load_existing(output_path: Path) -> dict[str, dict]:
    if not output_path.exists():
        return {}
    with open(output_path, encoding="utf-8") as f:
        data = json.load(f)
    return {item["place_name"]: item for item in data}


def save(results: dict[str, dict], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(list(results.values()), f, ensure_ascii=False, indent=2)


# ─── 메인 ─────────────────────────────────────────────────────────────────────


def main() -> None:
    if not GOOGLE_MAPS_API_KEY:
        print("❌ GOOGLE_MAPS_API_KEY가 비어 있습니다.")
        print("   스크립트 상단 GOOGLE_MAPS_API_KEY = \"\" 에 키를 입력하세요.")
        return

    place_names = load_place_names()
    print(f"총 장소명: {len(place_names)}개")

    existing = load_existing(OUTPUT_PATH)
    todo = [n for n in place_names if n not in existing or existing[n].get("status") == "REQUEST_DENIED"]
    print(f"이미 처리됨: {len(existing)}개 | 남은 작업: {len(todo)}개")

    if not todo:
        print("모두 완료되었습니다.")
        _print_summary(existing)
        return

    results = dict(existing)
    ok_count = sum(1 for v in existing.values() if v.get("status") == "OK")
    jeju_count = sum(1 for v in existing.values() if v.get("in_jeju"))
    fail_count = len(existing) - ok_count

    try:
        for i, name in enumerate(todo):
            result = geocode(name, GOOGLE_MAPS_API_KEY)
            results[name] = result

            if result["status"] == "OK":
                ok_count += 1
                if result.get("in_jeju"):
                    jeju_count += 1
                marker = "✅" if result.get("in_jeju") else "⚠️ (제주 외)"
                print(f"[{len(existing)+i+1}/{len(place_names)}] {marker} {name} → {result['lat']:.4f}, {result['lng']:.4f}")
            else:
                fail_count += 1
                print(f"[{len(existing)+i+1}/{len(place_names)}] ❌ {name} → {result['status']}")

            # 50건마다 중간 저장
            if (i + 1) % 50 == 0:
                save(results, OUTPUT_PATH)
                print(f"  💾 중간 저장 ({len(results)}건)")

            time.sleep(REQUEST_DELAY)

    except KeyboardInterrupt:
        print("\n중단됨. 지금까지 결과 저장 중...")

    save(results, OUTPUT_PATH)
    _print_summary(results)


def _print_summary(results: dict) -> None:
    total = len(results)
    ok = [v for v in results.values() if v.get("status") == "OK"]
    in_jeju = [v for v in ok if v.get("in_jeju")]
    failed = [v for v in results.values() if v.get("status") != "OK"]

    print("\n" + "=" * 50)
    print(f"총 처리: {total}개")
    print(f"성공: {len(ok)}개 ({len(ok)/total*100:.1f}%)")
    print(f"  └ 제주 내: {len(in_jeju)}개 ({len(in_jeju)/total*100:.1f}%)")
    print(f"  └ 제주 외: {len(ok)-len(in_jeju)}개")
    print(f"실패: {len(failed)}개 ({len(failed)/total*100:.1f}%)")
    print(f"저장 위치: {OUTPUT_PATH}")

    # 실패 사례 샘플
    if failed:
        print("\n실패 샘플 (최대 5개):")
        for v in failed[:5]:
            print(f"  {v['place_name']} → {v.get('status')}")


if __name__ == "__main__":
    main()
