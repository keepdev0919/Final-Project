## Why

현재 제주 설화·민담 데이터는 SQLite DB의 `chunks` 테이블에 텍스트 조각(chunk)으로만 저장되어 있습니다. 하지만 RAG(Retrieval-Augmented Generation) 시스템을 구축하기 위해서는 사용자의 질문과 의미적으로 유사한 텍스트를 빠르게 찾아낼 수 있는 벡터 검색 기능이 필수적입니다. 따라서 텍스트 청크를 숫자 벡터(embedding)로 변환하고 이를 검색에 최적화된 벡터 데이터베이스에 적재하는 단계가 필요합니다.

## What Changes

- `scripts/ingest_to_vector_db.py` 신규 생성: SQLite DB의 `chunks` 테이블에서 데이터를 읽어와 임베딩을 생성하고 벡터 DB에 저장하는 스크립트.
- `common.py` 수정: 벡터 DB 경로 및 임베딩 모델 설정을 위한 상수 추가.
- `requirements.txt` (필요시): `openai`, `chromadb` 등의 라이브러리 의존성 추가.

## Capabilities

### New Capabilities
- `embedding-ingestion`: SQLite에 저장된 텍스트 청크를 대량으로 임베딩하여 벡터 데이터베이스(예: ChromaDB)에 동기화하고 관리하는 기능.

### Modified Capabilities
- 없음.

## Impact

- `storage/` 디렉토리에 벡터 DB 인덱스 파일이 생성됨.
- `chunks` 테이블의 데이터를 벡터 DB와 동기화하는 파이프라인이 구축됨.
- 향후 검색 엔진 구현의 기점이 됨.
