from pydantic import BaseModel
from typing import Optional


class CourseListRequest(BaseModel):
    region: str                          # 동부 | 서부 | 남부 | 북부 | 전체
    duration_days: int                   # 1~4 (4 = 「3박4일 이상」, 4~7일 코스)


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
    # 동부 | 서부 | 남부 | 북부 | 전체. 코스 장소가 한 권역에 과반으로 몰리지
    # 않으면 "전체"다 (`build_curated_courses.py`). 앱이 권역색 배지에 쓴다.
    region: str = "전체"
    # 대표 장소(제목에 뜨는 그 장소)의 KTO 대표사진. 캐시에 없으면 None —
    # 앱은 그때 권역색 픽셀 블록을 깐다.
    thumbnail: str | None = None
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


