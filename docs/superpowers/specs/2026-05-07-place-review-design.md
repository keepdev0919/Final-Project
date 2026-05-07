# 장소별 설화 인상 태그 & 커뮤니티 피드 설계

**날짜:** 2026-05-07  
**범위:** 백엔드 API 2개 + iOS 뷰 1개 신규 + 기존 뷰 3개 수정

---

## 목표

AI가 여행 일지를 생성해주지만, 사용자가 직접 자신의 경험을 남기고 다른 사람의 경험과 연결되는 소셜 레이어가 없다. 장소별로 설화 반응을 태그로 점수화하고, 커뮤니티 피드백을 지도와 일지에 통합한다.

---

## 태그 체계

총 5개 고정 태그. 복수 선택 가능.

| 태그 | 이모지 |
|------|--------|
| 소름 돋아요 | 👻 |
| 감동이에요 | 🥹 |
| 신기해요 | 🤔 |
| 무서워요 | 😱 |
| 역사적이에요 | 📜 |

---

## 데이터 구조

### 백엔드 DB 테이블: `place_reviews`

```sql
CREATE TABLE place_reviews (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    place_name TEXT    NOT NULL,
    tags       TEXT    NOT NULL,  -- JSON 배열: ["감동이에요", "신기해요"]
    note       TEXT,              -- 최대 200자, nullable
    device_id  TEXT    NOT NULL,  -- 기기 UUID (익명 식별)
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(place_name, device_id) -- 같은 기기·장소 중복 방지 (ON CONFLICT REPLACE)
);
```

**익명 식별:** iOS 최초 실행 시 UUID 생성 → `UserDefaults["device_id"]` 영구 저장. 같은 기기에서 같은 장소 재방문 시 기존 리뷰 덮어씀(upsert).

---

## API

### POST /place/review

리뷰 제출 (upsert).

**Request body:**
```json
{
  "place_name": "비자림",
  "tags": ["감동이에요", "신기해요"],
  "note": "천년 된 나무 앞에서 설화가 더 실감났어요",
  "device_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response:** `201 Created`
```json
{ "ok": true }
```

**유효성 검사:**
- `tags`: 1개 이상, 허용된 5개 태그 내에서만
- `note`: 200자 초과 시 400
- `device_id`: UUID 형식

### GET /place/reviews/{place_name}

장소별 집계 조회.

**Response:**
```json
{
  "total": 47,
  "tag_counts": {
    "감동이에요": 20,
    "신기해요": 15,
    "소름 돋아요": 8,
    "역사적이에요": 4,
    "무서워요": 0
  },
  "recent_notes": [
    "천년 된 나무 앞에서 설화가 더 실감났어요",
    "비자나무 숲이 생각보다 웅장했어요"
  ]
}
```

`recent_notes`: 최신 3개, note가 있는 것만 포함.

---

## iOS UI

### 신규: `PlaceReviewSheet`

**트리거:** `CompanionChatView` dismiss 시 자동으로 sheet 표시.  
`onDismiss: { showReviewSheet = true }` — ExploreView에서 처리.

**레이아웃:**
```
"이 장소 어떠셨어요?"  (제목)

[👻 소름] [🥹 감동] [🤔 신기] [😱 무서움] [📜 역사]
← 탭으로 복수 선택, 선택된 태그는 themeColor 테두리 강조

───────────────────────────
(선택) 한 줄 남기기...   [TextEditor, 200자 제한]

[건너뛰기]          [남기기 →]
```

**API 호출:** "남기기" 탭 → `POST /place/review` → sheet dismiss.  
"건너뛰기" 탭 → 그냥 dismiss. 오류 시 조용히 실패 (리뷰는 선택 사항).

**device_id:** `DeviceIdentity.shared.id` — `UserDefaults`에서 읽거나 최초 생성.

---

### 수정: `CompanionChatView`

```swift
// ExploreView에서 sheet dismiss 시:
.sheet(isPresented: $vm.showCompanionChat, onDismiss: {
    vm.activeChatPlace = nil
    if let place = vm.lastArrivedPlace {
        reviewTargetPlace = place
        showPlaceReview = true
    }
})
```

---

### 수정: `ExploreView` — 지도 핀 필터

지도 우측 상단에 필터 버튼.

```
[전체] [👻] [🥹] [🤔] [😱] [📜]
```

선택된 태그 = 해당 태그가 1위인 장소만 핀 강조 (나머지 핀 opacity 0.3).  
커뮤니티 데이터는 `ExploreView.onAppear`에서 방문 장소 목록 기준 bulk 조회.

---

### 수정: `FolkloreDetailView` — 커뮤니티 반응 섹션

설화 상세 하단에 "다른 여행자들의 반응" 섹션 추가.

```
다른 여행자들의 반응  (총 47명)
───────────────────
🥹 감동이에요  ████████░░  43%
🤔 신기해요    ██████░░░░  32%
👻 소름 돋아요 ███░░░░░░░  17%
📜 역사적이에요 █░░░░░░░░░   9%

"천년 된 나무 앞에서 설화가 더 실감났어요"
"비자나무 숲이 생각보다 웅장했어요"
```

로딩 중 skeleton, 데이터 없으면 섹션 숨김.

---

### 수정: `ExploreView` 장소 카드

방문 완료된 장소 카드 하단에 상위 태그 2개 요약.

```
✓ 비자림   🥹 43% · 🤔 32%
```

---

## 여행 일지 통합

`POST /travel/journal` 호출 시 방문 장소의 리뷰 집계를 함께 조회해서 GPT 프롬프트에 포함.

**프롬프트 추가 컨텍스트:**
```
[커뮤니티 반응]
- 비자림: 47명 방문, 가장 많은 반응 '감동이에요(43%)'
- 한라산국립공원: 23명 방문, 가장 많은 반응 '역사적이에요(52%)'
이 정보를 일지에 자연스럽게 녹여주세요. 통계를 직접 나열하지 말고 이야기 흐름에 녹이세요.
```

장소 리뷰가 0건이면 컨텍스트 생략 (기존 프롬프트 그대로).

---

## 구현 범위 요약

| 구성 요소 | 파일 | 작업 |
|-----------|------|------|
| 백엔드 DB | `database.py` 또는 `init_db.py` | `place_reviews` 테이블 생성 |
| 백엔드 API | `routers/review.py` (신규) | 2개 엔드포인트 |
| 백엔드 스키마 | `models/schemas.py` | `PlaceReviewRequest`, `PlaceReviewsResponse` |
| 백엔드 일지 | `routers/travel.py` | 커뮤니티 컨텍스트 주입 |
| iOS 신규 | `Views/PlaceReviewSheet.swift` | 태그 선택 + 노트 입력 |
| iOS 신규 | `Services/DeviceIdentity.swift` | UUID 생성·저장 |
| iOS 수정 | `Views/ExploreView.swift` | 리뷰 시트 트리거, 핀 필터 |
| iOS 수정 | `Views/FolkloreDetailView.swift` | 커뮤니티 반응 섹션 |
| iOS 수정 | `APIClient.swift` | 리뷰 관련 API 호출 메서드 추가 (신규 파일 없음) |
| iOS xcodegen | `project.yml` | 신규 파일 추가 시 재생성 |

---

## 에러 처리

- 리뷰 제출 실패: 조용히 실패. 사용자에게 오류 알림 없음 (리뷰는 선택적)
- 커뮤니티 데이터 로딩 실패: 해당 섹션 숨김 (앱 동작에 영향 없음)
- 오프라인: 리뷰 제출 불가 → "건너뛰기"와 동일하게 처리

---

## 제약

- 계정/로그인 없음. device_id로만 식별
- 신규 Swift 파일 추가 시 반드시 `project.yml` 수정 후 `xcodegen generate`
- 졸업 발표 이후 기능이므로 발표 플로우 기존 동작 건드리지 않음
