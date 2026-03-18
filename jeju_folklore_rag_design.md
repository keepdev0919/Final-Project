# 제주 설화·민담 RAG 설계 문서

## 목표

`E07 제주설화정보` OpenAPI와 `E08 제주민담정보` OpenAPI를 활용해 제주 설화와 민담에 대해 답변하는 챗봇을 구축한다.

중요한 점은 이 API들이 본문 전체를 직접 주는 API가 아니라는 것이다. 실제 RAG용 코퍼스는 API가 제공하는 `pdfUrl`, `ebookUrl`을 따라가 원문을 수집하고, 텍스트를 추출해서 따로 만들어야 한다.

## API가 실제로 주는 정보

### E07 제주설화정보

- 엔드포인트: `http://www.jeju.go.kr/rest/JejuMythContents/getJejuMythContentsList`
- 요청 파라미터: `page`, `pageSize`
- 주요 응답 필드:
  - `type`
  - `codeNo`
  - `category`
  - `category2`
  - `ebook`
  - `ebookUrl`
  - `title`
  - `tag`
  - `pdf`
  - `pdfUrl`

### E08 제주민담정보

- 엔드포인트: `http://www.jeju.go.kr/rest/JejuFolktaleContents/getJejuFolktaleContentsList`
- 요청 파라미터: `page`, `pageSize`
- 주요 응답 필드:
  - `type`
  - `codeNo`
  - `category`
  - `category2`
  - `ebook`
  - `ebookUrl`
  - `title`
  - `tag`
  - `pdf`
  - `pdfUrl`

## 핵심 제약

이 API들은 검색 API가 아니라 목록 조회 API다. 또한 설화나 민담의 본문 텍스트를 직접 반환하지 않는다.

따라서 전체 구조는 아래 순서로 가야 한다.

1. API에서 전체 메타데이터를 수집한다.
2. 각 항목의 원문 문서를 다운로드한다.
3. 문서에서 텍스트를 추출하고 정제한다.
4. 정제된 텍스트를 청킹하고 임베딩한다.
5. 벡터 DB에 저장한다.
6. 챗봇 질의 시 관련 청크를 검색한다.

## 승인 요청이나 별도 신청이 필요한가

PDF 문서 기준으로는 다음과 같다.

- 서비스 키 필요 없음
- 로그인 필요 없음
- 인증서 필요 없음
- 별도 승인 절차 문서화 없음

즉 제주 OpenAPI 자체는 일반 HTTP 요청으로 바로 호출 가능해 보인다.

다만 네 프로젝트 쪽에서 별도로 준비해야 하는 것은 있다.

- 외부 임베딩 모델을 쓸 경우 임베딩 API 키
- 외부 LLM을 쓸 경우 LLM API 키
- 벡터 DB 선택

운영 관점에서 추가로 챙길 사항:

- 과도한 호출을 피하기 위한 속도 제한
- 메타데이터와 원문 파일 캐시
- 깨진 `pdfUrl`, `ebookUrl` 처리

## 권장 아키텍처

### 1. 메타데이터 수집

수집기는 최소 두 개로 나눈다.

- `collect_legends()`
- `collect_folktales()`

각 수집기는 아래 역할을 맡는다.

- 페이지를 끝까지 순회해서 전체 항목 수집
- XML 응답을 공통 스키마로 정규화
- 디버깅용 원본 API 응답 저장
- 정규화된 결과를 파일 또는 DB에 저장

권장 메타데이터 스키마:

- `source_type`: `legend` 또는 `folktale`
- `api_service`: `E07` 또는 `E08`
- `code_no`
- `type`
- `category`
- `category2`
- `title`
- `tags`
- `ebook_folder`
- `ebook_url`
- `pdf_filename`
- `pdf_url`
- `collected_at`

### 2. 원문 수집

각 항목마다 다음 우선순위로 원문을 확보한다.

- 1순위: `pdfUrl`
- 2순위: `ebookUrl`

처음에는 PDF를 우선하는 편이 텍스트 추출 자동화에 유리하다. PDF 품질이 나쁘거나 링크가 깨졌을 때만 E-Book HTML을 보조 소스로 사용한다.

권장 저장 경로:

```text
data/raw/
  legend/
    C_L_021.pdf
  folktale/
    W_F_001.pdf
```

다운로드 상태 값 예시:

- `pending`
- `downloaded`
- `failed`
- `extracted`

### 3. 텍스트 추출

다운로드된 각 문서에 대해 다음 작업을 수행한다.

- PDF 텍스트 추출
- 반복 헤더 제거
- 페이지 번호 제거
- 불필요한 뷰어 문구 제거
- 공백과 줄바꿈 정규화
- 제목과 명확한 문단 구조는 유지

권장 추출 문서 스키마:

- `doc_id`
- `source_type`
- `code_no`
- `title`
- `category`
- `category2`
- `tags`
- `source_url`
- `raw_text`
- `clean_text`
- `language`: `ko`

### 4. 정제 규칙

최소 정제 규칙은 아래 정도면 된다.

- 연속 공백 축소
- 과도한 빈 줄 제거
- 단독 페이지 번호 제거
- PDF 변환 뷰어의 불필요한 문구 제거
- 한국어 문장부호와 인용부호는 유지

본문을 너무 공격적으로 바꾸면 오히려 RAG 품질이 떨어질 수 있다. 이야기 원형은 최대한 유지하는 쪽이 낫다.

### 5. 청킹 전략

초기 버전 기준 권장값:

- 청크 크기: 한글 기준 700~1000자
- 오버랩: 100~150자

청크 메타데이터:

- `chunk_id`
- `doc_id`
- `source_type`
- `code_no`
- `title`
- `category`
- `category2`
- `tags`
- `chunk_index`
- `text`

PDF 구조가 깔끔하면 고정 길이로 바로 자르지 말고, 문단이나 소제목 기준으로 먼저 나눈 뒤 길이 보정 청킹을 하는 편이 좋다.

## 벡터 DB 설계

### 초기 선택 권장안

처음엔 `pgvector` 또는 `Qdrant`를 권장한다.

- `pgvector`: Postgres를 같이 쓰고 싶다면 단순하다.
- `Qdrant`: 벡터 검색과 메타데이터 필터링에 더 명확하다.

### 최소 저장 스키마

- `id`
- `embedding`
- `text`
- `source_type`
- `code_no`
- `title`
- `category`
- `category2`
- `tags`
- `source_url`
- `chunk_index`

### 검색 시 메타데이터 필터

질문 유형에 따라 아래 필터를 같이 쓰는 것이 좋다.

- source type: 설화 또는 민담
- category
- category2
- 정확한 title

이유는 사용자가 아래처럼 물을 수 있기 때문이다.

- "설화만 알려줘"
- "민담 중 도깨비 관련 이야기"
- "가파도 관련 민담 알려줘"

## 챗봇 검색 흐름

### 추론 흐름

1. 사용자 질문 입력
2. 질문 임베딩 생성
3. 상위 `k=5`~`k=8` 청크 검색
4. 필요 시 재정렬
5. 출처 포함 답변 생성

### 답변 형식

챗봇은 아래 요소를 포함해 답하는 것이 좋다.

- 짧은 직접 답변
- 이야기 요약
- 출처 제목
- 자료 유형

예시 출처 필드:

- `제목`
- `분류1`
- `분류2`
- `코드번호`

## 권장 프로젝트 구조

```text
project/
  data/
    raw/
    extracted/
    processed/
  scripts/
    fetch_metadata.py
    download_sources.py
    extract_text.py
    build_chunks.py
    build_embeddings.py
  app/
    retriever.py
    chatbot.py
  storage/
    metadata.db
```

## 실행 순서

### 1단계: 데이터 검증

- E07, E08에서 몇 페이지 먼저 수집
- 실제 전체 건수 확인
- `pdfUrl` 링크가 현재도 살아 있는지 확인
- 샘플 PDF 텍스트 추출 품질 확인

### 2단계: 전체 수집

- 전체 메타데이터 수집
- 전체 PDF 다운로드
- 전체 텍스트 추출
- 정규화된 문서 저장

### 3단계: 검색 인덱스 구축

- 문서 청킹
- 임베딩 생성
- 벡터 DB 적재

### 4단계: 챗봇 연결

- 검색기 연결
- 프롬프트 템플릿 구성
- 출처 표기 포함 응답 생성

## 리스크

### 1. 문서가 오래됐다

E07, E08 가이드는 2017년 문서다. 따라서 문서상 스펙과 실제 운영 API가 다를 가능성은 있다. 실제 호출 검증이 필요하다.

### 2. PDF 텍스트 품질이 일정하지 않을 수 있다

일부 PDF는 텍스트 추출이 잘 안 되거나 이미지 기반일 수 있다.

대응 방안:

- 추출 실패 문서에만 OCR 적용
- PDF 품질이 나쁘면 E-Book HTML 활용

### 3. 중복 이야기 가능성

유사한 이야기가 다른 편집 형태로 중복될 수 있다. 전체 수집 후 중복 또는 유사 문서 정리가 필요할 수 있다.

## 질문에 대한 직접 답변

제주 설화·민담 API 자체는 문서상 별도 승인 요청이나 신청 절차 없이 호출 가능해 보인다.

하지만 API만 호출해서 바로 끝나는 구조는 아니다.

- API는 메타데이터만 준다.
- 실제 챗봇용 코퍼스를 만들려면 원문 다운로드가 필요하다.
- 원문에서 텍스트를 추출하고 정제해야 한다.
- 그 다음에야 청킹, 임베딩, 벡터 DB 적재가 가능하다.

즉 가장 먼저 해결해야 할 마일스톤은 벡터 DB 구축이 아니라 아래다.

`API 메타데이터 수집 -> PDF/E-Book 본문 확보 -> 텍스트 품질 검증`

이 단계가 안정적으로 돌아가면 그 다음은 일반적인 RAG 파이프라인으로 이어가면 된다.
