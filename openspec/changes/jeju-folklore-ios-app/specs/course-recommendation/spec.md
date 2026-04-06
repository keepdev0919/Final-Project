## ADDED Requirements

### Requirement: theme-and-condition-input
앱은 코스 추천을 위해 테마, 여행 일수, 이동수단 세 가지 조건을 입력받는 화면을 제공해야 한다.

#### Scenario: theme-selection
- **WHEN** 사용자가 코스 추천 화면에 진입할 때
- **THEN** 신화, 도깨비·요괴, 사랑과 이별, 바다·해녀, 오름·자연 5개 테마 중 하나를 선택할 수 있어야 한다

#### Scenario: condition-input
- **WHEN** 테마를 선택한 후
- **THEN** 여행 일수(1~5)와 이동수단(차량/도보)을 선택할 수 있어야 한다

### Requirement: course-generation-request
조건 입력 완료 후 `/course/recommend` API를 호출하고, 생성이 완료될 때까지 진행 상황을 단계별 텍스트로 표시해야 한다.

#### Scenario: loading-feedback
- **WHEN** 추천 버튼을 탭하여 API 호출이 시작될 때
- **THEN** "설화 검색 중...", "동선 최적화 중...", "완성!" 순서로 단계별 로딩 텍스트가 표시되어야 한다

#### Scenario: generation-success
- **WHEN** `/course/recommend` API가 Course 객체를 반환할 때
- **THEN** 코스 미리보기 화면으로 자동 전환되어야 한다

#### Scenario: generation-failure
- **WHEN** API 호출이 실패하거나 에러 응답을 반환할 때
- **THEN** 에러 메시지와 함께 다시 시도 버튼이 표시되어야 한다
