## 1. 도구 구현

- [ ] 1.1 `search_jeju_courses(duration_days)` 도구 구현 — SQLite 조회, GPS 필터, JSON 반환
- [ ] 1.2 `get_folklore_near_place(lat, lng, query, radius_m)` 도구 구현 — ChromaDB RAG + GPS 반경 필터
- [ ] 1.3 folklore_gps.json 캐시 로딩 (모듈 레벨 싱글톤, 매 요청마다 파일 읽기 방지)

## 2. AgentState 및 structured output 스키마

- [ ] 2.1 `AgentState` 재정의 — messages(Annotated list), user_input, category_scores, duration_days, final_course, course_title, error
- [ ] 2.2 Pydantic 모델 정의 — `FolkloreRef`, `PlaceRef`, `CourseOutput` (format_output용)

## 3. 노드 구현

- [ ] 3.1 `initialize` 노드 — category_scores → 사람 읽기 좋은 문장 변환, SystemMessage + HumanMessage 생성
- [ ] 3.2 `call_model` 노드 — llm.bind_tools([tools])로 ReAct 루프 LLM 호출
- [ ] 3.3 `call_tools` 노드 — ToolNode(tools) 활용해 tool call 실행
- [ ] 3.4 `format_output` 노드 — llm.with_structured_output(CourseOutput)으로 최종 코스 추출
- [ ] 3.5 `should_continue` 라우터 — tool_calls 있으면 "tools", MAX_TOOL_CALLS 초과 또는 없으면 "format_output"

## 4. 그래프 조립

- [ ] 4.1 StateGraph 노드 등록 및 엣지 연결 (initialize → call_model → conditional → call_tools/format_output)
- [ ] 4.2 시스템 프롬프트 작성 — 도구 호출 순서 안내, GPS 직접 생성 금지 명시

## 5. 라우터 수정

- [ ] 5.1 `course.py` invoke state 정리 — messages:[] 추가, 불필요 필드(transport, region, candidate_courses 등) 제거

## 6. 검증

- [ ] 6.1 백엔드 로컬 실행 후 `POST /course/recommend` 수동 호출 테스트 (duration_days=1, category_scores 포함)
- [ ] 6.2 응답 JSON이 기존 Course 스키마와 호환되는지 확인
- [ ] 6.3 GPS 좌표가 실제 DB 데이터와 일치하는지 샘플 확인
