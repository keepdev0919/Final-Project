"""계정 삭제.

애플은 **로그인 기능이 있는 앱에 앱 내 계정 삭제 경로를 요구**한다. 없으면 앱스토어
심사에서 거절된다. 계정을 만들 수 있게 해놓고 지울 수 없게 두면 안 된다는 취지다.

## 역할 분담

이 엔드포인트는 **서버가 들고 있는 데이터만** 지운다.

| 무엇 | 어디서 지우나 |
|---|---|
| 장소 리뷰 (`place_reviews`) | 여기 (서버 SQLite) — uid + 기기 식별자 둘 다 |
| 저장한 코스 (`users/{uid}/savedCourses`) | 클라이언트 (Firestore SDK) |
| Firebase 사용자 레코드 | 클라이언트 (`Auth.auth().currentUser?.delete()`) |

Firestore와 Auth 레코드를 클라이언트가 지우는 이유: 이미 그쪽에서 쓰기 권한을 갖고
있어 서버가 Admin SDK로 중복 처리할 필요가 없다. 순서는 **서버 → Firestore → Auth**다
(Auth를 먼저 지우면 나머지를 지울 권한이 사라진다).
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address

from services.auth import require_user
from services.db import get_db_connection

router = APIRouter(prefix="/account", tags=["account"])
limiter = Limiter(key_func=get_remote_address)


class DeleteAccountRequest(BaseModel):
    """기기 식별자를 함께 받는다 (선택).

    ★ 로그인 전에 남긴 리뷰는 `user_id`가 비어 있고 `device_id`만 있다. uid로만
    지우면 그 리뷰가 서버에 남아, 처리방침의 "계정 삭제 시 데이터가 지워진다"가
    거짓이 된다. 그래서 기기 식별자도 함께 받아 지운다.

    `device_id`는 앱이 만든 UUID이며 UserDefaults에 저장된다(하드웨어 식별자 아님).
    """
    device_id: str | None = None


@router.delete("")
@limiter.limit("5/minute")
def delete_account(
    request: Request,
    body: DeleteAccountRequest | None = None,
    user: dict = Depends(require_user),
):
    """요청한 사용자가 서버에 남긴 데이터를 지운다.

    되돌릴 수 없다. 클라이언트가 확인 절차를 거친 뒤 호출한다.
    """
    uid = user.get("uid")
    device_id = body.device_id if body else None

    conn = get_db_connection()
    if device_id:
        cur = conn.execute(
            "DELETE FROM place_reviews WHERE user_id = ? OR device_id = ?",
            (uid, device_id),
        )
    else:
        cur = conn.execute("DELETE FROM place_reviews WHERE user_id = ?", (uid,))
    conn.commit()

    return {"deleted": True, "removed_reviews": cur.rowcount}
