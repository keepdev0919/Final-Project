"""화면 코드가 팔레트 밖 색을 쓰지 않는지 감시한다.

## 왜 테스트인가

색이 틀려도 앱은 죽지 않는다. **조용히 안 읽히게만 된다.** 2026-08-20 코드
리뷰에서 잡힌 것들이 전부 이 부류였다:

- 로딩 상자의 글자색과 배경색이 같은 토큰이라 대비 1.00:1 — 글자도 스피너도
  없는 빈 흰 사각형으로 보였다.
- `Color.orange` → `PixelColor.primary` 치환을 돌렸는데 **맨앞 점 축약형**
  (`? .white : .orange`)이 정규식을 빠져나가 주황이 4곳 남았다. 배경 줄만
  초록으로 바뀌고 글자 줄은 주황이라 초록 위 주황 1.89:1이 됐다.
- 어둠막에 `PixelColor.ink`(적응색)를 써서 **다크 모드에서 화면이 하얗게
  뒤집혔다.**

빌드는 통과하고 눌러도 동작한다. 그래서 사람이 화면을 볼 때까지 모른다.
"""
import re
from pathlib import Path

import pytest

VIEWS = Path(__file__).parent.parent / "ios/JejuFolklore/Sources/Views"
ICON = VIEWS / "DesignSystem/PixelIcon.swift"

# 팔레트 밖 색. `Color.orange` 형태와 `.orange` 축약형을 모두 잡는다.
BANNED = ["orange", "pink", "purple", "indigo", "teal", "mint", "brown"]


def _view_sources() -> list[Path]:
    """디자인 시스템 자신은 뺀다 — 거기가 색을 정의하는 자리다."""
    return [p for p in sorted(VIEWS.rglob("*.swift")) if "DesignSystem" not in str(p)]


@pytest.mark.parametrize("name", BANNED)
def test_no_system_hue_outside_palette(name):
    """팔레트에 없는 색조를 화면에서 쓰지 않는다.

    제주 4개 권역 색에 보라·분홍이 들어가 있던 것을 2026-08-20에 뺐다.
    구분이 필요하면 팔레트 안(primary·secondary·tertiary·locked)에서 고른다.
    """
    pat = re.compile(rf"(?:Color|UIColor)?\.(?:system)?{name.capitalize()}\b|\.{name}\b")
    hits = [f"{p.relative_to(VIEWS)}" for p in _view_sources() if pat.search(p.read_text(encoding="utf-8"))]
    assert not hits, f".{name} 를 쓰는 화면: {hits}"


def test_scrim_is_not_adaptive():
    """어둠막(scrim)에 적응색을 쓰지 않는다.

    `PixelColor.ink`는 다크 모드에서 거의 흰색(#F0EFFF)이 된다. 어둠막에 쓰면
    다크 모드에서 화면이 **하얗게 뒤집힌다.** 어둠막은 모드와 무관해야 하므로
    `Color.black.opacity(...)`를 쓴다.
    """
    hits = []
    for p in _view_sources():
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(r"PixelColor\.ink\.opacity\(", line):
                hits.append(f"{p.relative_to(VIEWS)}:{i}")
    assert not hits, f"어둠막에 적응색을 쓴 곳: {hits}"


def test_pixel_icon_inherits_ambient_color():
    """아이콘은 색을 안 주면 바깥의 `.foregroundColor`를 따라야 한다.

    2026-09-03 에 8×8 `Canvas` 를 걷어내고 Material Icons 글리프로 바꿨지만
    지켜야 할 규칙은 같다. 기본값을 잉크로 **고정하면** 바깥에서 준
    `.foregroundColor(...)`가 **조용히 무시된다.** 2026-08-20 리뷰에서 이 때문에
    19곳이 틀린 색으로 그려지고 있었다 — 도착 화면의 72pt 핀이 검은 어둠막에
    묻혀 1.39:1로 안 보이고, 방문 완료 체크가 초록이 아니라 검정으로 나왔다.

    그래서 ① 기본값은 nil이고 ② nil이면 `.style(.foreground)`로 그린다.
    """
    src = ICON.read_text(encoding="utf-8")
    assert re.search(r"var color: Color\?", src), \
        "color가 옵셔널이 아니다 — 기본색을 고정하면 바깥 지정이 무시된다"
    assert re.search(r"color:\s*Color\?\s*=\s*nil", src), \
        "init의 color 기본값이 nil이 아니다"
    assert "AnyShapeStyle(.foreground)" in src, \
        "nil일 때 환경의 foregroundStyle을 읽지 않는다"


def test_pixel_icon_size_is_not_set_by_font():
    """도트 아이콘 크기를 `.font(...)`로 정하려 한 자리가 없어야 한다.

    비트맵이라 `.font()`·`.resizable()`이 안 먹는다. 기본 24pt로 그려져
    12pt 글자 옆에서 튄다. 크기는 `size:`로 정한다.
    """
    hits = []
    for p in _view_sources():
        text = p.read_text(encoding="utf-8")
        # PixelIcon(...) 뒤에 (모디파이어를 건너) .font(가 붙은 것
        for m in re.finditer(r"PixelIcon\([^)]*\)((?:\s*\.\w+\([^()]*\))*)", text):
            if ".font(" in m.group(1):
                line = text[:m.start()].count("\n") + 1
                hits.append(f"{p.relative_to(VIEWS)}:{line}")
    assert not hits, f"도트 아이콘에 .font로 크기를 주려 한 곳: {hits}"
