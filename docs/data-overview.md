# 데이터 현황

추천 시스템이 사용하는 세 가지 데이터(비짓제주 장소, 설화, 매핑)의 현재 상태.

## 1. 비짓제주 데이터

실제 관광객이 만든 여행 일정에 등장한 장소 3,284개. 각 장소가 진짜 관광지인지 식당·카페 같은 비관광지인지로 분류돼 있다.

### 카테고리 분포 (3,284개)

| 카테고리 | 개수 | 비중 | 매핑 사용 |
|---|---|---|---|
| `nature` (오름·폭포·해변·동굴·포구·숲) | 429 | 13.1% | ✅ |
| `history` (유적지·기념관·4.3관련) | 139 | 4.2% | ✅ |
| `experience` (농장·정원·테마파크·페스티벌) | 127 | 3.9% | ✅ |
| `culture` (박물관·미술관·전시관) | 77 | 2.3% | ✅ |
| `village` (올레·마을시설·시장) | 36 | 1.1% | ✅ |
| `religious` (사찰·신당·성당) | 12 | 0.4% | ✅ |
| **소계 — 매핑 대상** | **820** | **25.0%** | |
| `food` (식당·음식점) | 462 | 14.1% | ❌ |
| `accommodation` (호텔·펜션·게스트하우스) | 405 | 12.3% | ❌ |
| `cafe` (카페·베이커리·디저트) | 149 | 4.5% | ❌ |
| `commercial` (골프·스파·렌터카·병원) | 21 | 0.6% | ❌ |
| `shopping` (면세점·마트·상점) | 3 | 0.1% | ❌ |
| `unclear` (이름만으로 판단 불가) | 1,424 | 43.4% | ❌ |
| **소계 — 매핑 제외** | **2,464** | **75.0%** | |

### 분류 방식

장소별로 세 가지 출처 중 하나로 카테고리 부여:

| 출처 | 개수 | 방법 |
|---|---|---|
| `kto` | 436 | KTO TourAPI(한국관광공사)의 contenttypeid + cat1으로 자동 매핑 |
| `kto+override` | 20 | KTO가 식당을 관광지로 잘못 매칭한 케이스 — 후처리로 강제 보정 |
| `keyword` | 1,395 | 장소명에서 키워드 매칭 (해변, 오름, 박물관 등) |
| `keyword+override` | 9 | 키워드로 attraction 분류 후 식당 패턴(○○점, 갈비밥 등) 발견 시 강제 보정 |
| `unclear` | 1,424 | 어느 패턴도 매칭 안 됨 — 매핑 제외 (대부분 식당·카페·펜션) |

### 위치
- 원본 좌표: `data/processed/visitjeju_places_geocoded.json`
- 분류 결과: `data/processed/visitjeju_places_final.json`
- KTO 캐시: `data/processed/kto_jeju_attractions.json` (618개)
- 분류 스크립트: `scripts/classify_visitjeju_places.py`

---

## 2. 설화 데이터

제주 신화·민담 504건. 5개 카테고리 중 하나로 분류돼 있고, 각각 GPS 좌표·요약·원문이 연결돼 있다.

### 카테고리 분포 (504개 중 매핑된 435개)

| 카테고리 | 설화 수 | 의미 |
|---|---|---|
| 생활민담·교훈담 | 183 | 권선징악·일상 지혜·계모·효자·콩데기팥데기 |
| 무속신화·신격 전승 | 102 | 본풀이·당신화·심방·천지왕·설문대할망 |
| 초자연 존재담 | 91 | 도체비·도깨비·헛게·귀신·저승 |
| 마을 공동체 전승 | 38 | 마을 유래·본향당·당제·풍수설화 |
| 해양·어촌 전승 | 20 | 해녀·물질·바다·용왕·영등신 |
| 매핑 안 됨 | 69 | GPS·지명 매칭 실패 |

### Source type
- `legend` (신화) — 182건
- `folktale` (민담) — 322건

### 위치
- 메타데이터: `storage/metadata.db` 테이블 `metadata`
- 원문 텍스트: `data/extracted/legend/*.txt`, `data/extracted/folktale/*.txt`
- 청크 임베딩: `storage/vector_db/` (ChromaDB, 1,749 청크, text-embedding-3-small)
- GPS 좌표: `data/processed/folklore_gps.json`
- 카테고리 분류본: `docs/experiments/gps-folklore-final.csv` (수동 분류 228건) + `docs/experiments/folktale_categorized_212.csv` (자동 분류 212건)

---

## 3. 매핑 관계 — 설화 × 장소

`place_folklore_mapping` 테이블이 "어느 장소에 어느 설화가 연결되는가"를 정의한다. 30,947개 매핑 row.

### specificity (지명 일치 정밀도)

설화 본문의 지명과 Visit Jeju 장소가 어떻게 매칭됐는지의 신뢰도.

| specificity | 의미 | 개수 |
|---|---|---|
| **10** | 리/동 단위 또는 명소명 정확 일치 (예: 납읍리, 성산일출봉) | 2,277 |
| **7** | 역사 지명 일치 (제주성, 정의현 등) | 3 |
| **5** | 읍/면 단위 일치 (애월읍, 한경면 등) | 4,446 |
| **3** | 텍스트 매칭 실패 → GPS 8km 반경 보조 매핑 | 24,221 |

**점수 계산에는 specificity ≥ 5만 사용** (3점짜리는 너무 광범위해서 노이즈).

### 카테고리별 매핑 분포 (30,947 row)

| 카테고리 | 매핑 수 |
|---|---|
| 무속신화·신격 전승 | 10,544 |
| 생활민담·교훈담 | 10,504 |
| 초자연 존재담 | 5,031 |
| 마을 공동체 전승 | 3,570 |
| 해양·어촌 전승 | 1,298 |

### 매핑 생성 로직

1. **텍스트 매칭**: 설화 본문의 지명(`PLACE_SPECIFICITY` 사전, 약 130개) 중 가장 구체적인 지명을 골라, 그 지명이 Visit Jeju 장소명 또는 주소에 포함되면 매핑 생성
2. **GPS 보조**: 위 매칭 실패 시 지명의 알려진 좌표에서 8km 반경 내 Visit Jeju 장소를 specificity=3으로 추가
3. **관광지 필터**: Visit Jeju 장소가 `is_attraction=True`인 경우만 매핑 대상 (식당·카페·숙박 제외)

### 위치
- 테이블: `storage/metadata.db` → `place_folklore_mapping`
- 빌드 스크립트: `scripts/build_place_folklore_mapping.py`

---

## 4. Visit Jeju 검증 코스

추천 시스템이 사용자에게 보여주는 단위. 실제 관광객이 만든 여행 일정 839개.

| 항목 | 값 |
|---|---|
| 코스 수 | 839 |
| 코스-장소 슬롯 | 146,525 (코스당 평균 175 슬롯) |
| 지역 분포 | 동부 163 · 서부 179 · 남부 126 · 북부 161 · 전체 210 |
| 기간 분포 | 1일 151 · 2일 150 · 3일 150 · 4일 150 · 5일 118 · 그 외 120 |

### 위치
- 테이블: `storage/metadata.db` → `curated_courses`, `course_places`
- 원본 CSV: `VISIT JEJU_여행세부일정.CSV`

---

## 5. 추천 점수 계산

사용자가 "이야기 결 + 배경 + 지역 + 기간"을 입력하면 카테고리 점수 딕셔너리가 생성되고, 그걸로 코스를 정렬한다.

### 점수 공식

```
1. 코스 내 모든 매핑 row를 (final_category, specificity)로 모음
2. 매핑마다 가중치 w = specificity / 5  (spec=5 → 1.0, spec=10 → 2.0)
3. 카테고리별 가중치 합 → 점유율 계산 (총합 대비 비율)
4. 점수 = Σ (사용자_점수[카테고리] × 점유율[카테고리]) × 10
```

### 예시

사용자 입력: `{"초자연 존재담": 4, "해양·어촌 전승": 3}`

코스 A 매핑 (가중치 적용 후):
- 초자연 존재담: 점유율 70%
- 마을 공동체 전승: 점유율 30%

점수 = 4 × 0.7 + 0 × 0.3 = 2.8 → ×10 → **28점**

### 위치
- 점수 함수: `backend/agents/course_list_agent.py:47` (`_score_course`)
- 추천 흐름: `backend/routers/course.py:19` (`/course/list`)

---

## 6. 데이터 흐름 한 장 요약

```
[사용자]
  region / Q1(이야기 결) / Q2(배경) / days
        ↓
[iOS]
  TasteDiscoveryView (4단계 위저드)
  computeCategoryScores() — 4지선다를 5개 설화 카테고리 점수로 환산
        ↓ POST /course/list
[Backend]
  ① curated_courses 50개 후보 추림 (region + duration_days)
  ② 각 후보에 대해 course_places JOIN place_folklore_mapping
     - specificity ≥ 5만
     - 매핑된 final_category × specificity 가중치 → 점유율 → 점수
  ③ Top 3 정렬
        ↓
[사용자]
  코스 카드 3장 (장소·일자별 동선 + 핀)
```

---

## 7. 핵심 파일·테이블 인덱스

### DB 테이블 (`storage/metadata.db`)
| 테이블 | 역할 | row 수 |
|---|---|---|
| `metadata` | 설화 메타 (제목·카테고리·GPS) | 504 |
| `curated_courses` | Visit Jeju 검증 코스 | 839 |
| `course_places` | 코스 ↔ 장소 슬롯 | 146,525 |
| `place_folklore_mapping` | 장소 ↔ 설화 (specificity 포함) | 30,947 |
| `documents` | 설화 원문 정규화 텍스트 | 504 |

### 데이터 파일
| 파일 | 내용 |
|---|---|
| `data/processed/visitjeju_places_final.json` | 3,284개 장소 + 12개 카테고리 |
| `data/processed/visitjeju_places_geocoded.json` | 3,284개 장소 + GPS |
| `data/processed/kto_jeju_attractions.json` | KTO 제주 관광지 618개 |
| `data/processed/folklore_gps.json` | 설화별 GPS 좌표 |
| `storage/vector_db/` | ChromaDB 1,749 청크 임베딩 |

### 분류·빌드 스크립트
| 스크립트 | 역할 |
|---|---|
| `scripts/classify_visitjeju_places.py` | Visit Jeju 장소 → 12 카테고리 분류 |
| `scripts/classify_uncategorized_folktales.py` | 설화 자동 분류 (키워드 기반) |
| `scripts/apply_folktale_categories.py` | 분류 결과를 DB의 final_category에 반영 |
| `scripts/build_place_folklore_mapping.py` | 장소 ↔ 설화 매핑 테이블 빌드 |
| `scripts/enrich_visitjeju_categories.py` | KTO API로 카테고리 보강 |
