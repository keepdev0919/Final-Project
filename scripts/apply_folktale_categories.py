"""미분류 설화 212개 분류 결과를 DB에 적용.

1. CSV의 자동분류 결과 로드
2. 명백한 오류 5개 수동 override 적용
3. place_folklore_mapping.final_category 업데이트
4. 검증
"""
from __future__ import annotations

import csv
import sqlite3
from pathlib import Path

BASE = Path(__file__).parent.parent
CSV_PATH = BASE / "docs" / "experiments" / "folktale_categorized_212.csv"
DB_PATH = BASE / "storage" / "metadata.db"

# 명백한 분류 오류 수동 보정 (검증 단계에서 발견)
MANUAL_OVERRIDES: dict[str, str] = {
    "W_F_063": "무속신화·신격 전승",  # 해와 달이 뒌 오누이 — 천지창조 모티프
    "W_F_650": "무속신화·신격 전승",  # 한라산 산신 설문대할망 — 창조여신
    "W_F_620": "무속신화·신격 전승",  # 삼승할망과 구삼승할망 — 산육신
    "W_F_528": "초자연 존재담",        # 베암으로 환생한 처녀 — 변신담
    "W_F_606": "마을 공동체 전승",      # 고종달과 차귀도 — 풍수설화/지명유래
}


def main() -> None:
    # 1. CSV 로드
    with open(CSV_PATH, encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))

    # 2. override 적용
    final_categories: dict[str, str] = {}
    override_count = 0
    for r in rows:
        code = r["code_no"]
        cat = r["final_category"]
        if code in MANUAL_OVERRIDES:
            cat = MANUAL_OVERRIDES[code]
            override_count += 1
            print(f"  override: {code} {r['title'][:25]:25s} {r['final_category']} → {cat}")
        final_categories[code] = cat

    print(f"\n총 {len(final_categories)}개, override {override_count}개 적용\n")

    # 3. DB 업데이트
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 업데이트 전 카테고리 분포
    print("=== 업데이트 전 분포 (전체 place_folklore_mapping) ===")
    rows_before = cursor.execute("""
        SELECT final_category, COUNT(*) FROM place_folklore_mapping
        GROUP BY final_category ORDER BY COUNT(*) DESC
    """).fetchall()
    for cat, cnt in rows_before:
        print(f"  {cat or '(NULL)':25s} {cnt}")

    # 백업 — 영향받는 행 수 미리 확인
    affected_rows = cursor.execute("""
        SELECT COUNT(*) FROM place_folklore_mapping WHERE final_category = '민담'
    """).fetchone()[0]
    print(f"\n수정 대상 매핑 row: {affected_rows}개 ('민담' 라벨)")

    # 업데이트 실행
    update_count = 0
    for code, cat in final_categories.items():
        result = cursor.execute("""
            UPDATE place_folklore_mapping
            SET final_category = ?
            WHERE folklore_code_no = ? AND final_category = '민담'
        """, (cat, code))
        update_count += result.rowcount

    conn.commit()
    print(f"\n✅ 업데이트 완료: {update_count}개 row 변경")

    # 4. 검증
    print("\n=== 업데이트 후 분포 ===")
    rows_after = cursor.execute("""
        SELECT final_category, COUNT(*) FROM place_folklore_mapping
        GROUP BY final_category ORDER BY COUNT(*) DESC
    """).fetchall()
    for cat, cnt in rows_after:
        print(f"  {cat or '(NULL)':25s} {cnt}")

    print("\n=== 카테고리별 distinct 설화 수 (전체) ===")
    rows_dist = cursor.execute("""
        SELECT final_category, COUNT(DISTINCT folklore_code_no) FROM place_folklore_mapping
        GROUP BY final_category ORDER BY COUNT(DISTINCT folklore_code_no) DESC
    """).fetchall()
    for cat, cnt in rows_dist:
        print(f"  {cat or '(NULL)':25s} {cnt}개 설화")

    conn.close()


if __name__ == "__main__":
    main()
