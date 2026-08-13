"""제거한 구방향 엔드포인트가 되살아나지 않았는지 확인.

일지·민화 생성(`/travel/journal`)과 설화 RAG 채팅(`/travel/companion`)은
2026-08-13에 제거했다. 현 방향(현장 참여형 오디오 경험)과 맞지 않고,
일지는 이미지 생성 비용까지 든다.

되살릴 일이 있으면 이 테스트를 먼저 지우면서 "왜 되살리는지"를 남길 것.
"""


def test_journal_endpoint_gone(client):
    """일지·민화 생성 엔드포인트가 없어야 한다.

    여정 완료 화면은 단계 1에서 픽셀아트 기록 화면으로 새로 만든다.
    """
    res = client.post("/travel/journal", json={})
    assert res.status_code == 404


def test_companion_chat_endpoint_gone(client):
    """설화 RAG 채팅 엔드포인트가 없어야 한다.

    도착 후 열리던 자리에 단계 1의 이야기 재생 화면이 들어간다.
    자유 질문 기능은 후순위로 이월했다.
    """
    res = client.post("/travel/companion", json={})
    assert res.status_code == 404


def test_no_travel_router_registered(client):
    """`/travel` 접두사를 쓰는 라우트가 하나도 없어야 한다.

    경로 두 개만 확인하면 `/travel/summary` 같은 다른 경로로 부활해도
    통과한다. 접두사 전체를 막는다.
    """
    from main import app

    travel_paths = [r.path for r in app.routes if getattr(r, "path", "").startswith("/travel")]
    assert not travel_paths, f"/travel 라우트가 남아 있다: {travel_paths}"
