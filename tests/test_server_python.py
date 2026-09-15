"""서버는 파이썬 3.12 로 돈다 — 개발 맥(3.14)에만 있는 것을 서버 코드가 쓰면 안 된다.

2026-09-15 발견: 미션 신고가 `uuid.uuid7()`(3.14 신설) 때문에 서버에서만 매번 실패했다.
로컬 테스트는 3.14 에서 돌아 통과했고, 앱은 실패한 신고를 기기에 쌓아 두니 화면도
멀쩡했다. 출시부터 나흘 동안 신고가 한 건도 서버에 저장되지 않았다.
"""
import re
import uuid
from pathlib import Path

from services.ids import uuid7

BACKEND = Path(__file__).resolve().parent.parent / "backend"


def test_ci_tests_with_the_same_python_as_the_server():
    """GitHub 자동 테스트가 서버와 다른 파이썬으로 돌면 오늘 같은 버그를 또 못 잡는다."""
    root = BACKEND.parent
    server = re.search(r"^FROM python:(\d+\.\d+)", (root / "Dockerfile").read_text(encoding="utf-8"), re.M)
    ci = re.search(r'python-version:\s*"(\d+\.\d+)"',
                   (root / ".github" / "workflows" / "server-tests.yml").read_text(encoding="utf-8"))
    assert server and ci and server.group(1) == ci.group(1)


def test_uuid7_is_a_real_time_ordered_uuid7():
    a, b = uuid7(), uuid7()
    assert uuid.UUID(a).version == 7
    assert uuid.UUID(a).variant == uuid.RFC_4122
    assert a[:8] <= b[:8]  # 앞 48비트가 밀리초 시각이라 시간순으로 정렬된다


def test_server_code_does_not_call_stdlib_uuid7():
    offenders = []
    for path in BACKEND.rglob("*.py"):
        if {"venv", "tests", "__pycache__"} & set(path.parts):
            continue
        # 설명 글의 `uuid.uuid7()` (백틱으로 감싼 언급)은 빼고 실제 호출만 센다
        if re.search(r"(?<![`\w.])uuid\.uuid7\(", path.read_text(encoding="utf-8")):
            offenders.append(str(path.relative_to(BACKEND)))
    assert offenders == [], f"서버 3.12 에 없는 uuid.uuid7() 을 쓴다 — services.ids.uuid7 로: {offenders}"


def test_mission_report_works_without_stdlib_uuid7(client, monkeypatch, tmp_path):
    """서버처럼 `uuid.uuid7` 이 없는 상태에서 앱이 신고를 보낸다."""
    import threading
    from services import db
    monkeypatch.delattr(uuid, "uuid7", raising=False)
    monkeypatch.setattr(db, "DB_PATH", tmp_path / "metadata.db")
    monkeypatch.setattr(db, "RECORDS_PATH", tmp_path / "volume" / "records.db")
    monkeypatch.setattr(db, "_thread_local", threading.local())

    res = client.post("/report/mission", json={
        "play_id": "seongeup-restore", "mission_id": "m07", "reason": "notVisible"})
    assert res.status_code == 201, res.text
