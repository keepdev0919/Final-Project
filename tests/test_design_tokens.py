"""픽셀 팔레트의 명도 대비를 못 박는다.

색은 틀려도 앱이 죽지 않는다. 조용히 안 읽히게만 된다. 그래서 테스트로 잡는다.

기준값의 근거:
- 본문·보조 텍스트: WCAG AA 4.5:1.
- 배지 글자: 배지는 Galmuri9를 18pt로 쓰는 굵은 픽셀 글자라 WCAG의
  large text(18pt 이상) 기준 3:1을 적용한다.
- 실측(2026-08-14)에서 다크 모드 "앞부분 무료" 배지가 1.26:1로 나왔다
  (강조 #FFC759 배경 + 잉크 #EDE7DC 글자). 밝은 배지 배경 위 글자는
  모드와 무관하게 항상 어두운 #1E1B18로 고정해 해결했다.
  이 값을 "다크에서도 잉크색"으로 되돌리면 글자가 사라진다.
"""
import re
from pathlib import Path

import pytest

PALETTE_SWIFT = (
    Path(__file__).parent.parent
    / "ios/JejuFolklore/Sources/Views/DesignSystem/PixelColor.swift"
)

BODY_MIN = 4.5   # WCAG AA 본문
BADGE_MIN = 3.0  # WCAG AA large text (배지는 18pt 픽셀 글자)


def _relative_luminance(hex_value: int) -> float:
    def channel(c: int) -> float:
        s = c / 255
        return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4

    r, g, b = (hex_value >> 16) & 0xFF, (hex_value >> 8) & 0xFF, hex_value & 0xFF
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a: int, b: int) -> float:
    la, lb = _relative_luminance(a), _relative_luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def _parse_palette() -> tuple[dict[str, int], dict[str, int]]:
    """PixelColor.swift에서 `adaptive(light: 0xRRGGBB, dark: 0xRRGGBB)` 를 읽는다.

    문서(DESIGN.md)가 아니라 코드를 읽는다. 실제로 화면에 나가는 값이 코드이기 때문이다.
    """
    source = PALETTE_SWIFT.read_text(encoding="utf-8")
    pattern = re.compile(
        r"static let (\w+)\s*=\s*adaptive\(light:\s*0x([0-9A-Fa-f]{6}),"
        r"\s*dark:\s*0x([0-9A-Fa-f]{6})\)"
    )
    light: dict[str, int] = {}
    dark: dict[str, int] = {}
    for name, l_hex, d_hex in pattern.findall(source):
        light[name] = int(l_hex, 16)
        dark[name] = int(d_hex, 16)
    assert light, f"{PALETTE_SWIFT} 에서 팔레트를 찾지 못했다"
    return light, dark


def _parse_fixed_dark_ink() -> int:
    source = PALETTE_SWIFT.read_text(encoding="utf-8")
    match = re.search(r"static let inkFixedDark\s*=\s*fixed\(0x([0-9A-Fa-f]{6})\)", source)
    assert match, "inkFixedDark 상수를 찾지 못했다"
    return int(match.group(1), 16)


def test_palette_matches_design_doc():
    """코드의 팔레트가 DESIGN.md §2에 적힌 값과 같아야 한다.

    DESIGN.md가 디자인 SSoT다. 코드만 몰래 바꾸면 문서가 거짓이 된다.
    """
    light, dark = _parse_palette()
    assert light == {
        "background": 0xF4EFE4, "surface": 0xFFFFFF, "ink": 0x1E1B18,
        "inkWeak": 0x6B635A, "primary": 0x1E6F6B, "accent": 0xF2B233,
        "locked": 0xC9503C, "done": 0x4E8C3F,
    }
    assert dark == {
        "background": 0x14181A, "surface": 0x1E2427, "ink": 0xEDE7DC,
        "inkWeak": 0x9A9187, "primary": 0x4FB3AD, "accent": 0xFFC759,
        "locked": 0xE0705A, "done": 0x6FAE5E,
    }


@pytest.mark.parametrize("mode_index", [0, 1], ids=["light", "dark"])
@pytest.mark.parametrize("fg,bg", [("ink", "background"), ("ink", "surface"),
                                   ("inkWeak", "background"), ("inkWeak", "surface")])
def test_text_contrast_meets_aa(mode_index, fg, bg):
    """본문·보조 텍스트는 배경 대비 4.5:1 이상이어야 한다."""
    palette = _parse_palette()[mode_index]
    ratio = contrast(palette[fg], palette[bg])
    assert ratio >= BODY_MIN, f"{fg} on {bg} = {ratio:.2f}:1 (기준 {BODY_MIN})"


@pytest.mark.parametrize("mode_index", [0, 1], ids=["light", "dark"])
@pytest.mark.parametrize("bg", ["accent", "locked", "done"])
def test_light_backed_badges_use_fixed_dark_ink(mode_index, bg):
    """강조·잠김·완료 배지는 항상 어두운 글자를 쓴다.

    다크 모드의 잉크(#EDE7DC)를 밝은 배지 배경에 올리면 1.26:1까지 떨어진다.
    모드와 무관하게 어두운 글자로 고정하면 최악값이 3.83:1(잠김/라이트)이 된다.
    """
    palette = _parse_palette()[mode_index]
    ratio = contrast(_parse_fixed_dark_ink(), palette[bg])
    assert ratio >= BADGE_MIN, f"inkFixedDark on {bg} = {ratio:.2f}:1 (기준 {BADGE_MIN})"


@pytest.mark.parametrize("mode_index", [0, 1], ids=["light", "dark"])
def test_primary_badge_uses_surface_ink(mode_index):
    """'지금 여기예요' 배지만 표면색 글자를 쓴다 — 주색은 어두운 계열이라서다."""
    palette = _parse_palette()[mode_index]
    ratio = contrast(palette["surface"], palette["primary"])
    assert ratio >= BADGE_MIN, f"surface on primary = {ratio:.2f}:1 (기준 {BADGE_MIN})"
