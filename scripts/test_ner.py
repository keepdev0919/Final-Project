"""
설화+민담 지역별 분포 분석
"""
from __future__ import annotations

import re
from collections import defaultdict
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent))
from common import EXTRACTED_DIR

JEJU_PLACES = {
    "제주시", "서귀포시",
    "애월읍", "구좌읍", "조천읍", "한림읍", "성산읍", "표선읍",
    "남원읍", "대정읍", "안덕읍", "우도면", "추자면", "표선면", "안덕면", "한경면",
    "일도동", "이도동", "삼도동", "용담동", "건입동", "화북동", "삼양동",
    "봉개동", "아라동", "오라동", "연동", "노형동", "외도동", "이호동", "도두동",
    "송산동", "정방동", "중앙동", "천지동", "효돈동", "영천동",
    "대륜동", "대천동", "중문동", "예래동", "호근동", "서홍동", "동홍동",
    "선흘리", "납읍리", "고내리", "한동리", "조천리", "신촌리", "함덕리",
    "김녕리", "세화리", "월정리", "행원리", "송당리", "성읍리", "표선리",
    "가시리", "신례리", "하효리", "위미리", "남원리", "태흥리",
    "하례리", "강정리", "대포리", "중문리", "색달리", "상예리",
    "화순리", "사계리", "모슬포", "인성리", "대정리", "보성리",
    "신도리", "용수리", "저지리", "청수리", "금악리", "동광리",
    "상창리", "광령리", "어음리", "봉성리", "장전리", "고성리",
    "오조리", "시흥리", "온평리", "신산리", "난산리", "수산리",
    "하도리", "종달리", "평대리",
    "한라산", "성산일출봉", "만장굴", "협재", "우도", "마라도", "가파도",
    "비양도", "추자도", "새별오름", "다랑쉬오름", "용눈이오름", "산굼부리",
    "항파두리", "고내봉", "무근성", "제주성", "남문통", "대정현", "정의현", "제주목",
}

# 읍면 단위로 묶기 위한 상위 지역 매핑
REGION_MAP = {
    "제주시": "제주시 (시내)",
    "용담동": "제주시 (시내)", "삼도동": "제주시 (시내)", "일도동": "제주시 (시내)",
    "이도동": "제주시 (시내)", "건입동": "제주시 (시내)", "화북동": "제주시 (시내)",
    "삼양동": "제주시 (시내)", "봉개동": "제주시 (시내)", "아라동": "제주시 (시내)",
    "오라동": "제주시 (시내)", "연동": "제주시 (시내)", "노형동": "제주시 (시내)",
    "외도동": "제주시 (시내)", "이호동": "제주시 (시내)", "도두동": "제주시 (시내)",
    "무근성": "제주시 (시내)", "제주성": "제주시 (시내)", "남문통": "제주시 (시내)",
    "제주목": "제주시 (시내)",
    "애월읍": "애월", "고내리": "애월", "납읍리": "애월", "어음리": "애월",
    "봉성리": "애월", "광령리": "애월", "장전리": "애월", "고내봉": "애월",
    "한림읍": "한림·한경", "한경면": "한림·한경", "용수리": "한림·한경",
    "저지리": "한림·한경", "청수리": "한림·한경", "금악리": "한림·한경",
    "신도리": "한림·한경", "협재": "한림·한경", "비양도": "한림·한경",
    "대정읍": "대정·모슬포", "안덕면": "대정·모슬포", "안덕읍": "대정·모슬포",
    "모슬포": "대정·모슬포", "사계리": "대정·모슬포", "화순리": "대정·모슬포",
    "인성리": "대정·모슬포", "대정리": "대정·모슬포", "대정현": "대정·모슬포",
    "마라도": "대정·모슬포", "가파도": "대정·모슬포",
    "서귀포시": "서귀포 (시내)", "송산동": "서귀포 (시내)", "정방동": "서귀포 (시내)",
    "중앙동": "서귀포 (시내)", "천지동": "서귀포 (시내)", "효돈동": "서귀포 (시내)",
    "영천동": "서귀포 (시내)", "대륜동": "서귀포 (시내)", "대천동": "서귀포 (시내)",
    "호근동": "서귀포 (시내)", "서홍동": "서귀포 (시내)", "동홍동": "서귀포 (시내)",
    "하효리": "서귀포 (시내)",
    "중문동": "중문·예래", "예래동": "중문·예래", "색달리": "중문·예래",
    "대포리": "중문·예래", "중문리": "중문·예래", "상예리": "중문·예래",
    "남원읍": "남원·표선", "표선읍": "남원·표선", "표선면": "남원·표선",
    "남원리": "남원·표선", "태흥리": "남원·표선", "위미리": "남원·표선",
    "하례리": "남원·표선", "신례리": "남원·표선", "성읍리": "남원·표선",
    "표선리": "남원·표선", "가시리": "남원·표선", "신산리": "남원·표선",
    "정의현": "남원·표선",
    "성산읍": "성산·우도", "오조리": "성산·우도", "시흥리": "성산·우도",
    "온평리": "성산·우도", "난산리": "성산·우도", "수산리": "성산·우도",
    "성산일출봉": "성산·우도", "우도": "성산·우도",
    "구좌읍": "구좌", "한동리": "구좌", "조천리": "구좌", "김녕리": "구좌",
    "세화리": "구좌", "월정리": "구좌", "행원리": "구좌", "송당리": "구좌",
    "하도리": "구좌", "종달리": "구좌", "평대리": "구좌", "다랑쉬오름": "구좌",
    "용눈이오름": "구좌", "산굼부리": "구좌",
    "조천읍": "조천", "신촌리": "조천", "함덕리": "조천", "선흘리": "조천",
    "조천리": "조천", "고성리": "조천", "보성리": "조천",
    "한라산": "한라산", "만장굴": "구좌",
    "항파두리": "애월", "동광리": "대정·모슬포", "상창리": "대정·모슬포",
    "강정리": "서귀포 (시내)",
    "추자도": "추자", "추자면": "추자",
}

def extract_places(text: str) -> list[str]:
    return [p for p in JEJU_PLACES if p in text]

def get_region(place: str) -> str:
    return REGION_MAP.get(place, "기타")

def main() -> None:
    region_contents: dict[str, list[str]] = defaultdict(list)

    # 설화
    legend_dir = EXTRACTED_DIR / "legend"
    for f in sorted(legend_dir.glob("*.txt")):
        text = f.read_text(encoding="utf-8")
        title = text.splitlines()[0].strip()
        places = extract_places(text)
        regions = list(dict.fromkeys(get_region(p) for p in places if get_region(p) != "기타"))
        for region in regions:
            region_contents[region].append(f"[설화] {title}")

    # 민담 (W_F만 - 조사장소 있는 것)
    folktale_dir = EXTRACTED_DIR / "folktale"
    for f in sorted(folktale_dir.glob("W-F-*.txt")):
        text = f.read_text(encoding="utf-8")
        title = text.splitlines()[0].strip()
        places = extract_places(text)
        regions = list(dict.fromkeys(get_region(p) for p in places if get_region(p) != "기타"))
        for region in regions:
            region_contents[region].append(f"[민담] {title}")

    print("=== 지역별 설화·민담 분포 ===\n")
    total = 0
    for region, contents in sorted(region_contents.items(), key=lambda x: -len(x[1])):
        count = len(contents)
        total += count
        bar = "█" * min(count, 30)
        print(f"{region:<18} {count:>3}건  {bar}")

    print(f"\n총 GPS 연결 가능 콘텐츠: {total}건")
    print(f"커버 지역 수: {len(region_contents)}개\n")

    print("=== 코스 구성 가능성 분석 ===")
    print("(3건 이상 = 단독 코스 구성 가능)\n")
    viable = [(r, c) for r, c in region_contents.items() if len(c) >= 3]
    not_viable = [(r, c) for r, c in region_contents.items() if len(c) < 3]
    print(f"단독 코스 가능 지역: {len(viable)}개")
    for region, contents in sorted(viable, key=lambda x: -len(x[1])):
        print(f"  {region:<18} {len(contents)}건")
    print(f"\n콘텐츠 부족 지역 (1~2건): {len(not_viable)}개")
    for region, contents in sorted(not_viable, key=lambda x: -len(x[1])):
        print(f"  {region:<18} {len(contents)}건")

if __name__ == "__main__":
    main()
