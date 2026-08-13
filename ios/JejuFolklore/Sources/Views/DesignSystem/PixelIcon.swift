import SwiftUI
import UIKit

/// 도트 아이콘. DESIGN.md §5 — SF Symbols를 쓰지 않는다.
///
/// 아이콘마다 Shape를 만들면 코드가 불어난다. 8×8 문자열 격자를 그리는
/// 렌더러 하나를 두고 모양은 데이터로 적는다. `#`이 채움, `.`이 투명이다.
struct PixelIcon: View {
    enum Glyph {
        case play, pause, next, photo, lock, check, mapPin, download, home, map, person, back
    }

    let glyph: Glyph
    var size: CGFloat
    var color: Color

    init(_ glyph: Glyph, size: CGFloat = 24, color: Color = PixelColor.ink) {
        self.glyph = glyph
        self.size = size
        self.color = color
    }

    var body: some View {
        Canvas { context, canvasSize in
            let rows = Self.bitmap(for: glyph)
            guard !rows.isEmpty else { return }
            let unit = canvasSize.width / CGFloat(rows.count)
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() where char == "#" {
                    let rect = CGRect(
                        x: CGFloat(x) * unit, y: CGFloat(y) * unit,
                        width: unit, height: unit
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - 모양 정의 (8×8)

    static func bitmap(for glyph: Glyph) -> [String] {
        switch glyph {
        case .play: return [
            "..#.....", "..##....", "..###...", "..####..",
            "..####..", "..###...", "..##....", "..#....."]
        case .pause: return [
            ".##..##.", ".##..##.", ".##..##.", ".##..##.",
            ".##..##.", ".##..##.", ".##..##.", ".##..##."]
        case .next: return [
            "#...#...", "##..#...", "###.#...", "#####...",
            "#####...", "###.#...", "##..#...", "#...#..."]
        // 액자 안의 산 — 사진임을 알아보게 한다
        case .photo: return [
            "########", "#......#", "#...#..#", "#..###.#",
            "#.######", "#......#", "#......#", "########"]
        case .lock: return [
            "..####..", ".#....#.", ".#....#.", "########",
            "##....##", "##.##.##", "##....##", "########"]
        case .check: return [
            "......##", ".....##.", "....##..", "##.##...",
            ".####...", "..##....", "........", "........"]
        case .mapPin: return [
            "..####..", ".######.", "##.##.##", "##....##",
            ".######.", "..####..", "...##...", "....#..."]
        case .download: return [
            "...##...", "...##...", "...##...", "##.##.##",
            ".######.", "..####..", "........", "########"]
        case .home: return [
            "...##...", "..####..", ".######.", "########",
            "##....##", "##.##.##", "##.##.##", "##.##.##"]
        // 두 지점을 잇는 경로 — 접힌 지도보다 "코스"가 바로 읽힌다
        case .map: return [
            "###.....", "###.....", ".##.....", "..##....",
            "...##...", "....##..", ".....###", ".....###"]
        case .person: return [
            "..####..", ".######.", ".######.", "..####..",
            "........", ".######.", "########", "########"]
        case .back: return [
            "....##..", "...##...", "..##....", ".##.....",
            ".##.....", "..##....", "...##...", "....##.."]
        }
    }
}

extension PixelIcon {
    /// `Image`만 받는 자리(탭바 등)에 쓰는 UIImage 렌더링.
    ///
    /// ⚠️ SwiftUI `tabItem`은 임의 View를 **조용히 무시하고** Image만 그린다.
    /// `PixelIcon`을 그대로 넘기면 아이콘 없이 글자만 나온다(2026-08-14 확인).
    /// 템플릿 모드로 돌려주므로 탭바가 선택/비선택 색을 알아서 입힌다.
    static func uiImage(_ glyph: Glyph, size: CGFloat = 24) -> UIImage {
        let rows = bitmap(for: glyph)
        guard !rows.isEmpty else { return UIImage() }
        let unit = size / CGFloat(rows.count)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            UIColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() where char == "#" {
                    context.fill(CGRect(
                        x: CGFloat(x) * unit, y: CGFloat(y) * unit,
                        width: unit, height: unit
                    ))
                }
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

private let previewGlyphs: [PixelIcon.Glyph] = [
    .play, .pause, .next, .photo, .lock, .check,
    .mapPin, .download, .home, .map, .person, .back
]

#Preview {
    ScrollView {
        VStack(spacing: PixelSpacing.l) {
            ForEach(Array(previewGlyphs.enumerated()), id: \.offset) { _, glyph in
                PixelIcon(glyph, size: 32)
            }
        }
        .padding(PixelSpacing.xl)
    }
    .background(PixelColor.background)
}
