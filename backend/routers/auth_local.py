"""심사용 ID/PW 로그인 → Firebase 커스텀 토큰 발급.

## 왜 필요한가

공모전 요건상 심사위원이 **지정 형식 계정**으로 로그인해 서비스 전체를 확인할 수 있어야
한다. 공지 원문: *"서비스 로그인이 불가할 경우 서비스 확인이 불가하여 심사에서 제외될
수 있습니다."* 그리고 개인 계정 제출은 불가하며 지정 형식(`openapi`)을 써야 한다.

일반 사용자는 소셜 로그인(Google/Apple)을 쓴다. 이 경로는 **심사 계정 하나만** 통과시킨다.

같은 계정을 애플 앱스토어 심사용 로그인 정보로도 제출한다 — 두 곳 겸용.

## 왜 커스텀 토큰인가

자체 세션·JWT를 만들면 기존 Firebase 사용자 체계와 분리돼, Firestore 동기화와 향후
결제 기간 기록(`사용자 × 여정 × 만료일`)을 두 갈래로 관리해야 한다. 백엔드가 자격
증명만 확인하고 Firebase 커스텀 토큰을 발급하면 그 뒤는 일반 사용자와 완전히 같은
경로를 탄다.

## 계정 정보는 환경변수로

**자격 증명 리터럴을 소스에 두지 않는다.** `.env`에만 넣는다(`.gitignore`에 이미 포함):

    REVIEW_ACCOUNT_ID=<아이디>
    REVIEW_ACCOUNT_PASSWORD=<비밀번호>
    REVIEW_ACCOUNT_UID=review-openapi

실제 값은 공모전이 지정한 형식이다 →
`docs/관광데이터 개발 공모전/_심사요약.md` §4-2 참조.

(공개 지정 값이라 비밀은 아니지만, 소스에 자격 증명을 적는 습관을 만들지 않는다.
`tests/test_auth_local.py::test_password_is_not_hardcoded`가 이를 지킨다.)
"""
from __future__ import annotations

import hmac
import os

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address

router = APIRouter(prefix="/auth", tags=["auth"])
limiter = Limiter(key_func=get_remote_address)

# 이 UID로 Firebase 사용자가 만들어진다. 심사 계정 해금 판정에도 쓴다.
REVIEW_UID = os.getenv("REVIEW_ACCOUNT_UID", "review-openapi")


class LocalLoginRequest(BaseModel):
    user_id: str
    password: str


class LocalLoginResponse(BaseModel):
    custom_token: str


# 분당 20회. 무차별 대입을 막으면서도 심사위원이 오타 몇 번으로 잠기지 않을 수준.
#
# ⚠️ 한계: slowapi의 get_remote_address는 프록시 뒤에서 모든 요청을 단일 IP로
# 집계한다. 배포 환경에 프록시가 있으면 여러 심사위원이 한 통에 묶여 락아웃될 수
# 있다. 그 환경에서는 X-Forwarded-For 기반 key_func로 바꿀 것.
@router.post("/local", response_model=LocalLoginResponse)
@limiter.limit("20/minute")
def local_login(request: Request, body: LocalLoginRequest):
    """심사 계정 자격 증명을 확인하고 Firebase 커스텀 토큰을 발급한다."""
    expected_id = os.getenv("REVIEW_ACCOUNT_ID", "")
    expected_pw = os.getenv("REVIEW_ACCOUNT_PASSWORD", "")

    # 환경변수가 비어 있으면 어떤 입력으로도 통과하지 못한다.
    # (빈 문자열끼리 비교해 통과하는 사고 방지)
    #
    # compare_digest로 비교하는 이유: 앞자리부터 순차 비교하는 == 는 응답 시간에
    # 일치 길이가 드러나 비밀번호를 한 글자씩 추측할 여지를 준다.
    # ★ bytes로 비교한다. compare_digest에 비ASCII 문자열을 넣으면 TypeError가 나고,
    # 전역 예외 핸들러를 타 500 + 예외 메시지 노출로 이어진다(한글 아이디로 재현됨).
    id_ok = bool(expected_id) and hmac.compare_digest(
        body.user_id.encode("utf-8"), expected_id.encode("utf-8")
    )
    pw_ok = bool(expected_pw) and hmac.compare_digest(
        body.password.encode("utf-8"), expected_pw.encode("utf-8")
    )
    if not (id_ok and pw_ok):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="아이디 또는 비밀번호가 올바르지 않습니다.",
        )

    # 지연 import: Firebase 미설정 환경에서도 모듈 로드가 가능해야 한다
    from services.auth import create_custom_token

    token = create_custom_token(REVIEW_UID)
    if token is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="인증 서버가 준비되지 않았습니다.",
        )
    return LocalLoginResponse(custom_token=token)
