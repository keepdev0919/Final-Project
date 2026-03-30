# 한국관광공사 OpenAPI 통합 설계

**날짜**: 2026-03-30
**연관 문서**: `docs/superpowers/specs/2026-03-25-jeju-folklore-app-design.md`
**배경**: 2026 관광데이터 활용 공모전 (① 웹·앱 개발 부문) 참가 — 기존 졸업프로젝트와 동일 서비스로 제출

---

## 1. 선택 API (5개)

| API명 | 역할 | 호출 주체 |
|-------|------|---------|
| 한국관광공사_국문 관광정보 서비스 | 제주 관광지 상세 정보 (운영시간, 주소, 카테고리 등) | FastAPI (캐싱) |
| 한국관광공사_관광사진 정보 | 관광지 대표 사진 | Flutter 직접 |
| 한국관광공사_관광지 오디오 가이드정보 | 관광지 공식 역사·문화 해설 음성+대본 | Flutter 직접 |
| 한국관광공사_관광지별 연관 관광지 정보 | 코스 장소의 연관 관광지 (설화 커버리지 보강) | FastAPI |
| 한국관광공사_관광지 집중률 방문자 추이 예측 | 여행 예정일 기준 혼잡도 예측 | FastAPI |

### 선택 근거

- API 개수보다 **서비스 흐름에 자연스럽게 녹아있는지**가 심사 기준 (데이터 활용 적절성 20점)
- 5개 전부 사용자가 앱을 쓰는 특정 순간에 직접 노출됨 — 억지로 끼워넣은 API 없음
- 혼잡도 예측은 "AI 설화 코스 + 혼잡도 회피"라는 차별화 포인트로 기획력(30점)에도 기여

---

## 2. 서비스 흐름별 API 연결

### 계획 단계 (코스 추천)

```
LangGraph 에이전트 실행
    ├─ search_courses: Visit Jeju DB에서 조건 맞는 후보 코스 선별
    ├─ map_folklore: 각 장소 인근 설화·민담 RAG 매핑
    ├─ [NEW] enrich_places: 국문 관광정보 API로 각 장소 최신 정보 보완
    │       └─ 운영시간, 주소, 카테고리, 전화번호
    ├─ [NEW] replace_low_coverage: 설화 커버리지 낮은 장소를 연관 관광지 API로 대안 탐색
    ├─ [NEW] fetch_congestion: 집중률 예측 API로 여행 예정일 기준 혼잡도 조회
    └─ rank_courses: 설화 커버리지 + [NEW] 혼잡도 낮을수록 가중치 부여
```

### 계획 단계 (코스 미리보기)

- Flutter가 관광사진 API 직접 호출 → 각 장소 카드 대표 이미지 표시
- 코스 카드에 혼잡도 배지 표시: 🟢 여유 / 🟡 보통 / 🔴 혼잡 (예측일 기준)

### 여행 단계 (탐험 모드)

- 장소 도착 시:
  - **메인**: 우리 설화·민담 TTS 재생
  - **보조 탭**: 오디오 가이드 API의 공식 역사·문화 해설 음성+대본 제공
  - 두 콘텐츠를 "설화" / "공식 안내" 탭으로 분리 — 사용자가 선택

---

## 3. 기존 아키텍처 변경 사항

### FastAPI — 새 엔드포인트 3개

| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/tourist/info` | 국문 관광정보 조회 (`contentId` 파라미터) |
| GET | `/tourist/related` | 연관 관광지 조회 (`contentId` 파라미터) |
| GET | `/tourist/congestion` | 집중률 예측 조회 (`contentId`, `date` 파라미터) |

### LangGraph 에이전트 — 노드 변경

```
기존: analyze_request → search_courses → map_folklore → rank_courses → validate_course

변경: analyze_request → search_courses → map_folklore
         → enrich_places (신규)
         → replace_low_coverage (신규)
         → fetch_congestion (신규)
         → rank_courses (혼잡도 가중치 반영)
         → validate_course
```

- `rank_courses` 점수 = (설화 커버리지 × 0.7) + (혼잡도 역수 × 0.3)
- 혼잡도 데이터 없는 장소(API 미지원)는 기본값 0.5 적용

### Visit Jeju 장소 → contentId 매핑 전략

국문 관광정보·연관 관광지·집중률 API는 한국관광공사 `contentId`를 키로 사용한다.
Visit Jeju 장소 CSV에는 contentId가 없으므로 사전 매핑 작업이 필요하다.

1. **일괄 매핑 (전처리 단계)**: 국문 관광정보 API의 위치기반 검색으로 제주 전체 관광지 목록 수집 → 장소명 유사도 매칭(장소명 정규화 후 완전일치 우선, 부분일치 차선) → `content_id` 컬럼을 Visit Jeju 장소 테이블에 추가
2. **매핑 실패 처리**: contentId를 찾지 못한 장소는 해당 API 호출 스킵, 기본값 적용 (사진 없음, 혼잡도 0.5)
3. **예상 매핑률**: Visit Jeju 6,002개 장소 중 주요 관광지(제주 내 국문 관광정보 등록 장소)는 대부분 매핑 가능, 소규모 식당·숙소 등은 미매핑 허용

### SQLite — 테이블 추가

```sql
-- Visit Jeju 장소에 contentId 컬럼 추가 (기존 테이블 alter)
ALTER TABLE visit_jeju_places ADD COLUMN content_id TEXT;

-- 국문 관광정보 캐시
CREATE TABLE tourist_info_cache (
    content_id TEXT PRIMARY KEY,
    name       TEXT,
    address    TEXT,
    phone      TEXT,
    category   TEXT,
    cached_at  DATETIME
);
```

- 국문 관광정보·연관 관광지는 변경이 드물어 7일 캐시
- 집중률 예측은 일별로 달라지므로 캐시 안 함 (매 코스 추천 시 실시간 조회)

### Flutter — 직접 호출 (백엔드 경유 없음)

- 관광사진 API: 코스 미리보기 화면, 탐험 모드 장소 카드
- 오디오 가이드 API: 탐험 모드 "공식 안내" 탭

---

## 4. 공모전 심사 기준 매핑

| 심사항목 | 배점 | 이 설계가 어필하는 방식 |
|---------|------|----------------------|
| 서비스 기획력 (독창성, 트렌드) | 30 | 설화 RAG + 혼잡도 회피 AI 에이전트 — 단순 관광정보 앱과 차별화 |
| 서비스 완성도 (기능성, 편의성) | 30 | 5개 API가 각 화면에 명확히 연결된 완성된 흐름 |
| 데이터 활용 적절성 | 20 | 5개 API 전부 사용자가 직접 체감하는 위치에 배치 |
| 서비스 발전성 (확장성) | 20 | 영문 관광정보 API 추가 시 외국인 확장 용이한 구조 |
| **지역 특화 가점** | +2 | 제주 특화 서비스 → 자동 해당 |
| **제주 RTO 특별상** | 별도 | 제주관광공사 협업 RTO 특별상 후보 |
