"""OpenAI TTS 래핑."""
import os
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse
from slowapi import Limiter
from slowapi.util import get_remote_address
from openai import OpenAI

from models.schemas import TTSRequest

router = APIRouter(prefix="/tts", tags=["tts"])
limiter = Limiter(key_func=get_remote_address)
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


@router.post("")
@limiter.limit("20/minute")
def generate_tts(request: Request, body: TTSRequest):
    if not body.text.strip():
        raise HTTPException(status_code=400, detail="text is empty")

    response = client.audio.speech.create(
        model="tts-1",
        voice="nova",
        input=body.text[:4096],
    )

    def stream():
        yield from response.iter_bytes(chunk_size=4096)

    return StreamingResponse(stream(), media_type="audio/mpeg")
