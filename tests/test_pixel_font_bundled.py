"""갈무리 픽셀 폰트가 앱에 실제로 들어가 있는지 확인한다.

폰트 파일이 없거나 Info.plist(UIAppFonts) 등록이 빠지면 **빌드는 성공하고**
런타임에 시스템 폰트로 조용히 폴백된다. 화면은 그럴듯하게 뜨는데 컨셉만
사라진다. 그래서 파일 존재와 등록을 함께 못 박는다.

라이선스: SIL Open Font License 1.1 (https://github.com/quiple/galmuri).
임베딩 가능하며, OFL 원문을 함께 배포해야 하므로 OFL.txt도 확인한다.
"""
import re
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).parent.parent
FONT_DIR = ROOT / "ios/JejuFolklore/Resources/Fonts"
PROJECT_YML = ROOT / "ios/project.yml"
PIXEL_FONT_SWIFT = ROOT / "ios/JejuFolklore/Sources/Views/DesignSystem/PixelFont.swift"

REQUIRED_FONTS = [
    "Galmuri9.ttf", "Galmuri11.ttf", "Galmuri11-Bold.ttf", "Galmuri14.ttf",
    # 시안이 쓰는 아이콘 폰트. 이게 안 실리면 아이콘이 전부 두부(□)가 된다.
    "MaterialIcons-Regular.ttf",
]

# SwiftUI의 `.custom(_:)`은 **파일명이 아니라 PostScript 이름**으로 폰트를 찾는다.
# 갈무리는 파일명이 Galmuri11.ttf인데 PostScript 이름은 Galmuri11-Regular다.
# 여기를 틀리면 예외 없이 시스템 폰트로 폴백되어 화면이 멀쩡해 보인다.
POSTSCRIPT_NAMES = {
    "Galmuri9.ttf": "Galmuri9-Regular",
    "Galmuri11.ttf": "Galmuri11-Regular",
    "Galmuri11-Bold.ttf": "Galmuri11-Bold",
    "Galmuri14.ttf": "Galmuri14-Regular",
}


@pytest.mark.parametrize("filename", REQUIRED_FONTS)
def test_font_file_present(filename):
    """`PixelFont.swift`의 크기 사다리가 이 세 파일을 전제한다."""
    path = FONT_DIR / filename
    assert path.exists(), f"{path} 없음 — 폰트가 빠지면 시스템 폰트로 조용히 폴백된다"
    assert path.stat().st_size > 10_000, f"{path} 가 비어 있다"


def test_ofl_license_bundled():
    """OFL 1.1은 폰트 재배포 시 라이선스 원문 동봉을 요구한다."""
    ofl = FONT_DIR / "OFL.txt"
    assert ofl.exists(), "OFL.txt 없음 — OFL 1.1은 라이선스 원문 동봉을 요구한다"
    assert "SIL OPEN FONT LICENSE" in ofl.read_text(encoding="utf-8").upper()


def test_fonts_registered_in_info_plist():
    """UIAppFonts 등록이 빠지면 파일이 있어도 iOS가 폰트를 못 찾는다.

    ⚠️ **경로가 아니라 파일명을 적는다.**

    2026-09-03 까지 여기에 `Fonts/Galmuri11.ttf` 라고 적혀 있었고, 이 테스트가
    그 값을 통과시키고 있었다. 그런데 xcodegen 은 `Resources/Fonts` 를 그룹으로
    다뤄 파일을 **번들 최상위에 평평하게** 복사한다. 그래서 `Fonts/…` 라는
    하위 경로는 존재하지 않았고, 갈무리는 **한 번도 실린 적이 없었다.**
    빌드는 성공했고 화면도 떴다 — `.custom()` 이 조용히 시스템 폰트로 폴백해서
    아무도 몰랐다. 테스트가 버그를 지켜주고 있었던 셈이다.
    """
    spec = yaml.safe_load(PROJECT_YML.read_text(encoding="utf-8"))
    props = spec["targets"]["JejuFolklore"]["info"]["properties"]
    registered = props.get("UIAppFonts", [])
    for filename in REQUIRED_FONTS:
        assert filename in registered, (
            f"UIAppFonts 에 {filename} 누락 — `Fonts/` 를 붙이면 안 된다. "
            "번들에는 파일이 최상위에 평평하게 복사된다."
        )


def test_fonts_included_as_target_source():
    """Fonts 폴더가 타깃 소스에 없으면 번들에 복사되지 않는다."""
    spec = yaml.safe_load(PROJECT_YML.read_text(encoding="utf-8"))
    paths = {entry.get("path") for entry in spec["targets"]["JejuFolklore"]["sources"]}
    assert "JejuFolklore/Resources/Fonts" in paths


@pytest.mark.parametrize("filename,postscript", sorted(POSTSCRIPT_NAMES.items()))
def test_font_file_declares_expected_postscript_name(filename, postscript):
    """폰트 파일이 실제로 그 PostScript 이름을 갖고 있어야 한다.

    폰트를 새 버전으로 갈아끼울 때 이름이 바뀌면 여기서 잡힌다.
    안 잡히면 앱은 조용히 시스템 폰트로 렌더링된다.
    """
    fontTools = pytest.importorskip("fontTools.ttLib")
    font = fontTools.TTFont(FONT_DIR / filename)
    names = {r.nameID: str(r) for r in font["name"].names if r.platformID == 3}
    assert names.get(6) == postscript


def test_swift_uses_postscript_names():
    """갈무리를 쓰는 자리는 파일명이 아니라 PostScript 이름을 써야 한다.

    ⚠️ 2026-09-03: 갈무리를 **화면 글자 전체에** 다시 썼다(조익준님 결정).
    2026-08-20 에 「시안이 산세리프라서」 뺐었는데, 시안이 산세리프인 것은
    선택이 아니라 사고였다 — Space Grotesk·Work Sans 에 한글 글리프가 없어
    브라우저가 시스템 폰트로 떨어뜨린 결과였다.

    이름을 한 글자라도 틀리면 예외 없이 시스템 폰트로 폴백해 화면이 멀쩡해 보인다.
    """
    source = PIXEL_FONT_SWIFT.read_text(encoding="utf-8")
    used = set(re.findall(r'^\s*private static let \w+\s*=\s*"([^"]+)"', source, re.M))
    used |= set(re.findall(r'\.custom\(\s*"([^"]+)"', source))
    assert used, "PixelFont.swift 에서 갈무리를 쓰는 자리를 찾지 못했다"
    assert used <= set(POSTSCRIPT_NAMES.values()), (
        f"PostScript 이름이 아닌 값이 쓰였다: {used - set(POSTSCRIPT_NAMES.values())}"
    )


def test_no_synthetic_bold_over_pixel_font():
    """픽셀 폰트 위에 `.bold()`·`.fontWeight()` 를 씌우지 않는다.

    갈무리에는 Regular 와 Bold 두 벌뿐이다. 없는 굵기를 요구하면 iOS 가 획을
    부풀려 흉내 내고, **도트가 번져서** 픽셀 폰트를 쓰는 의미가 사라진다.
    굵게 하려면 `PixelFont` 의 Bold 항목을 쓴다.
    """
    views = (ROOT / "ios/JejuFolklore/Sources/Views").rglob("*.swift")
    offenders = []
    for f in views:
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if "//" in line and line.index("//") < (line.find(".bold(") + 1 or 10**9):
                continue
            if re.search(r"\.bold\(\)|\.fontWeight\(", line):
                offenders.append(f"{f.name}:{n}")
    assert not offenders, (
        "픽셀 폰트에 가짜 굵기를 씌우는 자리: " + ", ".join(offenders)
    )


def test_icon_font_family_name_matches_swift():
    """`PixelIcon.fontName` 이 폰트가 실제로 선언한 패밀리 이름과 같아야 한다.

    UIKit 은 파일명이 아니라 **폰트 안에 적힌 이름**으로 찾는다. 어긋나면
    `UIFont(name:)` 이 nil 을 주고 SwiftUI 는 시스템 폰트로 폴백한다 —
    예외도 경고도 없이 아이콘 자리에 두부(□)만 남는다.
    """
    fontTools = pytest.importorskip("fontTools.ttLib")
    font = fontTools.TTFont(FONT_DIR / "MaterialIcons-Regular.ttf")
    family = {str(r) for r in font["name"].names if r.nameID == 1 and r.platformID == 3}

    icon_swift = ROOT / "ios/JejuFolklore/Sources/Views/DesignSystem/PixelIcon.swift"
    declared = re.search(r'static let fontName = "([^"]+)"', icon_swift.read_text(encoding="utf-8"))
    assert declared, "PixelIcon.fontName 을 찾지 못했다"
    assert declared.group(1) in family, (
        f"PixelIcon.fontName={declared.group(1)!r} 이 폰트 패밀리 {family} 와 다르다"
    )
