# 제주 설화·민담 수집 파이프라인

## 구성

- `scripts/fetch_metadata.py`: 설화/민담 API 메타데이터 수집
- `scripts/download_sources.py`: PDF 또는 E-Book 원문 다운로드
- `scripts/extract_text.py`: 원문에서 텍스트 추출 및 정제
- `scripts/normalize_text.py`: 검색용 현대 표기 정규화본 생성
- `scripts/audit_normalization.py`: 정규화 후 남은 특수문자와 문맥 예문 감사
- `scripts/build_chunks.py`: 정규화된 텍스트를 우선 사용해 청크 분할
- `scripts/ingest_to_vector_db.py`: 청크를 임베딩해 ChromaDB에 적재
- `scripts/chat_engine.py`: Chroma 검색 + OpenAI 응답 생성 CLI
- `scripts/evaluation_runner.py`: 평가 질문셋을 일괄 실행하고 JSONL/Markdown 결과 저장
- `scripts/common.py`: 경로, SQLite 스키마, 공통 유틸

## 실행 순서

```bash
python3 scripts/fetch_metadata.py --source all --page-size 100
python3 scripts/download_sources.py
python3 scripts/extract_text.py
python3 scripts/normalize_text.py
python3 scripts/audit_normalization.py --source all
python3 scripts/build_chunks.py --chunk-size 900 --overlap 120
python3 scripts/ingest_to_vector_db.py --provider openai
python3 scripts/chat_engine.py
python3 scripts/evaluation_runner.py --limit 5
```

## 생성되는 주요 경로

- `data/raw/api/`: API 원본 XML
- `data/raw/documents/`: 다운로드한 PDF/HTML
- `data/extracted/`: 정제된 텍스트 파일
- `data/normalized/`: 검색용 정규화 텍스트 파일
- `data/processed/`: 수집된 메타데이터 JSONL
- `reports/`: 2차 정규화 감사 리포트
- `reports/evaluations/`: 평가 질문셋 실행 결과 JSONL/Markdown
- `storage/metadata.db`: 메타데이터, 문서, 청크 SQLite DB
- `storage/vector_db/`: ChromaDB 로컬 벡터 인덱스

## 주의

- API는 XML 응답을 반환한다고 가정했다.
- PDF 텍스트 추출은 시스템의 `pdftotext` 명령을 사용한다.
- 정규화 단계는 원문을 보존한 채 검색 품질에 치명적인 문자만 보수적으로 치환한다.
- 벡터 적재는 `OPENAI_API_KEY`와 `chromadb`, `openai` 설치가 필요하다.
- 로컬 검증용으로 `python3 scripts/ingest_to_vector_db.py --provider dummy --limit 5`를 사용할 수 있다.
- 챗 엔진은 가상환경 활성화 후 `python scripts/chat_engine.py --show-retrieval`로 실행하는 것을 권장한다.
- 챗 엔진은 `--max-distance` 기본값(`0.62`)으로 낮은 관련성 청크를 버려 환각을 억제한다.
- 최종 답변의 출처는 모델 자유 생성에 맡기지 않고 `제목 (코드: 번호)` 형식으로 후처리해 붙인다.
- 평가 실행기는 [evaluation_questions.jsonl](/Users/choikjun/Desktop/keepdev/졸프/data/processed/evaluation_questions.jsonl)을 읽어 질문별 판정 결과를 `reports/evaluations/`에 저장한다.
- 일부 PDF가 이미지 기반이면 OCR 단계가 추가로 필요할 수 있다.
