"""Visit Jeju 3,284개 장소를 12개 카테고리로 분류.

분류 우선순위:
  1) KTO 매칭된 장소(이전 단계 결과): contenttypeid + cat1으로 자동 매핑
  2) 매칭 안 된 장소: 이름 + 주소 키워드 기반 분류
  3) 모호한 케이스: 'unclear'로 표시

카테고리:
  ✅ 매핑 대상 (설화 연결 가능):
    nature       — 자연명소 (오름, 폭포, 해변, 동굴, 곶자왈, 포구, 숲)
    culture      — 박물관, 전시관, 미술관
    history      — 유적지, 기념비, 사적지
    religious    — 신당, 사찰, 성당
    village      — 마을시설, 시장, 올레길
    experience   — 식물원, 자연체험형 시설, 농장·목장

  ❌ 매핑 제외 (식당/상업):
    food         — 식당, 음식점
    cafe         — 카페, 베이커리, 디저트
    accommodation — 호텔, 펜션, 게스트하우스
    shopping     — 상점, 토산품, 마트
    commercial   — 렌탈, 강습소, 골프장 등 일반 상업
    unclear      — 이름·주소만으로 판단 어려움
"""
from __future__ import annotations

import csv
import json
import re
from collections import Counter
from pathlib import Path

BASE = Path(__file__).parent.parent
INPUT_PATH = BASE / "data" / "processed" / "visitjeju_places_categorized.json"
OUTPUT_JSON = BASE / "data" / "processed" / "visitjeju_places_final.json"
OUTPUT_CSV = BASE / "docs" / "experiments" / "visitjeju_classification.csv"

CATEGORIES = [
    "nature", "culture", "history", "religious", "village", "experience",
    "food", "cafe", "accommodation", "shopping", "commercial", "unclear",
]
ATTRACTION_CATEGORIES = {"nature", "culture", "history", "religious", "village", "experience"}

# ─── 1) KTO contenttypeid + cat1 → 우리 카테고리 ──────────────────────────────

KTO_CONVERT = {
    # contenttypeid → 기본 분류
    "12": "nature",        # 관광지 — cat1으로 세분
    "14": "culture",       # 문화시설
    "15": "experience",    # 축제 → 체험
    "25": "village",       # 여행코스 → 마을·올레
    "28": "experience",    # 레포츠 → 체험
}

KTO_CAT1_REFINE = {
    # cat1으로 contenttypeid=12 세분
    "A01": "nature",       # 자연
    "A02": "history",      # 인문(문화/예술/역사) - 유적·역사
}


def from_kto(contenttypeid: str, cat1: str, kto_title: str) -> str:
    """KTO 매칭 결과 → 우리 카테고리."""
    if contenttypeid == "12":  # 관광지
        # 키워드로 보정
        t = kto_title
        if any(kw in t for kw in ["사찰", "암자", "사 ", "절", "당", "묘", "성당", "교회"]):
            return "religious"
        if any(kw in t for kw in ["박물관", "미술관", "전시관", "갤러리"]):
            return "culture"
        if any(kw in t for kw in ["유적", "사적", "기념관", "기념비"]):
            return "history"
        # cat1 우선
        return KTO_CAT1_REFINE.get(cat1, "nature")
    return KTO_CONVERT.get(contenttypeid, "experience")


# ─── 2) 키워드 기반 휴리스틱 ──────────────────────────────────────────────────

# 우선순위 순서대로 매칭 (위에 있을수록 우선)
KEYWORD_RULES: list[tuple[str, list[str]]] = [
    # 명백한 카페 (먼저 잡아야 음식 키워드와 충돌 안 함)
    ("cafe", [
        "카페", "까페", "Cafe", "CAFE", "Coffee", "COFFEE", "커피",
        "베이커리", "Bakery", "BAKERY",
        "베이글", "도넛", "케이크", "케익", "마카롱", "디저트",
        "빙수", "아이스크림", "젤라또", "푸딩",
        "브런치", "브렁치", "스타벅스", "투썸", "이디야", "할리스",
        "공차", "노티드", "런던베이글",
    ]),
    # 식당 (음식점)
    ("food", [
        "식당", "횟집", "갈비", "흑돼지", "한정식", "회집", "백반",
        "칼국수", "국수", "국밥", "분식", "라면", "우동", "라멘",
        "짜장", "짬뽕", "반점", "중국집",
        "삼겹살", "막창", "곱창", "도가니", "닭갈비", "닭볶음",
        "비빔밥", "곰탕", "추어탕", "갈치", "고등어",
        "솥밥", "솥", "정식", "한상", "찜", "탕", "구이",
        "두루치기", "막국수", "메밀", "모밀", "분식", "면",
        "본점", "분점", "직영", "맛집", "음식점", "주막",
        "어가", "어부", "어촌", "해산물",
        "스시", "초밥", "사시미", "이자카야",
        "버거", "햄버거", "피자", "Pizza", "PIZZA", "치킨",
        "떡볶이", "떡", "만두", "호떡", "전", "파전",
        "주방", "키친", "Kitchen",
    ]),
    # 숙박
    ("accommodation", [
        "호텔", "Hotel", "HOTEL",
        "펜션", "Pension", "PENSION",
        "리조트", "Resort", "RESORT",
        "콘도", "민박",
        "게스트하우스", "Guesthouse", "게스트",
        "스테이", "Stay", "한옥",
        "캠핑장", "야영장", "글램핑",
        "Inn", "Lodge",
    ]),
    # 쇼핑
    ("shopping", [
        "면세점", "면세",
        "마트", "슈퍼", "편의점", "백화점", "아울렛",
        "토산품", "특산품",
        "쇼핑몰", "Mall", "매장",
        "시장 ", "Market",
    ]),
    # 상업 (스파, 렌탈, 골프 등)
    ("commercial", [
        "골프", "Golf", "GOLF", "컨트리클럽", "CC",
        "스파", "Spa", "SPA", "사우나", "찜질방",
        "렌터카", "렌탈", "렌트",
        "강습소", "학원",
        "병원", "의원", "약국", "클리닉",
        "헤어", "네일", "미용실",
        "키즈카페", "PC방", "노래방", "당구장", "볼링장",
        "수퍼마켙",  # "노형수퍼마켙" 같은 경우 — 영화 시설이라 culture로 가야하지만 일단 보수적
    ]),
    # 자연
    ("nature", [
        "해수욕장", "해변", "해안", "백사장",
        "오름", "한라산", "백록담",
        "폭포", "동굴",
        "곶자왈", "숲길", "수목원",
        "포구", "방파제", "등대",
        "연못", "호수", "약수터", "용천수",
        "공원", "산책로", "둘레길",
        "우도", "마라도", "가파도", "비양도", "추자도",
        "절벽", "바위", "갯바위",
        "들녘", "들판", "초원", "목초지",
        "구두미", "당오름", "다랑쉬", "용눈이", "산방산", "성산일출",
    ]),
    # 문화시설
    ("culture", [
        "박물관", "미술관", "전시관", "전시장", "갤러리", "아트",
        "문화원", "문화센터", "문예회관",
        "도서관", "기록관", "자료관",
        "공연장", "극장",
    ]),
    # 역사 유적
    ("history", [
        "유적", "사적지", "사적", "기념관", "기념비", "기념물",
        "산성", "성지", "왕릉", "고분",
        "항몽", "초가", "전통가옥",
        "민속촌", "민속마을",
        "역사관", "역사문화", "4.3", "4·3", "사삼", "수용소",
        "관덕정", "삼성혈", "정의현", "대정현",
    ]),
    # 종교
    ("religious", [
        "사찰", "절(", "암자", "본향당", "신당",
        "성당", "교회", "사원",
    ]),
    # 마을 / 올레
    ("village", [
        "올레", "올레길",
        "마을회관", "마을길", "마을 ",
        "5일장", "5일시장", "오일장", "벨롱장",
        "노인회관",
    ]),
    # 체험·테마파크
    ("experience", [
        "농장", "목장", "낙농",
        "체험관", "체험장", "체험마을", "체험",
        "수족관", "동물원", "식물원",
        "테마파크", "테마관", "테마",
        "워터파크", "수상레저",
        "미로공원", "정원", "허브",
        "휴양림", "산림",
        "축제", "페스티벌",
        "사격장", "양식단지", "양식장",
        "캠퍼스", "브릭", "에듀",
        "승마", "ATV",
    ]),
]


def classify_by_keyword(name: str, addr: str = "") -> str:
    """이름 키워드로 분류 (주소는 사용 안 함 — 도로명에 자연 키워드 끼어들기 방지)."""
    text = name

    for cat, kws in KEYWORD_RULES:
        for kw in kws:
            if kw in text:
                return cat
    return "unclear"


# ─── 후처리 — 식당/카페 패턴 강제 재분류 ─────────────────────────────────────────

# attraction으로 분류돼도 진짜 식당일 만한 명백한 패턴
FOOD_OVERRIDE_KEYWORDS = [
    "갈비밥", "갈치", "회국수", "바당회", "갈비", "국수", "횟집",
    "맛집", "식당", "주막", "정식", "한상",
    "삼겹살", "막창", "곱창", "흑돼지", "곰탕", "추어탕",
    "수퍼마켙",
]
CAFE_OVERRIDE_KEYWORDS = [
    "카롱", "빙수", "망고홀릭", "베이글", "도넛", "케익", "케이크",
    "런던베이글", "공차",
]


def post_process_attraction(name: str, cat: str) -> tuple[str, bool]:
    """attraction으로 분류된 것 중 식당/카페 패턴 발견 시 강제 재분류.

    Returns: (new_category, overridden_bool)
    """
    if cat not in ATTRACTION_CATEGORIES:
        return cat, False

    # 식당 키워드 매칭
    for kw in FOOD_OVERRIDE_KEYWORDS:
        if kw in name:
            return "food", True

    # 카페 키워드 매칭
    for kw in CAFE_OVERRIDE_KEYWORDS:
        if kw in name:
            return "cafe", True

    # "○○점" 패턴 — 본점/분점/○호점/지역명+점
    # 단 박물관·미술관·문화원 같은 큰 시설은 제외
    attraction_endings = (
        "박물관", "미술관", "전시관", "기념관", "문화원", "문화센터",
        "센터", "도서관", "체험관", "수족관", "동물원", "식물원",
    )
    if name.endswith(attraction_endings):
        return cat, False

    # "본점" / "분점" / "1호점"~"99호점"
    if re.search(r"(본점|분점|\d+호점)$", name):
        return "food", True

    # "○○점"으로 끝나면서 앞에 지역명/관광지명이 있는 경우 (체인 식당/카페)
    # 예: "꽃가람 제주성산일출봉점", "리치망고우도점", "망고홀릭 성산일출봉점"
    if re.search(r".+점$", name) and not any(name.endswith(s) for s in attraction_endings):
        # ○○점 패턴이지만 정확한 카페/식당 판별이 어려움 → 안전하게 food로
        return "food", True

    return cat, False


# ─── 메인 ─────────────────────────────────────────────────────────────────────

def main() -> None:
    with open(INPUT_PATH) as f:
        places = json.load(f)

    print(f"총 장소: {len(places)}\n")

    results = []
    source_counter: Counter = Counter()
    cat_counter: Counter = Counter()

    for p in places:
        name = p["place_name"]
        addr = p.get("formatted_address", "")

        # 1) KTO 매칭된 것
        if p.get("kto_matched"):
            cat = from_kto(
                p.get("kto_contenttypeid", ""),
                p.get("kto_cat1", ""),
                p.get("kto_title", ""),
            )
            source = "kto"
        else:
            # 2) 키워드 분류
            cat = classify_by_keyword(name, addr)
            source = "keyword" if cat != "unclear" else "unclear"

        # 3) 후처리: attraction으로 분류돼도 식당/카페 패턴이면 강제 재분류
        cat, overridden = post_process_attraction(name, cat)
        if overridden:
            source += "+override"

        source_counter[source] += 1
        cat_counter[cat] += 1

        results.append({
            "place_name": name,
            "lat": p.get("lat"),
            "lng": p.get("lng"),
            "category": cat,
            "is_attraction": cat in ATTRACTION_CATEGORIES,
            "source": source,
            "kto_matched": p.get("kto_matched", False),
            "kto_title": p.get("kto_title", ""),
        })

    # 출력
    print("=" * 70)
    print("  분류 출처")
    print("=" * 70)
    for src, cnt in source_counter.most_common():
        print(f"  {src:12s} {cnt:5d} ({cnt/len(places)*100:.1f}%)")

    print(f"\n{'='*70}")
    print(f"  카테고리 분포")
    print(f"{'='*70}")
    attraction_total = 0
    excluded_total = 0
    for cat in CATEGORIES:
        cnt = cat_counter.get(cat, 0)
        is_attr = cat in ATTRACTION_CATEGORIES
        marker = "✅" if is_attr else "❌"
        if is_attr:
            attraction_total += cnt
        else:
            excluded_total += cnt
        print(f"  {marker} {cat:14s} {cnt:5d} ({cnt/len(places)*100:.1f}%)")

    print(f"\n  매핑 대상 (✅): {attraction_total} ({attraction_total/len(places)*100:.1f}%)")
    print(f"  매핑 제외 (❌): {excluded_total} ({excluded_total/len(places)*100:.1f}%)")

    # 저장
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f"\n💾 JSON: {OUTPUT_JSON}")

    OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["place_name", "category", "is_attraction", "source", "kto_title"],
        )
        writer.writeheader()
        for r in results:
            writer.writerow({k: r.get(k, "") for k in writer.fieldnames})
    print(f"💾 CSV:  {OUTPUT_CSV}")


if __name__ == "__main__":
    main()
