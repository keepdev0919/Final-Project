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


class TTSRequest(BaseModel):
    text: str
    pin_id: Optional[str] = None
    voice: str = "nova"


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


class JourneySummary(BaseModel):
    """여정 = 장소 1개 상품. 이야기 본문은 묶음 B에서 별도 스키마로 붙인다.

    값의 근거는 tests/test_journey.py의 docstring에 있다.
    """
    journey_id: str
    title: str
    subtitle: str = ""
    theme: str = ""
    story_count: int
    free_story_count: int
    total_minutes: int
    price_krw: int
    valid_days: int = 90
    cover_image: Optional[str] = None
    kto_content_id: str
    lat: float
    lng: float
