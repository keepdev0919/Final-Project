"""Visit Jeju 장소 3,284개에 KTO TourAPI 카테고리 보강.

흐름:
  1. KTO areaBasedList2로 제주(areaCode=39) 관광지 데이터 받기
     - contenttypeid in (12 관광지, 14 문화시설, 15 축제, 25 여행코스, 28 레포츠)
     - 결과: 약 619개 (cat1/cat2/cat3 + 좌표 포함)
  2. Visit Jeju 3,284개와 GPS 거리(<=300m) + 이름 유사도로 매칭
  3. 매칭된 장소 → KTO 카테고리 부여
  4. 매칭 안 된 장소 → "non_attraction" 라벨 (식당/카페/숙박 추정)
  5. data/processed/visitjeju_places_categorized.json 저장
"""
from __future__ import annotations

import json
import math
import os
import time
import urllib.parse
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).parent.parent
load_dotenv(BASE_DIR / ".env")
KEY = os.getenv("KTO_API_KEY", "")

INPUT_PATH = BASE_DIR / "data" / "processed" / "visitjeju_places_geocoded.json"
OUTPUT_PATH = BASE_DIR / "data" / "processed" / "visitjeju_places_categorized.json"
KTO_CACHE_PATH = BASE_DIR / "data" / "processed" / "kto_jeju_attractions.json"

# KTO contentTypeId: 의미 있는 것만
USEFUL_CONTENT_TYPES = {
    "12": "관광지",
    "14": "문화시설",
    "15": "축제공연",
    "25": "여행코스",
    "28": "레포츠",
}

MATCH_DISTANCE_M = 300        # GPS 매칭 임계
MIN_NAME_SIMILARITY = 0.35    # 이름 유사도 최소 기준 (너무 낮으면 거부)


# ─── Util ─────────────────────────────────────────────────────────────────────

def haversine_m(la1: float, lo1: float, la2: float, lo2: float) -> float:
    R = 6_371_000
    p1, p2 = math.radians(la1), math.radians(la2)
    dp = math.radians(la2 - la1)
    dl = math.radians(lo2 - lo1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def name_similarity(a: str, b: str) -> float:
    """이름 정규화 후 SequenceMatcher 비율."""
    import re
    def norm(s: str) -> str:
        s = re.sub(r"[\(\[\{].*?[\)\]\}]", "", s)
        s = re.sub(r"[\s_·\-‧&]+", "", s)
        return s.lower()
    return SequenceMatcher(None, norm(a), norm(b)).ratio()


# ─── 1. KTO 관광지 전체 받기 ────────────────────────────────────────────────────

def fetch_kto_attractions() -> list[dict]:
    """KTO areaBasedList2로 제주 의미있는 관광지 전체 페이지네이션."""
    base = "https://apis.data.go.kr/B551011/KorService2/areaBasedList2"
    all_items: list[dict] = []

    for ctid, label in USEFUL_CONTENT_TYPES.items():
        page = 1
        while True:
            params = {
                "serviceKey": KEY,
                "MobileOS": "ETC",
                "MobileApp": "jeju-folklore",
                "areaCode": "39",
                "contentTypeId": ctid,
                "numOfRows": "100",
                "pageNo": str(page),
                "_type": "json",
            }
            url = f"{base}?{urllib.parse.urlencode(params, safe='')}"
            try:
                with urllib.request.urlopen(url, timeout=15) as resp:
                    data = json.loads(resp.read().decode())
            except Exception as e:
                print(f"  [에러] ctid={ctid} page={page}: {e}")
                break

            body = data.get("response", {}).get("body", {})
            total = body.get("totalCount", 0)
            items = body.get("items", {})
            if not items:
                break
            item_list = items.get("item", [])
            if not isinstance(item_list, list):
                item_list = [item_list]

            for it in item_list:
                try:
                    mx, my = float(it.get("mapx", 0)), float(it.get("mapy", 0))
                except (ValueError, TypeError):
                    continue
                if mx <= 0 or my <= 0:
                    continue
                all_items.append({
                    "kto_title": it.get("title", ""),
                    "contentid": it.get("contentid", ""),
                    "contenttypeid": it.get("contenttypeid", ""),
                    "contenttype_label": USEFUL_CONTENT_TYPES.get(it.get("contenttypeid", ""), "?"),
                    "cat1": it.get("cat1", ""),
                    "cat2": it.get("cat2", ""),
                    "cat3": it.get("cat3", ""),
                    "addr1": it.get("addr1", ""),
                    "lat": my,   # KTO mapy=위도
                    "lng": mx,   # KTO mapx=경도
                })

            fetched_so_far = page * 100
            print(f"  [{label}] page {page}: {len(item_list)}개 수신 (누적 {min(fetched_so_far, total)}/{total})")
            if fetched_so_far >= total:
                break
            page += 1
            time.sleep(0.15)
        time.sleep(0.2)

    return all_items


# ─── 2. Visit Jeju × KTO 매칭 ────────────────────────────────────────────────

def match_places(visit_jeju: list[dict], kto: list[dict]) -> list[dict]:
    """각 Visit Jeju 장소에 가장 어울리는 KTO 매칭 부여."""
    results = []
    for vj in visit_jeju:
        if not vj.get("in_jeju") or not vj.get("lat") or not vj.get("lng"):
            results.append({
                **vj,
                "kto_matched": False,
                "exclusion_reason": "no_gps",
            })
            continue

        vlat, vlng = vj["lat"], vj["lng"]

        # 300m 이내 KTO 후보
        candidates = []
        for k in kto:
            d = haversine_m(vlat, vlng, k["lat"], k["lng"])
            if d <= MATCH_DISTANCE_M:
                sim = name_similarity(vj["place_name"], k["kto_title"])
                # 거리 가중치 살짝 (가까울수록 +): score = sim - 0.0005 * dist
                score = sim - 0.0005 * d
                candidates.append((score, sim, d, k))

        if not candidates:
            results.append({
                **vj,
                "kto_matched": False,
                "exclusion_reason": "no_kto_within_range",
            })
            continue

        candidates.sort(key=lambda x: -x[0])
        score, sim, dist, best = candidates[0]

        if sim < MIN_NAME_SIMILARITY:
            results.append({
                **vj,
                "kto_matched": False,
                "exclusion_reason": "low_name_similarity",
                "rejected_kto_title": best["kto_title"],
                "rejected_similarity": round(sim, 2),
                "rejected_distance_m": int(dist),
            })
            continue

        results.append({
            **vj,
            "kto_matched": True,
            "kto_title": best["kto_title"],
            "kto_contentid": best["contentid"],
            "kto_contenttypeid": best["contenttypeid"],
            "kto_contenttype_label": best["contenttype_label"],
            "kto_cat1": best["cat1"],
            "kto_cat2": best["cat2"],
            "kto_cat3": best["cat3"],
            "kto_addr": best["addr1"],
            "match_distance_m": int(dist),
            "match_similarity": round(sim, 2),
        })

    return results


# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    if not KEY:
        print("❌ KTO_API_KEY 비어있음")
        return

    # Step 1: KTO 관광지 수집 (캐시 있으면 재사용)
    if KTO_CACHE_PATH.exists():
        print(f"📂 캐시 사용: {KTO_CACHE_PATH}")
        with open(KTO_CACHE_PATH) as f:
            kto = json.load(f)
        print(f"  KTO 관광지 {len(kto)}개 로드\n")
    else:
        print("🌐 KTO TourAPI 수집 시작...")
        kto = fetch_kto_attractions()
        KTO_CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(KTO_CACHE_PATH, "w", encoding="utf-8") as f:
            json.dump(kto, f, ensure_ascii=False, indent=2)
        print(f"\n✅ KTO 관광지 {len(kto)}개 저장 → {KTO_CACHE_PATH}\n")

    # Step 2: Visit Jeju 로드
    with open(INPUT_PATH) as f:
        visit_jeju = json.load(f)
    print(f"📂 Visit Jeju {len(visit_jeju)}개 로드\n")

    # Step 3: 매칭
    print("🔗 매칭 시작...")
    matched = match_places(visit_jeju, kto)

    # Step 4: 저장
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(matched, f, ensure_ascii=False, indent=2)

    # Step 5: 통계
    total = len(matched)
    ok = [m for m in matched if m.get("kto_matched")]
    by_type: dict[str, int] = {}
    for m in ok:
        t = m.get("kto_contenttype_label", "?")
        by_type[t] = by_type.get(t, 0) + 1

    no_gps = sum(1 for m in matched if m.get("exclusion_reason") == "no_gps")
    no_kto = sum(1 for m in matched if m.get("exclusion_reason") == "no_kto_within_range")
    low_sim = sum(1 for m in matched if m.get("exclusion_reason") == "low_name_similarity")

    print(f"\n{'=' * 70}")
    print(f"  매칭 결과")
    print(f"{'=' * 70}")
    print(f"전체: {total}개")
    print(f"매칭 성공: {len(ok)}개 ({len(ok)/total*100:.1f}%)")
    for t, c in sorted(by_type.items(), key=lambda x: -x[1]):
        print(f"  └ {t}: {c}개")
    print(f"매칭 실패: {total-len(ok)}개")
    print(f"  └ GPS 없음:           {no_gps}개")
    print(f"  └ 300m 내 KTO 없음:   {no_kto}개  (식당/카페/숙박 추정)")
    print(f"  └ 이름 유사도 부족:    {low_sim}개")
    print(f"\n💾 저장: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
