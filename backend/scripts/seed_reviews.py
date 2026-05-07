"""주요 코스 장소에 초기 리뷰 시드 데이터를 삽입한다.
중복 실행 안전: seed_device_ 데이터가 이미 있으면 해당 장소 skip.
"""
import json
import random
import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent.parent.parent / "storage" / "metadata.db"

PLACES_SEED = [
    {
        "name": "성산일출봉(UNESCO 세계자연유산)",
        "dist": {"감동이에요": 18, "역사적이에요": 14, "신기해요": 8, "소름 돋아요": 4, "무서워요": 2},
        "notes": ["해가 뜰 때 설화가 눈앞에 펼쳐지는 느낌이었어요", "정상에서 바라본 제주 바다가 말로 표현이 안 돼요"],
    },
    {
        "name": "비자림",
        "dist": {"감동이에요": 20, "소름 돋아요": 10, "신기해요": 7, "역사적이에요": 5, "무서워요": 2},
        "notes": ["천년 된 나무 앞에서 설화가 더 실감났어요", "비자나무 숲이 생각보다 웅장했어요", "동행자가 들려준 이야기에 소름이 돋았어요"],
    },
    {
        "name": "산방산",
        "dist": {"소름 돋아요": 16, "역사적이에요": 14, "감동이에요": 8, "신기해요": 6, "무서워요": 4},
        "notes": ["산방덕이 설화가 산 모양과 딱 맞아떨어졌어요", "바위 동굴 안에서 설화를 들으니 진짜 같았어요"],
    },
    {
        "name": "항파두리항몽유적지",
        "dist": {"역사적이에요": 22, "감동이에요": 12, "소름 돋아요": 6, "신기해요": 4, "무서워요": 2},
        "notes": ["삼별초 이야기를 현장에서 들으니 교과서랑 완전 달랐어요", "역사의 무게가 느껴지는 곳이었어요"],
    },
    {
        "name": "용눈이오름",
        "dist": {"소름 돋아요": 18, "신기해요": 14, "감동이에요": 8, "역사적이에요": 4, "무서워요": 4},
        "notes": ["분화구 안에서 용 설화를 들으니 진짜 용이 살 것 같았어요", "오름 형태 자체가 신비로웠어요"],
    },
    {
        "name": "제주민속촌",
        "dist": {"역사적이에요": 20, "신기해요": 12, "감동이에요": 10, "소름 돋아요": 4, "무서워요": 2},
        "notes": ["조상들의 생활 방식을 설화와 함께 배웠어요", "무속 의식 재현 장면에서 소름이 돋았어요"],
    },
    {
        "name": "섭지코지",
        "dist": {"감동이에요": 18, "소름 돋아요": 12, "신기해요": 8, "역사적이에요": 6, "무서워요": 4},
        "notes": ["절벽 위에서 설화를 들으니 바람도 이야기를 전하는 것 같았어요"],
    },
    {
        "name": "천지연폭포",
        "dist": {"감동이에요": 20, "신기해요": 12, "소름 돋아요": 6, "역사적이에요": 4, "무서워요": 2},
        "notes": ["폭포 소리와 함께 설화를 들으니 몰입감이 달랐어요", "선녀 이야기가 실제로 일어난 것 같았어요"],
    },
    {
        "name": "한림공원(협재굴, 쌍용굴)",
        "dist": {"소름 돋아요": 18, "신기해요": 16, "감동이에요": 6, "역사적이에요": 4, "무서워요": 4},
        "notes": ["동굴 안에서 용 설화를 들으니 정말 무서웠어요", "석회동굴과 용암동굴이 함께 있다는 게 신기했어요"],
    },
    {
        "name": "주상절리대(중문대포해안)",
        "dist": {"신기해요": 20, "감동이에요": 12, "소름 돋아요": 8, "역사적이에요": 4, "무서워요": 2},
        "notes": ["수천만 년 전 화산이 만든 지형에서 설화를 들으니 스케일이 달랐어요"],
    },
    {
        "name": "우도(해양도립공원)",
        "dist": {"감동이에요": 22, "신기해요": 10, "역사적이에요": 8, "소름 돋아요": 4, "무서워요": 2},
        "notes": ["섬 안의 섬, 우도에서 해녀 설화를 들었어요", "바다 빛깔과 설화가 잘 어울렸어요"],
    },
    {
        "name": "협재해녀의집",
        "dist": {"역사적이에요": 18, "감동이에요": 14, "신기해요": 8, "소름 돋아요": 4, "무서워요": 2},
        "notes": ["해녀 할머니가 직접 들려주는 것 같은 생생한 이야기였어요"],
    },
    {
        "name": "오설록티뮤지엄",
        "dist": {"신기해요": 16, "감동이에요": 16, "역사적이에요": 8, "소름 돋아요": 4, "무서워요": 2},
        "notes": ["차밭 풍경과 제주 설화가 묘하게 잘 어울렸어요"],
    },
    {
        "name": "카멜리아힐",
        "dist": {"감동이에요": 26, "신기해요": 8, "역사적이에요": 4, "소름 돋아요": 4, "무서워요": 2},
        "notes": ["동백꽃 사이에서 들은 설화가 가장 아름다웠어요"],
    },
    {
        "name": "보롬왓",
        "dist": {"감동이에요": 22, "신기해요": 12, "소름 돋아요": 4, "역사적이에요": 4, "무서워요": 2},
        "notes": ["메밀꽃밭과 설화의 조합이 예상보다 훨씬 좋았어요"],
    },
    {
        "name": "월정리해수욕장",
        "dist": {"감동이에요": 20, "소름 돋아요": 10, "신기해요": 8, "역사적이에요": 4, "무서워요": 2},
        "notes": ["투명한 바다에서 해양 설화를 들으니 더 생생했어요"],
    },
    {
        "name": "세화해변",
        "dist": {"감동이에요": 24, "신기해요": 8, "역사적이에요": 6, "소름 돋아요": 4, "무서워요": 2},
        "notes": ["잔잔한 해변에서 들은 설화가 마음에 오래 남았어요"],
    },
    {
        "name": "광치기해변",
        "dist": {"소름 돋아요": 16, "감동이에요": 14, "신기해요": 8, "역사적이에요": 6, "무서워요": 4},
        "notes": ["검은 현무암 해변과 어두운 설화가 딱 맞는 분위기였어요"],
    },
    {
        "name": "다랑쉬오름(월랑봉)",
        "dist": {"소름 돋아요": 20, "역사적이에요": 12, "감동이에요": 8, "신기해요": 6, "무서워요": 4},
        "notes": ["4.3 역사와 오름 설화가 겹쳐져 가슴이 먹먹했어요"],
    },
    {
        "name": "새연교",
        "dist": {"역사적이에요": 18, "감동이에요": 14, "신기해요": 8, "소름 돋아요": 4, "무서워요": 2},
        "notes": ["다리 위에서 서귀포 설화를 들으니 바다가 무대 같았어요"],
    },
]

def seed():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS place_reviews (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            place_name TEXT    NOT NULL,
            tags       TEXT    NOT NULL,
            device_id  TEXT    NOT NULL,
            note       TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(place_name, device_id) ON CONFLICT REPLACE
        )
        """
    )

    device_counter = 1
    seeded = 0

    for place in PLACES_SEED:
        existing = conn.execute(
            "SELECT COUNT(*) FROM place_reviews WHERE device_id LIKE 'seed_%' AND place_name = ?",
            (place["name"],),
        ).fetchone()[0]
        if existing > 0:
            print(f"  SKIP (already seeded): {place['name']}")
            continue

        tags_flat: list[str] = []
        for tag, count in place["dist"].items():
            tags_flat.extend([tag] * count)
        random.shuffle(tags_flat)

        notes = place.get("notes", [])
        note_idx = 0

        for tag in tags_flat:
            note = notes[note_idx] if note_idx < len(notes) else None
            if note:
                note_idx += 1
            conn.execute(
                "INSERT OR REPLACE INTO place_reviews (place_name, tags, note, device_id) VALUES (?, ?, ?, ?)",
                (
                    place["name"],
                    json.dumps([tag], ensure_ascii=False),
                    note,
                    f"seed_{device_counter:05d}",
                ),
            )
            device_counter += 1
            seeded += 1

        print(f"  Seeded {sum(place['dist'].values())} reviews: {place['name']}")

    conn.commit()
    conn.close()
    print(f"\n총 {seeded}개 리뷰 시드 완료")


if __name__ == "__main__":
    seed()
