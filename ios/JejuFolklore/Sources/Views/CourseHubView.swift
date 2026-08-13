import SwiftUI

/// 코스 탭 — 설계 §1에서 "코스 만들기"와 "내 코스"를 하나로 합쳤다.
/// 탭 4개를 유지하면서 스토리 탭 자리를 만들기 위해서다.
struct CourseHubView: View {
    private enum Section: String, CaseIterable {
        case create = "코스 만들기"
        case saved = "내 코스"
    }

    @State private var section: Section = .create

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: PixelSpacing.s) {
                ForEach(Section.allCases, id: \.self) { item in
                    Button {
                        section = item
                    } label: {
                        Text(item.rawValue)
                            .pixelFont(PixelFont.button)
                            .foregroundStyle(section == item ? PixelColor.surface : PixelColor.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: PixelSpacing.buttonHeight)
                            .background(section == item ? PixelColor.primary : PixelColor.surface)
                            .pixelBorder(PixelColor.ink, width: PixelSpacing.borderThin)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(PixelSpacing.screenMargin)
            .background(PixelColor.background)

            switch section {
            case .create: TasteDiscoveryView()
            case .saved:  MyCourseListView()
            }
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationTitle("코스")
        .navigationBarTitleDisplayMode(.inline)
    }
}
