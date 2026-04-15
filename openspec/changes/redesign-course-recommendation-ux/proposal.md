## Why

현재 코스 추천 UX는 설화 취향(분위기·장소) 기반으로 사용자 입력을 받는다. 그러나 일반 제주 관광객은 설화 카테고리에 관심이 낮고, 실제 여행 계획 시 고려하는 요소(지역·스타일·기간)와 동떨어져 있다. 서비스의 핵심 가치를 "9,134개 실제 검증된 여행 경로"로 재정의하고, 설화는 스토리텔링 레이어로 재배치한다.

## What Changes

- **BREAKING** 사용자 입력 질문 교체: 분위기/장소 → 지역/스타일
- **BREAKING** 코스 결과 UX 변경: 단일 코스 바로 표시 → 리스트 3개 → 상세 선택
- **BREAKING** API 분리: `/course/recommend` → `/course/list` + `/course/detail`
- **BREAKING** 백엔드 요청 스키마 변경: category_scores → region + style
- 지역 선택 UI: 텍스트 버튼 → 제주도 지도 구역 탭
- 스타일 선택 UI: 이미지 카드 형태 유지, 선택지 내용 변경
- 에이전트 역할 분리:
  - List 에이전트: 조건 기반 코스 3개 빠르게 선택 (설화 없음)
  - Detail 에이전트: 선택된 코스에 설화 GPS 매핑 + LLM 내러티브 생성
- 설화는 필터 기준이 아닌 스토리텔링 레이어로 동작

## Capabilities

### New Capabilities
- `course-list`: 지역/스타일/기간 조건으로 코스 후보 3개를 빠르게 반환
- `course-detail`: course_id 기반으로 설화 매핑 + 여행 내러티브 생성

### Modified Capabilities
- `llm-course-agent`: List/Detail 두 에이전트로 분리됨

## Impact

- `backend/agents/course_agent.py`: List 에이전트로 재작성
- `backend/agents/course_detail_agent.py`: Detail 에이전트 신규 생성
- `backend/routers/course.py`: 엔드포인트 2개로 분리
- `backend/models/schemas.py`: CourseRequest → region/style 필드, CourseListItem 모델 추가
- `ios/JejuFolklore/Sources/Views/TasteDiscoveryView.swift`: 질문 교체, 지도 UI 추가
- `ios/JejuFolklore/Sources/Views/CourseListView.swift`: 신규 화면
- `ios/JejuFolklore/Sources/Services/CourseAPI.swift`: 엔드포인트 2개로 분리
- `ios/JejuFolklore/Sources/ViewModels/CourseRecommendViewModel.swift`: 흐름 변경
