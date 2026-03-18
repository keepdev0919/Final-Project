# 제주 설화·민담 RAG 챗봇

제주 설화와 민담 데이터를 수집하고, 텍스트로 정제한 뒤, 벡터 DB와 LLM을 결합해 질문에 답하는 RAG 챗봇 프로젝트다.

이 프로젝트는 `PDF 파일 자체`를 저장하는 것이 아니라, 원문 PDF/E-Book에서 추출한 텍스트를 정규화하고 청킹한 뒤 임베딩하여 검색 가능한 지식베이스를 만든다.

## 현재 구현 범위

- 공공 API 기반 메타데이터 수집
- PDF/E-Book 원문 다운로드
- 텍스트 추출 및 정규화
- 청킹
- OpenAI 임베딩 생성
- ChromaDB 적재
- CLI 기반 챗 엔진
- 평가 질문셋 기반 일괄 검증

## 현재 데이터 상태

- 메타데이터: `505건`
  - 설화 `182건`
  - 민담 `323건`
- 원문 파일: `504개`
- 추출 문서: `505건`
- 정규화 문서: `505건`
- 청크: `1749개`
- 평가 결과 리포트 생성 가능

## 핵심 스크립트

- `scripts/fetch_metadata.py`: 설화/민담 API 메타데이터 수집
- `scripts/download_sources.py`: PDF 또는 E-Book 원문 다운로드
- `scripts/extract_text.py`: 원문에서 텍스트 추출 및 정제
- `scripts/normalize_text.py`: 검색용 정규화본 생성
- `scripts/audit_normalization.py`: 정규화 감사
- `scripts/build_chunks.py`: 청크 생성
- `scripts/ingest_to_vector_db.py`: ChromaDB 적재
- `scripts/chat_engine.py`: 검색 + 답변 생성 CLI
- `scripts/evaluation_runner.py`: 평가 질문셋 일괄 실행

## 빠른 실행

가상환경 활성화:

```bash
source .venv/bin/activate
```

전체 파이프라인:

```bash
python3 scripts/fetch_metadata.py --source all --page-size 100
python3 scripts/download_sources.py
python3 scripts/extract_text.py
python3 scripts/normalize_text.py
python3 scripts/audit_normalization.py --source all
python3 scripts/build_chunks.py --chunk-size 900 --overlap 120
python3 scripts/ingest_to_vector_db.py --provider openai
```

챗봇 실행:

```bash
python3 scripts/chat_engine.py --show-retrieval
```

평가 질문셋 실행:

```bash
python3 scripts/evaluation_runner.py --limit 5
```

## 주요 경로

- `data/raw/api/`: API 원본 XML
- `data/raw/documents/`: 다운로드한 PDF/HTML 원문
- `data/extracted/`: 추출 텍스트
- `data/normalized/`: 검색용 정규화 텍스트
- `data/processed/`: 메타데이터 및 평가 질문셋
- `reports/`: 정규화 감사 및 수동 검증 문서
- `reports/evaluations/`: 평가 실행 결과 JSONL/Markdown
- `storage/metadata.db`: 메타데이터, 문서, 청크 SQLite DB
- `storage/vector_db/`: ChromaDB 로컬 인덱스

## 문서

- [jeju_rag_pipeline.md](/Users/choikjun/Desktop/keepdev/졸프/jeju_rag_pipeline.md): 전체 RAG 파이프라인 설명
- [jeju_folklore_rag_design.md](/Users/choikjun/Desktop/keepdev/졸프/jeju_folklore_rag_design.md): 데이터 수집 및 설계 정리
- [jeju_chatbot_direction.md](/Users/choikjun/Desktop/keepdev/졸프/jeju_chatbot_direction.md): 서비스 방향 정리
- [evaluation_question_set.md](/Users/choikjun/Desktop/keepdev/졸프/reports/evaluation_question_set.md): 평가 질문셋 문서
- [chat_engine_manual_validation.md](/Users/choikjun/Desktop/keepdev/졸프/reports/chat_engine_manual_validation.md): 수동 검증 기록

## 주의 사항

- `.env`에 `OPENAI_API_KEY`가 필요하다.
- 벡터 적재와 챗 엔진은 `openai`, `chromadb` 설치가 필요하다.
- PDF 추출은 시스템의 `pdftotext` 명령을 사용한다.
- 현재 추출 파이프라인은 `pdftotext` 기반이며 OCR 고도화는 이번 범위에서 제외했다.
- 챗 엔진은 `--max-distance` 기본값(`0.62`)으로 낮은 관련성 청크를 제거해 환각을 억제한다.
- 출처는 모델 자유 생성이 아니라 `제목 (코드: 번호)` 형식으로 후처리해 붙인다.

## 프로젝트 성격

이 프로젝트의 목표는 `원문 보존 시스템`이 아니라, `제주 설화·민담을 쉽게 설명해주는 해설형 RAG 챗봇`이다.

따라서 원문은 보존하되,
- 검색과 임베딩은 정규화 텍스트 기준
- 사용자 답변은 현대 한국어 기준
으로 구성한다.
