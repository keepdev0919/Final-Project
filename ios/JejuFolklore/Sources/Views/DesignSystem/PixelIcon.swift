import SwiftUI
import UIKit

/// 도트 아이콘. SF Symbols를 쓰지 않는다.
///
/// 아이콘마다 Shape를 만들면 코드가 불어난다. 8×8 문자열 격자를 그리는
/// 렌더러 하나를 두고 모양은 데이터로 적는다. `#`이 채움, `.`이 투명이다.
struct PixelIcon: View {
    enum Glyph {
        case play, pause, next, photo, lock, check, mapPin, download, home, map, person, back
        // 2026-08-20 추가 — SF Symbols를 걷어내며 필요해진 것들
        case forward, up, down, close, calendar, clock, warn, refresh, shuffle
        case share, edit, more, target, book, headphone
        // 장소 화면의 이용팁 줄(운영시간·입장료·주차·전화)과 받아쓰기 버튼에 쓴다
        case coin, car, phone, stop, mic
        // 홈 스테이지 카드의 세계관 라벨 6종 (data/home_stage.json의 `icon` 값과 짝이다)
        case volcano, wave, drop, tree, house, gate
    }

    let glyph: Glyph
    var size: CGFloat
    /// nil이면 바깥에서 준 `.foregroundColor`·`.foregroundStyle`을 따른다.
    ///
    /// ⚠️ 기본값을 잉크로 **고정하지 않는다.** `Canvas`는 색을 인자로 받은 것만 쓰기 때문에
    /// 고정하면 바깥의 `.foregroundColor(...)`가 **조용히 무시된다.** 2026-08-20 리뷰에서
    /// 이 때문에 19곳이 잘못된 색으로 그려지고 있었다 — 도착 화면의 큰 핀이 어둠막에
    /// 묻히고, 방문 완료 체크가 초록이 아니라 검정으로 나왔다.
    var color: Color?

    init(_ glyph: Glyph, size: CGFloat = 24, color: Color? = nil) {
        self.glyph = glyph
        self.size = size
        self.color = color
    }

    var body: some View {
        Canvas { context, canvasSize in
            let rows = Self.bitmap(for: glyph)
            guard !rows.isEmpty else { return }
            let unit = canvasSize.width / CGFloat(rows.count)
            // `.style(.foreground)`이 환경의 foregroundStyle을 읽는다.
            let shading: GraphicsContext.Shading =
                color.map { .color($0) } ?? .style(.foreground)
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() where char == "#" {
                    let rect = CGRect(
                        x: CGFloat(x) * unit, y: CGFloat(y) * unit,
                        width: unit, height: unit
                    )
                    context.fill(Path(rect), with: shading)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - 모양 정의 (8×8)

    static func bitmap(for glyph: Glyph) -> [String] {
        switch glyph {
        // ── 홈 스테이지 라벨 (8×8)
        // 분화구가 열린 산. 위가 뚫려 있어 그냥 산과 구분된다.
        case .volcano: return [
            "........", "..#..#..", ".##..##.", ".##..##.",
            "..####..", ".######.", "########", "########"]
        // 파도 두 겹. 한 겹이면 밑줄로 보인다.
        case .wave: return [
            "........", "##....##", ".##..##.", "..####..",
            "........", "##....##", ".##..##.", "..####.."]
        // 물방울.
        case .drop: return [
            "...##...", "...##...", "..####..", "..####..",
            ".######.", "########", "########", ".######."]
        // 잎이 셋인 나무. 줄기가 있어 버섯과 구분된다.
        case .tree: return [
            "...##...", "..####..", ".######.", "########",
            "..####..", "...##...", "...##...", "..####.."]
        // 초가 두 채. 지붕만 두 개 겹쳐 마을임을 알린다.
        case .house: return [
            "..##....", ".####.##", "########", "########",
            "##..####", "##..##.#", "##..##.#", "########"]
        // 돌하르방 문. 기둥 둘과 위 가로대.
        case .gate: return [
            "########", "########", ".##..##.", ".##..##.",
            ".##..##.", ".##..##.", ".##..##.", "###..###"]

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
        case .forward: return [
            "..##....", "...##...", "....##..", ".....##.",
            ".....##.", "....##..", "...##...", "..##...."]
        case .up: return [
            "...##...", "..####..", ".##..##.", "##....##",
            "........", "........", "........", "........"]
        case .down: return [
            "........", "........", "........", "........",
            "##....##", ".##..##.", "..####..", "...##..."]
        case .close: return [
            "##....##", ".##..##.", "..####..", "...##...",
            "...##...", "..####..", ".##..##.", "##....##"]
        case .calendar: return [
            ".##..##.", "########", "#......#", "#.##.#.#",
            "#......#", "#.#.##.#", "#......#", "########"]
        case .clock: return [
            "..####..", ".#.##.#.", "##.##.##", "##.####.",
            "##....##", "##....##", ".#....#.", "..####.."]
        case .warn: return [
            "...##...", "...##...", "..####..", "..####..",
            ".##..##.", ".##.###.", "##....##", "########"]
        case .refresh: return [
            "..####..", ".##..##.", "##....##", "##......",
            "......##", "##....##", ".##..##.", "..####.."]
        case .shuffle: return [
            "##....##", "..#..#..", "...##...", "....#.##",
            "##.#....", "...##...", "..#..#..", "##....##"]
        case .share: return [
            "...##...", "..####..", ".##..##.", "...##...",
            "########", "##....##", "##....##", "########"]
        case .edit: return [
            "......##", ".....##.", "....##..", "...##...",
            "..##....", ".###....", "####....", "##......"]
        case .more: return [
            "........", "........", "##.##.##", "##.##.##",
            "........", "........", "........", "........"]
        case .target: return [
            "..####..", ".#....#.", "#..##..#", "#.####.#",
            "#.####.#", "#..##..#", ".#....#.", "..####.."]
        case .book: return [
            "###..###", "#..##..#", "#..##..#", "#..##..#",
            "#..##..#", "#..##..#", "#..##..#", "########"]
        // 동전 — 입장료
        case .coin: return [
            "..####..", ".#....#.", "#..##..#", "#.#..#.#",
            "#.#..#.#", "#..##..#", ".#....#.", "..####.."]
        // 자동차 — 주차
        case .car: return [
            "........", "..#####.", ".##...##", "########",
            "########", "########", ".##..##.", "..#..#.."]
        // 수화기 — 전화
        case .phone: return [
            "###.....", "###.....", ".##.....", "..##.##.",
            "...####.", "....####", ".....###", ".....###"]
        // 정지 — 받아쓰기 중지
        case .stop: return [
            "........", ".######.", ".######.", ".######.",
            ".######.", ".######.", ".######.", "........"]
        // 마이크 — 받아쓰기 시작
        case .mic: return [
            "..####..", "..####..", "..####..", "..####..",
            "#..##..#", "#.####.#", ".#####..", "..####.."]
        case .headphone: return [
            "..####..", ".######.", "##....##", "##....##",
            "##....##", "##....##", "##....##", "##....##"]
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
    .mapPin, .download, .home, .map, .person, .back,
    .forward, .up, .down, .close, .calendar, .clock,
    .warn, .refresh, .shuffle, .share, .edit, .more,
    .target, .book, .headphone, .coin, .car, .phone, .stop, .mic
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
