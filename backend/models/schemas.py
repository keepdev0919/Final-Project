from pydantic import BaseModel
from typing import Optional


class Pin(BaseModel):
    code_no: str
    title: str
    source_type: str          # legend | folktale
    summary: str
    lat: float
    lng: float
    primary_place: str
    distance_m: Optional[float] = None
    hook: Optional[str] = None   # 30~50자 후크 (LLM 생성, 캐시됨)


class PinConnectionResponse(BaseModel):
    code_no: str
    place: str
    connection: str


class StoryPage(BaseModel):
    title: str
    body: str


class PinStoryResponse(BaseModel):
    code_no: str
    place: str
    pages: list[StoryPage]


class PinDetail(BaseModel):
    code_no: str
    title: str
    source_type: str
    summary: str
    full_text: str            # 내용 섹션 원문
    primary_place: str
    lat: float
    lng: float


class CourseListRequest(BaseModel):
    region: str                          # 동부 | 서부 | 남부 | 북부 | 전체
    duration_days: int                   # 1~5
    # ⚠️ 설화 취향 점수. 2026-08-13에 코스 추천에서 설화를 분리해 **무시된다.**
    # 선택 필드로 남긴 이유: 이미 배포된 클라이언트가 보내도 422로 막히지 않게.
    # 단계 1의 설화 전면 제거 때 삭제한다.
    category_scores: dict[str, int] = {}


class CourseDetailRequest(BaseModel):
    course_id: str
    category_scores: dict[str, int] = {}  # 위와 동일 — 무시된다


class CoursePlace(BaseModel):
    name: str
    lat: float
    lng: float
    day: int
    start_time: Optional[str] = None
    folklore_pins: list[Pin] = []


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
    narrative: str = ""


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


class JournalResponse(BaseModel):
    journal_text: str
    image_url: Optional[str] = None  # 이미지 생성 실패 시 None
