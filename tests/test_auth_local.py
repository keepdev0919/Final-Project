"""심사용 ID/PW 로그인.

공모전 요건: 심사위원이 지정 형식 계정으로 로그인해 서비스 전체를 확인할 수 있어야
하고, **로그인 실패 시 심사에서 제외**된다. 같은 계정을 애플 앱스토어 심사용
로그인 정보로도 제출한다.

지정 형식은 공모전이 정한다 → `docs/관광데이터 개발 공모전/_심사요약.md` §4-2 참조.
**자격 증명 리터럴을 이 파일에도 쓰지 않는다** — 원격 저장소에 올라간다.

이 테스트는 버그 잡기가 아니라 **자격 요건을 코드에 박아두기 위한 것**이다.
"""
import pytest

# 테스트 전용 더미 자격 증명. 실제 값과 무관하며 monkeypatch로 주입한다.
TEST_ID = "test-review-id"
TEST_PW = "test-review-pw-not-real"


@pytest.fixture()
def review_env(monkeypatch):
    """심사 계정 환경변수를 테스트 값으로 채운다."""
    monkeypatch.setenv("REVIEW_ACCOUNT_ID", TEST_ID)
    monkeypatch.setenv("REVIEW_ACCOUNT_PASSWORD", TEST_PW)


def test_wrong_password_returns_401(client, review_env):
    res = client.post("/auth/local", json={"user_id": TEST_ID, "password": "wrong"})
    assert res.status_code == 401


def test_unknown_user_returns_401(client, review_env):
    res = client.post("/auth/local", json={"user_id": "nobody", "password": TEST_PW})
    assert res.status_code == 401


def test_non_ascii_id_returns_401_not_500(client, review_env):
    """비ASCII 자격 증명이 500을 내지 않아야 한다.

    hmac.compare_digest에 한글 문자열을 그대로 넣으면 TypeError가 나고,
    전역 예외 핸들러를 타 500 + 예외 메시지 노출로 이어졌다(실제 발생).
    bytes로 비교해 401이 나와야 한다.
    """
    res = client.post("/auth/local", json={"user_id": "한글아이디", "password": "한글비번"})
    assert res.status_code == 401, "비ASCII 입력에서 401이 아니다"


def test_missing_fields_returns_422(client):
    res = client.post("/auth/local", json={"user_id": TEST_ID})
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
    monkeypatch.setenv("REVIEW_ACCOUNT_ID", TEST_ID)
    monkeypatch.setenv("REVIEW_ACCOUNT_PASSWORD", TEST_PW)
    res = client.post("/auth/local", json={"user_id": TEST_ID, "password": TEST_PW})
    assert res.status_code != 401, "자격 증명이 맞는데 401이 나왔다"
    assert res.status_code in (200, 503)


def test_credentials_not_in_source_code():
    """실제 심사 계정 자격 증명이 **실행되는 코드**에 없어야 한다.

    환경변수(.env, gitignore됨)로만 주입한다.

    ## 검사 범위를 코드로 한정하는 이유

    이 값은 공모전이 **모든 참가자에게 공개한 지정 값**이라 비밀이 아니다. 그래서
    요건을 기록하는 문서(`docs/`)에는 남겨둔다 — 값을 지우면 문서가 쓸모없어진다.

    막으려는 것은 **실행되는 코드에 자격 증명을 박는 습관**이다. 나중에 진짜 비밀이
    같은 자리에 들어가기 때문이다.

    이전 버전은 라우터 파일 하나만 검사해서 **이 테스트 파일 자체에 비밀번호가
    있는 것을 놓쳤다**(코드 리뷰 지적). 이제 코드 확장자 전체를 검사한다.
    """
    import subprocess
    from pathlib import Path

    repo = Path(__file__).parent.parent
    # 리터럴이 이 파일에 그대로 남지 않게 나눠 쓴다 (자기 자신을 잡지 않도록)
    needle = "2026" + "openapi"

    result = subprocess.run(
        ["git", "-C", str(repo), "grep", "-l", needle, "--",
         "*.py", "*.swift", "*.yml", "*.yaml", "*.json", "*.sh"],
        capture_output=True, text=True,
    )
    hits = [line for line in result.stdout.splitlines() if line.strip()]
    assert not hits, f"실행 코드에 자격 증명이 있다:\n" + "\n".join(hits)
