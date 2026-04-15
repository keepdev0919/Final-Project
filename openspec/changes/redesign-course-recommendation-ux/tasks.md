## 1. 백엔드 스키마 및 라우터

- [x] 1.1 `schemas.py` — CourseListRequest(region, style, duration_days), CourseDetailRequest(course_id, style), CourseListItem 모델 추가
- [x] 1.2 `course.py` — `/course/list` 엔드포인트 추가
- [x] 1.3 `course.py` — `/course/detail` 엔드포인트 추가

## 2. List 에이전트

- [x] 2.1 `course_list_agent.py` 신규 작성 — `search_jeju_courses(duration_days, region)` 도구 (지역 GPS 필터 포함)
- [x] 2.2 LLM이 스타일 힌트 보고 후보 10개 중 3개 선택하는 ReAct 루프 구현
- [x] 2.3 structured output: CourseListItem 3개 반환

## 3. Detail 에이전트

- [x] 3.1 `course_detail_agent.py` 신규 작성 — course_id로 장소 조회 후 GPS 설화 매핑 (코드)
- [x] 3.2 매핑 결과를 LLM에 전달해 여행 내러티브 생성
- [x] 3.3 structured output: Course(장소+설화핀+narrative) 반환

## 4. iOS — 입력 화면

- [x] 4.1 `TasteDiscoveryView.swift` — 질문 1단계: 제주도 지도 구역 탭 UI (지역 선택)
- [x] 4.2 `TasteDiscoveryView.swift` — 질문 2단계: 스타일 카드 4개 (기존 MoodCardView 재사용, 선택지 교체)
- [x] 4.3 `TasteDiscoveryView.swift` — 질문 3단계: 기간 선택 (기존 유지)
- [x] 4.4 `CourseRecommendViewModel.swift` — region/style/duration_days 상태 관리로 교체

## 5. iOS — 코스 리스트 화면

- [x] 5.1 `CourseListView.swift` 신규 작성 — 코스 카드 3개 리스트
- [x] 5.2 각 카드: 코스 제목, 일수, 대표 장소 2~3개 표시
- [x] 5.3 카드 탭 → `/course/detail` 호출 + 로딩 → CoursePreviewView 이동

## 6. iOS — API 클라이언트

- [x] 6.1 `CourseAPI.swift` — `list()` 함수 추가 (POST /course/list)
- [x] 6.2 `CourseAPI.swift` — `detail()` 함수 추가 (POST /course/detail)

## 7. iOS — 상세 화면

- [x] 7.1 `CoursePreviewView.swift` — narrative 텍스트 표시 영역 추가

## 8. 검증

- [ ] 8.1 `/course/list` 수동 테스트 — region/style/duration_days 조합별 응답 확인
- [ ] 8.2 `/course/detail` 수동 테스트 — 설화 핀 + 내러티브 포함 확인
- [ ] 8.3 iOS 시뮬레이터에서 전체 흐름 확인 (입력 → 리스트 → 상세)
