# 제주 설화·민담 RAG 파이프라인

## 개요

이 프로젝트의 목표는 제주 설화와 민담 데이터를 수집하고, 이를 검색 가능한 벡터 DB로 구성한 뒤, 최종적으로 사용자 질문에 답하는 RAG 챗봇을 만드는 것이다.

핵심은 `PDF 파일 자체`를 바로 벡터 DB에 넣는 것이 아니라, PDF나 E-Book에서 추출한 `텍스트`를 정규화하고 청킹한 뒤, 이를 임베딩하여 벡터 DB에 저장하는 것이다.

현재 프로젝트는 아래 파이프라인이 실제로 구현되어 있다.

1. 메타데이터 수집 `data/processed/metadata_folktale.jsonl`
2. PDF/E-Book 원문 다운로드 
3. 원문 텍스트 추출 `data/extracted/folktale`
4. 텍스트 정제 및 정규화 `data/normalized/folktale`
5. 청킹
6. 임베딩 생성 및 모델 선정(`text-embedding-3-small`)
7. 벡터 DB 적재 
8. 질문-응답용 RAG 챗 엔진 실행
9. 평가 질문셋 기반 반복 검증

## 현재 구현 상태 요약

- 메타데이터: `505건`
  - 설화: `182건`
  - 민담: `323건`
- 원문 파일: `504개`
- 추출 문서: `505건`
- 정규화 문서: `505건`
- 청크: `1749개`
- 벡터 DB: ChromaDB 로컬 인덱스 구성 완료
- 챗 엔진: CLI 기반 질의응답 가능
- 평가 실행기: 질문셋 일괄 실행 및 결과 파일 저장 가능

## 1. 메타데이터 수집

### 목적

제주 설화 API와 민담 API에서 전체 항목 목록을 받아오는 단계다.

### 입력

- `E07 제주설화정보` API
- `E08 제주민담정보` API

### 출력

- 코드번호
- 제목
- 분류
- 태그
- PDF URL
- E-Book URL

### 구현 스크립트

- [fetch_metadata.py](/Users/choikjun/Desktop/keepdev/졸프/scripts/fetch_metadata.py)

### 현재 상태

완료.

- 설화: `182건`
- 민담: `323건`
- 저장 위치:
  - [metadata_legend.jsonl](/Users/choikjun/Desktop/keepdev/졸프/data/processed/metadata_legend.jsonl)
  - [metadata_folktale.jsonl](/Users/choikjun/Desktop/keepdev/졸프/data/processed/metadata_folktale.jsonl)
  - [metadata.db](/Users/choikjun/Desktop/keepdev/졸프/storage/metadata.db)

## 2. PDF/E-Book 원문 다운로드

### 목적

메타데이터에 포함된 `pdf_url` 또는 `ebook_url`을 바탕으로 실제 원문 파일을 확보하는 단계다.

### 입력

- 메타데이터 JSONL 또는 SQLite DB

### 출력

- PDF 파일
- HTML E-Book 파일

### 구현 스크립트

- [download_sources.py](/Users/choikjun/Desktop/keepdev/졸프/scripts/download_sources.py)

### 현재 상태

완료.

- 원문 파일 수: `504개`
- 저장 위치: [data/raw/documents](/Users/choikjun/Desktop/keepdev/졸프/data/raw/documents)

## 3. 원문 텍스트 추출

### 목적

다운로드한 PDF 또는 HTML에서 실제 텍스트를 추출하는 단계다.

### 입력

- 다운로드된 PDF
- 다운로드된 HTML

### 출력

- 문서 단위 텍스트 파일
- SQLite `documents` 테이블 저장

### 구현 스크립트

- [extract_text.py](/Users/choikjun/Desktop/keepdev/졸프/scripts/extract_text.py)

### 현재 상태

완료.

- 문서 수: `505건`
- 저장 위치:
  - [data/extracted](/Users/choikjun/Desktop/keepdev/졸프/data/extracted)
  - [metadata.db](/Users/choikjun/Desktop/keepdev/졸프/storage/metadata.db)

## 4. 텍스트 정제 및 정규화

### 목적

추출 결과에서 페이지 구분 문자, 뷰어 노이즈, 특수문자, 옛표기 문제를 정리해 검색 친화적인 텍스트를 만드는 단계다.

### 입력

- 추출된 원문 텍스트

### 출력

- `raw_text`: 원문 보존본
- `clean_text`: 정제본
- `normalized_text`: RAG 검색용 정규화본

### 구현 스크립트

- [extract_text.py](/Users/choikjun/Desktop/keepdev/졸프/scripts/extract_text.py)
- [normalize_text.py](/Users/choikjun/Desktop/keepdev/졸프/scripts/normalize_text.py)
- [audit_normalization.py](/Users/choikjun/Desktop/keepdev/졸프/scripts/audit_normalization.py)

### 현재 상태

완료.

- 정규화 문서 수: `505건`
- 저장 위치: [data/normalized](/Users/choikjun/Desktop/keepdev/졸프/data/normalized)
- 감사 리포트:
  - [normalization_audit_folktale.md](/Users/choikjun/Desktop/keepdev/졸프/reports/normalization_audit_folktale.md)
  - [normalization_audit_legend.md](/Users/choikjun/Desktop/keepdev/졸프/reports/normalization_audit_legend.md)

### 중요 포인트

- 원문은 보존한다.
- 검색과 임베딩은 `normalized_text` 기준으로 수행한다.
- 이 프로젝트에서 정규화는 선택이 아니라 검색 품질 확보를 위한 핵심 단계였다.

## 5. 청킹

### 목적

긴 문서를 벡터 검색에 적합한 작은 단위로 나누는 단계다.

### 입력

- `normalized_text` 우선
- 없으면 `clean_text`

### 출력

- 청크 단위 텍스트
- SQLite `chunks` 테이블

### 구현 스크립트

- [build_chunks.py](/Users/choikjun/Desktop/keepdev/졸프/scripts/build_chunks.py)

### 현재 적용 방식

- 문자 수 기준 고정 길이 청킹
- `chunk_size=900`
- `overlap=120`

### 현재 상태

완료.

- 전체 청크 수: `1749개`
- 저장 위치: [metadata.db](/Users/choikjun/Desktop/keepdev/졸프/storage/metadata.db)

## 6. 임베딩 생성

### 목적

각 청크 텍스트를 의미 기반 검색이 가능한 숫자 벡터로 변환하는 단계다.

### 입력

- 청크 텍스트

### 출력

- OpenAI 임베딩 벡터

### 구현 스크립트

- [ingest_to_vector_db.py](/Users/choikjun/Desktop/keepdev/졸프/scripts/ingest_to_vector_db.py)

### 현재 적용 모델

- `text-embedding-3-small`

### 중요 포인트

- 문서 임베딩과 질문 임베딩은 같은 모델을 사용한다.
- 현재 파이프라인은 OpenAI 임베딩을 기준으로 동작한다.

## 7. 벡터 DB 적재

### 목적

임베딩된 청크와 메타데이터를 유사도 검색 가능한 형태로 저장하는 단계다.

### 입력

- 임베딩 벡터
- 청크 텍스트
- 메타데이터

### 출력

- ChromaDB 로컬 벡터 인덱스

### 구현 스크립트

- [ingest_to_vector_db.py](/Users/choikjun/Desktop/keepdev/졸프/scripts/ingest_to_vector_db.py)

### 현재 적용 DB

- `ChromaDB`

### 저장 메타데이터 예시

- `source_type`
- `code_no`
- `title`
- `category`
- `category2`
- `tags`
- `chunk_index`

### 현재 상태

완료.

- 적재 대상 청크: `1749개`
- 저장 위치: [storage/vector_db](/Users/choikjun/Desktop/keepdev/졸프/storage/vector_db)

## 8. 질문-응답용 RAG 챗 엔진

### 목적

사용자 질문을 임베딩하고, 관련 청크를 검색한 뒤, 검색 결과를 LLM에 넣어 설명형 답변을 생성하는 단계다.

### 입력

- 사용자 질문

### 출력

- 검색 결과 Top-K
- 최종 답변
- 출처

### 구현 스크립트

- [chat_engine.py](/Users/choikjun/Desktop/keepdev/졸프/scripts/chat_engine.py)

### 현재 동작 방식

- 질문 임베딩 생성
- ChromaDB에서 Top-K 검색
- `max-distance=0.62` 기준으로 낮은 관련성 청크 제거
- 검색 결과를 `gpt-4o`에 전달
- 답변 뒤에 `출처: 제목 (코드: 번호)` 형식 후처리 부착

### 현재 상태

완료.

- 단일 질의 실행 가능
- 대화형 CLI 실행 가능
- 최근 3턴 메모리 기반 연속 질의 가능

## 9. 평가 질문셋 기반 반복 검증

### 목적

질문셋을 고정해두고, 파라미터나 구현 변경 전후의 검색/답변 품질을 반복 비교하는 단계다.

### 입력

- 평가 질문셋 JSONL

### 출력

- 질문별 판정 결과 JSONL
- 사람이 읽는 Markdown 리포트

### 구현 스크립트

- [evaluation_runner.py](/Users/choikjun/Desktop/keepdev/졸프/scripts/evaluation_runner.py)

### 현재 평가 데이터

- 질문셋: [evaluation_questions.jsonl](/Users/choikjun/Desktop/keepdev/졸프/data/processed/evaluation_questions.jsonl)
- 설명 문서: [evaluation_question_set.md](/Users/choikjun/Desktop/keepdev/졸프/reports/evaluation_question_set.md)

### 현재 상태

완료.

- 평가 실행 결과 저장 가능
- 저장 위치: [reports/evaluations](/Users/choikjun/Desktop/keepdev/졸프/reports/evaluations)
- 현재 생성된 결과 파일 수: `6개`

## 현재 실행 순서

```bash
source .venv/bin/activate
python scripts/fetch_metadata.py --source all --page-size 100
python scripts/download_sources.py
python scripts/extract_text.py
python scripts/normalize_text.py
python scripts/audit_normalization.py --source all
python scripts/build_chunks.py --chunk-size 900 --overlap 120
python scripts/ingest_to_vector_db.py --provider openai
python scripts/chat_engine.py --show-retrieval
python scripts/evaluation_runner.py --limit 5
```

## 이 파이프라인에서 중요한 포인트

### 1. PDF 수집이 끝이 아니다

PDF를 모았다고 바로 챗봇이 되는 것이 아니다. 실제로 중요한 것은 PDF 안의 텍스트를 얼마나 안정적으로 추출하고 정규화하느냐다.

### 2. 벡터 DB는 중간 단계다

벡터 DB는 최종 목표가 아니라 검색을 위한 저장소다. 품질은 `텍스트 품질`, `정규화`, `청킹`, `임베딩 모델`, `프롬프트`에서 결정된다.

### 3. 검색과 생성은 분리해서 봐야 한다

- 검색: 관련 자료를 잘 찾는 문제
- 생성: 찾은 자료를 바탕으로 잘 설명하는 문제

둘 중 하나만 좋아도 챗봇 품질은 충분하지 않다.

### 4. 평가 질문셋이 있어야 전후 비교가 가능하다

RAG 시스템은 청킹, 거리 임계값, 프롬프트만 바뀌어도 결과가 달라진다. 따라서 고정 질문셋과 평가 리포트가 있어야 개선 여부를 비교할 수 있다.

## 다음 개선 과제

현재 1차 파이프라인은 완성됐지만, 아래는 후속 개선 과제로 남아 있다.

1. 오타/띄어쓰기 질문 대응 개선
2. 질의 재순위화(reranking)
3. 정량 평가 기준 정교화
4. 웹 UI 또는 서비스 인터페이스 구축

## 한 줄 요약

지금 프로젝트는 `수집 -> 추출 -> 정규화 -> 청킹 -> 임베딩 -> Chroma 적재 -> 챗 엔진 -> 평가 실행기`까지 구현된 상태이며, 다음 단계는 검색 품질 고도화와 서비스화다.
