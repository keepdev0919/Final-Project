import SwiftUI

/// 코스 탭 — "코스 만들기"와 "내 코스"를 하나로 합쳤다 (설계 §3).
struct CourseHubView: View {
    private enum Section: String, CaseIterable {
        case create = "코스 만들기"
        case saved = "내 코스"
    }

    @State private var section: Section = .create

    var body: some View {
        VStack(spacing: 0) {
            PixelTopBar(title: "코스", accent: PixelColor.secondary)

            // 세그먼트 — 선택된 쪽만 주색으로 채우고 그림자를 준다 (시안 탭 방식).
            HStack(spacing: PixelSpacing.s) {
                ForEach(Section.allCases, id: \.self) { item in
                    let on = section == item
                    Button { section = item } label: {
                        Text(item.rawValue)
                            .font(PixelFont.label)
                            .foregroundStyle(on ? PixelColor.onPrimary : PixelColor.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: PixelSpacing.buttonHeight)
                            .background(on ? PixelColor.primary : PixelColor.surface)
                            .pixelBorder()
                            .pixelShadow(on ? PixelSpacing.shadowSmall : 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, PixelSpacing.screenMargin)
            .padding(.vertical, PixelSpacing.l)

            switch section {
            case .create: TasteDiscoveryView()
            case .saved:  MyCourseListView()
            }
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}
