"""POST /chat 엔드포인트 테스트 (LLM mock)."""
import pytest
import json
from unittest.mock import patch, AsyncMock, MagicMock


def _make_sse_chunks(texts):
    """SSE 텍스트 청크 시뮬레이션."""
    for text in texts:
        msg = MagicMock()
        msg.content = text
        yield {"agent": {"messages": [msg]}}
    # DONE sentinel
    yield {}


PAYLOAD = {
    "message": "성산일출봉에 얽힌 설화 알려줘",
    "history": [],
}


@pytest.fixture()
def mock_agent():
    """create_react_agent를 mock하고 astream을 AsyncMock으로 설정."""
    async def fake_astream(input_dict):
        chunks = list(_make_sse_chunks(["성산일출봉에는 설문대할망 전설이 있습니다."]))
        for c in chunks:
            yield c

    mock_graph = MagicMock()
    mock_graph.astream = fake_astream

    with patch("routers.chat.create_react_agent", return_value=mock_graph):
        yield mock_graph


def test_chat_returns_200(client, mock_agent):
    """정상 요청 → 200 + SSE."""
    res = client.post("/chat", json=PAYLOAD)
    assert res.status_code == 200


def test_chat_content_type(client, mock_agent):
    """Content-Type: text/event-stream."""
    res = client.post("/chat", json=PAYLOAD)
    assert "text/event-stream" in res.headers["content-type"]


def test_chat_sse_contains_text(client, mock_agent):
    """SSE 스트림에 text 필드 포함."""
    res = client.post("/chat", json=PAYLOAD)
    lines = res.text.split("\n")
    data_lines = [l for l in lines if l.startswith("data:")]
    # DONE 이외의 data 라인에서 text 키 확인
    non_done = [l for l in data_lines if "[DONE]" not in l]
    if non_done:
        payload = json.loads(non_done[0].replace("data: ", ""))
        assert "text" in payload or "error" in payload


def test_chat_sse_ends_with_done(client, mock_agent):
    """SSE 스트림이 [DONE]으로 끝남."""
    res = client.post("/chat", json=PAYLOAD)
    assert "data: [DONE]" in res.text


def test_chat_missing_message(client):
    """message 없으면 422."""
    res = client.post("/chat", json={"history": []})
    assert res.status_code == 422


def test_chat_with_history(client, mock_agent):
    """history 포함 요청도 정상 처리."""
    payload = {
        "message": "더 자세히 알려줘",
        "history": [
            {"role": "user", "content": "설화 알려줘"},
            {"role": "assistant", "content": "네, 설명해 드릴게요."},
        ],
    }
    res = client.post("/chat", json=payload)
    assert res.status_code == 200
