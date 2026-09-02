"""홈 화면용 엔드포인트.

- `GET /home/places` — 순위 목록 전체. 지도·검색이 쓴다. 홈은 쓰지 않는다
- `GET /home/recommendations` — 추천 코스 3선. 코스 탭으로 들어가는 곁길
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
from services import home_places
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


@router.get("/places")
@limiter.limit("30/minute")
def get_home_places(request: Request, limit: int = 10) -> dict[str, Any]:
    """순위 목록. 지도 탭이 전부 받아 핀을 찍는다.

    `limit`은 1~200으로 묶는다. 지도는 **전부**(현재 103곳) 받아야 한다 —
    「우리가 가진 게 몇 개인지 한눈에」가 지도 탭의 목적이라 일부만 내려보내면 목적이 깨진다.
    상한을 200으로 둔 것은 오디 목록이 늘어도 견디게 하려는 것이고, 무한은 아니다.
    """
    limit = max(1, min(limit, 200))
    try:
        places = home_places.top(limit)
    except Exception as exc:  # noqa: BLE001
        logger.exception("home.places failed")
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}")
    return {"places": places}


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
        # ⚠️ iOS `Course`가 비옵셔널로 요구하는 필드다. 빠지면 Swift의 합성 Codable이
        # 디코딩 전체를 실패시키고, 호출부의 `try?`가 예외를 삼켜 목록이 조용히 빈다.
        # 계산식은 /course/detail과 맞춘다. tests/test_folklore_removed.py 참조.
        c_dict["estimated_minutes"] = len(places) * 60
        c_dict["source_course_id"] = c_dict.get("id", "")
        out.append(c_dict)

    return {"courses": out}
