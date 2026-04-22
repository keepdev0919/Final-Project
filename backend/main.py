from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from routers import pins, chat, course, tts, tourist, place

limiter = Limiter(key_func=get_remote_address)

app = FastAPI(title="제주 설화 탐험 API", version="0.1.0")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(pins.router)
app.include_router(chat.router)
app.include_router(course.router)
app.include_router(tts.router)
app.include_router(tourist.router)
app.include_router(place.router)


@app.get("/health")
def health():
    return {"status": "ok"}
