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
