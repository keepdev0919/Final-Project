# Sprint 1 콘텐츠 파이프라인 아키텍처

> ⚠️ **[2026-07-20 방향 재정립]** "90개소 99,000자 양산" 목표는 새 전략(양산 지양, 성산 1개 압도적 완성)과 충돌 → 폐기. 단 GPS 앵커링·Grounding facts·미디어 인프라 섹션은 성산 1개 스코프로 **재활용 예정.** 현행 방향 SSoT → [`방향성_재정립_2026-07-20.md`](방향성_재정립_2026-07-20.md).

**목표:** 5개 공공 데이터 소스를 통합해 제주 관광지 90개소에 대한 RAG 원자재 99,000자 확보
**기간:** Sprint 1 (2026-07-21~08-17, 4주)
**성공 기준:** TestFlight 배포 시점에 30개소 이상 실사용 가능 콘텐츠 준비 (Deep Research 최소 목표)
**연관 문서:** [공공데이터.md](공공데이터.md) · [방향성_재정립_2026-07-14.md](../legacy/방향성_재정립_2026-07-14.md)

---

## 0. 파이프라인 개요

```
        [소스 수집]              [정제·통합]                [저장·인덱싱]              [배포]
┌─────────────────────┐    ┌──────────────────────┐    ┌────────────────────┐    ┌─────────────────┐
│  Layer 1: Spatial   │    │  Merge Engine        │    │  PostgreSQL        │    │  FastAPI        │
│  #3 제주도청 CSV     │───▶│  · GeoHash 매핑      │───▶│  · spots           │    │  · /spots/near  │
│  (1,047개소 GPS)    │    │  · 좌표 정규화        │    │  · geohash index   │    │  · /story/:id   │
└─────────────────────┘    │  · 결측치 처리        │    └────────┬───────────┘    │  · /verify/:id  │
                           └──────────────────────┘             │                └────────┬────────┘
                                     │                          │                         │
┌─────────────────────┐              ▼                          ▼                         │
│  Layer 2: Story     │    ┌──────────────────────┐    ┌────────────────────┐             │
│  #1 제주학연구센터   │───▶│  Rewrite Engine      │───▶│  Qdrant / pgvector │             │
│  #2 지역N문화        │    │  · LLM 톤 통일        │    │  · 임베딩 (bge-m3) │             │
│  #7 국립제주박물관   │    │  · 방언 표준어 병기   │    │  · story chunks    │             │
└─────────────────────┘    │  · 1,000자 정제       │    └────────┬───────────┘             │
                           └──────────────────────┘             │                         │
                                                                 │                         ▼
┌─────────────────────┐    ┌──────────────────────┐             │                ┌─────────────────┐
│  Layer 3: Grounding │    │  Verification Cache  │             ▼                │  iOS Client     │
│  #4 문화재청 API     │───▶│  · 사실 근거 앵커    │───▶  [RAG Query 시점 조인]  │  (Sprint 1 v0.2)│
│  (200+ 유적)        │    │  · 인용 문구 저장     │                              └─────────────────┘
└─────────────────────┘    └──────────────────────┘
                                                     ┌────────────────────┐
┌─────────────────────┐                              │  CDN Cache         │
│  Layer 4: Media     │─────────────────────────────▶│  · 관광지 이미지    │
│  #5 비짓제주 API     │                              │  · WebP 압축        │
└─────────────────────┘                              └────────────────────┘
```

---

## 1. 데이터 레이어 (4단 구조)

### Layer 1 — Spatial Base (좌표·분류 SSoT)

| 필드 | 소스 | 예시 |
|---|---|---|
| `spot_id` | #3 제주도청 (UUID 재발급) | `spot_a1b2c3d4` |
| `name_ko` | #3 제주도청 | "성산일출봉" |
| `latitude`, `longitude` | #3 제주도청 | 33.4586, 126.9426 |
| `geohash` | 계산 필드 (Level 7) | `wydk48z` |
| `category` | #3 카테고리 매핑 | `oreum`, `beach`, `temple`, `heritage`, `village` |
| `region` | 시·군·읍·면 | "제주시 성산읍" |
| `address` | #3 제주도청 | "제주특별자치도 서귀포시 성산읍 일출로 284-12" |

**용도:** iOS CoreLocation에서 사용자 좌표 → GeoHash Level 7 매칭 → `spot_id` 획득 → 이후 스토리·이미지·검증 조회

### Layer 2 — Story Content (RAG 원자재)

| 필드 | 설명 |
|---|---|
| `story_id` | UUID |
| `spot_id` | Layer 1 FK |
| `title` | 이야기 제목 (LLM 생성) |
| `body_narration` | 1,000자 내외 정제 본문 (전문 가이드 톤) |
| `body_dialect_original` | 원문 (방언·구어 보존) |
| `theme` | `origin_myth`, `haenyeo`, `history`, `nature`, `folk_life` |
| `source_type` | #1 / #2 / #7 |
| `source_credit` | "제주학연구센터 (공공누리 제1유형)" |
| `source_url` | 원본 페이지 |
| `rewrite_prompt_version` | 리라이팅 프롬프트 버전 (v1.0 등) |
| `embedding` | pgvector · bge-m3 임베딩 |
| `created_at`, `updated_at` | |

**용도:** RAG 검색 시 Vector 유사도 기반 top-k 조회. 내레이션 원본으로 사용.

### Layer 3 — Grounding Facts (사실 검증)

| 필드 | 설명 |
|---|---|
| `fact_id` | UUID |
| `spot_id` | Layer 1 FK |
| `fact_text` | 국가유산청 공식 해설 원문 |
| `heritage_type` | 국보 / 보물 / 사적 / 천연기념물 / 명승 |
| `designation_date` | 지정일 |
| `official_citation` | "국가유산청 국가유산검색 상세 (2026-02 기준)" |
| `source_url` | 문화재청 원본 페이지 |

**용도:** LLM 답변 생성 시 System Prompt에 `fact_text` 주입 → Hallucination 방지. 답변 하단에 "출처: 국가유산청" 표기.

### Layer 4 — Media Assets (UI 자원)

| 필드 | 설명 |
|---|---|
| `media_id` | UUID |
| `spot_id` | Layer 1 FK |
| `image_url_original` | 비짓제주 원본 |
| `image_url_cdn` | 자체 CDN 캐싱 (WebP 변환) |
| `image_credit` | "© 제주관광공사 비짓제주" |
| `is_primary` | 대표 이미지 여부 |

**용도:** 내레이션 재생 시 UI 배경 이미지 렌더링.

---

## 2. 소스별 수집 방식

### Source #1 — 제주학연구센터 (`jst.re.kr`)

**접근:** HTTP GET · 세션 없음 · 무료
**형태:** PDF 발간물 + HTML 아카이브 페이지

**파이프라인:**
```
1. 아카이브 목록 크롤링 (jejustudiesDBList.do)
   → 문서 메타데이터 (제목·발간연도·다운로드 URL) 수집
   → data/raw/jst/manifest.jsonl 저장

2. PDF 다운로드 (rate limit 1req/2sec)
   → data/raw/jst/pdf/{doc_id}.pdf

3. PDF → 텍스트 추출 (pdfplumber 또는 pypdf)
   → data/raw/jst/text/{doc_id}.txt

4. 지명 매핑 (spot_id 후보 추출)
   → 텍스트에서 관광지명 매치 (Layer 1 name_ko와 교차)
   → data/processed/jst/{doc_id}_spots.jsonl
```

**리라이팅 프롬프트 (v1.0):**
```
당신은 제주 관광 전문 가이드입니다. 아래 원문은 제주학연구센터 채록 자료로,
방언과 구어체가 섞여 있습니다. 다음 규칙에 따라 재구성해주세요:

1. 표준어 위주로 재작성하되, 제주 방언의 정체성 있는 표현은 각주로 보존
2. 톤은 "옆에서 옛 이야기 들려주는 인생 가이드"의 자연스러운 서술
3. 분량은 공백 포함 900~1,100자 사이
4. 도입부에 장소감을 살리는 감각 묘사 (풍경·바람·냄새 등) 1문장
5. 결말부에 사용자가 실제 그 장소에서 무엇을 관찰하면 좋을지 힌트 1문장
6. 학술 용어·전문 어휘는 대괄호로 뜻 설명 병기
7. 사실 관계는 원문 유지, 창작 금지

원문:
{raw_text}

관광지: {spot_name}
카테고리: {category}
지역: {region}

위 규칙을 지켜 재구성한 가이드 대본만 출력:
```

### Source #2 — 지역N문화 (`nculture.org`)

**접근:** HTTP GET · 세션 불필요 · 무료
**형태:** HTML 웹 페이지 (테마별 스토리)

**파이프라인:**
```
1. "제주" 태그 검색 URL 크롤링
   → nculture.org/mobile/theme/searchList.do?theme=제주

2. 페이지 순회 (rate limit 1req/1sec)
   → 각 스토리 상세 페이지 URL 수집

3. BeautifulSoup으로 본문 추출
   → <div class="cont-body"> 등 실제 셀렉터는 첫 페이지 확인 후 확정
   → data/raw/nculture/{story_id}.html + data/raw/nculture/{story_id}.txt

4. 하위 문화원 크레딧 추출 (서귀포문화원 등)
   → 메타에 정확히 저장 (source_credit)

5. 지명 매핑 (Layer 1 join)
```

**리라이팅 프롬프트 (v1.0):**
```
아래 원문은 이미 정제된 문화 스토리이지만 관광 가이드용으로 톤 조정이 필요합니다.

1. 원문의 서사 흐름을 유지 (뼈대는 그대로)
2. "~있었다", "~된다" 같은 서술체 → "~있답니다", "~된답니다" 자연스러운 구어체
3. 분량 900~1,100자 유지
4. 사용자가 그 장소에 서 있는 감각으로 도입 문장 재구성
5. 사실 창작·왜곡 금지

원문:
{raw_text}

관광지: {spot_name}

재구성 결과만 출력:
```

### Source #3 — 제주도청 관광지 데이터셋

**접근:** CSV 파일 다운로드 (즉시)
**형태:** CSV (EUC-KR 가능성)

**파이프라인:**
```
1. wget으로 CSV 다운로드
   → data/raw/jeju_gov/spots_20260714.csv

2. 인코딩 자동 감지 후 UTF-8 변환

3. 컬럼 정규화:
   원본 컬럼 → Layer 1 스키마 매핑
   좌표 결측치는 카카오 지오코딩 API로 보완

4. GeoHash Level 7 계산 (python-geohash)

5. spots 테이블 INSERT
```

**필수 검증:**
- 좌표 범위: 33.0 < lat < 34.0, 126.0 < lng < 127.0 (제주 범위 밖 데이터 제외)
- 카테고리 표준화: 원본 17개 카테고리 → 5개 표준 카테고리로 매핑

### Source #4 — 문화재청 국가유산포털 API

**접근:** OpenAPI · 인증키 필요 · XML 응답
**형태:** REST API

**파이프라인:**
```
1. 인증키 신청 (www.khs.go.kr)
   → env/secrets: HERITAGE_API_KEY

2. 제주 지정 문화재 목록 조회
   → GET /openapi/search?ccbaCtcd=50 (제주 지역코드)
   → data/raw/heritage/list.xml

3. 각 문화재 상세 조회
   → GET /openapi/detail/{id}
   → data/raw/heritage/detail/{id}.xml

4. XML → JSON 변환 (xmltodict)
   → data/processed/heritage/{id}.json

5. Layer 3 facts 테이블 INSERT
   → spot_id는 좌표 근접도로 Layer 1과 조인 (500m 이내)
```

**주의사항:**
- XML 파서 필수 (JSON 지원 없음)
- 이미지 자원 공공누리 범위 밖 (텍스트만 사용)

### Source #5 — 비짓제주 API

**접근:** OpenAPI · 인증키 필요 · JSON 응답
**형태:** REST API

**파이프라인:**
```
1. 활용신청 (visitjeju.net/kr/visitjejuapi)
   → 담당자 수동 승인 (1~2일 소요)
   → env/secrets: VISITJEJU_API_KEY

2. 제주 전체 관광지 리스트 조회 (1,128개소)
   → 페이징 순회

3. 각 관광지 이미지 URL 추출
   → data/processed/visitjeju/{id}.json

4. 이미지 다운로드 + WebP 변환 + CDN 업로드
   → S3 or Cloudflare R2
   → image_url_cdn 필드 저장

5. Layer 4 media 테이블 INSERT
```

**Rate limit 대응:**
- 초당 5req 이하 유지
- 서버 사이드 캐싱 필수 (사용자 앱이 직접 호출 금지)

---

## 3. 정제·통합 엔진 (Merge Engine)

### 3.1 지명 정규화

동일 장소가 소스마다 다르게 표기되는 문제 대응:
- "성산일출봉" (도청) = "일출봉" (제주학) = "성산 일출봉" (문화재청)
- 정규화 룰: 공백 제거 + 접미사 통일 + 관용 표기 매핑
- 매핑 실패 시 spot_id 부여하지 않고 review queue에 넣음

### 3.2 좌표 기반 조인

Layer 3 (문화재청)은 좌표만 있고 관광지 이름은 다를 수 있음 → **좌표 500m 이내 근접도**로 Layer 1과 조인.

### 3.3 결측치 정책

| 상황 | 처리 |
|---|---|
| 좌표 결측 | 카카오 지오코딩 API 시도 → 실패 시 spot 제외 |
| 카테고리 결측 | LLM 분류 (제로샷) |
| 대표 이미지 없음 | 기본 제주 스톡 이미지 (라이선스 안전한 것) |
| 스토리 없음 | Layer 3 (사실만) 기반 짧은 안내로 대체 |

### 3.4 중복 스토리 처리

동일 spot에 대해 여러 소스에서 스토리가 들어오면:
- 가장 긴 원문을 primary로 선택
- 다른 소스는 secondary로 저장 (RAG 검색 시 함께 반환)
- LLM에게 "여러 관점을 통합해 하나의 대본으로" 프롬프트

---

## 4. LLM 리라이팅 스텝

### 4.1 프롬프트 버전 관리

```
prompts/
├── rewrite_v1_jst.txt          (제주학연구센터용)
├── rewrite_v1_nculture.txt     (지역N문화용)
├── rewrite_v1_museum.txt       (박물관 도록용)
├── rewrite_v1_heritage.txt     (문화재 사실용)
└── system_narrator.txt         (전체 System Prompt)
```

각 리라이팅 결과에 `rewrite_prompt_version` 필드 기록 → 프롬프트 개선 시 A/B 비교 가능.

### 4.2 모델 선택

- **1차 리라이팅:** Claude Sonnet 4.6 또는 GPT-4o mini (품질/비용 균형)
- **최종 QA:** Claude Opus 4.7 · 표본 10% 사람 검수 병행

### 4.3 QA 체크리스트

리라이팅 후 자동 검증:
- [ ] 분량 900~1,100자
- [ ] 사실 오류 없음 (Layer 3 원문 대조)
- [ ] 방언 각주 보존
- [ ] 도입/결말 문장 규칙 준수
- [ ] 출처 크레딧 필드 채워짐

---

## 5. Vector DB 인덱싱

### 5.1 임베딩 모델

- **모델:** `BAAI/bge-m3` (한국어 성능 좋음, 다국어 지원, 오픈소스)
- **차원:** 1024
- **청킹:** 스토리 1건당 청크 1~2개 (500~700 토큰)

### 5.2 저장

- **DB:** pgvector on PostgreSQL (초기 규모 작아서 Qdrant 굳이 안 씀)
- **인덱스:** HNSW (ef_construction=64, m=16)

### 5.3 검색 전략

사용자 좌표 도착 시:
```
1. GeoHash 매칭 → spot_id 후보 리스트
2. spot_id → story chunks 조회
3. 사용자 질문이 있으면 → 질문 임베딩 + 유사도 top-3
4. Grounding facts join → System Prompt에 주입
5. LLM 응답 생성 (스트리밍)
```

---

## 6. Sprint 1 4주 타임라인

### Week 1 (7/21~7/27) — 인프라 & 좌표 SSoT

- [ ] Day 1-2: 프로젝트 스캐폴딩 (Python + PostgreSQL + pgvector)
- [ ] Day 3-4: **Source #3 (제주도청) 완료** — 1,047개소 spots 테이블 채움
- [ ] Day 5-6: GeoHash 인덱싱 + FastAPI `/spots/near` 엔드포인트
- [ ] Day 7: iOS 클라이언트 CoreLocation → API 통신 뼈대

**주말 마일스톤:** iOS 앱에서 GPS 트리거 → 스팟 매칭 → 이름·좌표 표시 (콘텐츠 없어도 됨)

### Week 2 (7/28~8/3) — 스토리 수집 (#1 + #2)

- [ ] Day 1-3: **Source #2 (지역N문화) 크롤러** + 리라이팅 파이프라인
- [ ] Day 4-5: **Source #1 (제주학연구센터) PDF 파이프라인**
- [ ] Day 6: 지명 매핑 · 결측치 정리
- [ ] Day 7: 스토리 30개 정제 완료 · 임베딩 · pgvector 인덱스

**주말 마일스톤:** iOS 앱에서 GPS → 스팟 매칭 → 스토리 1개 표시 (내레이션 재생)

### Week 3 (8/4~8/10) — 검증 & 미디어 (#4 + #5)

- [ ] Day 1-2: **Source #4 (문화재청)** 인증키 발급 · Grounding facts 로드
- [ ] Day 3-4: **Source #5 (비짓제주)** 이미지 파이프라인 · CDN 캐싱
- [ ] Day 5-6: RAG 답변에 Grounding + 이미지 통합
- [ ] Day 7: 인터럽트 Q&A UX 뼈대 (음성 인식은 v0.3으로 유보)

**주말 마일스톤:** iOS 앱에서 스토리 재생 중 텍스트 질문 입력 → RAG 응답 → 재생 재개

### Week 4 (8/11~8/17) — QA · TestFlight

- [ ] Day 1-2: 스토리 커버리지 확장 (60~90개소 목표)
- [ ] Day 3: 라이선스 크레딧 UI 완비 (About 페이지)
- [ ] Day 4: W1 Retention 측정 훅 (Firebase Analytics 이벤트)
- [ ] Day 5: TestFlight 빌드 · 심사 제출
- [ ] Day 6-7: 내부 dogfood · 버그 픽스

**Sprint 1 종료 조건:**
- ✅ TestFlight 승인
- ✅ 30개소 이상 스토리 재생 가능
- ✅ Grounding 정확도 95%+ (수동 검수 표본)
- ✅ 첫 W1 Retention 측정 시작 (수치는 아직 안 나옴)

---

## 7. 리스크 & 대응

| 리스크 | 대응 |
|---|---|
| 비짓제주 승인 지연 (1~2일 → 1주+) | Week 1에 즉시 신청 · 대체 이미지 소스 (Unsplash `제주` CC0) 준비 |
| 제주학연구센터 PDF OCR 품질 나쁨 | 우선순위 낮추고 #2 우선 · Week 3부터 시작 |
| LLM 리라이팅 비용 폭증 | Sprint 1에는 정제 대상 90개만 · 이후 배치 처리로 확장 |
| 스팟 매칭 실패율 높음 | 매칭 실패 spot은 review queue에 넣고 수동 매핑 (하루 30개 처리) |
| 문화재청 API XML 파싱 실패 | xmltodict + fallback lxml · 실패 시 log에 저장하고 다음 |
| pgvector 성능 (Sprint 1은 90건이라 문제 없음) | 데이터 커지면 Qdrant 마이그레이션 (Sprint 3+) |

---

## 8. 관측 지표 (Sprint 1 종료 시 리포트)

- 총 spot 등록 수 (목표 1,047)
- 총 story 정제 완료 수 (목표 90)
- 총 facts 로드 수 (목표 200)
- 지명 매칭 성공률 (목표 80%+)
- 리라이팅 평균 처리 시간 · 총 LLM 비용
- Grounding 정확도 표본 검수 결과
- TestFlight 승인 여부 · 첫 배포 사용자 수

---

## 9. Sprint 1 이후 (Sprint 2 이월)

- **게임화 레이어** — 미션·퀘스트·수집 요소 (Sprint 2)
- **다국어 확장** — 영/중/일 (Sprint 3, 오디 API 재활용)
- **음성 인식 인터럽트** — 텍스트 → 음성 (Sprint 2)
- **콘텐츠 유료화 게이팅** — W1 Retention 20% 도달 시 (Sprint 2 후반)
- **B2B 라이선싱 파일럿** — 제주도청·관광공사 데모 (Sprint 3)
