"""공개 법적 고지 페이지.

앱스토어 심사와 공모전 제출 모두 "접속 가능한 개인정보 처리방침 URL"을 요구한다.
앱은 이 서버 없이는 동작하지 않으므로, 처리방침만 따로 호스팅해 두 곳을 관리하는 대신
같은 서버에서 함께 서빙한다. 서버가 살아 있으면 처리방침도 살아 있다.
"""

from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["legal"])

_STATIC = Path(__file__).resolve().parent.parent / "static"
_PRIVACY_HTML = (_STATIC / "privacy.html").read_text(encoding="utf-8")
# App Store Connect 의 필수 항목 「지원 URL」. 비어 있으면 앱 등록 자체가 저장되지 않는다.
_SUPPORT_HTML = (_STATIC / "support.html").read_text(encoding="utf-8")


@router.get("/privacy", response_class=HTMLResponse)
def privacy_policy() -> HTMLResponse:
    return HTMLResponse(_PRIVACY_HTML)


@router.get("/support", response_class=HTMLResponse)
def support_page() -> HTMLResponse:
    return HTMLResponse(_SUPPORT_HTML)


@router.get("/support", response_class=HTMLResponse)
def support_page() -> HTMLResponse:
    return HTMLResponse(_SUPPORT_HTML)
