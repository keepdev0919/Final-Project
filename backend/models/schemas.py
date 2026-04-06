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


class CourseRequest(BaseModel):
    theme: str                # 신화 | 도깨비 | 사랑과이별 | 바다해녀 | 오름자연
    duration_days: int        # 1~5
    transport: str = "car"    # car | walk


class CoursePlace(BaseModel):
    name: str
    lat: float
    lng: float
    day: int
    start_time: Optional[str] = None
    folklore_pins: list[Pin] = []


class Course(BaseModel):
    id: str
    title: str
    duration_days: int
    places: list[CoursePlace]
    estimated_minutes: int


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
    pin_id: str
