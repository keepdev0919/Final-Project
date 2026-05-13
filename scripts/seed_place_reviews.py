"""매핑된 장소 중 리뷰 없는 곳에 카테고리 기반 시드 리뷰 1개씩 INSERT.

흐름:
  1. place_folklore_mapping에서 attraction 장소 + 주된 카테고리 추출
  2. place_reviews에 이미 리뷰 있는 장소 제외
  3. 카테고리별 리뷰 풀에서 랜덤 선택 + 가짜 device_id 분산
  4. INSERT (UNIQUE(place_name, device_id) 충돌 시 REPLACE)
"""
from __future__ import annotations

import json
import random
import sqlite3
import uuid
from pathlib import Path

BASE = Path(__file__).parent.parent
DB_PATH = BASE / "storage" / "metadata.db"

random.seed(42)  # 재현 가능성

# ─── 카테고리별 리뷰 풀 ───────────────────────────────────────────────────────

REVIEW_POOL: dict[str, dict] = {
    "초자연 존재담": {
        "notes": [
            "도체비 이야기 듣고 진짜 으스스했어요. 분위기 묘함.",
            "낮인데도 뭔가 서늘한 기운... 옛날 이야기 떠올라서 그런가.",
            "친구랑 같이 갔는데 둘 다 소름 돋았어요.",
            "전해 내려오는 이야기 들으니 이 자리가 다르게 보이네요.",
            "혼자 가긴 좀 그래도 분위기 진짜 특별해요.",
            "기이한 이야기가 깃든 곳이라 그런지 묘하게 끌림.",
            "도깨비 출몰담 들으니 밤엔 절대 못 올 듯.",
            "옛 어른들이 무서워했던 자리라는 게 느껴져요.",
        ],
        "tags": ["무서워요", "소름 돋아요", "신기해요"],
    },
    "무속신화·신격 전승": {
        "notes": [
            "신령이 좌정한 자리라는 게 와닿더라구요. 마음이 차분.",
            "본향당 이야기 듣고 절로 숙연해졌어요.",
            "여기 깃든 신화가 진짜 깊이 있더라.",
            "옛 제주의 신앙이 살아있는 자리.",
            "조용히 둘러보기 좋아요. 함부로 발 못 디딜 듯한 느낌.",
            "심방이 본풀이 부르는 모습이 떠오르는 자리.",
            "신성한 공간이라는 게 분위기로 느껴짐.",
            "옛 사람들이 왜 여기를 신성시 했는지 알 것 같아요.",
        ],
        "tags": ["역사적이에요", "감동이에요", "신기해요"],
    },
    "해양·어촌 전승": {
        "notes": [
            "바람 맞으면서 영등할망 이야기 들으니 바다가 다르게 보여요.",
            "해녀 분들이 대대로 지킨 자리라는 게 느껴짐.",
            "파도 소리 들으면서 옛 이야기 떠올리기 좋아요.",
            "어촌 마을 정취 그대로 남아있어요.",
            "용왕 이야기 듣고 바다 보니 신비롭더라.",
            "물질하던 분들의 숨소리가 들리는 것 같아요.",
            "영등 달에는 진짜 특별한 자리겠어요.",
            "바다와 사람의 이야기가 같이 흐르는 곳.",
        ],
        "tags": ["감동이에요", "역사적이에요", "신기해요"],
    },
    "마을 공동체 전승": {
        "notes": [
            "마을 사람들이 대대로 지켜온 자리라는 게 느껴졌어요.",
            "당제 이야기 들으니 마을 전체가 한 식구 같았던 시절이 보임.",
            "주민분들이 자부심 가지고 가꾸는 게 보여요.",
            "조용한 동네인데 깊이가 있어요.",
            "마을 어른들 이야기 듣고 가니 더 좋았어요.",
            "공동체가 살아있는 자리. 정겹습니다.",
            "옛 마을의 풍습이 아직 남아있는 느낌.",
        ],
        "tags": ["역사적이에요", "감동이에요"],
    },
    "생활민담·교훈담": {
        "notes": [
            "옛날 사람들 지혜에 감탄. 이야기가 살아있는 곳.",
            "단순한 이야기인데 묘하게 울림이 있어요.",
            "할머니께 들었던 이야기 같은 느낌.",
            "사람 사는 이야기라 친근하게 다가와요.",
            "재밌게 들었어요. 교훈도 있고.",
            "옛 인물 일화가 깃든 자리라니 새롭게 보임.",
            "이야기 한 자락에 마을 한 시대가 담겨있네요.",
        ],
        "tags": ["감동이에요", "역사적이에요"],
    },
}

# ─── 가짜 device_id 풀 ───────────────────────────────────────────────────────

# seed_ 접두사 → 진짜 사용자 리뷰와 구분, 나중에 일괄 삭제 가능
SEED_DEVICE_POOL = [f"seed_{uuid.UUID(int=i).hex[:12]}" for i in range(1000, 1050)]


# ─── 메인 ─────────────────────────────────────────────────────────────────────

def main() -> None:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    # 1) attraction 장소 + 주된 final_category
    rows = conn.execute("""
        SELECT
            place_name,
            final_category,
            COUNT(*) AS cnt
        FROM place_folklore_mapping
        WHERE specificity >= 5
        GROUP BY place_name, final_category
    """).fetchall()

    place_main_cat: dict[str, str] = {}
    place_score: dict[str, int] = {}
    for r in rows:
        p = r["place_name"]
        cat = r["final_category"]
        if not cat or cat == "민담":
            continue
        if cat not in REVIEW_POOL:
            continue
        if r["cnt"] > place_score.get(p, 0):
            place_main_cat[p] = cat
            place_score[p] = r["cnt"]

    print(f"매핑 attraction 장소: {len(place_main_cat)}개")

    # 2) 이미 리뷰 있는 장소 제외
    existing = {
        r[0] for r in conn.execute(
            "SELECT DISTINCT place_name FROM place_reviews"
        ).fetchall()
    }
    todo = [p for p in place_main_cat if p not in existing]
    print(f"이미 리뷰 있는 장소: {len(existing)}개")
    print(f"이번 시드 대상: {len(todo)}개\n")

    # 3) INSERT
    inserted = 0
    by_cat: dict[str, int] = {}
    for place in todo:
        cat = place_main_cat[place]
        pool = REVIEW_POOL[cat]
        note = random.choice(pool["notes"])

        # 태그 1~2개 랜덤
        n_tags = random.choice([1, 1, 2])  # 1개가 더 자주
        tag_count = min(n_tags, len(pool["tags"]))
        tags = random.sample(pool["tags"], tag_count)

        device_id = random.choice(SEED_DEVICE_POOL)

        # 같은 device_id가 같은 장소에 충돌하면 REPLACE
        conn.execute("""
            INSERT INTO place_reviews (place_name, tags, note, device_id)
            VALUES (?, ?, ?, ?)
        """, (place, json.dumps(tags, ensure_ascii=False), note, device_id))
        inserted += 1
        by_cat[cat] = by_cat.get(cat, 0) + 1

    conn.commit()

    print(f"✅ {inserted}개 리뷰 INSERT 완료\n")
    print("카테고리별 시드 분포:")
    for cat, cnt in sorted(by_cat.items(), key=lambda x: -x[1]):
        print(f"  {cat:25s} {cnt}개")

    # 4) 검증
    print("\n=== 검증: 매핑 attraction 중 리뷰 있는 비율 ===")
    has_review = conn.execute("""
        SELECT COUNT(DISTINCT place_name) FROM place_reviews
        WHERE place_name IN (SELECT DISTINCT place_name FROM place_folklore_mapping WHERE specificity >= 5)
    """).fetchone()[0]
    print(f"  리뷰 있는 매핑 장소: {has_review}/{len(place_main_cat)}")

    print("\n=== 샘플 5개 ===")
    samples = conn.execute("""
        SELECT pr.place_name, pr.tags, pr.note, pr.device_id
        FROM place_reviews pr
        WHERE pr.device_id LIKE 'seed_%'
        ORDER BY RANDOM() LIMIT 5
    """).fetchall()
    for r in samples:
        print(f"  📍 {r['place_name']}")
        print(f"     tags: {r['tags']}, note: {r['note']}")
        print(f"     device: {r['device_id']}\n")

    conn.close()


if __name__ == "__main__":
    main()
