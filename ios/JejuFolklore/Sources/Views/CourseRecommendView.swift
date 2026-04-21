import SwiftUI

// CourseRecommendView는 레거시 뷰입니다. TasteDiscoveryView로 대체됐습니다.
struct CourseRecommendView: View {
    var body: some View {
        TasteDiscoveryView()
    }
}

// MARK: - ThemeCard (레거시)
struct ThemeCard: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSelected ? Color.orange : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

