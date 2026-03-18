## 1. 환경 구축 및 라이브러리 연동

- [ ] 1.1 시스템에 `tesseract-ocr` 및 `poppler-utils` 설치 안내 및 확인
- [ ] 1.2 `requirements.txt`에 `pytesseract`, `pdf2image`, `Pillow` 추가

## 2. OCR 추출 엔진 구현

- [ ] 2.1 PDF 페이지를 이미지 컬렉션으로 변환하는 유틸리티 구현
- [ ] 2.2 Tesseract를 사용하여 이미지에서 한국어 텍스트를 추출하는 함수 작성
- [ ] 2.3 이미지 전처리(Denoising, Thresholding) 파이프라인 적용

## 3. 기존 추출 로직 고도화

- [ ] 3.1 `scripts/extract_text.py`에 OCR 폴백(Fallback) 로직 통합
- [ ] 3.2 텍스트 추출 품질 점수화 및 OCR 전환 임계값 설정
- [ ] 3.3 추출된 텍스트의 후처리(불필요한 기호 제거 등) 강화

## 4. 품질 검증

- [ ] 4.1 이미지 기반 PDF 샘플(글자가 그림으로 된 파일)로 추출 테스트
- [ ] 4.2 기존 텍스트 기반 PDF의 추출 결과와 비교하여 사이드 이펙트 확인
