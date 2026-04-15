## Context

기존 설화 취향 기반 UX에서 범용 여행 계획 UX로 전환.
핵심 자산: Visit Jeju 9,134개 실제 여행 경로 (SQLite).
설화(228개 GPS 보유)는 경로 선택 이후 스토리텔링 레이어로 동작.

참고 오픈소스 구조:
- `LangGraph Template Travel Planner`: 조건 → LLM 코스 선택 → 결과
- `Travel Guide Adaptive RAG`: RAG를 보조 레이어로 사용

제약:
- iOS SwiftUI 기반
- 설화 GPS 228개, 지역 편중 있음 (북부 105개, 중부 98개, 남부 25개)
- gpt-4o 기존 의존성 유지

## Goals / Non-Goals

**Goals:**
- 일반 관광객이 자연스럽게 답할 수 있는 3가지 질문으로 입력 단순화
- 코스 리스트 → 상세 2단계 UX로 사용자 선택권 부여
- 설화를 스토리텔링 레이어로 활용 (LLM이 코스+설화 엮어 내러티브 생성)
- 리스트 로딩은 빠르게, 상세 생성은 클릭 시점에 lazy 처리

**Non-Goals:**
- 동행 유형 입력 (DB에 16%만 반영 가능, 제외)
- 설화 GPS 데이터 확장 (별도 작업)
- 챗봇 에이전트 변경

## Decisions

### 1. 사용자 입력 3가지 확정

| 항목 | 선택지 | 활용 방식 |
|------|--------|----------|
| 기간 | 1~5일 | SQLite duration_days 필터 |
| 지역 | 동부/서부/남부/북부/전체 | GPS 기반 course_places 필터 |
| 스타일 | 자연·오름/해변·바다/맛집·카페/문화·역사 | LLM 판단 힌트 + 코스 제목 키워드 |

지역별 GPS 범위 (제주 중심 33.36°N, 126.53°E 기준):
- 북부: lat >= 33.45
- 남부: lat < 33.30
- 동부: lng >= 126.70
- 서부: lng < 126.40
- 전체: 필터 없음

### 2. API 2개 분리

**POST /course/list**
- 입력: region, style, duration_days
- 처리: LLM이 조건 맞는 코스 3개 선택, 제목+장소 목록만 반환
- 목표 응답시간: 5초 이내

**POST /course/detail**
- 입력: course_id, region, style
- 처리: GPS 설화 매핑 + LLM 내러티브 생성
- 목표 응답시간: 15초 이내

### 3. List 에이전트 설계

도구 1개: `search_jeju_courses(duration_days, region)`
- SQLite에서 지역 GPS 필터 + 기간 필터 + RANDOM LIMIT 15
- 반환: 코스 10개 후보

LLM이 스타일 힌트 보고 3개 선택.
설화 검색 없음 → 빠른 응답.

### 4. Detail 에이전트 설계

코드가 GPS 매핑 처리 (LLM 환각 방지):
1. course_id로 장소 목록 조회
2. 각 장소 GPS 기준 반경 3km 내 설화 매핑
3. 매핑 결과 + 스타일 힌트를 LLM에 전달

LLM이 하는 일:
- 코스 전체를 관통하는 여행 내러티브 생성
- 각 장소별 설화 연결 문장 생성

### 5. 지역 선택 UI

SwiftUI에서 제주도 지도 이미지 위에 투명 버튼 오버레이.
지도 이미지: 단순화된 제주도 실루엣 (Assets.xcassets 추가).
5개 구역 (북/남/동/서/전체) 탭 영역 좌표 하드코딩.

### 6. 스타일 카드 UI

기존 MoodCardView 재사용, 선택지만 교체.
이미지는 기존 mood_* 이미지 임시 재사용.

| 스타일 | 임시 이미지 | 백엔드 키 |
|--------|------------|----------|
| 자연·오름 | mood_grand_sacred | nature |
| 해변·바다 | mood_village | ocean |
| 맛집·카페 | mood_cheerful | food |
| 문화·역사 | mood_mysterious | culture |

## Risks / Trade-offs

- **스타일 필터링 약함**: Visit Jeju 코스 제목에 스타일 키워드 명시 비율 낮음. LLM 판단에 의존.
  → 시스템 프롬프트로 스타일별 장소 특성 명시해 보완

- **남부 설화 커버리지**: 서귀포 인근 설화 25개로 적음. 남부 선택 시 설화 없는 장소 다수 가능.
  → Detail 화면에서 설화 없는 장소는 조용히 표시하되 내러티브는 생성

- **로딩 2회**: 리스트 + 상세 각각 로딩 발생.
  → 각 단계 로딩 UI 명확히 표시

## Migration Plan

1. 백엔드: schemas.py → course.py → course_agent.py → course_detail_agent.py 순 작업
2. iOS: TasteDiscoveryView → CourseListView → CoursePreviewView 순 작업
3. 기존 /course/recommend 엔드포인트 유지하며 병행 개발 후 교체

롤백: git revert로 즉시 복구 가능.
