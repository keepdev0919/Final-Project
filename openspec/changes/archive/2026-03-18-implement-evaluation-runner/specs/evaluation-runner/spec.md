## ADDED Requirements

### Requirement: batch-question-execution
시스템은 평가 질문셋 파일을 읽어 각 질문을 순차적으로 실행해야 한다.

#### Scenario: run-all-questions
- **WHEN** 사용자가 평가 실행기를 실행하면
- **THEN** 시스템은 질문셋의 각 질문을 순서대로 검색 및 답변 생성 파이프라인에 전달해야 한다.

### Requirement: structured-result-output
시스템은 각 질문의 실행 결과를 구조화된 파일로 저장해야 한다.

#### Scenario: save-jsonl-results
- **WHEN** 평가 실행이 완료되면
- **THEN** 시스템은 질문 ID, 질문 본문, 검색 결과, 답변, 판정 정보를 포함한 JSONL 결과 파일을 생성해야 한다.

#### Scenario: save-markdown-report
- **WHEN** 평가 실행이 완료되면
- **THEN** 시스템은 사람이 읽을 수 있는 Markdown 요약 리포트를 생성해야 한다.

### Requirement: rule-based-evaluation
시스템은 질문셋의 기대 동작을 바탕으로 최소한의 규칙 기반 판정 정보를 제공해야 한다.

#### Scenario: rejection-expected-question
- **WHEN** 질문셋 항목에서 `rejection_expected=true`인 질문을 실행하면
- **THEN** 시스템은 답변에 거부 문구와 `출처: 없음`이 포함되는지 검사해야 한다.

#### Scenario: keyword-check-question
- **WHEN** 일반 질문을 실행하면
- **THEN** 시스템은 답변에 기대 키워드 일부와 출처가 포함되는지 검사해야 한다.

### Requirement: configurable-run-parameters
시스템은 동일한 질문셋에 대해 검색 및 생성 파라미터를 바꿔 반복 실험할 수 있어야 한다.

#### Scenario: override-run-parameters
- **WHEN** 사용자가 `--k` 또는 `--max-distance` 같은 실행 옵션을 지정하면
- **THEN** 시스템은 해당 설정으로 질문셋 전체를 평가해야 한다.
