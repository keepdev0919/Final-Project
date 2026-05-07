# Place Review Community Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 장소별 설화 인상 태그 + 경험 노트를 수집해 지도와 일지에 커뮤니티 반응을 보여주는 소셜 레이어를 추가한다.

**Architecture:** 백엔드에 `place_reviews` SQLite 테이블과 2개 REST 엔드포인트를 추가하고, iOS에서 채팅 종료 후 리뷰 시트를 표시해 제출한다. 설화 상세 화면에 커뮤니티 반응 섹션을 추가하고, 여행 일지 생성 시 커뮤니티 데이터를 GPT 프롬프트에 주입한다.

**Tech Stack:** FastAPI + SQLite (백엔드), SwiftUI + URLSession (iOS), `APIClient.shared.get/postData` 패턴

---

## 파일 구조

**백엔드 — 생성/수정:**
- `backend/services/db.py` — `place_reviews` 테이블 CREATE 추가
- `backend/models/schemas.py` — `PlaceReviewRequest`, `PlaceReviewsResponse` 스키마 추가
- `backend/routers/review.py` — **신규** POST /place/review, GET /place/reviews/{name}
- `backend/main.py` — review 라우터 등록
- `backend/routers/travel.py` — journal 프롬프트에 커뮤니티 컨텍스트 주입
- `backend/scripts/seed_reviews.py` — **신규** 시드 데이터 스크립트

**iOS — 생성/수정:**
- `ios/JejuFolklore/Sources/Models/PlaceReview.swift` — **신규** `PlaceReviewsResponse` Decodable 모델
- `ios/JejuFolklore/Sources/Services/DeviceIdentity.swift` — **신규** UUID 생성·저장
- `ios/JejuFolklore/Sources/Services/APIClient.swift` — 리뷰 메서드 2개 추가
- `ios/JejuFolklore/Sources/Views/PlaceReviewSheet.swift` — **신규** 태그 선택 + 노트 입력 시트
- `ios/JejuFolklore/Sources/Views/ExploreView.swift` — 리뷰 시트 트리거 + 핀 필터 추가
- `ios/JejuFolklore/Sources/Views/FolkloreDetailView.swift` — 커뮤니티 반응 섹션 추가

---

## Task 1: DB 테이블 추가

**Files:**
- Modify: `backend/services/db.py`
- Test: `backend/tests/test_review_api.py` (Task 3에서 생성, 여기선 수동 확인)

- [ ] **Step 1: `get_db_connection()` 함수에 `place_reviews` 테이블 생성 추가**

`backend/services/db.py`의 `get_db_connection()` 내부, `conn.commit()` 바로 위에 추가:

```python
conn.execute(
    """
    CREATE TABLE IF NOT EXISTS place_reviews (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        place_name TEXT    NOT NULL,
        tags       TEXT    NOT NULL,
        note       TEXT,
        device_id  TEXT    NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(place_name, device_id) ON CONFLICT REPLACE
    )
    """
)
```

- [ ] **Step 2: 테이블 생성 확인**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/backend
python3 -c "
from services.db import get_db_connection
conn = get_db_connection()
tables = conn.execute(\"SELECT name FROM sqlite_master WHERE type='table'\").fetchall()
print([r[0] for r in tables])
"
```

기대 출력: 기존 테이블 목록에 `place_reviews` 포함

- [ ] **Step 3: 커밋**

```bash
git add backend/services/db.py
git commit -m "feat: add place_reviews table to SQLite schema"
```

---

## Task 2: 백엔드 스키마 추가

**Files:**
- Modify: `backend/models/schemas.py`

- [ ] **Step 1: `schemas.py` 파일 끝에 두 스키마 추가**

```python
VALID_REVIEW_TAGS = {"소름 돋아요", "감동이에요", "신기해요", "무서워요", "역사적이에요"}

class PlaceReviewRequest(BaseModel):
    place_name: str
    tags: list[str]
    note: str | None = None
    device_id: str

class PlaceReviewsResponse(BaseModel):
    total: int
    tag_counts: dict[str, int]
    recent_notes: list[str]
```

- [ ] **Step 2: import 확인**

`schemas.py` 상단에 이미 `from pydantic import BaseModel`이 있는지 확인. 없으면 추가.

- [ ] **Step 3: 커밋**

```bash
git add backend/models/schemas.py
git commit -m "feat: add PlaceReviewRequest and PlaceReviewsResponse schemas"
```

---

## Task 3: 리뷰 라우터 생성 + 테스트

**Files:**
- Create: `backend/routers/review.py`
- Create: `backend/tests/test_review_api.py`

- [ ] **Step 1: 테스트 파일 먼저 작성 (`backend/tests/test_review_api.py`)**

```python
import json
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_submit_review_success():
    resp = client.post("/place/review", json={
        "place_name": "비자림",
        "tags": ["감동이에요", "신기해요"],
        "note": "천년 나무 앞에서 설화가 실감났어요",
        "device_id": "test-device-001"
    })
    assert resp.status_code == 201
    assert resp.json()["ok"] is True

def test_submit_review_invalid_tag():
    resp = client.post("/place/review", json={
        "place_name": "비자림",
        "tags": ["없는태그"],
        "device_id": "test-device-002"
    })
    assert resp.status_code == 400

def test_submit_review_note_too_long():
    resp = client.post("/place/review", json={
        "place_name": "비자림",
        "tags": ["감동이에요"],
        "note": "a" * 201,
        "device_id": "test-device-003"
    })
    assert resp.status_code == 400

def test_get_reviews_returns_counts():
    # 먼저 리뷰 제출
    client.post("/place/review", json={
        "place_name": "test_place_unique_xyz",
        "tags": ["소름 돋아요"],
        "device_id": "test-device-get-001"
    })
    resp = client.get("/place/reviews/test_place_unique_xyz")
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] >= 1
    assert data["tag_counts"]["소름 돋아요"] >= 1
    assert "recent_notes" in data

def test_get_reviews_empty_place():
    resp = client.get("/place/reviews/존재하지않는장소99999")
    assert resp.status_code == 200
    assert resp.json()["total"] == 0
```

- [ ] **Step 2: 테스트 실행 — FAIL 확인**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/backend
python -m pytest tests/test_review_api.py -v 2>&1 | head -20
```

기대: `ImportError` 또는 `404` — 라우터 미등록 상태

- [ ] **Step 3: `backend/routers/review.py` 구현**

```python
"""장소 리뷰 엔드포인트."""
import json
from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from models.schemas import PlaceReviewRequest, PlaceReviewsResponse, VALID_REVIEW_TAGS
from services.db import get_db_connection

router = APIRouter(prefix="/place", tags=["review"])
limiter = Limiter(key_func=get_remote_address)


@router.post("/review", status_code=201)
@limiter.limit("30/minute")
def submit_review(request: Request, body: PlaceReviewRequest):
    if not body.tags:
        raise HTTPException(status_code=400, detail="태그를 1개 이상 선택해주세요.")
    invalid = set(body.tags) - VALID_REVIEW_TAGS
    if invalid:
        raise HTTPException(status_code=400, detail=f"유효하지 않은 태그: {invalid}")
    if body.note and len(body.note) > 200:
        raise HTTPException(status_code=400, detail="노트는 200자 이내로 작성해주세요.")

    conn = get_db_connection()
    conn.execute(
        """
        INSERT OR REPLACE INTO place_reviews (place_name, tags, note, device_id)
        VALUES (?, ?, ?, ?)
        """,
        (
            body.place_name,
            json.dumps(body.tags, ensure_ascii=False),
            body.note,
            body.device_id,
        ),
    )
    conn.commit()
    return {"ok": True}


@router.get("/reviews/{place_name}", response_model=PlaceReviewsResponse)
def get_reviews(place_name: str):
    conn = get_db_connection()
    rows = conn.execute(
        "SELECT tags, note FROM place_reviews WHERE place_name = ? ORDER BY created_at DESC",
        (place_name,),
    ).fetchall()

    total = len(rows)
    tag_counts = {tag: 0 for tag in VALID_REVIEW_TAGS}
    recent_notes: list[str] = []

    for row in rows:
        for tag in json.loads(row["tags"]):
            if tag in tag_counts:
                tag_counts[tag] += 1
        if row["note"] and len(recent_notes) < 3:
            recent_notes.append(row["note"])

    return PlaceReviewsResponse(
        total=total,
        tag_counts=tag_counts,
        recent_notes=recent_notes,
    )
```

- [ ] **Step 4: `main.py`에 라우터 등록**

`backend/main.py`에서 import 줄에 `review` 추가:
```python
from routers import pins, chat, course, tts, tourist, place, travel, review
```

그리고 `app.include_router` 줄 추가:
```python
app.include_router(review.router)
```

- [ ] **Step 5: 테스트 실행 — PASS 확인**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/backend
python -m pytest tests/test_review_api.py -v
```

기대: 5개 모두 PASSED

- [ ] **Step 6: 커밋**

```bash
git add backend/routers/review.py backend/tests/test_review_api.py backend/main.py
git commit -m "feat: add place review API (POST /place/review, GET /place/reviews/{name})"
```

---

## Task 4: 시드 데이터 스크립트

**Files:**
- Create: `backend/scripts/seed_reviews.py`

- [ ] **Step 1: `backend/scripts/seed_reviews.py` 작성**

```python
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
            note       TEXT,
            device_id  TEXT    NOT NULL,
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
```

- [ ] **Step 2: 시드 스크립트 실행**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프
python backend/scripts/seed_reviews.py
```

기대 출력: 각 장소별 "Seeded N reviews: 장소명", 마지막 줄에 총 개수

- [ ] **Step 3: 결과 확인**

```bash
python3 -c "
import sqlite3
conn = sqlite3.connect('storage/metadata.db')
rows = conn.execute('SELECT place_name, COUNT(*) FROM place_reviews GROUP BY place_name LIMIT 5').fetchall()
for r in rows: print(r[0], '-', r[1], '건')
"
```

- [ ] **Step 4: 커밋**

```bash
git add backend/scripts/seed_reviews.py
git commit -m "feat: add seed_reviews.py with 20 curated Jeju places"
```

---

## Task 5: 여행 일지 커뮤니티 컨텍스트 주입

**Files:**
- Modify: `backend/routers/travel.py`

- [ ] **Step 1: `generate_journal` 함수 상단에서 리뷰 집계 조회 추가**

`backend/routers/travel.py`의 `async def generate_journal` 함수 안에서 `places_text = ...` 줄 바로 앞에 추가:

```python
# 커뮤니티 반응 컨텍스트 수집
import json as _json
from services.db import get_db_connection as _get_db

def _get_community_context(visited_places: list[str]) -> str:
    if not visited_places:
        return ""
    conn = _get_db()
    lines = []
    for place_name in visited_places:
        rows = conn.execute(
            "SELECT tags FROM place_reviews WHERE place_name = ?",
            (place_name,),
        ).fetchall()
        if not rows:
            continue
        counts: dict[str, int] = {}
        for row in rows:
            for tag in _json.loads(row[0]):
                counts[tag] = counts.get(tag, 0) + 1
        top_tag = max(counts, key=counts.get)
        top_pct = round(counts[top_tag] / len(rows) * 100)
        lines.append(f"- {place_name}: {len(rows)}명 방문, 가장 많은 반응 '{top_tag}({top_pct}%)'")
    if not lines:
        return ""
    return "[커뮤니티 반응]\n" + "\n".join(lines) + "\n이 정보를 일지에 자연스럽게 녹여주세요. 통계를 직접 나열하지 말고 이야기 흐름에 녹이세요.\n"
```

그리고 `generate_journal` 함수 내 GPT 프롬프트 조립 부분 (`places_text` 사용 이후)에 커뮤니티 컨텍스트 추가:

```python
community_context = _get_community_context(body.visited_places)
# 기존 system prompt 문자열에 community_context 앞부분에 추가
# 기존 코드에서 system_prompt 변수 또는 messages 리스트를 찾아
# community_context가 비어있지 않으면 user 메시지 앞에 붙임
```

> **구현 주의:** `travel.py`를 먼저 읽어서 `generate_journal` 함수의 정확한 GPT 호출 구조를 확인한 후, `community_context`를 system message 또는 user message의 앞부분에 자연스럽게 추가할 것. `community_context`가 빈 문자열이면 아무것도 추가하지 않음.

- [ ] **Step 2: 수동 테스트**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/backend
curl -s -X POST http://localhost:8000/travel/journal \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "test",
    "companion_type": "마을 할망",
    "visited_places": ["비자림", "성산일출봉(UNESCO 세계자연유산)"],
    "chat_logs": []
  }' | python3 -m json.tool
```

기대: 200, 일지 텍스트에 "감동", "역사" 관련 표현 자연스럽게 포함

- [ ] **Step 3: 커밋**

```bash
git add backend/routers/travel.py
git commit -m "feat: inject community review context into journal GPT prompt"
```

---

## Task 6: iOS — PlaceReview 모델

**Files:**
- Create: `ios/JejuFolklore/Sources/Models/PlaceReview.swift`

- [ ] **Step 1: `PlaceReview.swift` 생성**

```swift
import Foundation

struct PlaceReviewsResponse: Decodable {
    let total: Int
    let tagCounts: [String: Int]   // snake_case → camelCase 자동 변환 (APIClient decoder)
    let recentNotes: [String]
}

struct PlaceReviewBody: Encodable {
    let placeName: String          // → place_name
    let tags: [String]
    let note: String?
    let deviceId: String           // → device_id
}
```

- [ ] **Step 2: xcodegen 재생성 + 빌드 확인**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/ios
xcodegen generate
xcodebuild -project JejuFolklore.xcodeproj -scheme JejuFolklore \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

기대: BUILD SUCCEEDED

- [ ] **Step 3: 커밋**

```bash
git add ios/JejuFolklore/Sources/Models/PlaceReview.swift ios/JejuFolklore.xcodeproj
git commit -m "feat(ios): add PlaceReviewsResponse and PlaceReviewBody models"
```

---

## Task 7: iOS — DeviceIdentity 서비스

**Files:**
- Create: `ios/JejuFolklore/Sources/Services/DeviceIdentity.swift`

- [ ] **Step 1: `DeviceIdentity.swift` 생성**

```swift
import Foundation

final class DeviceIdentity {
    static let shared = DeviceIdentity()
    private init() {}

    private let key = "jeju_device_uuid"

    var id: String {
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
```

- [ ] **Step 2: xcodegen 재생성 + 빌드**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/ios
xcodegen generate
xcodebuild -project JejuFolklore.xcodeproj -scheme JejuFolklore \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

기대: BUILD SUCCEEDED

- [ ] **Step 3: 커밋**

```bash
git add ios/JejuFolklore/Sources/Services/DeviceIdentity.swift ios/JejuFolklore.xcodeproj
git commit -m "feat(ios): add DeviceIdentity singleton for anonymous review auth"
```

---

## Task 8: iOS — APIClient 리뷰 메서드 추가

**Files:**
- Modify: `ios/JejuFolklore/Sources/Services/APIClient.swift`

- [ ] **Step 1: `APIClient.swift` 파일 끝에 extension 추가**

```swift
// MARK: - Place Reviews
extension APIClient {
    func submitReview(placeName: String, tags: [String], note: String?) async {
        let body = PlaceReviewBody(
            placeName: placeName,
            tags: tags,
            note: note,
            deviceId: DeviceIdentity.shared.id
        )
        _ = try? await postData("/place/review", body: body)
    }

    func fetchReviews(placeName: String) async throws -> PlaceReviewsResponse {
        let encoded = placeName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? placeName
        return try await get("/place/reviews/\(encoded)")
    }
}
```

- [ ] **Step 2: 빌드 확인**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/ios
xcodebuild -project JejuFolklore.xcodeproj -scheme JejuFolklore \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

기대: BUILD SUCCEEDED

- [ ] **Step 3: 커밋**

```bash
git add ios/JejuFolklore/Sources/Services/APIClient.swift
git commit -m "feat(ios): add submitReview and fetchReviews to APIClient"
```

---

## Task 9: iOS — PlaceReviewSheet 뷰

**Files:**
- Create: `ios/JejuFolklore/Sources/Views/PlaceReviewSheet.swift`

- [ ] **Step 1: `PlaceReviewSheet.swift` 생성**

```swift
import SwiftUI

struct PlaceReviewSheet: View {
    let placeName: String
    let companion: CompanionCharacter
    let onDone: () -> Void

    private static let tags: [(key: String, display: String)] = [
        ("소름 돋아요", "👻 소름 돋아요"),
        ("감동이에요",  "🥹 감동이에요"),
        ("신기해요",   "🤔 신기해요"),
        ("무서워요",   "😱 무서워요"),
        ("역사적이에요","📜 역사적이에요"),
    ]

    @State private var selectedKeys: Set<String> = []
    @State private var note: String = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(placeName)")
                    .font(.title3.weight(.semibold))
                Text("어떤 설화 경험이었나요?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Self.tags, id: \.key) { tag in
                        Button {
                            if selectedKeys.contains(tag.key) {
                                selectedKeys.remove(tag.key)
                            } else {
                                selectedKeys.insert(tag.key)
                            }
                        } label: {
                            Text(tag.display)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    selectedKeys.contains(tag.key)
                                        ? companion.themeColor.opacity(0.15)
                                        : Color(.secondarySystemBackground)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            selectedKeys.contains(tag.key)
                                                ? companion.themeColor
                                                : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)
                    }
                }

                TextField("한 줄 감상 남기기 (선택, 200자)", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: note) {
                        if note.count > 200 { note = String(note.prefix(200)) }
                    }

                Spacer()

                HStack(spacing: 12) {
                    Button("건너뛰기") { onDone() }
                        .buttonStyle(.bordered)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)

                    Button(isSubmitting ? "저장 중..." : "남기기 →") {
                        Task { await submit() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(companion.themeColor)
                    .disabled(selectedKeys.isEmpty || isSubmitting)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func submit() async {
        isSubmitting = true
        await APIClient.shared.submitReview(
            placeName: placeName,
            tags: Array(selectedKeys),
            note: note.isEmpty ? nil : note
        )
        isSubmitting = false
        onDone()
    }
}
```

- [ ] **Step 2: xcodegen 재생성 + 빌드**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/ios
xcodegen generate
xcodebuild -project JejuFolklore.xcodeproj -scheme JejuFolklore \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

기대: BUILD SUCCEEDED

- [ ] **Step 3: 커밋**

```bash
git add ios/JejuFolklore/Sources/Views/PlaceReviewSheet.swift ios/JejuFolklore.xcodeproj
git commit -m "feat(ios): add PlaceReviewSheet with tag picker and note input"
```

---

## Task 10: iOS — ExploreView 수정 (리뷰 시트 트리거 + 핀 필터)

**Files:**
- Modify: `ios/JejuFolklore/Sources/Views/ExploreView.swift`

- [ ] **Step 1: ExploreView에 상태 변수 추가**

`ExploreView` struct 안의 `@State private var isListExpanded` 줄 아래에 추가:

```swift
@State private var reviewTargetPlace: CoursePlace? = nil
@State private var showPlaceReview = false
@State private var activeTagFilter: String? = nil
@State private var placeReviews: [String: PlaceReviewsResponse] = [:]
```

- [ ] **Step 2: 채팅 sheet의 `onDismiss` 수정**

기존:
```swift
.sheet(isPresented: $vm.showCompanionChat, onDismiss: { vm.activeChatPlace = nil }) {
```

변경:
```swift
.sheet(isPresented: $vm.showCompanionChat, onDismiss: {
    let place = vm.lastArrivedPlace
    vm.activeChatPlace = nil
    if place != nil {
        reviewTargetPlace = place
        showPlaceReview = true
    }
}) {
```

- [ ] **Step 3: 리뷰 시트 `.sheet` 추가**

기존 `.sheet(item: $selectedFolklorePlace)` 줄 아래에 추가:

```swift
.sheet(isPresented: $showPlaceReview) {
    if let place = reviewTargetPlace {
        PlaceReviewSheet(
            placeName: place.name,
            companion: vm.companion,
            onDone: {
                showPlaceReview = false
                reviewTargetPlace = nil
            }
        )
    }
}
```

- [ ] **Step 4: 리뷰 데이터 로딩 추가**

`.onAppear { vm.startExploring() }` 줄 아래에 추가:

```swift
.task {
    await loadPlaceReviews()
}
```

그리고 `ExploreView` 내부 `private var nextUnvisitedPlace` 위에 함수 추가:

```swift
private func loadPlaceReviews() async {
    await withTaskGroup(of: (String, PlaceReviewsResponse?).self) { group in
        for place in course.places {
            group.addTask {
                let r = try? await APIClient.shared.fetchReviews(placeName: place.name)
                return (place.name, r)
            }
        }
        for await (name, reviews) in group {
            if let reviews { placeReviews[name] = reviews }
        }
    }
}
```

- [ ] **Step 5: 지도 위에 태그 필터 바 추가**

`exploreMap` computed property 안의 `Map(position:)` 뷰를 감싸는 ZStack에서, Map 위에 오버레이로 필터 추가. `exploreMap`을 아래처럼 수정:

```swift
private var exploreMap: some View {
    ZStack(alignment: .top) {
        Map(position: $mapPosition) {
            UserAnnotation()
            ForEach(course.places.indices, id: \.self) { i in
                let place = course.places[i]
                let isVisited = vm.visitedPlaceNames.contains(place.name)
                let isFiltered = isPlaceFiltered(place)
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)) {
                    Button {
                        if !place.folklorePins.isEmpty {
                            selectedFolklorePlace = place
                        }
                    } label: {
                        NumberedMarker(number: i + 1, hasfolklore: !place.folklorePins.isEmpty)
                            .opacity(isVisited ? 0.35 : (isFiltered ? 0.2 : 1.0))
                    }
                    .buttonStyle(.plain)
                }
            }
            if placeCoordinates.count >= 2 {
                MapPolyline(coordinates: placeCoordinates)
                    .stroke(.orange.opacity(0.75), style: StrokeStyle(lineWidth: 3.5, dash: [8, 5]))
            }
        }

        // 태그 필터 바
        if !placeReviews.isEmpty {
            tagFilterBar
                .padding(.top, 8)
                .padding(.horizontal, 12)
        }
    }
}

private func isPlaceFiltered(_ place: CoursePlace) -> Bool {
    guard let filter = activeTagFilter,
          let reviews = placeReviews[place.name],
          reviews.total > 0 else { return false }
    let topTag = reviews.tagCounts.max(by: { $0.value < $1.value })?.key
    return topTag != filter
}

private var tagFilterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            filterChip(label: "전체", key: nil)
            filterChip(label: "👻 소름", key: "소름 돋아요")
            filterChip(label: "🥹 감동", key: "감동이에요")
            filterChip(label: "🤔 신기", key: "신기해요")
            filterChip(label: "😱 무서움", key: "무서워요")
            filterChip(label: "📜 역사", key: "역사적이에요")
        }
        .padding(.horizontal, 4)
    }
}

private func filterChip(label: String, key: String?) -> some View {
    let isActive = activeTagFilter == key
    return Button {
        withAnimation(.easeInOut(duration: 0.2)) {
            activeTagFilter = isActive ? nil : key
        }
    } label: {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.orange : Color(.systemBackground).opacity(0.9))
            .foregroundColor(isActive ? .white : .primary)
            .clipShape(Capsule())
            .shadow(radius: isActive ? 0 : 2, y: 1)
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 6: 빌드 확인**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/ios
xcodebuild -project JejuFolklore.xcodeproj -scheme JejuFolklore \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

기대: BUILD SUCCEEDED

- [ ] **Step 7: 커밋**

```bash
git add ios/JejuFolklore/Sources/Views/ExploreView.swift ios/JejuFolklore.xcodeproj
git commit -m "feat(ios): add review sheet trigger and tag filter overlay in ExploreView"
```

---

## Task 11: iOS — FolkloreDetailView 커뮤니티 섹션

**Files:**
- Modify: `ios/JejuFolklore/Sources/Views/FolkloreDetailView.swift`

- [ ] **Step 1: 상태 변수 추가**

`FolkloreDetailView`의 `@State private var isLoadingTTS` 줄 아래에 추가:

```swift
@State private var placeReviews: PlaceReviewsResponse? = nil
```

- [ ] **Step 2: `.task { await loadDetail() }` 수정**

기존:
```swift
.task { await loadDetail() }
```

변경:
```swift
.task {
    async let detailTask: () = loadDetail()
    async let reviewTask: () = loadReviews()
    await detailTask
    await reviewTask
}
```

- [ ] **Step 3: `loadReviews()` 함수 추가**

`loadDetail()` 함수 아래에 추가:

```swift
private func loadReviews() async {
    guard !pin.primaryPlace.isEmpty else { return }
    placeReviews = try? await APIClient.shared.fetchReviews(placeName: pin.primaryPlace)
}
```

- [ ] **Step 4: `contentSection` 아래에 커뮤니티 섹션 추가**

`body`의 `VStack` 안에서 `contentSection` 다음, `Divider()` 추가 후 커뮤니티 섹션:

```swift
if let reviews = placeReviews, reviews.total > 0 {
    Divider()
    communitySection(reviews: reviews)
}
```

그리고 `communitySection` computed property 추가:

```swift
private func communitySection(reviews: PlaceReviewsResponse) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("다른 여행자들의 반응")
                .font(.headline)
            Spacer()
            Text("총 \(reviews.total)명")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        let sortedTags = reviews.tagCounts
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }

        ForEach(sortedTags, id: \.key) { tag, count in
            let pct = Double(count) / Double(reviews.total)
            HStack(spacing: 8) {
                Text(tag)
                    .font(.caption)
                    .frame(width: 90, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemFill))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(tagColor)
                            .frame(width: geo.size.width * pct)
                    }
                }
                .frame(height: 8)
                Text("\(Int(pct * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }

        if !reviews.recentNotes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(reviews.recentNotes, id: \.self) { note in
                    Text(""\(note)"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding(.top, 4)
        }
    }
}
```

- [ ] **Step 5: 빌드 확인**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/ios
xcodebuild -project JejuFolklore.xcodeproj -scheme JejuFolklore \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

기대: BUILD SUCCEEDED

- [ ] **Step 6: 커밋**

```bash
git add ios/JejuFolklore/Sources/Views/FolkloreDetailView.swift
git commit -m "feat(ios): add community reaction section to FolkloreDetailView"
git push origin main
```

---

## 셀프 리뷰 체크리스트

- [x] **스펙 커버리지:** 데이터 구조, API 2개, PlaceReviewSheet, ExploreView 필터, FolkloreDetailView 섹션, 일지 통합, 시드 데이터 — 전부 Task 포함
- [x] **Placeholder 없음:** 모든 Step에 실제 코드 포함
- [x] **타입 일관성:**
  - `PlaceReviewsResponse` — Task 6 정의 → Task 8, 10, 11에서 사용 ✅
  - `PlaceReviewBody` — Task 6 정의 → Task 8에서 사용 ✅
  - `DeviceIdentity.shared.id` — Task 7 정의 → Task 8에서 사용 ✅
  - `APIClient.shared.submitReview/fetchReviews` — Task 8 정의 → Task 9, 11에서 사용 ✅
  - `companion.themeColor` — 기존 TravelSession.swift에 정의됨 ✅
- [x] **xcodegen:** 신규 Swift 파일 생성 후 매 Task에서 `xcodegen generate` 실행
