## ADDED Requirements

### Requirement: course-map-preview
추천된 코스의 장소들을 지도 위에 경로 선과 함께 표시해야 한다.

#### Scenario: route-display
- **WHEN** 코스 미리보기 화면이 로드될 때
- **THEN** 코스에 포함된 모든 장소가 번호 마커로 지도 위에 표시되어야 한다
- **AND** 장소들을 방문 순서대로 연결하는 폴리라인이 표시되어야 한다

### Requirement: place-card-list
코스에 포함된 장소 목록을 카드 형태로 스크롤하며 확인할 수 있어야 한다.

#### Scenario: place-card-display
- **WHEN** 사용자가 코스 미리보기 화면 하단 시트를 스크롤할 때
- **THEN** 각 장소 카드에 장소명, 매핑된 설화 제목, 혼잡도 배지가 표시되어야 한다

#### Scenario: congestion-badge
- **WHEN** 장소 카드가 렌더링될 때
- **THEN** 혼잡도 데이터가 있는 경우 🟢 여유 / 🟡 보통 / 🔴 혼잡 배지가 표시되어야 한다
- **AND** 혼잡도 데이터가 없는 경우 배지를 표시하지 않아야 한다

### Requirement: course-save
마음에 드는 코스를 기기 로컬 SQLite에 저장할 수 있어야 한다.

#### Scenario: save-course
- **WHEN** 사용자가 저장 버튼을 탭할 때
- **THEN** Course 객체가 기기 로컬 SQLite에 저장되어야 한다
- **AND** 저장 완료 토스트 메시지가 표시되어야 한다

#### Scenario: retry-recommendation
- **WHEN** 사용자가 다시 추천 버튼을 탭할 때
- **THEN** 동일한 조건으로 `/course/recommend` API를 재호출해야 한다
