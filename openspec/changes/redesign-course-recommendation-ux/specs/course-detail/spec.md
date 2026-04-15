## ADDED Requirements

### Requirement: course_id 기반 설화 매핑 및 내러티브 생성
`POST /course/detail`은 course_id를 받아 해당 코스 장소에 설화를 GPS 매핑하고, LLM이 코스와 설화를 엮은 여행 내러티브를 생성해 반환해야 한다.

#### Scenario: 정상 요청
- **WHEN** 유효한 course_id와 style이 요청되면
- **THEN** 장소별 설화 핀이 매핑된 코스와 전체 여행 내러티브 텍스트를 반환해야 한다

#### Scenario: 설화 없는 장소 처리
- **WHEN** 특정 장소 반경 3km 내 설화가 없으면
- **THEN** 해당 장소의 folklore_pins는 빈 배열로 반환하고 나머지 응답은 정상 생성해야 한다

### Requirement: LLM 여행 내러티브 생성
Detail 에이전트는 선택된 코스의 장소들과 매핑된 설화를 엮어 하나의 여행 내러티브를 생성해야 한다.

#### Scenario: 내러티브 포함 응답
- **WHEN** 설화가 1개 이상 매핑된 코스를 요청하면
- **THEN** 응답에 코스 전체를 관통하는 narrative 텍스트 필드가 포함되어야 한다

#### Scenario: 설화 전혀 없는 경우
- **WHEN** 모든 장소에 설화가 매핑되지 않으면
- **THEN** narrative는 설화 없이 장소 기반 여행 소개 텍스트로 생성해야 한다

### Requirement: GPS 좌표는 실제 DB 데이터만 사용
Detail 에이전트가 반환하는 모든 GPS 좌표는 SQLite 또는 folklore_gps.json의 실제 값이어야 한다.

#### Scenario: 좌표 출처 검증
- **WHEN** 코스 상세가 반환될 때
- **THEN** 모든 place의 lat/lng는 course_places 테이블의 실제 값과 동일해야 한다
