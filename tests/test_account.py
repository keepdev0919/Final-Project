"""계정 삭제 — 애플 필수 요건.

애플은 **로그인 기능이 있는 앱에 앱 내 계정 삭제 경로를 요구**한다. 없으면
앱스토어 심사에서 거절된다. 계정을 만들 수 있게 해놓고 지울 수 없게 두면 안 된다는
취지다.

이 테스트는 버그 잡기가 아니라 **요건을 코드에 박아두기 위한 것**이다.
"""


def test_delete_without_token_returns_401(client):
    """토큰 없이 삭제 요청하면 401이어야 한다.

    남의 계정을 지울 수 있으면 안 된다.
    """
    res = client.delete("/account")
    assert res.status_code == 401


def test_delete_with_invalid_token_returns_401(client):
    """위조·만료 토큰도 401이어야 한다."""
    res = client.delete("/account", headers={"Authorization": "Bearer invalid-token"})
    assert res.status_code == 401


def test_delete_route_exists(client):
    """DELETE /account 경로 자체가 있어야 한다.

    404가 나오면 애플 요건을 충족하지 못한다 — 401이어야 한다(경로는 있고
    인증만 막힌 상태).
    """
    res = client.delete("/account")
    assert res.status_code != 404, "DELETE /account 경로가 없다 — 애플 심사 거절 사유"


def test_account_route_is_registered_in_app():
    """라우터가 앱에 등록되어 있어야 한다.

    파일만 만들고 include_router를 잊는 실수를 막는다.
    """
    from main import app

    paths = {getattr(r, "path", "") for r in app.routes}
    assert "/account" in paths, f"/account가 등록되지 않았다. 등록된 경로: {sorted(paths)}"
