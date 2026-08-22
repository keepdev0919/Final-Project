import sys
import os
import warnings
warnings.filterwarnings("ignore")

# backend 모듈 경로 추가
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

# 테스트용 환경변수 (실제 API 호출 없음)
os.environ.setdefault("OPENAI_API_KEY", "sk-test-dummy")
os.environ.setdefault("GOOGLE_MAPS_API_KEY", "dummy")
os.environ.setdefault("KTO_API_KEY", "dummy")

import pytest
from fastapi.testclient import TestClient
from main import app


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="session")
def db_conn():
    """실제 로컬 DB 연결. 읽기만 한다.

    홈 순위·오디 목록 테스트는 실제 데이터(비짓제주 146,357건 · 오디 224건)를
    봐야 의미가 있다. 가짜 데이터로는 "성산일출봉이 상위에 있나"를 물을 수 없다.
    """
    from services.db import get_db_connection
    return get_db_connection()
