## Context

현재 `course_agent.py`는 LangGraph를 쓰지만 LLM은 테마 분류 1회(analyze_request)와 제목 생성 1회(finish)에만 사용된다. 나머지 노드(search_courses, map_folklore, rank_courses, validate_course)는 순수 코드 분기다. 에이전트가 아닌 파이프라인.

참고한 검증된 패턴:
- `Travel Guide Adaptive RAG` (github.com/enesbesinci/travel-guide-adaptive-rag): Chroma + 도구 기반 RAG, LLM이 검색 전략 결정
- `LangGraph Template Travel Planner` (github.com/datarootsio/langgraph-template-travel-planner): ReAct 패턴, LLM이 도구 호출 순서 자율 결정

제약:
- GPS 좌표는 실제 DB 데이터만 사용해야 함 (LLM 환각 방지)
- iOS 클라이언트 응답 형식(Course, CoursePlace, Pin) 변경 불가
- `gpt-4o`, LangGraph 기존 의존성 유지

## Goals / Non-Goals

**Goals:**
- LLM이 `search_jeju_courses`, `get_folklore_near_place` 도구를 직접 호출해 코스를 탐색
- LLM이 사용자 취향(category_scores)을 보고 코스를 선택 (숫자 정렬 대신 의미적 판단)
- LLM이 코스 제목을 자유롭게 생성
- GPS 거리 계산은 도구 내부 코드에서만 수행

**Non-Goals:**
- 챗봇 에이전트(ReAct chat) 변경
- iOS 클라이언트 변경
- KTO OpenAPI 연동 (별도 change)
- 스트리밍 응답 (현재 동기 방식 유지)

## Decisions

### 1. ReAct 패턴 채택 (create_react_agent vs 커스텀 그래프)

**결정**: 커스텀 LangGraph 그래프 (노드 4개)

**이유**: `create_react_agent`는 마지막에 structured output 추출이 어렵다. 커스텀 그래프로 `format_output` 노드를 명시적으로 추가하면 `llm.with_structured_output()`으로 안정적인 JSON 추출 가능.

**노드 구성**:
```
initialize → call_model → [tool_calls?] → call_tools → call_model (루프)
                        → [done]        → format_output → END
```

### 2. 도구 2개 설계

**`search_jeju_courses(duration_days: int) → str`**
- SQLite `courses` + `course_places` 조회
- `ORDER BY RANDOM() LIMIT 15` → GPS 있는 장소만 필터 후 최대 10개 반환
- 반환: JSON 배열 (id, title, duration_days, places[{place_name, lat, lng, day}])

**`get_folklore_near_place(lat: float, lng: float, query: str, radius_m: int = 3000) → str`**
- ChromaDB RAG 검색 (cosine distance < 0.70인 결과만)
- 해당 code_nos 중 GPS 반경 내 설화만 필터
- 반환: JSON 배열 (code_no, title, source_type, distance_m, lat, lng) 상위 10개

### 3. 초기 메시지 구성 (initialize 노드)

`category_scores`를 사람이 읽을 수 있는 문장으로 변환해 HumanMessage에 포함.
SystemMessage에 도구 사용 순서와 GPS 좌표 직접 생성 금지 명시.

```
system: 당신은 제주 설화 여행 플래너. 도구를 써서 코스 탐색. GPS는 직접 생성 금지.
human: 여행 일수: 2일. 취향: 무속신화 +3, 초자연 +1. 최적 코스를 계획하세요.
```

### 4. format_output: structured output 추출

ReAct 루프 종료 후 대화 히스토리 전체를 `llm.with_structured_output(CourseOutput)`에 넘겨 구조화.
`CourseOutput`은 Pydantic 모델 (course_id, course_title, places[{place_name, lat, lng, day, folklore_nearby}]).

**대안 고려**: `submit_course` 도구로 LLM이 직접 제출 → 추가 LLM 호출 없이 가능하나, 중첩 Pydantic 스키마 직렬화 복잡도가 높아 format_output 방식 채택.

### 5. 최대 반복 횟수 제한

도구 호출 횟수가 `MAX_TOOL_CALLS = 12` 초과 시 `format_output`으로 강제 이동.
무한 루프 방지.

### 6. 코스 후보 수: LIMIT 15 → 필터 후 최대 10개

설화 없는 코스는 LLM에게 넘기기 전에 제거 (GPS 매핑 후 folklore_coverage == 0 제외).
LLM 컨텍스트 절약 + 응답 품질 향상.

단, 필터 후 3개 미만이면 필터 완화 (coverage == 0도 포함).

## Risks / Trade-offs

- **LLM 응답 지연**: 도구 호출 N회 → 총 응답시간 증가 (기존 ~2초 → ~8~15초 예상)
  → 클라이언트 로딩 UI 유지 (이미 구현됨)

- **format_output 파싱 실패**: LLM이 도구 결과를 바탕으로 CourseOutput 구조화 실패 가능
  → try/except로 잡고 error 필드 반환, 라우터에서 404 처리 (기존 동일)

- **GPS 좌표 환각**: LLM이 format_output 단계에서 임의 좌표 생성 가능
  → 시스템 프롬프트에 금지 명시 + format_output 프롬프트에서 "도구에서 받은 좌표만 사용" 강조

- **비용**: gpt-4o 호출 2~4회 (도구 루프 + format_output) → 요청당 약 $0.02~0.05 예상
  → 기존 거의 0원 대비 증가, 졸업 프로젝트 규모에서는 허용 범위

## Migration Plan

1. `course_agent.py` 전면 재작성 (기존 파일 백업 불필요, git history 유지)
2. `course.py` 라우터: invoke state 구조 변경 (messages 추가, 불필요 필드 제거)
3. 로컬 백엔드 재시작 후 `POST /course/recommend` 수동 테스트
4. iOS 클라이언트 변경 없음

롤백: git revert 1커밋으로 즉시 복구 가능.

## Open Questions

- LLM이 모든 장소에 대해 `get_folklore_near_place`를 각각 호출할지, 아니면 대표 장소만 호출할지는 시스템 프롬프트로 유도하되 LLM 자율에 맡김.
- `radius_m` 기본값 3000m가 적절한지는 테스트 후 조정.
