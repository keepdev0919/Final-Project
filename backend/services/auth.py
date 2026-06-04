"""Firebase ID Token 검증.

키 파일(`FIREBASE_CREDENTIALS_PATH`)이 없거나 `firebase_admin` import 실패 시에도
앱이 가동되도록 안전하게 fallback 한다. 이 경우 모든 토큰은 None으로 검증된다.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Optional

from fastapi import Header, HTTPException, status

# services/db.py가 모듈 import 시점에 .env를 로드하므로,
# 동일하게 환경변수를 가져오기 위해 명시적으로 _load_env를 호출한다.
try:  # 순환 import 방지: db 모듈은 부수 효과로 .env를 로드함
    from services import db as _db  # noqa: F401  (side effect: load env)
except Exception:  # pragma: no cover - import 실패해도 인증은 동작해야 함
    pass


# ─────────────────────────────────────────────────────────────────────────────
# firebase_admin 초기화 (idempotent, 안전한 fallback)
# ─────────────────────────────────────────────────────────────────────────────
_firebase_ready: bool = False
_firebase_auth = None  # firebase_admin.auth 모듈 핸들 (사용 가능 시)


def _init_firebase() -> None:
    """모듈 import 시 한 번 호출. 어떤 에러도 raise하지 않는다."""
    global _firebase_ready, _firebase_auth

    cred_path_str = os.environ.get("FIREBASE_CREDENTIALS_PATH", "").strip()
    if not cred_path_str:
        print("[auth] FIREBASE_CREDENTIALS_PATH 미설정 → 인증 미작동 (앱은 가동)")
        return

    cred_path = Path(cred_path_str)
    if not cred_path.is_absolute():
        # backend/ 또는 그 상위(졸프/)에서 실행되는 두 경우 모두 대응
        backend_dir = Path(__file__).parent.parent
        candidates = [
            Path.cwd() / cred_path,
            backend_dir / cred_path,
            backend_dir.parent / cred_path,
        ]
        for c in candidates:
            if c.exists():
                cred_path = c
                break

    if not cred_path.exists():
        print(f"[auth] Firebase 키 파일 없음: {cred_path} → 인증 미작동 (앱은 가동)")
        return

    try:
        import firebase_admin
        from firebase_admin import auth as fb_auth, credentials as fb_credentials
    except Exception as e:  # ImportError 등
        print(f"[auth] firebase_admin import 실패: {e} → 인증 미작동")
        return

    try:
        if not firebase_admin._apps:
            cred = fb_credentials.Certificate(str(cred_path))
            firebase_admin.initialize_app(cred)
        _firebase_auth = fb_auth
        _firebase_ready = True
        print(f"[auth] Firebase Admin 초기화 완료 ({cred_path.name})")
    except Exception as e:
        print(f"[auth] Firebase Admin 초기화 실패: {e} → 인증 미작동")


_init_firebase()


# ─────────────────────────────────────────────────────────────────────────────
# FastAPI 의존성
# ─────────────────────────────────────────────────────────────────────────────
async def get_current_user_optional(
    authorization: Optional[str] = Header(default=None),
) -> Optional[dict]:
    """Authorization 헤더에서 Firebase ID Token을 검증.

    - 헤더 없음 / "Bearer " 접두사 없음 → None
    - 검증 실패 → None (예외 발생 X)
    - 성공 → 디코딩된 dict (uid, email, name 등)
    """
    if not authorization:
        return None

    parts = authorization.split(" ", 1)
    if len(parts) != 2 or parts[0].lower() != "bearer":
        return None
    token = parts[1].strip()
    if not token:
        return None

    if not _firebase_ready or _firebase_auth is None:
        return None

    try:
        decoded = _firebase_auth.verify_id_token(token)
        if not isinstance(decoded, dict):
            return None
        return decoded
    except Exception as e:
        # 만료/위변조/네트워크 등 모든 실패를 None으로
        print(f"[auth] verify_id_token 실패: {type(e).__name__}: {e}")
        return None


async def require_user(
    authorization: Optional[str] = Header(default=None),
) -> dict:
    """인증 필수 엔드포인트용. 실패 시 401."""
    user = await get_current_user_optional(authorization=authorization)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="유효한 Firebase ID Token이 필요합니다.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user
