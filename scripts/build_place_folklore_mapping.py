"""설화-비짓제주 명소 사전 매핑 테이블 빌드.

매핑 방식:
  1단계 (텍스트 매칭, 우선):
    설화 all_places 지명 중 가장 구체적인 수준만 선택
    → 그 지명이 비짓제주 명소의 formatted_address 또는 place_name에 포함되면 매핑

  2단계 (GPS 보조):
    각 지명의 알려진 좌표(folklore_gps.json에서 추출)에서 8km 이내 명소도 포함
    → 주소가 불완전한 명소(성산일출봉 등) 보완

결과 활용:
  course_detail_agent.py에서 map_folklore_to_places()가 이 테이블을 조회.
"""
from __future__ import annotations

import json
import math
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

BASE_DIR = Path(__file__).parent.parent
VISITJEJU_PATH = BASE_DIR / "data" / "processed" / "visitjeju_places_geocoded.json"
FOLKLORE_GPS_PATH = BASE_DIR / "data" / "processed" / "folklore_gps.json"
DB_PATH = BASE_DIR / "storage" / "metadata.db"

# ─── 지명 구체성 점수 ──────────────────────────────────────────────────────────
# 높을수록 구체적. 설화의 all_places에서 가장 높은 점수의 지명만 매핑에 사용.

PLACE_SPECIFICITY: dict[str, int] = {
    # 리/동 단위 (구체, 10)
    "선흘리": 10, "납읍리": 10, "고내리": 10, "한동리": 10, "조천리": 10,
    "신촌리": 10, "함덕리": 10, "김녕리": 10, "세화리": 10, "월정리": 10,
    "행원리": 10, "송당리": 10, "성읍리": 10, "표선리": 10, "가시리": 10,
    "신례리": 10, "하효리": 10, "위미리": 10, "남원리": 10, "태흥리": 10,
    "오조리": 10, "시흥리": 10, "온평리": 10, "신산리": 10, "난산리": 10,
    "수산리": 10, "하도리": 10, "종달리": 10, "평대리": 10, "북촌리": 10,
    "삼달리": 10, "신풍리": 10, "신흥리": 10, "토산리": 10, "명월리": 10,
    "귀덕리": 10, "금능리": 10, "고산리": 10, "두모리": 10, "판포리": 10,
    "무릉리": 10, "수원리": 10, "덕천리": 10, "신천리": 10, "한남리": 10,
    "와산리": 10, "상명리": 10, "월림리": 10, "보목동": 10, "상효동": 10,
    "강정동": 10, "도순동": 10, "법환동": 10, "하원동": 10, "호근동": 10,
    "대포리": 10, "색달리": 10, "상예리": 10, "중문리": 10,
    "삼도동": 10, "용담동": 10, "건입동": 10, "화북동": 10, "삼양동": 10,
    "봉개동": 10, "아라동": 10, "오라동": 10, "연동": 10, "노형동": 10,
    "외도동": 10, "이호동": 10, "도두동": 10,
    "보성리": 10, "고성리": 10,
    # 랜드마크 (구체, 10)
    "성산일출봉": 10, "만장굴": 10, "협재": 10, "우도": 10, "마라도": 10,
    "가파도": 10, "비양도": 10, "추자도": 10, "한라산": 10,
    "새별오름": 10, "다랑쉬오름": 10, "용눈이오름": 10, "산굼부리": 10,
    "항파두리": 10, "고내봉": 10, "무근성": 10,
    # 역사 지명 (준구체, 7)
    "제주성": 7, "남문통": 7, "대정현": 7, "정의현": 7, "제주목": 7,
    # 읍/면 단위 (중간, 5)
    "성산읍": 5, "애월읍": 5, "구좌읍": 5, "조천읍": 5, "한림읍": 5,
    "표선읍": 5, "남원읍": 5, "대정읍": 5, "안덕읍": 5, "한경면": 5,
    "표선면": 5, "안덕면": 5, "우도면": 5, "추자면": 5,
    "예래동": 5, "중문동": 5, "천지동": 5, "효돈동": 5, "영천동": 5,
    "대륜동": 5, "대천동": 5, "서홍동": 5, "동홍동": 5,
    "모슬포": 5, "사계리": 5, "화순리": 5, "인성리": 5, "대정리": 5,
    "동광리": 5, "상창리": 5,
    # 시 단위 (광역, 2) — 단독으로는 매핑하지 않음
    "제주시": 2, "서귀포시": 2,
}

ALL_PLACES = set(PLACE_SPECIFICITY.keys())
MIN_SCORE_FOR_MAPPING = 5  # 시 단위(2) 단독은 매핑 제외


GPS_ASSIST_RADIUS_M = 8_000  # GPS 보조 매핑 반경 (8km)
GPS_ASSIST_SPECIFICITY = 3   # GPS 보조는 낮은 점수 (텍스트 매칭보다 후순위)


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6_371_000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def extract_places(text: str) -> list[str]:
    return [p for p in ALL_PLACES if p in text]


def select_best_places(places: list[str]) -> list[str]:
    """가장 구체적인 수준의 지명들만 반환."""
    if not places:
        return []
    max_score = max((PLACE_SPECIFICITY.get(p, 0) for p in places), default=0)
    if max_score < MIN_SCORE_FOR_MAPPING:
        return []
    return [p for p in places if PLACE_SPECIFICITY.get(p, 0) == max_score]


def build_vj_index(vj_places: list[dict]) -> dict[str, list[dict]]:
    """지명 → 비짓제주 명소 인덱스 구축."""
    idx: dict[str, list[dict]] = defaultdict(list)
    for vj in vj_places:
        lat, lng = vj.get("lat"), vj.get("lng")
        if not lat or not lng:
            continue
        addr = vj.get("formatted_address", "")
        name = vj.get("place_name", "")
        for p in ALL_PLACES:
            if p in addr or p in name:
                idx[p].append(vj)
    return idx


def main() -> None:
    print("데이터 로드 중...")
    with open(VISITJEJU_PATH, encoding="utf-8") as f:
        vj_places = json.load(f)
    with open(FOLKLORE_GPS_PATH, encoding="utf-8") as f:
        gps_folklore = json.load(f)

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    # GPS 없는 설화 본문 로드
    no_gps_rows = conn.execute(
        """
        SELECT m.code_no, m.title, m.summary, m.category, d.normalized_text
        FROM metadata m
        JOIN documents d ON m.code_no = d.code_no
        WHERE m.lat IS NULL
        """
    ).fetchall()

    # GPS 없는 설화의 all_places: normalized_text에서 NER
    no_gps_map: dict[str, dict] = {}
    for r in no_gps_rows:
        places = extract_places(r["normalized_text"] or "")
        no_gps_map[r["code_no"]] = {
            "code_no": r["code_no"],
            "title": r["title"],
            "summary": r["summary"] or "",
            "final_category": r["category"] or "",
            "all_places": places,
        }

    print(f"비짓제주 명소: {len(vj_places)}개")
    print(f"GPS 확정 설화: {len(gps_folklore)}개")
    print(f"GPS 없는 설화: {len(no_gps_rows)}개 (지명 추출 대상)")

    # 지명별 대표 좌표 추출 (folklore_gps.json primary_place 기반)
    place_coords: dict[str, tuple[float, float]] = {}
    for f in gps_folklore:
        pp = f.get("primary_place", "")
        if pp and f.get("lat") and f.get("lng") and pp not in place_coords:
            place_coords[pp] = (f["lat"], f["lng"])
    print(f"지명 좌표 커버: {len(place_coords)}개 지명")

    print("\n비짓제주 지명 인덱스 구축 중...")
    vj_idx = build_vj_index(vj_places)
    print(f"지명 인덱스: {len(vj_idx)}개 지명 커버")

    # ─── 매핑 테이블 생성 ────────────────────────────────────────────────────
    conn.execute("DROP TABLE IF EXISTS place_folklore_mapping")
    conn.execute(
        """
        CREATE TABLE place_folklore_mapping (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            place_name       TEXT NOT NULL,
            place_lat        REAL,
            place_lng        REAL,
            folklore_code_no TEXT NOT NULL,
            folklore_title   TEXT,
            folklore_summary TEXT,
            final_category   TEXT,
            matched_place    TEXT,   -- 매핑에 사용된 지명
            specificity      INTEGER -- 지명 구체성 점수
        )
        """
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_pfm_place ON place_folklore_mapping(place_name)"
    )

    rows_to_insert: list[tuple] = []
    seen: set[tuple] = set()  # (place_name, folklore_code_no) 중복 방지

    def add_mapping(vj: dict, folklore: dict, matched_place: str, spec: int) -> None:
        key = (vj["place_name"], folklore["code_no"])
        if key in seen:
            return
        seen.add(key)
        rows_to_insert.append((
            vj["place_name"],
            vj.get("lat"),
            vj.get("lng"),
            folklore["code_no"],
            folklore.get("title", ""),
            folklore.get("summary", ""),
            folklore.get("final_category", ""),
            matched_place,
            spec,
        ))

    # ─── GPS 있는 설화 매핑 ───────────────────────────────────────────────────
    gps_mapped = 0
    for f in gps_folklore:
        best = select_best_places(f.get("all_places", []))
        if not best:
            continue
        spec = PLACE_SPECIFICITY.get(best[0], 0)
        for p in best:
            for vj in vj_idx.get(p, []):
                add_mapping(vj, f, p, spec)
        if best:
            gps_mapped += 1

    # ─── GPS 없는 설화 매핑 ───────────────────────────────────────────────────
    no_gps_mapped = 0
    for code_no, f in no_gps_map.items():
        best = select_best_places(f["all_places"])
        if not best:
            continue
        spec = PLACE_SPECIFICITY.get(best[0], 0)
        for p in best:
            for vj in vj_idx.get(p, []):
                add_mapping(vj, f, p, spec)
        if best:
            no_gps_mapped += 1

    # ─── GPS 보조 매핑 (텍스트 매칭 미커버 명소 보완) ────────────────────────
    # 각 지명의 알려진 좌표에서 GPS_ASSIST_RADIUS_M 내 명소를 추가 연결
    # 이미 텍스트 매칭으로 연결된 (명소, 설화) 쌍은 seen으로 중복 방지됨
    gps_assist_added = 0
    all_folklore_list = list(gps_folklore) + [
        {
            "code_no": f["code_no"],
            "title": f["title"],
            "summary": f["summary"],
            "final_category": f["final_category"],
            "all_places": f["all_places"],
        }
        for f in no_gps_map.values()
    ]

    for f in all_folklore_list:
        best = select_best_places(f.get("all_places", []))
        if not best:
            continue
        for p in best:
            coords = place_coords.get(p)
            if not coords:
                continue
            plat, plng = coords
            for vj in vj_places:
                vlat, vlng = vj.get("lat"), vj.get("lng")
                if not vlat or not vlng:
                    continue
                if haversine_m(plat, plng, vlat, vlng) <= GPS_ASSIST_RADIUS_M:
                    before = len(seen)
                    add_mapping(vj, f, p + "(GPS)", GPS_ASSIST_SPECIFICITY)
                    if len(seen) > before:
                        gps_assist_added += 1

    # ─── DB 저장 ─────────────────────────────────────────────────────────────
    conn.executemany(
        """
        INSERT INTO place_folklore_mapping
            (place_name, place_lat, place_lng, folklore_code_no,
             folklore_title, folklore_summary, final_category,
             matched_place, specificity)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows_to_insert,
    )
    conn.commit()

    total = len(rows_to_insert)
    print(f"\n완료!")
    print(f"  GPS 있는 설화 매핑: {gps_mapped}개 설화")
    print(f"  GPS 없는 설화 매핑: {no_gps_mapped}개 설화")
    print(f"  GPS 보조 매핑 추가: {gps_assist_added}쌍")
    print(f"  총 (명소, 설화) 매핑 쌍: {total:,}개")

    # ─── 결과 샘플 출력 ───────────────────────────────────────────────────────
    print("\n성산일출봉 매핑 샘플:")
    rows = conn.execute(
        """
        SELECT folklore_title, matched_place, specificity, final_category
        FROM place_folklore_mapping
        WHERE place_name = '성산일출봉'
        ORDER BY specificity DESC
        LIMIT 8
        """
    ).fetchall()
    if rows:
        for r in rows:
            print(f"  [{r['specificity']}점/{r['matched_place']}] {r['folklore_title'][:40]} ({r['final_category']})")
    else:
        print("  (결과 없음)")

    print("\n협재 매핑 샘플:")
    rows = conn.execute(
        """
        SELECT folklore_title, matched_place, specificity
        FROM place_folklore_mapping
        WHERE place_name = '협재해수욕장' OR place_name LIKE '%협재%'
        ORDER BY specificity DESC
        LIMIT 5
        """
    ).fetchall()
    for r in rows:
        print(f"  [{r['specificity']}점/{r['matched_place']}] {r['folklore_title'][:40]}")

    conn.close()


if __name__ == "__main__":
    main()
