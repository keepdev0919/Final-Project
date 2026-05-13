# Place Detail View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 코스 미리보기에서 장소 탭 시 트리플 앱 스타일의 전체 화면 장소 상세 뷰를 표시한다 — 사진 캐러셀, 액션 버튼, 설화, 기본정보(지도·주소·전화·길찾기), 이용팁(운영시간·입장료·주차).

**Architecture:** 백엔드 `/place/detail`을 확장해 KTO `detailImage2`(사진 복수), `detailIntro2`(이용팁)를 추가 조회하고, iOS에서는 기존 바텀 시트(`PlaceDetailSheet`)를 전체 화면 네비게이션 뷰(`PlaceDetailView`)로 교체한다. DB 캐시 테이블은 스키마 변경 감지 시 자동 재생성.

**Tech Stack:** Swift 5.9 / SwiftUI / MapKit, Python 3.11 / FastAPI, KTO OpenAPI KorService2, SQLite

---

## 파일 맵

| 역할 | 경로 | 작업 |
|------|------|------|
| DB 연결 + 캐시 테이블 | `backend/services/db.py` | 수정 — 스키마 마이그레이션 |
| 장소 상세 API | `backend/routers/place.py` | 수정 — 사진 복수 + 이용팁 추가 |
| iOS 응답 모델 | `ios/JejuFolklore/Sources/Models/PlaceDetail.swift` | 수정 — 필드 확장 |
| iOS 장소 상세 뷰 (신규) | `ios/JejuFolklore/Sources/Views/PlaceDetailView.swift` | 생성 |
| iOS 장소 상세 뷰 (구) | `ios/JejuFolklore/Sources/Views/PlaceDetailSheet.swift` | 삭제 |
| 코스 미리보기 뷰 | `ios/JejuFolklore/Sources/Views/CoursePreviewView.swift` | 수정 — sheet → navigationDestination |

---

## Task 1: 백엔드 DB 스키마 마이그레이션

**Files:**
- Modify: `backend/services/db.py:41-73`

`place_detail_cache` 테이블에 `images`(JSON 배열), `tel`, `open_time`, `rest_date`, `use_fee`, `parking`, `content_type_id` 컬럼을 추가한다. SQLite는 `ALTER TABLE ADD COLUMN IF NOT EXISTS`를 지원하지 않으므로, 서버 기동 시점에 컬럼 존재 여부를 `PRAGMA table_info`로 확인하고 없으면 테이블을 재생성한다. `@lru_cache`로 인해 이 로직은 첫 호출 시 한 번만 실행되므로 안전하다.

- [ ] **Step 1: `get_db_connection()` 내부의 `place_detail_cache` 생성 블록 교체**

`backend/services/db.py` 의 기존 `place_detail_cache` CREATE TABLE 블록(58~71행)을 아래로 전체 교체:

```python
    # place_detail_cache: 스키마 변경 감지 시 DROP + 재생성 (캐시라 데이터 손실 무방)
    _existing_cols = {
        row[1] for row in conn.execute("PRAGMA table_info(place_detail_cache)").fetchall()
    }
    if "images" not in _existing_cols:
        conn.execute("DROP TABLE IF EXISTS place_detail_cache")
        conn.execute(
            """
            CREATE TABLE place_detail_cache (
                name             TEXT,
                lat              REAL,
                lng              REAL,
                overview         TEXT,
                images           TEXT,
                address          TEXT,
                tel              TEXT,
                open_time        TEXT,
                rest_date        TEXT,
                use_fee          TEXT,
                parking          TEXT,
                content_type_id  TEXT,
                cached_at        REAL,
                PRIMARY KEY (name, lat, lng)
            )
            """
        )
```

- [ ] **Step 2: 서버 재기동 후 테이블 컬럼 확인**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프
source .venv/bin/activate
python3 -c "
import sys; sys.path.insert(0, 'backend')
from services.db import get_db_connection
conn = get_db_connection()
cols = [r[1] for r in conn.execute('PRAGMA table_info(place_detail_cache)').fetchall()]
print(cols)
"
```

예상 출력:
```
['name', 'lat', 'lng', 'overview', 'images', 'address', 'tel', 'open_time', 'rest_date', 'use_fee', 'parking', 'content_type_id', 'cached_at']
```

- [ ] **Step 3: 커밋**

```bash
git add backend/services/db.py
git commit -m "feat(db): add images/tel/intro columns to place_detail_cache"
```

---

## Task 2: 백엔드 `/place/detail` 응답 확장

**Files:**
- Modify: `backend/routers/place.py`

`_find_content_id`가 `content_type_id`도 함께 반환하도록 변경하고, `_fetch_images`(최대 5장)와 `_fetch_intro`(이용팁)를 추가한다. 캐시 read/write와 응답 구조를 모두 업데이트한다.

- [ ] **Step 1: `_find_content_id` 반환값을 `(contentId, contentTypeId) | None`으로 변경**

기존 함수 전체를 아래로 교체:

```python
def _find_content_id(name: str, lat: float, lng: float) -> tuple[str, str] | None:
    """GPS 반경 검색으로 (contentId, contentTypeId) 반환."""
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
        best = next(
            (it for it in item_list if it["title"] == matches[0]),
            item_list[0]
        ) if matches else item_list[0]
        return best["contentid"], str(best.get("contenttypeid", "12"))
    except Exception:
        return None
```

- [ ] **Step 2: `_fetch_images` 추가 (최대 5장)**

`_fetch_detail` 함수 아래에 추가:

```python
def _fetch_images(content_id: str) -> list[str]:
    """contentId로 사진 URL 최대 5장 조회."""
    try:
        data = _kto_get("KorService2", "detailImage2", {
            "contentId": content_id,
            "imageYN": "Y",
            "numOfRows": 5,
        })
        items = data["response"]["body"]["items"]
        if not items or items == "":
            return []
        item_list = items["item"] if isinstance(items["item"], list) else [items["item"]]
        return [it["originimgurl"] for it in item_list if it.get("originimgurl")]
    except Exception:
        return []
```

- [ ] **Step 3: `_fetch_intro` 추가 (이용팁)**

```python
def _fetch_intro(content_id: str, content_type_id: str) -> dict:
    """운영시간·휴무·입장료·주차 조회. 없는 필드는 빈 문자열."""
    try:
        data = _kto_get("KorService2", "detailIntro2", {
            "contentId": content_id,
            "contentTypeId": content_type_id,
        })
        item = data["response"]["body"]["items"]["item"]
        if isinstance(item, list):
            item = item[0]
        # 관광지(12) 기준 필드명; 다른 타입은 일부 없을 수 있음
        return {
            "open_time": item.get("opentime") or item.get("usetimefestival") or item.get("opentimefood") or "",
            "rest_date": item.get("restdate") or item.get("restdatefood") or "",
            "use_fee":   item.get("usefee") or "",
            "parking":   item.get("parking") or item.get("parkingfood") or "",
        }
    except Exception:
        return {"open_time": "", "rest_date": "", "use_fee": "", "parking": ""}
```

- [ ] **Step 4: 기존 단일 `_fetch_image` 함수 삭제**

`_fetch_image(content_id: str) -> str` 함수 전체 삭제 (이제 `_fetch_images`로 대체됨).

- [ ] **Step 5: `get_place_detail` 엔드포인트 전체 교체**

```python
import json as _json

@router.get("/detail")
@limiter.limit("30/minute")
def get_place_detail(request: Request, name: str, lat: float, lng: float):
    """장소명 + GPS로 KTO 사진·설명·이용팁 조회 (7일 캐시)."""
    conn = get_db_connection()

    cached = conn.execute(
        "SELECT * FROM place_detail_cache WHERE name = ? AND ABS(lat - ?) < 0.001 AND ABS(lng - ?) < 0.001",
        (name, lat, lng),
    ).fetchone()
    if cached and (time.time() - cached["cached_at"]) < CACHE_TTL:
        return {
            "name":             cached["name"],
            "overview":         cached["overview"] or "",
            "images":           _json.loads(cached["images"] or "[]"),
            "address":          cached["address"] or "",
            "tel":              cached["tel"] or "",
            "open_time":        cached["open_time"] or "",
            "rest_date":        cached["rest_date"] or "",
            "use_fee":          cached["use_fee"] or "",
            "parking":          cached["parking"] or "",
        }

    result = _find_content_id(name, lat, lng)
    if not result:
        raise HTTPException(status_code=404, detail="KTO에서 해당 장소를 찾을 수 없습니다.")
    content_id, content_type_id = result

    detail  = _fetch_detail(content_id)
    images  = _fetch_images(content_id)
    # firstimage를 배열 앞에 합성 (중복 제거)
    first   = detail.get("firstimage", "")
    if first and first not in images:
        images = [first] + images
    intro   = _fetch_intro(content_id, content_type_id)

    overview = detail.get("overview", "")
    address  = detail.get("addr1", "")
    tel      = detail.get("tel", "")

    conn.execute(
        """INSERT OR REPLACE INTO place_detail_cache
           (name, lat, lng, overview, images, address, tel,
            open_time, rest_date, use_fee, parking, content_type_id, cached_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (name, lat, lng, overview, _json.dumps(images, ensure_ascii=False),
         address, tel,
         intro["open_time"], intro["rest_date"], intro["use_fee"], intro["parking"],
         content_type_id, time.time()),
    )
    conn.commit()

    return {
        "name":      name,
        "overview":  overview,
        "images":    images,
        "address":   address,
        "tel":       tel,
        "open_time": intro["open_time"],
        "rest_date": intro["rest_date"],
        "use_fee":   intro["use_fee"],
        "parking":   intro["parking"],
    }
```

- [ ] **Step 6: 파일 상단 `import json as _json` 추가 확인**

`place.py` 상단에 `import json as _json` 이 없다면 추가 (`_json`으로 별칭 사용, 표준 `json` 이름 충돌 방지).

- [ ] **Step 7: curl 테스트 (기존 캐시 삭제 후)**

```bash
# 기존 캐시 초기화 (스키마 재생성은 서버 재기동 시 자동)
# 서버 재기동 필요 (백엔드 이미 실행 중이라면)
curl -s "http://localhost:8000/place/detail?name=용두암&lat=33.5160&lng=126.5059" | python3 -m json.tool
```

예상 출력:
```json
{
  "name": "용두암",
  "overview": "...",
  "images": ["http://tong.visitkorea.or.kr/...jpg", "..."],
  "address": "제주특별자치도 제주시 ...",
  "tel": "064-...",
  "open_time": "...",
  "rest_date": "",
  "use_fee": "무료",
  "parking": "..."
}
```

- [ ] **Step 8: 커밋**

```bash
git add backend/routers/place.py
git commit -m "feat(place): add multi-image, tel, and intro fields to /place/detail"
```

---

## Task 3: iOS PlaceDetail 모델 업데이트

**Files:**
- Modify: `ios/JejuFolklore/Sources/Models/PlaceDetail.swift`

- [ ] **Step 1: 파일 전체 교체**

```swift
import Foundation

struct PlaceDetail: Decodable {
    let name: String
    let overview: String
    let images: [String]
    let address: String
    let tel: String
    let openTime: String
    let restDate: String
    let useFee: String
    let parking: String
}
```

`APIClient.decoder`가 `.convertFromSnakeCase`를 사용하므로 `open_time` → `openTime` 자동 변환됨. `CodingKeys` 불필요.

- [ ] **Step 2: 커밋**

```bash
git add ios/JejuFolklore/Sources/Models/PlaceDetail.swift
git commit -m "feat(model): expand PlaceDetail with images array and intro fields"
```

---

## Task 4: iOS PlaceDetailView 생성

**Files:**
- Create: `ios/JejuFolklore/Sources/Views/PlaceDetailView.swift`
- Delete: `ios/JejuFolklore/Sources/Views/PlaceDetailSheet.swift`

전체 화면 스크롤 뷰. 섹션 순서: 사진 캐러셀 → 액션 버튼 → 설명 → 설화 → 기본정보(지도·주소·전화·길찾기) → 이용팁.

- [ ] **Step 1: `PlaceDetailView.swift` 생성**

```swift
import SwiftUI
import MapKit

struct PlaceDetailView: View {
    let place: CoursePlace
    @State private var detail: PlaceDetail?
    @State private var isLoading = true
    @State private var failed = false
    @State private var currentPhotoIndex = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                photoCarousel
                actionRow
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                Divider()
                if let detail {
                    overviewSection(detail)
                    folkloreSection
                    basicInfoSection(detail)
                    introSection(detail)
                } else if isLoading {
                    skeletonView
                } else {
                    failedView
                }
            }
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
    }

    // MARK: - Photo Carousel

    private var photoCarousel: some View {
        let images = detail?.images ?? []
        return ZStack(alignment: .topTrailing) {
            if images.isEmpty {
                placeholderPhoto
                    .frame(height: 260)
            } else {
                TabView(selection: $currentPhotoIndex) {
                    ForEach(Array(images.enumerated()), id: \.offset) { idx, urlStr in
                        AsyncImage(url: URL(string: urlStr)) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                placeholderPhoto
                            }
                        }
                        .clipped()
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 260)

                // 트리플 스타일 카운터 뱃지
                Text("\(currentPhotoIndex + 1)/\(images.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(12)
            }
        }
    }

    private var placeholderPhoto: some View {
        Color.orange.opacity(0.08)
            .overlay(
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.orange.opacity(0.35))
            )
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 0) {
            ShareLink(
                item: "\(place.name)\n\(detail?.address ?? "")"
            ) {
                VStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                    Text("공유하기")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.primary)
            }
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private func overviewSection(_ detail: PlaceDetail) -> some View {
        if !detail.overview.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(detail.overview)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineSpacing(5)
            }
            .padding(20)
            Divider()
        }
    }

    // MARK: - Folklore

    @ViewBuilder
    private var folkloreSection: some View {
        if !place.folklorePins.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text("이 곳에 깃든 이야기")
                        .font(.headline)
                        .foregroundColor(.orange)
                }

                ForEach(place.folklorePins) { pin in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(pin.sourceTypeLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.85))
                                .clipShape(Capsule())
                            Text(pin.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                        }
                        if !pin.summary.isEmpty {
                            Text(pin.summary)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineSpacing(4)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(20)
            Divider()
        }
    }

    // MARK: - Basic Info

    @ViewBuilder
    private func basicInfoSection(_ detail: PlaceDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("기본정보")
                .font(.headline)

            // 소형 지도 (탭 → Apple Maps)
            Map(coordinateRegion: .constant(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng),
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            )))
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(true)
            .onTapGesture { openInMaps() }

            // 주소
            if !detail.address.isEmpty {
                InfoRow(icon: "mappin", text: detail.address)
            }

            // 전화번호
            if !detail.tel.isEmpty {
                InfoRow(icon: "phone", text: detail.tel)
            }

            // 길찾기 버튼
            Button {
                openInMaps()
            } label: {
                Text("길찾기")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        Divider()
    }

    // MARK: - Intro (이용팁)

    @ViewBuilder
    private func introSection(_ detail: PlaceDetail) -> some View {
        let tips = [
            ("clock", "운영시간", detail.openTime),
            ("calendar.badge.minus", "휴무일", detail.restDate),
            ("wonsign.circle", "입장료", detail.useFee),
            ("car", "주차", detail.parking),
        ].filter { !$2.isEmpty }

        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("이용팁")
                    .font(.headline)
                ForEach(tips, id: \.1) { icon, label, value in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(value)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Skeleton / Failed

    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 16)
            }
        }
        .padding(20)
    }

    private var failedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange.opacity(0.6))
            Text("장소 정보를 불러오지 못했어요.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Helpers

    private func openInMaps() {
        let url = URL(string: "maps://?daddr=\(place.lat),\(place.lng)&dirflg=d")!
        UIApplication.shared.open(url)
    }

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

// MARK: - InfoRow

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
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
        PlaceDetailView(place: place)
    }
}
```

- [ ] **Step 2: `PlaceDetailSheet.swift` 삭제**

```bash
rm ios/JejuFolklore/Sources/Views/PlaceDetailSheet.swift
```

- [ ] **Step 3: 커밋**

```bash
git add ios/JejuFolklore/Sources/Views/PlaceDetailView.swift
git rm ios/JejuFolklore/Sources/Views/PlaceDetailSheet.swift
git commit -m "feat(ui): replace PlaceDetailSheet with full-screen PlaceDetailView (Triple style)"
```

---

## Task 5: CoursePreviewView — sheet → navigationDestination 교체

**Files:**
- Modify: `ios/JejuFolklore/Sources/Views/CoursePreviewView.swift:53-55`

- [ ] **Step 1: `.sheet` 블록을 `.navigationDestination(item:)`으로 교체**

기존 (`CoursePreviewView.swift:53-55`):
```swift
        .sheet(item: $selectedPlace) { place in
            PlaceDetailSheet(place: place)
        }
```

교체 후:
```swift
        .navigationDestination(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
        }
```

- [ ] **Step 2: 커밋**

```bash
git add ios/JejuFolklore/Sources/Views/CoursePreviewView.swift
git commit -m "feat(ui): place card tap → push PlaceDetailView instead of sheet"
```

---

## Task 6: xcodegen 재생성 및 빌드 확인

**Files:**
- Regenerate: `ios/JejuFolklore.xcodeproj`

새 파일(`PlaceDetailView.swift`) 추가, 구 파일(`PlaceDetailSheet.swift`) 삭제 후 xcodeproj를 재생성해야 Xcode가 인식한다.

- [ ] **Step 1: xcodegen 실행**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/ios && xcodegen generate
```

예상 출력:
```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at .../JejuFolklore.xcodeproj
```

- [ ] **Step 2: Xcode에서 프로젝트 리로드 확인**

Xcode가 "The project file was modified — Reload?" 다이얼로그를 띄우면 **Reload** 클릭. 안 뜨면 File → Close Project → 다시 열기.

- [ ] **Step 3: 수동 검증 체크리스트**

```
□ 코스 미리보기 → 장소 카드 탭 → 우측에서 슬라이드되며 PlaceDetailView 열림
□ 네비게이션 바에 장소명 표시, 뒤로가기 버튼 작동
□ 사진 캐러셀: 스와이프 시 이미지 전환, "N/총계" 뱃지 업데이트
□ 사진 없는 장소 → 주황 placeholder 표시
□ 공유하기 → iOS 공유 시트 열림
□ overview 있는 장소 → 설명 섹션 표시
□ overview 없는 장소 → 설명 섹션 숨김
□ 설화 있는 장소 → "이 곳에 깃든 이야기" 섹션 표시
□ 설화 없는 장소 → 설화 섹션 숨김
□ 기본정보 지도 탭 → Apple Maps 열림 (시뮬레이터는 지원 안 될 수 있음)
□ 길찾기 버튼 탭 → Apple Maps 열림
□ open_time 있는 장소 → 이용팁 섹션 표시
□ 이용팁 데이터 전부 없는 장소 → 이용팁 섹션 숨김
```

- [ ] **Step 4: 커밋**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프
git add ios/JejuFolklore.xcodeproj/project.pbxproj
git commit -m "chore: regenerate xcodeproj for PlaceDetailView"
```

---

## Self-Review

### Spec 커버리지 체크

| 요구사항 | 구현 태스크 |
|---------|-----------|
| 우측 슬라이드 전환 (sheet 아님) | Task 5 (navigationDestination) |
| 사진 캐러셀 + N/총계 뱃지 | Task 4 (TabView + counter) |
| 공유하기 버튼 | Task 4 (ShareLink) |
| 설명 텍스트 | Task 4 (overviewSection) |
| 설화 섹션 (우리 차별점) | Task 4 (folkloreSection) |
| 기본정보 소형 지도 | Task 4 (Map + disabled) |
| 주소 · 전화번호 | Task 4 (InfoRow) |
| 길찾기 버튼 | Task 4 (openInMaps) |
| 이용팁 (운영시간·휴무·입장료·주차) | Task 4 (introSection) |
| KTO 사진 복수 | Task 2 (_fetch_images) |
| KTO 이용팁 데이터 | Task 2 (_fetch_intro) |
| DB 스키마 자동 마이그레이션 | Task 1 (PRAGMA + DROP + CREATE) |

### Placeholder 없음 확인 ✓

모든 Step에 실제 코드 포함.

### 타입 일관성 확인 ✓

- `PlaceDetail.images: [String]` ↔ 백엔드 `images: list[str]` ↔ `_fetch_images() -> list[str]`
- `PlaceDetail.openTime` ↔ `.convertFromSnakeCase` ↔ 백엔드 `open_time`
- `PlaceDetailView(place: CoursePlace)` ↔ `navigationDestination(item: $selectedPlace)`에서 `CoursePlace` 전달
- `InfoRow(icon:text:)` — Task 4 내에서 정의·사용 일치

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-22-place-detail-view.md`.**

**Two execution options:**

**1. Subagent-Driven (recommended)** — 태스크마다 서브에이전트 디스패치, 태스크 간 리뷰

**2. Inline Execution** — 이 세션에서 직접 실행, 체크포인트마다 확인

**Which approach?**
