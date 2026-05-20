"""홈 화면용 엔드포인트 — 오늘의 설화 + 추천 코스 3선."""
from __future__ import annotations

import json as _json
import logging
import random
import re
from datetime import date
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

# "C_M_022 동복본향당본풀이" 같은 접두사 제거용
_CODE_PREFIX_RE = re.compile(r"^[CTW]_[A-Z]_\d+\s+")

# 추천 코스 호출 시 사용할 기본 카테고리 가중치
_DEFAULT_CATEGORY_SCORES: dict[str, int] = {
    "마을 공동체 전승": 1,
    "무속신화·신격 전승": 1,
    "해양·어촌 전승": 1,
    "생활민담·교훈담": 1,
    "초자연 존재담": 1,
}


def _strip_code_prefix(title: str) -> str:
    if not title:
        return ""
    return _CODE_PREFIX_RE.sub("", title).strip()


def _candidate_pins(conn) -> list[dict[str, Any]]:
    """오늘의 설화 후보 풀.

    1차: hook 컬럼이 존재하고 NOT NULL인 핀만.
    2차(fallback): hook 컬럼이 없거나 비어 있으면 hook=NULL 허용한 채 GPS+장소 보유 핀 전체.
    """
    base_sql = (
        "SELECT code_no, title, primary_place, lat, lng, summary FROM metadata "
        "WHERE primary_place IS NOT NULL AND lat IS NOT NULL AND lng IS NOT NULL"
    )

    # hook 컬럼이 추가되었는지 PRAGMA로 확인
    cols = {row[1] for row in conn.execute("PRAGMA table_info(metadata)").fetchall()}
    has_hook = "hook" in cols

    if has_hook:
        try:
            rows = conn.execute(
                "SELECT code_no, title, primary_place, lat, lng, summary, hook "
                "FROM metadata "
                "WHERE primary_place IS NOT NULL AND lat IS NOT NULL AND lng IS NOT NULL "
                "AND hook IS NOT NULL AND TRIM(hook) != ''"
            ).fetchall()
            if rows:
                return [dict(r) for r in rows]
        except Exception as exc:
            logger.warning("home.today hook query failed, falling back: %s", exc)

    # Fallback: hook 없이도 선택 가능
    rows = conn.execute(base_sql).fetchall()
    return [{**dict(r), "hook": None} for r in rows]


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


@router.get("/today")
@limiter.limit("30/minute")
def get_today_folklore(request: Request) -> dict[str, Any]:
    """오늘 날짜 시드 기반 결정적 선택 — 같은 날 누가 호출해도 동일 결과."""
    conn = get_db_connection()
    candidates = _candidate_pins(conn)
    if not candidates:
        raise HTTPException(status_code=404, detail="오늘의 설화 후보가 없습니다.")

    today_str = date.today().isoformat()  # 'YYYY-MM-DD'
    rng = random.Random(today_str)
    # 결정적 정렬 후 선택 — DB row 순서가 바뀌어도 동일 시드로 동일 결과
    candidates.sort(key=lambda r: r["code_no"])
    pick = rng.choice(candidates)

    hook_val = pick.get("hook")
    hero = _hero_image_for_place(conn, pick.get("primary_place") or "")

    return {
        "code_no": pick["code_no"],
        "title": _strip_code_prefix(pick.get("title") or ""),
        "hook": hook_val if hook_val else None,
        "hero_image": hero,
        "primary_place": pick.get("primary_place") or "",
        "lat": float(pick["lat"]),
        "lng": float(pick["lng"]),
    }


@router.get("/recommendations")
@limiter.limit("30/minute")
def get_recommendations(request: Request) -> dict[str, Any]:
    """기본 가중치로 /course/list 재사용 — iOS는 동일 CourseListItem 모델로 디코드 가능."""
    body = CourseListRequest(
        region="전체",
        category_scores=_DEFAULT_CATEGORY_SCORES,
        duration_days=2,
    )

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
