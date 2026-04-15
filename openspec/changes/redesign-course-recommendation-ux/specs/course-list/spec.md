## ADDED Requirements

### Requirement: 지역/스타일/기간 기반 코스 후보 3개 반환
`POST /course/list`는 region, style, duration_days를 입력받아 조건에 맞는 코스 후보 3개를 반환해야 한다. 설화 매핑은 포함하지 않는다.

#### Scenario: 정상 요청
- **WHEN** region, style, duration_days가 유효한 값으로 요청되면
- **THEN** 코스 3개를 title, duration_days, places(place_name, lat, lng, day) 포함하여 반환해야 한다

#### Scenario: 지역 필터 동작
- **WHEN** region이 "동부"로 요청되면
- **THEN** 반환된 코스의 장소 GPS가 제주 동부(lng >= 126.70) 에 위치해야 한다

#### Scenario: 전체 지역 요청
- **WHEN** region이 "전체"로 요청되면
- **THEN** 지역 필터 없이 duration_days 조건만으로 코스를 반환해야 한다

### Requirement: 리스트 응답 속도
`/course/list`는 5초 이내에 응답해야 한다.

#### Scenario: 응답 시간 준수
- **WHEN** 정상 요청이 들어오면
- **THEN** 서버는 5초 이내에 코스 리스트를 반환해야 한다
