import SwiftUI

/// 탐험 지도에서 장소 마커 탭 시 표시되는 설화 목록 시트.
/// 각 핀을 탭하면 FolkloreDetailView로 이동한다.
struct FolklorePlacePinsView: View {
    let place: CoursePlace

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPin: Pin?

    var body: some View {
        NavigationStack {
            List(place.folklorePins) { pin in
                Button {
                    selectedPin = pin
                } label: {
                    FolklorePinListRow(pin: pin)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .sheet(item: $selectedPin) { pin in
            FolkloreDetailView(pin: pin)
        }
    }
}

private struct FolklorePinListRow: View {
    let pin: Pin

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack {
                Text(pin.sourceType == "legend" ? "📖" : "🎙️")
                    .font(.title3)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pin.sourceTypeLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.85))
                        .clipShape(Capsule())
                }

                Text(pin.displayTitle)
                    .font(.subheadline.weight(.semibold))

                if !pin.summary.isEmpty {
                    Text(pin.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .lineSpacing(3)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}
