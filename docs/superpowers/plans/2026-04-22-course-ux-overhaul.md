# Course UX Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 코스 추천 UX를 "리스트 선택" → "1위 자동 제시 + 순환 탐색"으로 개편하고, 장소 탭 시 KTO 사진·설명·설화를 보여주는 상세 시트를 추가한다.

**Architecture:** Task A는 iOS 전용으로 ViewModel에 인덱스 상태를 추가하고 CourseListView를 로딩 화면으로 단순화하며 CoursePreviewView에 3개 액션 버튼을 붙인다. Task B는 백엔드에 `/place/detail` 엔드포인트를 추가하고 iOS에 PlaceDetailSheet를 새로 만들어 PlaceCard 탭에 연결한다. 두 Task는 독립적으로 구현·테스트 가능하다.

**Tech Stack:** Swift 5.9 / SwiftUI, Python 3.11 / FastAPI, KTO OpenAPI (`KorService2`), SQLite (기존 캐시 테이블 확장)

---

## 파일 맵

| 역할 | 경로 | 작업 |
|------|------|------|
| 추천 흐름 ViewModel | `ios/.../ViewModels/CourseRecommendViewModel.swift` | 수정 |
| 코스 리스트 뷰 | `ios/.../Views/CourseListView.swift` | 수정 |
| 코스 미리보기 뷰 | `ios/.../Views/CoursePreviewView.swift` | 수정 |
| 장소 상세 시트 (신규) | `ios/.../Views/PlaceDetailSheet.swift` | 생성 |
| 장소 상세 모델 (신규) | `ios/.../Models/PlaceDetail.swift` | 생성 |
| 장소 상세 API 클라이언트 (신규) | `ios/.../Services/PlaceAPI.swift` | 생성 |
| 백엔드 장소 라우터 (신규) | `backend/routers/place.py` | 생성 |
| 백엔드 진입점 | `backend/main.py` | 수정 |

---

## Task A: 코스 추천 UX 플로우 개편 (iOS only)

### 변경 전/후 흐름

```
[Before] 취향 질문 → CourseListView(3개 카드) → 탭 → CoursePreviewView
[After]  취향 질문 → CourseListView(로딩만) → 자동 → CoursePreviewView(1위)
                                                          ↓ 새로운 추천받기
                                                     CoursePreviewView(2위)
                                                          ↓ 새로운 추천받기
                                                     CoursePreviewView(3위)
                                                          ↓ 다시하기
                                                     취향 질문 (초기화)
```

---

### A-1. CourseRecommendViewModel — 인덱스 상태 및 메서드 추가

**Files:**
- Modify: `ios/JejuFolklore/Sources/ViewModels/CourseRecommendViewModel.swift`

- [ ] **Step 1: `currentCourseIndex` 프로퍼티 및 `hasNextCourse` 추가**

`@Published var courseList: [CourseListItem] = []` 바로 아래에 추가:

```swift
@Published var currentCourseIndex: Int = 0
var hasNextCourse: Bool { currentCourseIndex + 1 < courseList.count }
```

- [ ] **Step 2: `fetchList()` 완료 후 첫 번째 코스 자동 조회**

```swift
// 기존 fetchList() 내부
courseList = items
loadingStep = .idle
isLoadingList = false
// ↓ 추가: 리스트 로드 완료 시 1위 자동 조회
if let first = items.first {
    await fetchDetail(courseId: first.id)
}
```

기존 `isLoadingList = false`는 `fetchDetail` 호출 전에 실행되도록 위치 조정:
```swift
func fetchList() async {
    guard !selectedRegion.isEmpty, !categoryScores.isEmpty else { return }
    errorMessage = nil
    courseList = []
    isLoadingList = true
    loadingStep = .searching

    do {
        let items = try await CourseAPI.list(
            region: selectedRegion,
            categoryScores: categoryScores,
            durationDays: durationDays
        )
        courseList = items
        isLoadingList = false
        loadingStep = .idle
        if let first = items.first {
            await fetchDetail(courseId: first.id)
        }
    } catch {
        errorMessage = error.localizedDescription
        loadingStep = .idle
        isLoadingList = false
    }
}
```

- [ ] **Step 3: `advanceToNextCourse()` 추가**

```swift
func advanceToNextCourse() async {
    guard hasNextCourse else { return }
    currentCourseIndex += 1
    await fetchDetail(courseId: courseList[currentCourseIndex].id)
}
```

- [ ] **Step 4: `reset()` 에 `currentCourseIndex` 초기화 추가**

기존 `reset()` 함수 마지막에:
```swift
currentCourseIndex = 0
```

- [ ] **Step 5: Xcode Preview 빌드 확인 후 커밋**

```bash
git add ios/JejuFolklore/Sources/ViewModels/CourseRecommendViewModel.swift
git commit -m "feat(vm): add course index cycling — auto-fetch first, advance to next"
```

---

### A-2. CourseListView — 카드 목록 제거, 로딩 화면으로 단순화

**Files:**
- Modify: `ios/JejuFolklore/Sources/Views/CourseListView.swift`

- [ ] **Step 1: `@State private var shouldLoadNext = false` 추가**

`@State private var navigateToPreview = false` 바로 아래에:
```swift
@State private var shouldLoadNext = false
```

- [ ] **Step 2: body에서 카드 목록 제거, 로딩/에러 상태로 교체**

기존 `body` 전체를 아래로 교체:

```swift
var body: some View {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()

        if vm.isLoadingList {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                Text("코스를 찾고 있어요...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        } else if let err = vm.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text(err)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Button("다시 시도") {
                    Task { await vm.fetchList() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(32)
        } else if !vm.courseList.isEmpty {
            // Back 버튼으로 돌아온 경우 (세 액션 버튼 대신 기본 Back 사용)
            VStack(spacing: 12) {
                Text("다른 코스를 탐색하려면\n처음부터 다시 시작해주세요.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("처음으로") { vm.reset() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            .padding(32)
        }

        if vm.isLoadingDetail {
            LoadingOverlay(step: vm.loadingStep)
        }
    }
    .navigationTitle("코스 추천")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: $navigateToPreview) {
        if let course = vm.selectedCourse {
            CoursePreviewView(
                course: course,
                hasNext: vm.hasNextCourse,
                onNext: { shouldLoadNext = true },
                onReset: { vm.reset() }
            )
            .onDisappear {
                if shouldLoadNext {
                    shouldLoadNext = false
                    Task { await vm.advanceToNextCourse() }
                } else {
                    vm.selectedCourse = nil
                }
            }
        }
    }
    .onChange(of: vm.selectedCourse) {
        if vm.selectedCourse != nil {
            navigateToPreview = true
        }
    }
    .alert("코스를 가져오지 못했어요", isPresented: Binding(
        get: { vm.errorMessage != nil && !vm.isLoadingList },
        set: { if !$0 { vm.errorMessage = nil } }
    )) {
        Button("확인", role: .cancel) {}
    } message: {
        Text(vm.errorMessage ?? "다시 시도해주세요.")
    }
}
```

- [ ] **Step 3: 사용되지 않는 `CourseCardView`, `regionLabel`, `styleLabel` 삭제 확인**

`CourseCardView`는 이 파일에서만 사용되므로 파일 전체에서 삭제. `regionLabel`, `styleLabel`도 body에서 더 이상 참조하지 않으면 삭제.

- [ ] **Step 4: Preview 확인 후 커밋**

```bash
git add ios/JejuFolklore/Sources/Views/CourseListView.swift
git commit -m "feat(ui): CourseListView → auto-navigate to first course, remove card list"
```

---

### A-3. CoursePreviewView — 3개 액션 버튼 + "마음에 드세요?" 문구

**Files:**
- Modify: `ios/JejuFolklore/Sources/Views/CoursePreviewView.swift`

- [ ] **Step 1: 생성자에 파라미터 추가**

기존:
```swift
struct CoursePreviewView: View {
    let course: Course
    @StateObject private var vm: CoursePreviewViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var navigateToExplore = false
    @State private var isSheetExpanded = true

    init(course: Course) {
        self.course = course
        _vm = StateObject(wrappedValue: CoursePreviewViewModel(course: course))
    }
```

수정:
```swift
struct CoursePreviewView: View {
    let course: Course
    let hasNext: Bool
    let onNext: (() -> Void)?
    let onReset: (() -> Void)?
    @StateObject private var vm: CoursePreviewViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var navigateToExplore = false
    @State private var isSheetExpanded = true

    init(course: Course, hasNext: Bool = false, onNext: (() -> Void)? = nil, onReset: (() -> Void)? = nil) {
        self.course = course
        self.hasNext = hasNext
        self.onNext = onNext
        self.onReset = onReset
        _vm = StateObject(wrappedValue: CoursePreviewViewModel(course: course))
    }
```

- [ ] **Step 2: `actionButtons` 교체**

기존 `actionButtons` 계산 속성 전체를 아래로 교체:

```swift
// MARK: - Action Buttons

private var actionButtons: some View {
    VStack(spacing: 12) {
        Text("추천 일정이 마음에 드세요?")
            .font(.footnote)
            .foregroundColor(.secondary)

        HStack(spacing: 10) {
            // 다시하기
            Button {
                dismiss()
                onReset?()
            } label: {
                Label("다시하기", systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            // 새로운 추천받기 (다음 코스 없으면 비활성)
            Button {
                dismiss()
                onNext?()
            } label: {
                Label("새로운 추천", systemImage: "shuffle")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(!hasNext)

            // 내 일정으로 담기
            Button {
                vm.save(context: modelContext)
            } label: {
                Label(vm.isSaved ? "저장됨" : "담기", systemImage: vm.isSaved ? "checkmark" : "square.and.arrow.down")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(vm.isSaved)
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
}
```

- [ ] **Step 3: Preview의 `CoursePreviewView` 호출 시그니처는 기본값 처리로 변경 불필요 확인**

`#Preview` 블록은 `init(course:)` 기본값 파라미터 덕분에 그대로 동작. 확인만.

- [ ] **Step 4: Preview로 3버튼 레이아웃 확인 후 커밋**

```bash
git add ios/JejuFolklore/Sources/Views/CoursePreviewView.swift
git commit -m "feat(ui): replace 2 buttons with 3-action row — save/next/reset"
```

---

## Task B: 장소 상세 시트 (KTO 사진·설명·설화)

---

### B-1. 백엔드 `/place/detail` 엔드포인트

**Files:**
- Create: `backend/routers/place.py`
- Modify: `backend/main.py`

- [ ] **Step 1: `backend/routers/place.py` 생성**

```python
"""장소 상세 정보 — KTO API로 사진·설명 조회 (GPS 기반 contentId 탐색)."""
from __future__ import annotations

import difflib
import time
from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from services.db import get_db_connection
from routers.tourist import _kto_get  # tourist.py와 중복 방지

router = APIRouter(prefix="/place", tags=["place"])
limiter = Limiter(key_func=get_remote_address)

CACHE_TTL = 7 * 24 * 3600  # 7일


def _find_content_id(name: str, lat: float, lng: float) -> str | None:
    """GPS 반경 검색으로 가장 이름이 비슷한 장소의 contentId를 반환."""
    try:
        data = _kto_get("KorService2", "locationBasedList2", {
            "mapX": lng,
            "mapY": lat,
            "radius": 500,
            "numOfRows": 10,
        })
        items = data["response"]["body"]["items"]
        if not items or items == "":
            return None
        item_list = items["item"] if isinstance(items["item"], list) else [items["item"]]
        titles = [it["title"] for it in item_list]
        matches = difflib.get_close_matches(name, titles, n=1, cutoff=0.3)
        if not matches:
            # cutoff 낮춰서 거리 기반 첫 번째 반환
            return item_list[0]["contentid"] if item_list else None
        best = next(it for it in item_list if it["title"] == matches[0])
        return best["contentid"]
    except Exception:
        return None


def _fetch_detail(content_id: str) -> dict:
    """contentId로 상세 정보(overview, 사진, 주소) 조회."""
    try:
        data = _kto_get("KorService2", "detailCommon2", {
            "contentId": content_id,
            "overviewYN": "Y",
            "defaultYN": "Y",
        })
        item = data["response"]["body"]["items"]["item"]
        if isinstance(item, list):
            item = item[0]
        return item
    except Exception:
        return {}


def _fetch_image(content_id: str) -> str:
    """contentId로 대표 사진 URL 조회."""
    try:
        data = _kto_get("KorService2", "detailImage2", {
            "contentId": content_id,
            "imageYN": "Y",
            "numOfRows": 1,
        })
        items = data["response"]["body"]["items"]
        if not items or items == "":
            return ""
        item_list = items["item"] if isinstance(items["item"], list) else [items["item"]]
        return item_list[0].get("originimgurl", "") if item_list else ""
    except Exception:
        return ""


@router.get("/detail")
@limiter.limit("30/minute")
def get_place_detail(request: Request, name: str, lat: float, lng: float):
    """장소명 + GPS로 KTO 사진·설명 조회 (7일 캐시)."""
    conn = get_db_connection()

    # 캐시 확인
    cached = conn.execute(
        "SELECT * FROM place_detail_cache WHERE name = ? AND ABS(lat - ?) < 0.001 AND ABS(lng - ?) < 0.001",
        (name, lat, lng),
    ).fetchone()
    if cached and (time.time() - cached["cached_at"]) < CACHE_TTL:
        return {
            "name": cached["name"],
            "overview": cached["overview"],
            "image_url": cached["image_url"],
            "address": cached["address"],
        }

    # KTO 조회
    content_id = _find_content_id(name, lat, lng)
    if not content_id:
        raise HTTPException(status_code=404, detail="KTO에서 해당 장소를 찾을 수 없습니다.")

    detail = _fetch_detail(content_id)
    image_url = detail.get("firstimage") or _fetch_image(content_id)
    overview = detail.get("overview", "")
    address = detail.get("addr1", "")

    # 캐시 저장
    conn.execute(
        """INSERT OR REPLACE INTO place_detail_cache
           (name, lat, lng, overview, image_url, address, cached_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (name, lat, lng, overview, image_url, address, time.time()),
    )
    conn.commit()

    return {
        "name": name,
        "overview": overview,
        "image_url": image_url,
        "address": address,
    }
```

- [ ] **Step 2: `place_detail_cache` 테이블 생성 마이그레이션**

`backend/services/db.py` — `@lru_cache(maxsize=1)` 때문에 함수 바디는 최초 호출 시 **단 한 번만** 실행됨.
반드시 `get_db_connection()` **함수 바디 안에**, `tourist_info_cache` 바로 다음에 추가:

```python
@lru_cache(maxsize=1)
def get_db_connection():
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tourist_info_cache (
            content_id TEXT PRIMARY KEY,
            name       TEXT,
            address    TEXT,
            phone      TEXT,
            category   TEXT,
            cached_at  REAL
        )
    """)
    # ↓ 여기에 추가 (함수 바디 안, conn.commit() 이전)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS place_detail_cache (
            name        TEXT,
            lat         REAL,
            lng         REAL,
            overview    TEXT,
            image_url   TEXT,
            address     TEXT,
            cached_at   REAL,
            PRIMARY KEY (name, lat, lng)
        )
    """)
    conn.commit()
    return conn
```

- [ ] **Step 3: `backend/main.py` 에 place 라우터 등록**

```python
from routers import pins, chat, course, tts, tourist, place
# ...
app.include_router(place.router)
```

- [ ] **Step 4: 서버 재시작 후 수동 테스트**

```bash
curl "http://localhost:8000/place/detail?name=용두암&lat=33.5160&lng=126.5059"
# 예상: { "name": "용두암", "overview": "...", "image_url": "http://tong...", "address": "..." }
```

- [ ] **Step 5: 커밋**

```bash
git add backend/routers/place.py backend/main.py
git commit -m "feat(backend): add /place/detail endpoint with KTO lookup and 7-day cache"
```

---

### B-2. iOS 모델 및 API 클라이언트

**Files:**
- Create: `ios/JejuFolklore/Sources/Models/PlaceDetail.swift`
- Create: `ios/JejuFolklore/Sources/Services/PlaceAPI.swift`

- [ ] **Step 1: `PlaceDetail.swift` 생성**

```swift
import Foundation

// APIClient.decoder가 .convertFromSnakeCase를 사용하므로
// image_url → imageUrl 자동 변환됨. CodingKeys 불필요.
struct PlaceDetail: Decodable {
    let name: String
    let overview: String
    let imageUrl: String
    let address: String
}
```

- [ ] **Step 2: `PlaceAPI.swift` 생성**

```swift
import Foundation

// APIClient.get(_:query:)은 [String: String]을 받음 — URLQueryItem 아님
enum PlaceAPI {
    static func detail(name: String, lat: Double, lng: Double) async throws -> PlaceDetail {
        try await APIClient.shared.get(
            "/place/detail",
            query: ["name": name, "lat": String(lat), "lng": String(lng)]
        )
    }
}
```

- [ ] **Step 3: 커밋**

```bash
git add ios/JejuFolklore/Sources/Models/PlaceDetail.swift \
        ios/JejuFolklore/Sources/Services/PlaceAPI.swift
git commit -m "feat(ios): PlaceDetail model and PlaceAPI client"
```

---

### B-3. PlaceDetailSheet — 사진·설명·설화 바텀 시트

**Files:**
- Create: `ios/JejuFolklore/Sources/Views/PlaceDetailSheet.swift`

- [ ] **Step 1: `PlaceDetailSheet.swift` 생성**

```swift
import SwiftUI

struct PlaceDetailSheet: View {
    let place: CoursePlace
    @State private var detail: PlaceDetail?
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 사진
                photoSection
                    .frame(height: 220)
                    .clipped()

                VStack(alignment: .leading, spacing: 16) {
                    // 장소명 + 주소
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .font(.title3.weight(.bold))
                        if let address = detail?.address, !address.isEmpty {
                            Text(address)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 설명
                    if let overview = detail?.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineSpacing(5)
                    } else if isLoading {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 80)
                    } else if failed {
                        Text("장소 정보를 불러오지 못했어요.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // 설화 섹션
                    if !place.folklorePins.isEmpty {
                        Divider()
                        folkloreSection
                    }
                }
                .padding(20)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadDetail()
        }
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoSection: some View {
        if let urlStr = detail?.imageUrl, !urlStr.isEmpty, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    placeholderPhoto
                default:
                    Color.secondary.opacity(0.1)
                        .overlay(ProgressView())
                }
            }
        } else {
            placeholderPhoto
        }
    }

    private var placeholderPhoto: some View {
        Color.orange.opacity(0.08)
            .overlay(
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.orange.opacity(0.4))
            )
    }

    // MARK: - Folklore

    private var folkloreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("이 곳에 깃든 이야기")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.orange)
            }

            ForEach(place.folklorePins) { pin in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(pin.sourceTypeLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.8))
                            .clipShape(Capsule())
                        Text(pin.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                    }
                    if !pin.summary.isEmpty {
                        Text(pin.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Data

    private func loadDetail() async {
        isLoading = true
        failed = false
        do {
            detail = try await PlaceAPI.detail(name: place.name, lat: place.lat, lng: place.lng)
        } catch {
            failed = true
        }
        isLoading = false
    }
}

// MARK: - Preview

#Preview {
    let mockPin = Pin(
        codeNo: "001",
        title: "용두암 전설",
        sourceType: "legend",
        summary: "용이 승천하려다 굳어버린 바위라는 전설이 전해진다.",
        lat: 33.516, lng: 126.505,
        primaryPlace: "용두암", distanceM: 30
    )
    let place = CoursePlace(
        name: "용두암", lat: 33.5160, lng: 126.5059,
        day: 1, folklorePins: [mockPin]
    )
    PlaceDetailSheet(place: place)
}
```

- [ ] **Step 2: 커밋**

```bash
git add ios/JejuFolklore/Sources/Views/PlaceDetailSheet.swift
git commit -m "feat(ui): PlaceDetailSheet with KTO photo, description, and folklore pins"
```

---

### B-4. CoursePreviewView — PlaceCard 탭 연결

**Files:**
- Modify: `ios/JejuFolklore/Sources/Views/CoursePreviewView.swift`

- [ ] **Step 1: `@State private var selectedPlace: CoursePlace?` 추가**

`@State private var isSheetExpanded = true` 바로 아래에:
```swift
@State private var selectedPlace: CoursePlace?
```

- [ ] **Step 2: body에 `.sheet` 추가**

`body`의 `.animation(...)` 다음 모디파이어 체인에 추가:
```swift
.sheet(item: $selectedPlace) { place in
    PlaceDetailSheet(place: place)
}
```

- [ ] **Step 3: `DaySectionView`에 탭 핸들러 전달**

`DaySectionView` 구조체에 `onPlaceTap: (CoursePlace) -> Void` 추가:

```swift
private struct DaySectionView: View {
    let day: Int
    let places: [CoursePlace]
    let globalOffset: Int
    let onPlaceTap: (CoursePlace) -> Void   // ← 추가

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ... 헤더 동일 ...

            ForEach(Array(places.enumerated()), id: \.offset) { idx, place in
                PlaceCard(index: globalOffset + idx + 1, place: place)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .onTapGesture { onPlaceTap(place) }   // ← 추가
            }
        }
    }
}
```

- [ ] **Step 4: `bottomSheet` 내부의 `DaySectionView` 호출에 `onPlaceTap` 전달**

```swift
DaySectionView(
    day: day,
    places: placesByDay[day] ?? [],
    globalOffset: globalOffset(for: day),
    onPlaceTap: { selectedPlace = $0 }   // ← 추가
)
```

- [ ] **Step 5: Preview로 시트 동작 확인**

Preview에서 장소 카드 탭 → `PlaceDetailSheet` 올라오는지 확인 (mock 데이터라 이미지 없음, overview 없음 상태 확인).

- [ ] **Step 6: 커밋**

```bash
git add ios/JejuFolklore/Sources/Views/CoursePreviewView.swift
git commit -m "feat(ui): tap PlaceCard to open PlaceDetailSheet"
```

---

## Self-Review

### Spec 커버리지 체크

| 요구사항 | 구현 태스크 |
|---------|------------|
| 3개 리스트 대신 1위 자동 제시 | A-1 (fetchList auto-fetchDetail), A-2 (카드 제거) |
| 내 일정으로 담기 버튼 | A-3 (actionButtons 교체) |
| 새로운 추천받기 → 2위 코스 | A-1 (advanceToNextCourse), A-2 (shouldLoadNext), A-3 (onNext) |
| 다시하기 → 초기 질문 화면 | A-3 (onReset → vm.reset()) |
| 장소 탭 → 상세 시트 | B-4 (onTapGesture + sheet) |
| KTO 사진 | B-1 (detailImage2), B-3 (AsyncImage) |
| 장소 설명 | B-1 (detailCommon2 overview), B-3 (Text) |
| 설화 정보 | B-3 (folkloreSection — 기존 folklorePins 활용) |
| 7일 캐시 | B-1 (place_detail_cache 테이블) |

### Placeholder 없음 확인 ✓

모든 Step에 실제 코드 포함, TBD 없음.

### 타입 일관성 확인 ✓

- `CoursePlace` — `Identifiable` (`id = "\(name)-\(day)"`) → `.sheet(item:)` 호환
- `Pin` — `Identifiable` (`id = codeNo`), `sourceTypeLabel` 프로퍼티 존재 → `PlaceDetailSheet` 호환
- `PlaceDetail.imageUrl` ↔ APIClient `.convertFromSnakeCase` → 백엔드 `image_url` 자동 변환
- `PlaceAPI.detail(query:)` — `APIClient.get(_:query:)` 시그니처와 일치
- `DaySectionView.onPlaceTap: (CoursePlace) -> Void` — Step 3, 4 일치

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-22-course-ux-overhaul.md`.**

**Two execution options:**

**1. Subagent-Driven (recommended)** — 태스크마다 서브에이전트 디스패치, 태스크 간 리뷰

**2. Inline Execution** — 이 세션에서 직접 실행, 체크포인트마다 확인

**Which approach?**
