import SwiftUI

// 장소 상세 「장소 정보」 탭의 두 구역 (2026-09-10 조익준님 결정).
//
//   이용 정보  → 시안 A 「칩과 카드」: 한 마디 정보는 칩으로 한 줄에, 운영시간·입장료처럼
//                긴 것만 카드로.
//   무장애 정보 → 시안 C 「현장 대시보드」: 있음·가능은 아이콘 타일로, 설명 문장은
//                읽는 글꼴로 상자 하나에.
//   두 구역의 제목·밑줄은 잉크, 아이콘만 파랑.
//
// 전에는 스무 줄 가까운 항목을 「작은 이름표 + 본문」 한 가지 모양으로 줄줄이 찍었다.
// 「화장실 있음」 한 마디와 일곱 줄짜리 입장료 표가 같은 무게로 놓여서 어디서 끊기는지
// 눈으로 찾아야 했고, 「장애인 주차 / 장애인 주차장 있음」처럼 같은 말을 두 번 했다.

// MARK: - KTO 원문 파서

/// KTO 이용정보 한 칸의 값을 `[머리]` · `- 항목` · `※ 각주` 로 나눈다.
///
/// 서버가 줄은 끊어 주지만(`_clean_text`) 구조는 그대로 온다:
///
///     [개인]
///     - 성인 12,000원
///     - 청소년/경로/군인 10,000원
///     [단체(30명 이상)]
///     - 성인 10,000원
///     ※ 자세한 입장료는 공식 홈페이지 참조
struct PlaceInfoText {
    struct Group {
        var header: String?
        var items: [String]
    }

    let groups: [Group]
    let footnotes: [String]

    init(_ raw: String) {
        var groups: [Group] = []
        var notes: [String] = []
        for piece in raw.split(separator: "\n") {
            let line = piece.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("["), line.hasSuffix("]"), line.count > 2 {
                groups.append(Group(header: String(line.dropFirst().dropLast()), items: []))
            } else if line.hasPrefix("※") || line.hasPrefix("*") {
                notes.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else {
                var item = line
                if item.hasPrefix("-") {
                    item = String(item.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                if groups.isEmpty { groups.append(Group(header: nil, items: [])) }
                groups[groups.count - 1].items.append(item)
            }
        }
        self.groups = groups
        self.footnotes = notes
    }

    /// 묶음마다 같은 이름의 항목이 「이름 금액원」 꼴이면 표로 그릴 수 있다.
    /// 카멜리아힐처럼 `[개인]`·`[단체]` 가 같은 구분(성인·청소년·어린이)을 갖는 경우다.
    struct PriceTable {
        let columns: [String]
        let rows: [(name: String, prices: [String])]
    }

    var priceTable: PriceTable? {
        guard groups.count >= 2,
              groups.allSatisfy({ $0.header != nil && !$0.items.isEmpty }) else { return nil }
        var parsed: [[(name: String, price: String)]] = []
        for group in groups {
            var rows: [(name: String, price: String)] = []
            for item in group.items {
                guard let split = Self.splitPrice(item) else { return nil }
                rows.append(split)
            }
            parsed.append(rows)
        }
        let names = parsed[0].map(\.name)
        guard parsed.allSatisfy({ $0.map(\.name) == names }) else { return nil }
        let rows = names.enumerated().map { index, name in
            (name: name, prices: parsed.map { $0[index].price })
        }
        return PriceTable(columns: groups.compactMap(\.header), rows: rows)
    }

    /// 「청소년/경로/군인 10,000원」 → (청소년/경로/군인, 10,000)
    private static func splitPrice(_ text: String) -> (name: String, price: String)? {
        let pattern = #"^(.+?)\s+([\d,]+)\s*원$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let nameRange = Range(match.range(at: 1), in: text),
              let priceRange = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[nameRange]), String(text[priceRange]))
    }
}

// MARK: - 이용 정보 (시안 A)

struct PlaceUsageSection: View {
    let rows: [PlaceInfoRow]

    private struct Chip: Hashable {
        let text: String
        let icon: PixelIcon.Glyph
    }

    var body: some View {
        let (chips, cards) = split()
        VStack(alignment: .leading, spacing: PixelSpacing.m) {
            PixelSectionHeader(title: "이용 정보", icon: .book, iconColor: PixelColor.secondary)
            if !chips.isEmpty {
                PixelWrap(spacing: PixelSpacing.s) {
                    ForEach(chips, id: \.self) { chip in
                        PixelChip(text: chip.text, icon: chip.icon)
                    }
                }
                .padding(.top, PixelSpacing.xs)
            }
            ForEach(cards, id: \.self) { row in
                card(row)
            }
        }
        .padding(.horizontal, PixelSpacing.xl)
        .padding(.vertical, PixelSpacing.l)
    }

    /// **한 마디로 끝나는 것은 칩, 나머지는 카드.**
    ///
    /// 주차는 「주차: 가능」과 「주차요금: 무료」가 따로 두 줄이던 것을 「주차 무료」 한
    /// 칩으로 합친다. 「화장실: 있음」은 「화장실」로, 「휴무일: 연중무휴」는 「연중무휴」로 —
    /// 이름표와 값이 같은 말을 두 번 하지 않게.
    private func split() -> (chips: [Chip], cards: [PlaceInfoRow]) {
        var chips: [Chip] = []
        var cards: [PlaceInfoRow] = []
        let byLabel = Dictionary(rows.map { ($0.label, $0.value) }, uniquingKeysWith: { first, _ in first })
        var consumed = Set<String>()

        for row in rows where !consumed.contains(row.label) {
            let value = row.value
            let oneLine = !value.contains("\n")

            if row.label == "주차" {
                consumed.insert("주차")
                let fee = byLabel["주차요금"]
                // 「가능 (약 대형 60대, 소형 75대)」 처럼 대수·조건이 붙은 값은 칩으로
                // 접지 않는다 — 렌터카 여행자가 현장에서 제일 먼저 찾는 정보다.
                let bare = oneLine && (value == "가능" || value == "있음")
                if oneLine, isShort(value, max: 6), value.contains("불가") || value.contains("없음") {
                    chips.append(Chip(text: "주차 불가", icon: .car))
                } else if bare, let fee, isShort(fee, max: 6) {
                    consumed.insert("주차요금")
                    chips.append(Chip(text: "주차 \(fee)", icon: .car))
                } else if bare {
                    chips.append(Chip(text: "주차 가능", icon: .car))
                } else {
                    cards.append(row)
                }
                continue
            }

            guard oneLine else { cards.append(row); continue }
            switch row.label {
            case "휴무일" where isShort(value, max: 10):
                chips.append(Chip(text: value.contains("무휴") ? value : "휴무 \(value)", icon: .dayOpen))
            case "운영시간" where isShort(value, max: 14):
                chips.append(Chip(text: value, icon: .clock))
            case "화장실" where isShort(value, max: 6):
                chips.append(Chip(text: value == "있음" ? "화장실" : "화장실 \(value)", icon: .wc))
            case "입장료" where isShort(value, max: 8):
                chips.append(Chip(text: value == "무료" ? "입장료 무료" : "입장료 \(value)", icon: .ticket))
            case "주차요금" where isShort(value, max: 6):
                chips.append(Chip(text: "주차 \(value)", icon: .car))
            default:
                if (row.label + value).count <= 12 {
                    chips.append(Chip(text: "\(row.label) \(value)", icon: .info))
                } else {
                    cards.append(row)
                }
            }
        }
        return (chips, cards)
    }

    private func isShort(_ text: String, max: Int) -> Bool {
        !text.contains("\n") && text.count <= max
    }

    // MARK: 카드

    private func card(_ row: PlaceInfoRow) -> some View {
        let text = PlaceInfoText(row.value)
        return VStack(alignment: .leading, spacing: PixelSpacing.s) {
            HStack(spacing: 6) {
                PixelIcon(cardIcon(row.label), size: 18, color: PixelColor.inkWeak)
                Text(row.label)
                    .font(PixelFont.label)
                    .foregroundStyle(PixelColor.inkWeak)
            }
            if let table = text.priceTable {
                priceTable(table)
            } else {
                ForEach(Array(text.groups.enumerated()), id: \.offset) { index, group in
                    groupBlock(group, isFirst: index == 0)
                }
            }
            ForEach(text.footnotes, id: \.self) { note in
                Text(note)
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
            }
        }
        .padding(PixelSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixelColor.surface)
        .pixelBorder()
        .pixelShadow(PixelSpacing.shadowCard)
    }

    private func cardIcon(_ label: String) -> PixelIcon.Glyph {
        switch label {
        case "운영시간": return .clock
        case "휴무일":   return .dayOpen
        case "입장료":   return .ticket
        case "주차", "주차요금": return .car
        case "화장실":   return .wc
        default:         return .info
        }
    }

    /// `[하절기/간절기(3월~11월)]` 머리는 노란(첫 묶음)·옅은 칩으로, 항목은 그 아래.
    /// 「입장 마감 17:30」·「마지막 주문 22:00」 같은 곁말은 작게.
    private func groupBlock(_ group: PlaceInfoText.Group, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: PixelSpacing.xs) {
            if let header = group.header {
                Text(header)
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isFirst ? PixelColor.accent : PixelColor.surfaceLow)
                    .pixelBorder()
            }
            ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                let aside = item.contains("마감") || item.contains("마지막 주문") || item.contains("준비시간")
                Text(item)
                    .font(aside ? PixelFont.labelSmall : PixelFont.body)
                    .foregroundStyle(aside ? PixelColor.inkWeak : PixelColor.ink)
            }
        }
    }

    /// 구분 | 개인 | 단체 표. 첫 값 열은 잉크, 나머지는 옅게 — 대개 첫 열이 「내가 낼 값」이다.
    private func priceTable(_ table: PlaceInfoText.PriceTable) -> some View {
        let priceWidth: CGFloat = 72
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("원")
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(table.columns, id: \.self) { column in
                    Text(column)
                        .font(PixelFont.labelSmall)
                        .foregroundStyle(PixelColor.inkWeak)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .frame(width: priceWidth, alignment: .trailing)
                }
            }
            .padding(.vertical, 6)
            .overlay(alignment: .top) { Rectangle().fill(PixelColor.ink).frame(height: PixelSpacing.border) }
            .overlay(alignment: .bottom) { Rectangle().fill(PixelColor.outlineVariant).frame(height: PixelSpacing.border) }

            ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 4) {
                    Text(row.name)
                        .font(PixelFont.label)
                        .foregroundStyle(PixelColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(row.prices.enumerated()), id: \.offset) { column, price in
                        Text(price)
                            .font(PixelFont.body)
                            .foregroundStyle(column == 0 ? PixelColor.ink : PixelColor.inkWeak)
                            .frame(width: priceWidth, alignment: .trailing)
                    }
                }
                .padding(.vertical, PixelSpacing.s)
                .overlay(alignment: .bottom) {
                    if index < table.rows.count - 1 {
                        Rectangle().fill(PixelColor.outlineVariant).frame(height: PixelSpacing.border)
                    }
                }
            }
        }
    }
}

// MARK: - 무장애 정보 (시안 C)

struct PlaceAccessibilitySection: View {
    let rows: [PlaceInfoRow]

    private struct Tile: Hashable {
        let label: String
        let icon: PixelIcon.Glyph
    }

    private struct Note: Hashable {
        let label: String
        let text: String
        let warns: Bool
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PixelSpacing.s), count: 4)

    var body: some View {
        let (tiles, notes) = split()
        VStack(alignment: .leading, spacing: PixelSpacing.m) {
            PixelSectionHeader(title: "무장애 정보", icon: .wheelchair, iconColor: PixelColor.secondary)
            if !tiles.isEmpty {
                LazyVGrid(columns: columns, spacing: PixelSpacing.s) {
                    ForEach(tiles, id: \.self) { tile in
                        tileView(tile)
                    }
                }
                .padding(.top, PixelSpacing.xs)
            }
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: PixelSpacing.m) {
                    ForEach(notes, id: \.self) { note in
                        noteRow(note)
                    }
                }
                .padding(PixelSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PixelColor.surfaceLow)
                .pixelBorder()
            }
        }
        .padding(.horizontal, PixelSpacing.xl)
        .padding(.vertical, PixelSpacing.l)
    }

    /// **「있음·가능」으로 끝나는 짧은 값은 타일, 문장은 설명 상자.**
    ///
    /// 「장애인 주차 / 장애인 주차장 있음」은 타일 「장애인 주차」 하나로 접힌다.
    /// 「대여가능(1대/관리사무소)」처럼 꼬리가 붙으면 타일을 두고 꼬리는 상자에 적는다.
    /// 「주의」·「없음」·「불가」가 든 문장은 경고색으로.
    private func split() -> (tiles: [Tile], notes: [Note]) {
        var tiles: [Tile] = []
        var notes: [Note] = []
        for row in rows {
            let value = row.value.trimmingCharacters(in: .whitespaces)
            if let remainder = Self.availabilityRemainder(value) {
                tiles.append(Tile(label: row.label, icon: Self.icon(for: row.label)))
                if !remainder.isEmpty {
                    notes.append(Note(label: row.label, text: remainder, warns: Self.warns(remainder)))
                }
            } else {
                notes.append(Note(label: row.label, text: value, warns: Self.warns(value)))
            }
        }
        return (tiles, notes)
    }

    /// 값이 「있다」는 뜻이면 남는 꼬리를 돌려준다(없으면 빈 문자열). 아니면 nil.
    private static func availabilityRemainder(_ value: String) -> String? {
        // 「휠체어 접근 불가능」은 `가능` 으로 끝나고, 「가능하나 계단 있음」은 `가능` 으로
        // 시작한다. 부정어가 하나라도 있으면 타일이 아니라 설명이다 — 무장애 정보는
        // 틀리면 없느니만 못하다.
        if negatives.contains(where: { value.contains($0) }) { return nil }
        let leads = ["대여가능", "대여 가능", "이용가능", "이용 가능", "있음", "가능"]
        for lead in leads where value.hasPrefix(lead) {
            var rest = String(value.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("("), rest.hasSuffix(")") {
                rest = String(rest.dropFirst().dropLast())
            }
            return rest
        }
        // 「장애인 주차장 있음」·「기저귀교환대 있음」·「주출입구는 턱이 없어 휠체어 접근 가능함」
        let tails = ["있음", "가능함", "가능"]
        if value.count <= 14, tails.contains(where: { value.hasSuffix($0) }) {
            return ""
        }
        return nil
    }

    private static let negatives = ["주의", "없음", "불가", "어려", "제한", "하나", "지만"]

    private static func warns(_ text: String) -> Bool {
        negatives.contains { text.contains($0) }
    }

    private static func icon(for label: String) -> PixelIcon.Glyph {
        switch label {
        case "장애인 주차":              return .parkingSign
        case "장애인 화장실":            return .wheelchairForward
        case "휠체어 대여":              return .wheelchair
        case "유모차 대여", "유아 편의":  return .stroller
        case "수유실":                   return .nursing
        case "대중교통":                 return .bus
        case "엘리베이터":               return .up
        case "점자블록", "점자 안내물", "시각장애 편의": return .eye
        case "음성 안내":                return .sound
        case "수어·영상 안내", "청각장애 편의": return .hearing
        case "안내 인력":                return .person
        case "안내견 동반":              return .walk
        case "접근로":                   return .walk
        case "출입구":                   return .gate
        case "매표소":                   return .ticket
        default:                         return .check
        }
    }

    private func tileView(_ tile: Tile) -> some View {
        VStack(spacing: 6) {
            PixelIcon(tile.icon, size: 26, color: PixelColor.ink)
            Text(tile.label)
                .font(PixelFont.labelSmall)
                .foregroundStyle(PixelColor.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(PixelColor.surface)
        .pixelBorder()
        .pixelShadow(PixelSpacing.shadowSmall)
    }

    private func noteRow(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: PixelSpacing.s) {
            PixelIcon(note.warns ? .warn : .wheelchair, size: 20,
                      color: note.warns ? PixelColor.error : PixelColor.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.label)
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
                Text(note.text)
                    .font(PixelFont.reading)
                    .foregroundStyle(PixelColor.ink)
                    .lineSpacing(3)
            }
        }
    }
}

// MARK: - 줄바꿈 흐름 배치

/// 칩을 왼쪽부터 채우고 넘치면 다음 줄로. SwiftUI 에 기본 흐름 배치가 없어 만든다.
struct PixelWrap: Layout {
    var spacing: CGFloat = PixelSpacing.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return place(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = place(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                                  proposal: .unspecified)
        }
    }

    private func place(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

#Preview("카멜리아힐") {
    ScrollView {
        VStack(spacing: 0) {
            PlaceUsageSection(rows: [
                PlaceInfoRow(label: "운영시간", value: "[하절기/간절기(3월~11월)]\n- 08:30~18:30\n- 입장 마감 17:30\n[동절기(11월~2월)]\n- 08:30~18:00\n- 입장 마감 17:00"),
                PlaceInfoRow(label: "휴무일", value: "연중무휴"),
                PlaceInfoRow(label: "주차", value: "가능"),
                PlaceInfoRow(label: "입장료", value: "[개인]\n- 성인 12,000원\n- 청소년/경로/군인 10,000원\n- 어린이/장애인/보훈대상/4.3유족 9,000원\n[단체(30명 이상)]\n- 성인 10,000원\n- 청소년/경로/군인 9,000원\n- 어린이/장애인/보훈대상/4.3유족 8,000원\n※ 자세한 입장료는 공식 홈페이지 참조"),
                PlaceInfoRow(label: "주차요금", value: "무료"),
                PlaceInfoRow(label: "화장실", value: "있음"),
            ])
            PlaceAccessibilitySection(rows: [
                PlaceInfoRow(label: "장애인 주차", value: "장애인 주차장 있음"),
                PlaceInfoRow(label: "접근로", value: "출입구까지 턱이 없어 휠체어 접근 가능함(산책로 내 포토존 제외한 길 휠체어 이동 용이)"),
                PlaceInfoRow(label: "출입구", value: "주출입구는 턱이 없어 휠체어 접근 가능함"),
                PlaceInfoRow(label: "장애인 화장실", value: "장애인 화장실 있음"),
                PlaceInfoRow(label: "휠체어 대여", value: "대여가능(1대/관리사무소)"),
                PlaceInfoRow(label: "유모차 대여", value: "대여가능"),
                PlaceInfoRow(label: "수유실", value: "수유실 있음"),
                PlaceInfoRow(label: "기타 편의", value: "일부 박석 구간이 있어 휠체어 이용시 주의"),
            ])
        }
    }
    .background(PixelColor.background)
}
