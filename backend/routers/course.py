"""코스 추천 엔드포인트 (LangGraph 에이전트 연결)."""
import uuid
from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import StreamingResponse
from slowapi import Limiter
from slowapi.util import get_remote_address
import json

from models.schemas import CourseRequest, Course, CoursePlace, Pin
from agents.course_agent import course_graph

router = APIRouter(prefix="/course", tags=["course"])
limiter = Limiter(key_func=get_remote_address)


@router.post("/recommend", response_model=Course)
@limiter.limit("10/minute")
def recommend_course(request: Request, body: CourseRequest):
    state = course_graph.invoke({
        "user_input": f"{body.theme} {body.duration_days}일 {body.transport}",
        "theme": body.theme,
        "duration_days": body.duration_days,
        "transport": body.transport,
        "folklore_results": [],
        "folklore_locations": [],
        "route": [],
        "enriched_route": [],
        "course_title": "",
        "error": "",
    })

    if state.get("error"):
        raise HTTPException(status_code=404, detail=state["error"])

    places = []
    for p in state["enriched_route"]:
        places.append(CoursePlace(
            name=p["place"],
            lat=p["lat"],
            lng=p["lng"],
            day=p.get("day", 1),
            folklore_pins=[
                Pin(
                    code_no=p.get("code_no", ""),
                    title=p.get("title", ""),
                    source_type="legend",
                    summary=p.get("text", "")[:80],
                    lat=p["lat"],
                    lng=p["lng"],
                    primary_place=p["place"],
                )
            ] if p.get("code_no") else [],
        ))

    return Course(
        id=str(uuid.uuid4()),
        title=state["course_title"],
        duration_days=body.duration_days,
        places=places,
        estimated_minutes=len(places) * 60,
    )
