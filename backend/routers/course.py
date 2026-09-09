"""코스 추천 엔드포인트."""
import uuid
import traceback
import logging
from fastapi import APIRouter, Request, HTTPException
from slowapi import Limiter
from slowapi.util import get_remote_address

logger = logging.getLogger(__name__)

from models.schemas import CourseListRequest, CourseDetailRequest, CourseListItem, Course, CoursePlace
from agents.course_list_agent import course_list_graph, run_featured_courses
from agents.course_detail_agent import run_detail_agent
from services.course_thumbnail import attach_thumbnails
from services.db import get_db_connection

router = APIRouter(prefix="/course", tags=["course"])
limiter = Limiter(key_func=get_remote_address)


@router.post("/list", response_model=list[CourseListItem])
@limiter.limit("10/minute")
def list_courses(request: Request, body: CourseListRequest):
    state = course_list_graph.invoke({
        "messages": [],
        "region": body.region,
        "duration_days": body.duration_days,
        "result_courses": [],
        "error": "",
    })

    if state.get("error"):
        raise HTTPException(status_code=500, detail=state["error"])

    courses = state.get("result_courses", [])[:3]
    if not courses:
        raise HTTPException(status_code=404, detail="조건에 맞는 코스를 찾지 못했습니다.")

    attach_thumbnails(get_db_connection(), courses)

    result = []
    for c in courses:
        places = [
            CoursePlace(
                name=p["place_name"],
                lat=p["lat"],
                lng=p["lng"],
                day=p["day"],
            )
            for p in c.get("places", [])
        ]
        result.append(CourseListItem(
            id=c["id"],
            title=c["title"],
            duration_days=c["duration_days"],
            region=c.get("region", "전체"),
            thumbnail=c.get("thumbnail"),
            places=places,
        ))

    return result


@router.get("/featured", response_model=list[CourseListItem])
@limiter.limit("30/minute")
def featured_courses(request: Request, limit: int = 5):
    """코스 탭 첫 화면에서 그냥 둘러보라고 깔아 두는 목록.

    권역·기간을 묻지 않는다. 부를 때마다 다른 코스가 나오므로 새로고침이 곧 갱신이다
    (그래서 `/list` 보다 호출 제한이 넉넉하다).
    """
    limit = max(1, min(limit, 10))
    result = run_featured_courses(limit=limit)

    if result.get("error"):
        raise HTTPException(status_code=404, detail=result["error"])

    featured = result.get("result_courses", [])
    attach_thumbnails(get_db_connection(), featured)

    return [
        CourseListItem(
            id=c["id"],
            title=c["title"],
            duration_days=c["duration_days"],
            region=c.get("region", "전체"),
            thumbnail=c.get("thumbnail"),
            places=[
                CoursePlace(name=p["place_name"], lat=p["lat"], lng=p["lng"], day=p["day"])
                for p in c.get("places", [])
            ],
        )
        for c in featured
    ]


@router.post("/detail", response_model=Course)
@limiter.limit("10/minute")
def detail_course(request: Request, body: CourseDetailRequest):
    try:
        result = run_detail_agent(course_id=body.course_id)

        if result.get("error"):
            status = 404 if "찾을 수 없습니다" in result["error"] else 500
            raise HTTPException(status_code=status, detail=result["error"])

        places = []
        for p in result.get("places", []):
            # 장소 자체에 lat/lng가 없으면 스킵 (Pydantic 검증 실패 방지)
            if p.get("lat") is None or p.get("lng") is None:
                logger.warning(
                    "[DETAIL] place skipped due to NULL coords: name=%s day=%s",
                    p.get("place_name"), p.get("day"),
                )
                continue

            places.append(CoursePlace(
                name=p["place_name"],
                lat=p["lat"],
                lng=p["lng"],
                day=p["day"],
            ))

        return Course(
            id=str(uuid.uuid4()),
            title=result["title"],
            duration_days=result["duration_days"],
            places=places,
            estimated_minutes=len(places) * 60,
            source_course_id=body.course_id,
        )
    except HTTPException:
        raise
    except Exception as exc:
        print(f"[DETAIL 500] course_id={body.course_id} | {type(exc).__name__}: {exc}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}")
