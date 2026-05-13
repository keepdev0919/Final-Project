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
    category_scores: dict[str, int]      # 카테고리별 취향 점수
    duration_days: int                   # 1~5


class CourseDetailRequest(BaseModel):
    course_id: str
    category_scores: dict[str, int]      # 카테고리별 취향 점수


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


class ChatMessage(BaseModel):
    role: str       # user | assistant
    content: str
    sources: list[str] = []


class ChatRequest(BaseModel):
    message: str
    history: list[ChatMessage] = []
    course_id: Optional[str] = None


class TTSRequest(BaseModel):
    text: str
    pin_id: Optional[str] = None
    voice: str = "nova"
