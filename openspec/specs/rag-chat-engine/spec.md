## ADDED Requirements

### Requirement: question-understanding
시스템은 사용자의 자연어 질문을 입력받아 직접 임베딩하거나 검색에 적합한 쿼리로 변환하여 유사도 검색을 수행해야 한다.

#### Scenario: natural-language-input
- **WHEN** 사용자가 제주 설화나 민담에 대해 자연어로 질문할 때
- **THEN** 시스템은 해당 질문의 의미 벡터를 생성해 검색에 사용한다.

### Requirement: context-retrieval
시스템은 ChromaDB에서 질문과 가장 유사한 상위 K개의 청크를 관련 문맥으로 가져와야 한다.

#### Scenario: accurate-retrieval
- **WHEN** 검색을 수행할 때
- **THEN** 질문의 의미와 가장 가까운 설화/민담 텍스트 조각들이 순위별로 반환된다.

### Requirement: grounded-generation
시스템은 검색된 설화/민담 내용을 바탕으로 답변을 생성하며, 제공되지 않은 정보에 대해서는 답변을 거부해야 한다.

#### Scenario: hallucination-prevention
- **WHEN** 질문에 대한 답이 검색 문맥에 없을 때
- **THEN** 시스템은 `제공된 설화 자료에는 해당 내용이 없습니다.`라고 답변한다.

### Requirement: citation-output
시스템은 답변에 반드시 참고한 설화의 제목과 고유 번호를 포함해야 한다.

#### Scenario: citation-format
- **WHEN** 답변이 생성될 때
- **THEN** 답변 하단에 `출처: [설화 제목] (코드: [번호])` 형식의 참고 문헌이 붙는다.
