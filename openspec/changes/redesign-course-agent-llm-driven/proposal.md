## Why

현재 LangGraph 코스 추천 에이전트는 LLM을 거의 사용하지 않는 코드 파이프라인이다 (SQL → GPS 거리 계산 → coverage 정렬 → 하드코딩 제목). LLM이 중심이 되어 도구를 직접 호출하고 사용자 취향에 맞는 코스를 선택·종합하는 진짜 AI 에이전트로 재설계한다.

## What Changes

- **BREAKING** `course_agent.py` 전면 재작성: 코드 파이프라인 → ReAct 패턴 LLM 에이전트
- LLM이 두 도구를 직접 호출하며 코스 후보 탐색 및 설화 매핑 수행
  - `search_jeju_courses(duration_days)`: SQLite에서 비짓제주 코스 조회
  - `get_folklore_near_place(lat, lng, query, radius_m)`: GPS + ChromaDB RAG로 인근 설화 검색
- GPS 거리 계산은 도구 내부에서 코드로 처리 (LLM 환각 방지)
- LLM이 설화 커버리지·테마 적합성을 보고 최종 코스 선택 (기존: 숫자 정렬)
- LLM이 코스 제목 생성 (기존: 하드코딩 템플릿)
- `AgentState`에서 중간 처리용 필드 제거, `messages` 리스트 추가
- `transport` 필드 완전 제거 (이미 UI·스키마에서 제거됨)

## Capabilities

### New Capabilities
- `llm-course-agent`: LLM이 도구를 직접 호출해 비짓제주 코스와 설화를 연결하는 ReAct 에이전트

### Modified Capabilities
- `rag-chat-engine`: 변경 없음 (챗봇 에이전트는 그대로)

## Impact

- `backend/agents/course_agent.py`: 전면 재작성
- `backend/routers/course.py`: 초기 state 구조 변경 (messages 필드 추가, 불필요 필드 제거)
- `backend/models/schemas.py`: 변경 없음 (Course, CoursePlace 스키마 동일)
- iOS 클라이언트: 변경 없음 (API 응답 형식 동일)
- 의존성: `langchain-core`, `langgraph` (기존 설치됨)
