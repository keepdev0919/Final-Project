## Why

평가 질문셋은 준비되었지만, 현재는 사용자가 질문을 하나씩 수동으로 입력하고 결과를 복사해 기록해야 한다. 반복 평가를 빠르게 수행하고, 파라미터 변경 전후 결과를 비교하려면 질문셋을 일괄 실행하고 결과를 구조화된 파일로 저장하는 평가 실행기가 필요하다.

## What Changes

- `data/processed/evaluation_questions.jsonl`을 읽어 질문을 순차 실행하는 평가 실행 스크립트를 추가한다.
- 각 질문의 검색 결과, 답변, 출처, 간단한 규칙 기반 판정 정보를 JSONL과 Markdown 리포트로 저장한다.
- 기존 `chat_engine.py`의 검색/생성 로직을 재사용할 수 있도록 평가 스크립트가 공통 함수를 호출한다.

## Capabilities

### New Capabilities
- `evaluation-runner`: 고정 질문셋을 반복 실행하고 결과를 파일로 저장하는 평가 자동화 기능

### Modified Capabilities

## Impact

- 신규 코드: `scripts/evaluation_runner.py`
- 가능 시 공통 로직 재사용을 위한 `scripts/chat_engine.py` 보강
- 신규 산출물: `reports/evaluations/` 하위 결과 파일
- 기존 평가 질문셋 데이터(`data/processed/evaluation_questions.jsonl`) 활용
