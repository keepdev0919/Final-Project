"""KTO 사진 주소를 **https 로 올려서** 내보낸다.

## 왜 필요한가

KTO OpenAPI 는 사진 주소를 `http://tong.visitkorea.or.kr/...` 로 준다. iOS 는 평문
HTTP 를 기본으로 막는다(App Transport Security). 우리 `Info.plist` 는
`NSAllowsLocalNetworking` 만 열어 뒀으므로 이 주소는 **앱에서 조용히 실패한다** —
에러도 없고, 사진 자리에 대체 그림만 뜬다.

같은 주소를 `https://` 로 부르면 200 이 온다. 그래서 호스트는 그대로 두고
스킴만 올린다.

2026-09-09 에 코스 카드 사진을 붙이다 발견했는데, **이미 있던 화면들도 같은 이유로
사진이 빠져 있었다** — 지도 탭 준비 중 카드 썸네일 69개 중 42개, 장소 상세 사진
197개 전부가 `http` 였다. 그래서 고치는 자리를 한 곳으로 모았다.

## 왜 DB 를 고치지 않나

캐시에 든 값을 일괄로 바꿔도 다음 KTO 응답이 다시 `http` 로 들어온다. 들어오는 값을
믿지 말고 **나갈 때 고치는** 편이 한 번만 맞으면 계속 맞다.
"""
from urllib.parse import urlsplit

# KTO 사진 호스트. 다른 호스트의 http 를 함부로 올리면 https 를 지원하지 않는 곳이
# 통째로 죽는다 — 아는 호스트만 올린다.
_HTTPS_OK_HOSTS = ("visitkorea.or.kr",)


def to_https(url: str | None) -> str | None:
    """KTO 사진 주소면 https 로 올린다. 그 밖에는 손대지 않는다."""
    if not url or not url.startswith("http://"):
        return url
    host = urlsplit(url).hostname or ""
    if any(host == h or host.endswith("." + h) for h in _HTTPS_OK_HOSTS):
        return "https://" + url[len("http://"):]
    return url


def all_to_https(urls: list[str] | None) -> list[str]:
    """사진 목록 전체에 적용한다."""
    if not urls:
        return []
    return [to_https(u) or u for u in urls]
