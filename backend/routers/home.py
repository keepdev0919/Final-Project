"""홈 화면용 엔드포인트 — 추천 코스 3선.

'오늘의 설화'는 2026-08-14에 제거했다. 홈 최상단 자리는 성산 여정 카드가 가져갔다
(설계 §1 — 유료 콘텐츠 진입을 코스 추천에 종속시키지 않는다).
"""
from __future__ import annotations

import json as _json
import logging
from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from models.schemas import CourseListRequest
from routers.course import list_courses
from services.db import get_db_connection

router = APIRouter(prefix="/home", tags=["home"])
limiter = Limiter(key_func=get_remote_address)
logger = logging.getLogger(__name__)


def _hero_image_for_place(conn, primary_place: str) -> Optional[str]:
    """place_detail_cache.images JSON에서 첫 이미지 URL을 꺼낸다 (없으면 None)."""
    if not primary_place:
        return None
    try:
        row = conn.execute(
            "SELECT images FROM place_detail_cache WHERE name = ? "
            "AND images IS NOT NULL AND images != '' AND images != '[]' "
            "LIMIT 1",
            (primary_place,),
        ).fetchone()
    except Exception as exc:
        logger.warning("home.today place_detail_cache lookup failed: %s", exc)
        return None
    if not row:
        return None
    try:
        imgs = _json.loads(row["images"] or "[]")
        if isinstance(imgs, list) and imgs:
            first = imgs[0]
            return first if isinstance(first, str) and first else None
    except Exception:
        return None
    return None


@router.get("/recommendations")
@limiter.limit("30/minute")
def get_recommendations(request: Request) -> dict[str, Any]:
    """`/course/list` 재사용 — iOS는 동일 CourseListItem 모델로 디코드 가능."""
    body = CourseListRequest(region="전체", duration_days=2)

    try:
        courses = list_courses(request=request, body=body)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("home.recommendations list_courses failed")
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}")

    conn = get_db_connection()
    out: list[dict[str, Any]] = []
    for c in courses[:3]:
        # CourseListItem(pydantic) → dict
        c_dict = c.model_dump() if hasattr(c, "model_dump") else dict(c)
        preview: Optional[str] = None
        places = c_dict.get("places") or []
        if places:
            first_place = places[0]
            preview = _hero_image_for_place(conn, first_place.get("name") or "")
        c_dict["preview_image"] = preview
        # iOS 모델 호환: course_id 키도 같이 노출
        c_dict["course_id"] = c_dict.get("id", "")
        out.append(c_dict)

    return {"courses": out}
