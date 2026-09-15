"""GitHub 자동 배포가 서버에 들어가는 파일이 바뀐 커밋을 놓치지 않게 한다 (2026-09-15).

railway.json 의 watchPatterns 에 걸린 파일이 바뀐 커밋만 Railway 가 다시 배포한다.
iOS·미니앱·문서만 고친 push 로 서버가 괜히 재시작되지 않게 하려는 것이다.
그런데 Dockerfile 에 COPY 를 새로 넣고 여기에 안 적으면, 그 파일을 고쳐 push 해도
서버에 반영되지 않는다 — 에러 없이 옛 파일로 계속 돈다.
"""
import fnmatch
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_every_file_the_server_image_copies_is_watched():
    patterns = json.loads((ROOT / "railway.json").read_text(encoding="utf-8"))["build"]["watchPatterns"]
    sources = re.findall(r"^COPY\s+(\S+)\s", (ROOT / "Dockerfile").read_text(encoding="utf-8"), re.M)
    assert sources
    for src in sources:
        probe = src.rstrip("/") + ("/x" if src.endswith("/") else "")
        assert any(fnmatch.fnmatch(probe, p) for p in patterns), f"Dockerfile 이 {src} 를 싣는데 watchPatterns 에 없다"
