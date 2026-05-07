import traceback
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from routers import pins, chat, course, tts, tourist, place, travel

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
app.include_router(travel.router)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    tb = traceback.format_exc()
    print(f"[GLOBAL 500] {request.method} {request.url.path}")
    print(f"  {type(exc).__name__}: {exc}")
    print(tb)
    return JSONResponse(status_code=500, content={"detail": f"{type(exc).__name__}: {exc}"})


@app.get("/health")
def health():
    return {"status": "ok"}
