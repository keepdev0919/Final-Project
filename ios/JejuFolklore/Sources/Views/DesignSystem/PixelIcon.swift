import SwiftUI

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
        case .photo: return [
            "########", "#......#", "#..##..#", "#.####.#",
            "#..##..#", "#......#", "#......#", "########"]
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
        case .map: return [
            "########", "##.##.##", "##.##.##", "##.##.##",
            "##.##.##", "##.##.##", "##.##.##", "########"]
        case .person: return [
            "..####..", "..####..", "..####..", "........",
            ".######.", "########", "##.##.##", "##....##"]
        case .back: return [
            "....##..", "...##...", "..##....", ".##.....",
            ".##.....", "..##....", "...##...", "....##.."]
        }
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
