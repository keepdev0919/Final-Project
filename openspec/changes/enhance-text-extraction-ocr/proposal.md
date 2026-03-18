## Why

현재 `scripts/extract_text.py`는 `pdftotext`를 사용하여 텍스트 레이어에서 데이터를 추출합니다. 하지만 일부 제주 설화 PDF는 이미지 스캔본이거나, 다단 구성 등 복잡한 레이아웃을 가지고 있어 텍스트 추출이 불완전하거나 문맥이 섞이는 문제가 발생할 수 있습니다. 이를 해결하기 위해 OCR(광학 문자 인식) 기능과 레이아웃 분석 기능을 도입하여 데이터 수집의 정확도를 극대화해야 합니다.

## What Changes

- `scripts/extract_text_v2.py` (또는 기존 파일 수정): OCR 엔진(예: Tesseract, EasyOCR, 또는 업스테이지 OCR API) 연동 로직 추가.
- 이미지 처리 로직: PDF의 각 페이지를 이미지로 변환하고 전처리하는 과정 추가.
- 레이아웃 분석: 표나 그림을 제외하고 본문 텍스트만 논리적인 순서로 추출하는 기능 강화.

## Capabilities

### New Capabilities
- `ocr-extraction`: 텍스트 레이어가 없는 이미지 기반 PDF에서도 텍스트를 정확하게 추출하는 기능.
- `layout-aware-extraction`: 복잡한 문서 구조에서도 문맥 흐름을 깨지 않고 본문을 추출하는 기능.

### Modified Capabilities
- `text-extraction`: 기존 텍스트 추출 기능에 OCR 폴백(Fallback) 로직을 추가하여 고도화.

## Impact

- 기존에 텍스트 추출이 불가능했던 문서들도 RAG 데이터셋에 포함할 수 있게 됨.
- 특히 옛날 문헌의 스캔본 등에 대한 대응력이 확보됨.
