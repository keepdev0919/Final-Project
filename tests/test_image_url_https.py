"""KTO 사진 주소가 **https 로 나가는지** 못 박는다.

## 왜 테스트인가

`http://` 로 나가면 iOS 가 App Transport Security 로 막는다. 그런데 **아무 에러도
안 난다** — 앱은 멀쩡히 돌고 사진 자리에 대체 그림만 뜬다. 그래서 사람이 화면을
들여다보기 전까지 아무도 모른다.

실제로 2026-09-09 에 그 상태였다: 지도 탭 준비 중 카드 42개, 장소 상세 사진 197개
전부가 http 였고, 코스 카드 사진을 새로 붙이다가 「왜 하나도 안 뜨지」에서 발견했다.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "backend"))

from services.image_url import all_to_https, to_https  # noqa: E402


def test_kto_photo_is_upgraded():
    assert to_https("http://tong.visitkorea.or.kr/cms/resource/84/3546884_image2_1.jpg") \
        == "https://tong.visitkorea.or.kr/cms/resource/84/3546884_image2_1.jpg"


def test_already_https_is_left_alone():
    u = "https://tong.visitkorea.or.kr/a.jpg"
    assert to_https(u) == u


def test_other_hosts_are_left_alone():
    """모르는 호스트를 https 로 올리면 그 호스트가 https 를 지원하지 않을 때
    사진이 통째로 죽는다. 아는 호스트만 올린다."""
    u = "http://example.com/a.jpg"
    assert to_https(u) == u


def test_lookalike_host_is_not_upgraded():
    """`visitkorea.or.kr.evil.com` 같은 주소를 KTO 로 착각하면 안 된다."""
    u = "http://visitkorea.or.kr.evil.com/a.jpg"
    assert to_https(u) == u


def test_empty_and_none_survive():
    assert to_https(None) is None
    assert to_https("") == ""
    assert all_to_https(None) == []


def test_list_form():
    assert all_to_https(["http://tong.visitkorea.or.kr/a.jpg", "https://tong.visitkorea.or.kr/b.jpg"]) \
        == ["https://tong.visitkorea.or.kr/a.jpg", "https://tong.visitkorea.or.kr/b.jpg"]
