## 1. 환경 설정 및 의존성 추가

- [x] 1.1 `requirements.txt`에 `openai`, `chromadb` 추가 (또는 `pip install`)
- [x] 1.2 `.env` 파일에 `OPENAI_API_KEY` 설정 확인 및 안내
- [x] 1.3 `common.py`에 `VECTOR_DB_PATH` 및 `EMBEDDING_MODEL` 상수 추가

## 2. 임베딩 및 적재 스크립트 구현

- [x] 2.1 `scripts/ingest_to_vector_db.py` 기본 골격 작성
- [x] 2.2 SQLite `chunks` 테이블 읽기 및 필터링 로직 구현 (미처리 데이터 대상)
- [x] 2.3 OpenAI API를 이용한 배치 임베딩 생성 함수 구현
- [x] 2.4 ChromaDB 컬렉션 생성 및 데이터(벡터 + 메타데이터) 적재 로직 구현

## 3. 검증 및 테스트

- [x] 3.1 소량의 데이터(예: --limit 5)로 적재 테스트 수행
- [x] 3.2 ChromaDB에 데이터가 정상적으로 저장되었는지 간단한 쿼리로 확인
- [x] 3.3 중복 실행 시 이미 적재된 데이터가 건너뛰어지는지 확인
