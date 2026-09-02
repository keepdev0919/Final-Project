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

REQUIRED_FONTS = ["Galmuri9.ttf", "Galmuri11.ttf", "Galmuri14.ttf"]

# SwiftUI의 `.custom(_:)`은 **파일명이 아니라 PostScript 이름**으로 폰트를 찾는다.
# 갈무리는 파일명이 Galmuri11.ttf인데 PostScript 이름은 Galmuri11-Regular다.
# 여기를 틀리면 예외 없이 시스템 폰트로 폴백되어 화면이 멀쩡해 보인다.
POSTSCRIPT_NAMES = {
    "Galmuri9.ttf": "Galmuri9-Regular",
    "Galmuri11.ttf": "Galmuri11-Regular",
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
    """UIAppFonts 등록이 빠지면 파일이 있어도 iOS가 폰트를 못 찾는다."""
    spec = yaml.safe_load(PROJECT_YML.read_text(encoding="utf-8"))
    props = spec["targets"]["JejuFolklore"]["info"]["properties"]
    registered = props.get("UIAppFonts", [])
    for filename in REQUIRED_FONTS:
        assert f"Fonts/{filename}" in registered, f"UIAppFonts에 Fonts/{filename} 누락"


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

    ⚠️ 2026-08-20: 갈무리를 **UI 본문에서 뺐다**. 시안 4개가 전부
    산세리프이고, 시안이 촘촘하고 읽기 쉬운 이유의 절반이 폰트였다.
    지금 갈무리는 **로고에만** 쓴다 — `PixelFont.logo()` 하나뿐이다.

    폰트 파일과 번들 등록은 그대로 검사한다(위 테스트들). 로고가 조용히
    시스템 폰트로 폴백되면 앱 이름의 픽셀 정체성이 사라지는데, 그건 눈으로
    잡기 어렵다.
    """
    source = PIXEL_FONT_SWIFT.read_text(encoding="utf-8")
    used = set(re.findall(r'\.custom\(\s*"([^"]+)"', source))
    assert used, "PixelFont.swift에서 갈무리를 쓰는 자리를 찾지 못했다 (로고가 사라졌나?)"
    assert used <= set(POSTSCRIPT_NAMES.values()), (
        f"PostScript 이름이 아닌 값이 쓰였다: {used - set(POSTSCRIPT_NAMES.values())}"
    )
