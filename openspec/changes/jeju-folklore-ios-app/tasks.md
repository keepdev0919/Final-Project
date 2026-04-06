## 1. Xcode 프로젝트 셋업

- [ ] 1.1 `ios/` 디렉토리에 SwiftUI + SwiftData Xcode 프로젝트 생성 (번들 ID: com.keepdev.jejufolklore)
- [ ] 1.2 `Config.swift` 작성 — DEBUG/RELEASE 백엔드 베이스 URL 분기
- [ ] 1.3 `APIClient.swift` 작성 — URLSession async/await 기반 공통 request/response 레이어
- [ ] 1.4 Info.plist에 위치 권한 설명 추가 (NSLocationWhenInUseUsageDescription, NSLocationAlwaysAndWhenInUseUsageDescription)
- [ ] 1.5 Info.plist에 백그라운드 모드 설정 (location, audio)

## 2. 데이터 모델 (SwiftData + Codable)

- [ ] 2.1 `Pin.swift` — Codable struct (code_no, title, source_type, summary, lat, lng, primary_place, distance_m)
- [ ] 2.2 `Course.swift` — Codable struct (id, title, duration_days, places, estimated_minutes)
- [ ] 2.3 `CoursePlace.swift` — Codable struct (name, lat, lng, day, start_time, folklore_pins)
- [ ] 2.4 `ChatMessage.swift` — Codable struct (role, content, sources)
- [ ] 2.5 `SavedCourse.swift` — @Model 클래스 (SwiftData 로컬 저장용)

## 3. 서비스 레이어

- [ ] 3.1 `LocationService.swift` — CLLocationManager 싱글톤, 백그라운드 GPS 추적, 도착 반경 감지
- [ ] 3.2 `PinsAPI.swift` — GET /pins 호출, lat/lng/radius_m 파라미터
- [ ] 3.3 `CourseAPI.swift` — POST /course/recommend 호출
- [ ] 3.4 `ChatAPI.swift` — POST /chat SSE 스트리밍 파싱 (AsyncStream<String>)
- [ ] 3.5 `TTSAPI.swift` — POST /tts 호출, MP3 Data 반환
- [ ] 3.6 `AudioPlayer.swift` — AVAudioPlayer 래퍼, AVAudioSession .playback 설정

## 4. 홈 지도 화면 (map-home)

- [ ] 4.1 `HomeViewModel.swift` — 핀 로딩, 지도 이동 감지, 뷰포트 기반 API 호출 로직
- [ ] 4.2 `HomeView.swift` — Map(MapKit) + 핀 마커 어노테이션, clusteringIdentifier 설정
- [ ] 4.3 마커 탭 → 바텀 팝업 카드 (설화 제목 + summary + "더 보기" 버튼)
- [ ] 4.4 팝업 외부 탭 시 dismiss 처리

## 5. 코스 추천 화면 (course-recommendation)

- [ ] 5.1 `CourseRecommendViewModel.swift` — 테마/일수/이동수단 상태, API 호출 및 단계별 로딩 상태 관리
- [ ] 5.2 `CourseRecommendView.swift` — 테마 선택 그리드, 일수·이동수단 피커
- [ ] 5.3 로딩 화면 — "설화 검색 중...", "동선 최적화 중...", "완성!" 단계별 텍스트 애니메이션
- [ ] 5.4 에러 상태 뷰 + 다시 시도 버튼

## 6. 코스 미리보기 + 저장 (course-preview)

- [ ] 6.1 `CoursePreviewViewModel.swift` — 코스 데이터 보관, SwiftData 저장 로직
- [ ] 6.2 `CoursePreviewView.swift` — Map 위 번호 마커 + 폴리라인 경로 표시
- [ ] 6.3 하단 시트 — 장소 카드 스크롤 뷰 (장소명, 설화 제목, 혼잡도 배지 🟢🟡🔴)
- [ ] 6.4 저장 버튼 → SwiftData에 SavedCourse 저장 + 토스트 피드백
- [ ] 6.5 다시 추천 버튼 → 동일 조건 재호출

## 7. 내 코스 목록 화면

- [ ] 7.1 `MyCourseListView.swift` — SwiftData @Query로 저장된 코스 목록 표시
- [ ] 7.2 코스 카드 탭 → 탐험 시작 버튼 포함 상세 뷰

## 8. 탐험 모드 (explore-mode)

- [ ] 8.1 `ExploreViewModel.swift` — 탐험 상태 관리, 도착 이벤트 수신, 방문 완료 장소 추적
- [ ] 8.2 `ExploreView.swift` — 실시간 GPS 지도 뷰, 현재 위치 블루닷, 다음 목적지 표시
- [ ] 8.3 LocationService에 도착 반경 감지 추가 (도보 100m / 차량 300m, 중복 방지)
- [ ] 8.4 UNUserNotificationCenter 도착 알림 — "설화 듣기" 액션 버튼 포함
- [ ] 8.5 알림 액션 → 백그라운드에서 TTS 재생 (UNNotificationAction + AudioPlayer)
- [ ] 8.6 `FolkloreDetailView.swift` — 설화 탭 (텍스트 + TTS 재생 버튼) / 공식 안내 탭 (KTO 오디오 가이드)
- [ ] 8.7 TTS 재생 백그라운드 유지 (AVAudioSession .playback 카테고리)

## 9. 챗봇 화면 (chatbot-ui)

- [ ] 9.1 `ChatViewModel.swift` — 메시지 히스토리 관리, SSE 스트림 수신, course_id 컨텍스트 주입
- [ ] 9.2 `ChatView.swift` — 메시지 버블 리스트, 스트리밍 토큰 append 애니메이션
- [ ] 9.3 텍스트 입력창 + 전송 버튼, 스트리밍 중 전송 비활성화

## 10. 스토리 생성 화면 (story-generation, 스트레치)

- [ ] 10.1 `StoryViewModel.swift` — POST /story/generate 호출, 이미지 URL 유무에 따른 폴백 처리
- [ ] 10.2 `StoryView.swift` — 에세이 텍스트 + DALL-E 삽화 (이미지 없으면 텍스트만)
- [ ] 10.3 TTS 재생 버튼 — 에세이 텍스트를 AudioPlayer로 팟캐스트 형식 재생

## 11. 통합 확인

- [ ] 11.1 시뮬레이터에서 홈 지도 핀 로딩 동작 확인
- [ ] 11.2 코스 추천 → 미리보기 → 저장 전체 플로우 확인
- [ ] 11.3 실기기에서 백그라운드 GPS 추적 및 도착 알림 동작 확인
- [ ] 11.4 챗봇 SSE 스트리밍 텍스트 렌더링 확인
