"""코스 추천 엔드포인트."""
import uuid
import traceback
import logging
from fastapi import APIRouter, Request, HTTPException
from slowapi import Limiter
from slowapi.util import get_remote_address

logger = logging.getLogger(__name__)

from models.schemas import CourseListRequest, CourseDetailRequest, CourseListItem, Course, CoursePlace, Pin
from agents.course_list_agent import course_list_graph
from agents.course_detail_agent import run_detail_agent

router = APIRouter(prefix="/course", tags=["course"])
limiter = Limiter(key_func=get_remote_address)


@router.post("/list", response_model=list[CourseListItem])
@limiter.limit("10/minute")
def list_courses(request: Request, body: CourseListRequest):
    state = course_list_graph.invoke({
        "messages": [],
        "region": body.region,
        "category_scores": body.category_scores,
        "duration_days": body.duration_days,
        "result_courses": [],
        "error": "",
    })

    if state.get("error"):
        raise HTTPException(status_code=500, detail=state["error"])

    courses = state.get("result_courses", [])[:3]
    if not courses:
        raise HTTPException(status_code=404, detail="조건에 맞는 코스를 찾지 못했습니다.")

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
            places=places,
        ))

    return result


@router.post("/detail", response_model=Course)
@limiter.limit("10/minute")
def detail_course(request: Request, body: CourseDetailRequest):
    try:
        result = run_detail_agent(course_id=body.course_id, category_scores=body.category_scores)

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

            folklore_pins = []
            for f in p.get("folklore_pins", []):
                # NULL lat/lng 핀 제외 (course_detail_agent에서도 거르지만 이중 방어)
                f_lat = f.get("lat")
                f_lng = f.get("lng")
                if f_lat is None or f_lng is None:
                    logger.warning(
                        "[DETAIL] folklore pin skipped due to NULL coords: code_no=%s title=%s",
                        f.get("code_no"), f.get("title"),
                    )
                    continue
                folklore_pins.append(Pin(
                    code_no=f.get("code_no", ""),
                    title=f.get("title", ""),
                    source_type=f.get("source_type", "legend"),
                    summary=f.get("summary", ""),
                    lat=f_lat,
                    lng=f_lng,
                    primary_place=p["place_name"],
                    distance_m=f.get("distance_m"),
                ))

            places.append(CoursePlace(
                name=p["place_name"],
                lat=p["lat"],
                lng=p["lng"],
                day=p["day"],
                folklore_pins=folklore_pins,
            ))

        return Course(
            id=str(uuid.uuid4()),
            title=result["title"],
            duration_days=result["duration_days"],
            places=places,
            estimated_minutes=len(places) * 60,
            source_course_id=body.course_id,
            narrative=result.get("narrative", ""),
        )
    except HTTPException:
        raise
    except Exception as exc:
        print(f"[DETAIL 500] course_id={body.course_id} | {type(exc).__name__}: {exc}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}")
