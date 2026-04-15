## ADDED Requirements

### Requirement: LLM이 도구를 직접 호출해 코스 탐색
에이전트는 `search_jeju_courses` 도구와 `get_folklore_near_place` 도구를 LLM이 자율적으로 호출하는 ReAct 패턴으로 동작해야 한다. 코스 선택 및 설화 연결은 코드 분기가 아닌 LLM의 추론으로 수행된다.

#### Scenario: LLM이 코스 검색 도구 호출
- **WHEN** 사용자가 여행 일수와 취향 카테고리를 전달하면
- **THEN** LLM은 `search_jeju_courses(duration_days)` 도구를 호출하여 비짓제주 후보 코스를 조회해야 한다

#### Scenario: LLM이 설화 검색 도구 호출
- **WHEN** LLM이 코스 후보를 확인하고 특정 장소의 설화 정보가 필요하면
- **THEN** LLM은 `get_folklore_near_place(lat, lng, query)` 도구를 호출하여 해당 장소 인근 설화를 조회해야 한다

#### Scenario: 도구 호출 최대 횟수 초과
- **WHEN** 도구 호출 누적 횟수가 12회를 초과하면
- **THEN** 에이전트는 루프를 종료하고 format_output 단계로 강제 이동해야 한다

### Requirement: GPS 좌표는 실제 데이터만 사용
에이전트가 반환하는 모든 장소·설화의 GPS 좌표는 도구에서 반환된 실제 DB 데이터여야 하며, LLM이 임의로 생성한 좌표를 포함해서는 안 된다.

#### Scenario: 장소 좌표 출처 검증
- **WHEN** 최종 코스에 장소가 포함될 때
- **THEN** 해당 장소의 lat/lng는 `search_jeju_courses` 도구가 반환한 값과 동일해야 한다

#### Scenario: 설화 좌표 출처 검증
- **WHEN** 최종 코스에 설화 핀이 포함될 때
- **THEN** 해당 설화의 lat/lng는 `get_folklore_near_place` 도구가 반환한 값과 동일해야 한다

### Requirement: LLM이 최종 코스 선택 및 제목 생성
LLM은 취향 카테고리 점수와 설화 내용을 바탕으로 후보 코스 중 가장 적합한 코스를 선택하고, 설화 주제를 반영한 코스 제목을 생성해야 한다.

#### Scenario: 취향 기반 코스 선택
- **WHEN** 복수의 후보 코스가 있고 사용자 category_scores가 전달된 경우
- **THEN** LLM은 점수가 높은 카테고리와 관련된 설화가 풍부한 코스를 선택해야 한다

#### Scenario: 코스 제목 생성
- **WHEN** 최종 코스가 결정되면
- **THEN** 에이전트는 하드코딩 템플릿이 아닌 LLM이 생성한 고유 제목을 `course_title`로 반환해야 한다

### Requirement: 구조화된 코스 출력
에이전트는 기존 `Course`, `CoursePlace`, `Pin` 스키마와 호환되는 구조화된 결과를 반환해야 한다.

#### Scenario: 정상 완료 시 구조화 출력
- **WHEN** ReAct 루프가 완료되면
- **THEN** `final_course`는 `{id, title, places[{place_name, lat, lng, day, folklore_nearby[{code_no, title, source_type, lat, lng, distance_m}]}]}` 형태여야 한다

#### Scenario: 구조화 실패 시 에러 반환
- **WHEN** format_output 단계에서 structured output 추출에 실패하면
- **THEN** `error` 필드에 오류 메시지를 담고 `final_course`는 빈 dict를 반환해야 한다

### Requirement: search_jeju_courses 도구 스펙
`search_jeju_courses(duration_days: int)` 도구는 비짓제주 SQLite DB에서 여행 일수에 맞는 코스 목록을 반환해야 한다.

#### Scenario: 정상 조회
- **WHEN** `duration_days`가 1~5 사이 정수로 호출되면
- **THEN** GPS 좌표가 있는 장소를 포함하는 코스 목록을 JSON 배열로 반환해야 한다 (최대 10개)

#### Scenario: 일수 유연성
- **WHEN** 정확한 일수의 코스가 부족하면
- **THEN** `duration_days ± 1` 범위의 코스도 포함하여 반환해야 한다

### Requirement: get_folklore_near_place 도구 스펙
`get_folklore_near_place(lat, lng, query, radius_m=3000)` 도구는 GPS 좌표 기준 반경 내 관련 설화를 반환해야 한다.

#### Scenario: RAG + GPS 복합 필터
- **WHEN** lat, lng, query가 주어지면
- **THEN** ChromaDB RAG 검색(cosine distance < 0.70)과 GPS 반경 필터를 모두 통과한 설화만 반환해야 한다

#### Scenario: 결과 정렬
- **WHEN** 반경 내 설화가 복수 존재하면
- **THEN** 거리 오름차순으로 정렬하여 최대 10개를 반환해야 한다
