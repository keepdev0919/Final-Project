# 개발 변경 이력

## 2026-04-08

### UX 재설계
- 메인 화면을 지도(HomeView)에서 Taste Discovery 온보딩으로 교체
- 4단계 퀴즈(분위기→장소→일수→이동수단)로 내부 테마를 자동 추론
- 탭 구조: 지도/코스추천/내코스/챗봇 → 코스만들기/내코스/챗봇
- → [결정 기록](decisions/001-ux-redesign-taste-discovery.md)

### 버그 수정: API 422 오류
- iOS JSONEncoder snake_case 설정 누락으로 `durationDays` → `duration_days` 변환 안 됨
- `APIClient.swift`에 `keyEncodingStrategy = .convertToSnakeCase` 추가

### 버그 수정: ChromaDB 500 오류
- 인제스트(1536-dim OpenAI)와 쿼리(384-dim 로컬 모델) 간 임베딩 차원 불일치
- `embed_query()` 함수 추가, `query_texts` → `query_embeddings` 방식으로 변경
- → [결정 기록](decisions/002-chromadb-embedding-dimension-fix.md)

### 설화 키워드 데이터 기반 재설계
- 505개 설화 파일 전수 분석으로 실제 출현 단어 추출
- 직관 키워드 → 실제 텍스트 기반 문장형 쿼리로 교체
- 예상 커버리지: 82.6% (417/505개)
- → [실험 결과](experiments/001-folklore-keyword-coverage-analysis.md)
- → [결정 기록](decisions/003-keyword-query-data-driven-redesign.md)

### 개발 워크플로우
- `start_dev.sh` 추가: 로컬 IP 자동 감지 후 Config.swift 업데이트 + 백엔드 실행
- `Config.swift` .gitignore 추가 (IP 주소 노출 방지)
