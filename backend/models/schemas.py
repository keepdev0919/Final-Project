from pydantic import BaseModel
from typing import Optional


class CourseListRequest(BaseModel):
    region: str                          # 동부 | 서부 | 남부 | 북부 | 전체
    duration_days: int                   # 1~5


class CourseDetailRequest(BaseModel):
    course_id: str


class CoursePlace(BaseModel):
    name: str
    lat: float
    lng: float
    day: int
    start_time: Optional[str] = None


class CourseListItem(BaseModel):
    id: str
    title: str
    duration_days: int
    places: list[CoursePlace]


class Course(BaseModel):
    id: str
    title: str
    duration_days: int
    places: list[CoursePlace]
    estimated_minutes: int
    source_course_id: str = ""


VALID_REVIEW_TAGS = {"소름 돋아요", "감동이에요", "신기해요", "무서워요", "역사적이에요"}


class PlaceReviewRequest(BaseModel):
    place_name: str
    tags: list[str]
    note: str | None = None
    device_id: str


class PlaceReviewsResponse(BaseModel):
    total: int
    tag_counts: dict[str, int]
    recent_notes: list[str]


