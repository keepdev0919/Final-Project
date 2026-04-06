## ADDED Requirements

### Requirement: folklore-pin-display
앱은 제주도 전역 지도 위에 설화·민담 위치를 마커 핀으로 표시해야 한다. 핀은 `/pins` API가 반환하는 데이터를 기반으로 하며, 현재 지도 뷰포트 중심 좌표와 반경을 기준으로 조회한다.

#### Scenario: initial-map-load
- **WHEN** 앱이 처음 실행되어 홈 화면이 나타날 때
- **THEN** 제주도 전체가 보이는 줌 레벨로 MapKit 지도가 표시되어야 한다
- **AND** 현재 위치 권한이 허용된 경우 사용자 위치 블루닷이 표시되어야 한다

#### Scenario: pin-loading-on-map-move
- **WHEN** 사용자가 지도를 이동하거나 줌 변경 후 정지할 때
- **THEN** 새 뷰포트 중심 좌표와 화면 대각선 거리의 절반을 반경으로 `/pins` API를 호출해야 한다
- **AND** 응답받은 핀이 지도 위에 마커로 표시되어야 한다

### Requirement: pin-clustering
핀 개수가 밀집된 영역에서는 개별 마커 대신 클러스터 마커로 묶어 표시해야 한다.

#### Scenario: clustered-view
- **WHEN** 동일 화면 영역 내 핀이 5개 이상 겹칠 때
- **THEN** 개별 마커 대신 숫자가 표시된 클러스터 마커 하나로 대체되어야 한다

#### Scenario: cluster-expand
- **WHEN** 사용자가 클러스터 마커를 탭할 때
- **THEN** 지도가 해당 클러스터 영역으로 줌인되어야 한다

### Requirement: pin-popup
마커를 탭하면 해당 설화·민담의 제목과 한 줄 요약을 담은 팝업 카드가 표시되어야 한다.

#### Scenario: marker-tap
- **WHEN** 사용자가 개별 핀 마커를 탭할 때
- **THEN** 설화 제목과 summary 필드 텍스트를 담은 바텀 팝업 카드가 나타나야 한다
- **AND** 팝업 카드에는 "더 보기" 버튼이 있어야 한다

#### Scenario: popup-dismiss
- **WHEN** 사용자가 팝업 카드 외부 지도 영역을 탭할 때
- **THEN** 팝업 카드가 사라져야 한다
