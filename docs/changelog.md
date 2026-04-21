# 개발 변경 이력

## 2026-04-21

### 아키텍처 전환: 설화가 코스를 선택한다

교수 피드백("기존 여행앱과 차별점이 없다")을 반영해 코스 선택 로직을 설화 중심으로 전면 재설계.
이전까지 설화는 코스 생성 후 내러티브에 "얹히는" 부가 콘텐츠였다. 이제는 설화 밀도가 코스를 고른다.

**흐름 변경 전:**
`사용자 취향(여행 스타일) → 여행 키워드 매칭 → 코스 선택 → 설화 내러티브 추가`

**흐름 변경 후:**
`사용자 취향(설화 테마) → ChromaDB 설화 검색 → GPS 반경 필터 → 설화 풍부한 코스 선택 → 내러티브`

#### 백엔드: `course_list_agent.py` 재작성

| 항목 | 이전 | 변경 후 |
|------|------|---------|
| 취향 매핑 | `STYLE_HINTS` (여행 키워드) | `FOLKLORE_THEME_QUERIES` (설화 텍스트) |
| 코스 선택 기준 | 여행 스타일 키워드 유사도 | `get_folklore_near_place` 도구로 실제 설화 밀도 확인 |
| 새 도구 | 없음 | `get_folklore_near_place`: ChromaDB 임베딩 검색 + GPS 3km 반경 필터 |
| MAX_TOOL_CALLS | 5 | 8 (여러 코스 설화 확인 위해) |

#### iOS: `TasteDiscoveryView.swift` 스타일 카드 업데이트

| 이전 레이블 | 이전 key | 변경 후 레이블 | 변경 후 key |
|-----------|---------|-------------|-----------|
| 자연·오름 | nature | 신비로운 제주 | dokkaebi |
| 문화·역사 | culture | 신성한 제주 | mythology |
| 해변·바다 | ocean | 바다의 제주 | haenyeo |
| 맛집·카페 | food | 사람의 제주 | human_story |

이미지는 기존 `mood_*.png` 4장 그대로 사용 (도안이 설화 테마와 정확히 매핑).

### 버그 수정: ChromaDB 멀티스레드 레이스 컨디션

`get_chroma_collection()`이 `@lru_cache`만 사용해 `PersistentClient`를 로컬 변수로 관리하던 구조에서
LangGraph ToolNode가 도구를 스레드에서 동시 호출할 때 GC + 레이스 컨디션으로 `KeyError` 발생.

- `services/db.py`: `_chroma_client` 모듈 레벨 보관 + double-checked locking으로 교체
- 5스레드 동시 접근 테스트 통과

### 버그 수정: `course_list_agent.py` 경로 오류 2건

- `BASE_DIR = Path(__file__).parent.parent` → `.parent.parent.parent` (프로젝트 루트로 수정)
  - `data/processed/folklore_gps.json` 파일을 `backend/data/`에서 찾던 오류
- `format_output` ID 매핑 실패: 메시지 슬라이스(`[-20:]`)로 코스 검색 결과가 잘려 LLM이 가짜 ID 생성
  - 유효 코스 ID 목록을 extraction_prompt에 명시적으로 포함해 수정

## 2026-04-15

### 분위기 질문 옵션 재설계 (카테고리 데이터 기반)

기존 4개 분위기 옵션은 직관으로 만들어 실제 카테고리 분포와 맞지 않았음.
GPS 설화 최종 분류(228개, 5개 카테고리) 결과를 바탕으로 역설계.

| 이전 | 변경 후 | 대응 카테고리 |
|------|---------|-------------|
| 신비롭고 으스스한 | 웅장하고 신성한 | 무속신화·신격 전승 (94개) |
| 따뜻하고 감동적인 | 유쾌하고 교훈 있는 | 생활민담·교훈담 (74개) |
| 웅장하고 신성한 | 마을과 공동체의 기억 | 마을 공동체 전승 (39개) |
| 사람들의 삶 이야기 | 신비롭고 으스스한 | 초자연 존재담 (10개) |

- 해양·어촌 전승(11개)은 장소 질문 "바다" 선택으로 점수 부여 (분위기 옵션 불필요)
- `지명·지형 유래`, `가족·인간사 서사`는 최종 분석에서 인접 범주로 통합 → 카테고리 목록에서 제거
- `mapCategoryScores()` 및 `CATEGORY_QUERIES` 5개 카테고리 기준으로 정리

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
- → [실험 결과](legacy/experiments/001-folklore-keyword-coverage-analysis.md)
- → [결정 기록](decisions/003-keyword-query-data-driven-redesign.md)

### 설화 카테고리 점수 기반 브리지 구현
- 기존 4단계 iOS 온보딩은 유지한 채, 내부적으로 7개 설화 카테고리 점수 계산 로직 추가
- iOS `theme` 요청과 함께 `category_scores` 전송
- 백엔드 코스 추천 파이프라인이 `category_scores`를 우선 사용하고, 없으면 기존 5개 테마 흐름으로 fallback
- → [결정 기록](decisions/005-user-question-redesign-from-folklore-analysis.md)

### 개발 워크플로우
- `start_dev.sh` 추가: 로컬 IP 자동 감지 후 Config.swift 업데이트 + 백엔드 실행
- `Config.swift` .gitignore 추가 (IP 주소 노출 방지)
