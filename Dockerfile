# 놀멍봅서 API 서버 — Railway 배포용
#
# 로컬 개발은 start_dev.sh 와 루트 requirements.txt 를 쓴다. 이 이미지는 배포 전용이라
# 서버가 요청을 처리하는 데 필요한 것만 담는다 (backend/requirements.txt 참조).
#
# 파이썬을 3.12로 고정한 이유: 개발 환경은 3.14지만 배포에서까지 최신 런타임을 쫓으면
# 휠이 없는 패키지에서 빌드가 깨진다. 3.12는 의존성 휠이 모두 준비돼 있다.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# 의존성을 먼저 복사해 코드가 바뀌어도 설치 레이어가 캐시되게 한다
COPY backend/requirements.txt /app/backend/requirements.txt
RUN pip install --no-cache-dir -r /app/backend/requirements.txt

# 서버 코드
COPY backend/ /app/backend/

# 서버가 읽는 데이터.
#   data/           PLAY 원고(data/plays/*.json)와 장소 목록(data/places.json)
#   storage/*.db    코스 1,255개·홈 장소·오디 목록. 이게 없으면 앱이 빈 화면으로 뜬다
# ⚠️ storage/metadata.db 는 .gitignore 에 있으면 빌드 컨텍스트에 들어오지 않아
#    이 COPY 가 실패한다. 배포하려면 추적 대상으로 바꿔 커밋해야 한다.
COPY data/ /app/data/
COPY storage/metadata.db /app/storage/metadata.db

# 경로 규칙: services/*.py 가 BASE_DIR = parent.parent.parent 로 /app 을 가리킨다.
# 따라서 /app/data, /app/storage 위치가 그대로 맞다.
WORKDIR /app/backend

# Railway 가 PORT 를 주입한다. 로컬 실행 시에는 8000.
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
