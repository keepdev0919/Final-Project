"""문서 뷰어가 지켜야 할 결정을 코드에 박아둔다.

이 테스트는 버그를 잡으려는 게 아니라, **나중에 이 값을 함부로 바꾸지 못하게**
하려고 있다. 문서 뷰어는 편의 도구지만 다루는 내용이 미공개 기획이라,
바인딩 주소와 열람 범위 두 가지가 틀리면 조용히 사고가 난다.
"""

import sys
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "scripts" / "docs_viewer"))

import server  # noqa: E402


def test_binds_to_localhost_only():
    """서버는 127.0.0.1에만 묶여야 한다.

    docs/ 안에는 공모전 전략, 미발표 서비스 기획, 가격 고민이 들어 있다.
    0.0.0.0으로 바꾸면 같은 와이파이에 붙은 아무 기기나 이 문서를 볼 수 있다.
    카페·공유오피스에서 개발할 때 실제로 노출된다. 편의를 위해서라도 바꾸지 않는다.
    폰에서 보고 싶어지면, 바인딩을 여는 게 아니라 별도 인증을 먼저 붙인다.
    """
    source = (PROJECT_ROOT / "scripts" / "docs_viewer" / "server.py").read_text(encoding="utf-8")
    assert '"127.0.0.1"' in source, "서버 바인딩 주소가 127.0.0.1이 아니다"
    assert "0.0.0.0" not in source, "서버가 외부에 열려 있다"


@pytest.mark.parametrize(
    "attack",
    [
        "../.env",
        "../../../../etc/passwd",
        ".env",
        "backend/main.py",
        "ios/JejuFolklore/Sources/App/Config.swift",
        "docs/../.env",
    ],
)
def test_rejects_paths_outside_the_document_list(attack):
    """열람 대상으로 수집된 문서가 아니면 무조건 거절한다.

    `.env`에는 KTO API 키가 들어 있다. 뷰어는 브라우저에 열려 있으므로,
    경로만 바꿔 요청하면 읽히는 구조였다면 그 자체로 유출 경로가 된다.
    문자열 검사(`..` 포함 여부)가 아니라 **수집된 목록과 대조**하는 방식이라야
    새로운 우회 표현이 나와도 막힌다.
    """
    assert server.resolve_doc(attack) is None


def test_only_markdown_is_listed():
    """열람 목록에는 .md만 들어간다.

    PDF·hwp·소스코드까지 열게 만들면 열람 범위가 슬금슬금 넓어지고,
    그만큼 위 화이트리스트가 헐거워진다. 뷰어의 목적은 md 가독성 하나다.
    """
    paths = list(server._iter_doc_paths())
    assert paths, "문서를 하나도 못 찾았다 — 수집 경로가 깨졌다"
    assert all(p.suffix == ".md" for p in paths)


def test_documents_are_never_cached_by_the_browser():
    """문서 응답에 캐시를 걸지 않는다.

    이 뷰어의 존재 이유가 '항상 최신'이다. 브라우저가 문서를 캐시하면
    미리 생성한 HTML을 보던 것과 똑같은 실패(오래된 내용을 모른 채 보기)가
    돌아온다. 폰트·스크립트는 안 바뀌므로 캐시해도 된다.
    """
    source = (PROJECT_ROOT / "scripts" / "docs_viewer" / "server.py").read_text(encoding="utf-8")
    assert '"Cache-Control", "no-store"' in source


def test_viewer_runs_without_project_dependencies():
    """뷰어는 표준 라이브러리만 쓴다.

    backend/requirements.txt가 바뀌거나 .venv를 다시 만들어도 문서는 열려야 한다.
    문서를 못 보는 상황이 가장 자주 오는 때가 바로 환경을 갈아엎을 때다.
    """
    source = (PROJECT_ROOT / "scripts" / "docs_viewer" / "server.py").read_text(encoding="utf-8")
    banned = ["import fastapi", "import uvicorn", "import markdown", "import requests", "from fastapi"]
    for token in banned:
        assert token not in source, f"외부 패키지 의존이 생겼다: {token}"
