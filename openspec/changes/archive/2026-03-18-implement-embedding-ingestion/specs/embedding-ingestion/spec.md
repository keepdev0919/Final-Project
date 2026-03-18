## ADDED Requirements

### Requirement: embedding-generation
시스템은 SQLite `chunks` 테이블의 모든 텍스트 청크에 대해 OpenAI `text-embedding-3-small` 모델을 사용하여 벡터 임베딩을 생성해야 한다.

#### Scenario: bulk-embedding
- **WHEN** 초기 적재 스크립트가 실행될 때
- **THEN** 모든 청크가 배치 단위로 OpenAI API에 전달되어 임베딩이 생성된다.

### Requirement: vector-db-storage
시스템은 생성된 임베딩을 ChromaDB 로컬 인덱스에 저장해야 하며, 각 벡터에는 원본 청크의 메타데이터가 포함되어야 한다.

#### Scenario: storage-consistency
- **WHEN** 벡터 DB에 데이터가 저장될 때
- **THEN** `doc_id`, `source_type`, `code_no`, `title`, `category`, `tags`가 메타데이터로 함께 저장된다.

### Requirement: incremental-sync
시스템은 이미 벡터 DB에 적재된 청크를 다시 임베딩하지 않고 건너뛰어야 한다.

#### Scenario: skip-existing
- **WHEN** 동기화 스크립트를 재실행할 때
- **THEN** 해당 `chunk_id`가 이미 존재하면 중복 적재를 수행하지 않는다.
