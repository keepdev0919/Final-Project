"""시간순으로 정렬되는 uuid7 — 서버에서도 돌도록 직접 만든다 (2026-09-15).

`uuid.uuid7()` 은 파이썬 3.14 에 들어왔다. 개발 맥은 3.14 라 잘 돌지만 배포 이미지는
3.12 다(Dockerfile 참조). 그대로 부르면 서버에서만 AttributeError 가 난다 — 미션 신고가
출시(2026-09-11)부터 서버에 한 번도 저장되지 않은 이유가 이것이었다. 로컬 테스트는
3.14 에서 돌아서 아무도 몰랐다.

그래서 서버 코드는 `uuid.uuid7()` 대신 이걸 부른다. 형식은 RFC 9562 uuid7 과 같다.
"""
import os
import time
import uuid


def uuid7() -> str:
    ms = time.time_ns() // 1_000_000
    value = (ms & ((1 << 48) - 1)) << 80 | int.from_bytes(os.urandom(10), "big")
    value = (value & ~(0xF << 76)) | (0x7 << 76)   # version 7
    value = (value & ~(0x3 << 62)) | (0x2 << 62)   # RFC 9562 variant
    return str(uuid.UUID(int=value))
