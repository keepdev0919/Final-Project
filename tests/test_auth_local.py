"""심사용 ID/PW 로그인.

공모전 요건: 심사위원이 지정 형식 계정으로 로그인해 서비스 전체를 확인할 수 있어야
하고, **로그인 실패 시 심사에서 제외**된다. 같은 계정을 애플 앱스토어 심사용
로그인 정보로도 제출한다.

지정 형식(변경 불가): `openapi` / `2026openapi!`

이 테스트는 버그 잡기가 아니라 **자격 요건을 코드에 박아두기 위한 것**이다.
"""
import os


def test_wrong_password_returns_401(client):
    res = client.post("/auth/local", json={"user_id": "openapi", "password": "wrong"})
    assert res.status_code == 401


def test_unknown_user_returns_401(client):
    res = client.post("/auth/local", json={"user_id": "nobody", "password": "2026openapi!"})
    assert res.status_code == 401


def test_missing_fields_returns_422(client):
    res = client.post("/auth/local", json={"user_id": "openapi"})
    assert res.status_code == 422


def test_empty_env_never_authenticates(client, monkeypatch):
    """환경변수가 비어 있으면 어떤 입력으로도 통과하지 못해야 한다.

    빈 문자열끼리 비교해 통과하는 사고를 막는다. 계정 정보를 설정하지 않은
    서버가 빈 자격 증명으로 열리면 안 된다.
    """
    monkeypatch.delenv("REVIEW_ACCOUNT_ID", raising=False)
    monkeypatch.delenv("REVIEW_ACCOUNT_PASSWORD", raising=False)
    res = client.post("/auth/local", json={"user_id": "", "password": ""})
    assert res.status_code == 401


def test_correct_credentials_reach_token_issuance(client, monkeypatch):
    """자격 증명이 맞으면 토큰 발급 단계까지 간다.

    Firebase가 설정되지 않은 환경에서는 503을 반환한다. **401이 아니라는 점**이
    확인 대상이다 — 자격 증명 검증 자체는 통과했다는 뜻이다.
    """
    monkeypatch.setenv("REVIEW_ACCOUNT_ID", "openapi")
    monkeypatch.setenv("REVIEW_ACCOUNT_PASSWORD", "2026openapi!")
    res = client.post("/auth/local", json={"user_id": "openapi", "password": "2026openapi!"})
    assert res.status_code != 401, "자격 증명이 맞는데 401이 나왔다"
    assert res.status_code in (200, 503)


def test_password_is_not_hardcoded():
    """비밀번호가 소스에 박혀 있지 않아야 한다.

    공개 저장소에 올라가는 코드에 심사 계정 비밀번호를 커밋하면 안 된다.
    환경변수(REVIEW_ACCOUNT_PASSWORD)로만 주입한다.
    """
    from pathlib import Path

    router = Path(__file__).parent.parent / "backend" / "routers" / "auth_local.py"
    source = router.read_text(encoding="utf-8")
    assert "2026openapi!" not in source, "비밀번호가 소스에 하드코딩됐다"
