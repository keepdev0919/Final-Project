import SwiftUI

struct PlaceDetailSheet: View {
    let place: CoursePlace
    @State private var detail: PlaceDetail?
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 사진
                photoSection
                    .frame(height: 220)
                    .clipped()

                VStack(alignment: .leading, spacing: 16) {
                    // 장소명 + 주소
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .font(.title3.weight(.bold))
                        if let address = detail?.address, !address.isEmpty {
                            Text(address)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 설명
                    if let overview = detail?.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineSpacing(5)
                    } else if isLoading {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 80)
                    } else if failed {
                        Text("장소 정보를 불러오지 못했어요.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // 설화 섹션
                    if !place.folklorePins.isEmpty {
                        Divider()
                        folkloreSection
                    }
                }
                .padding(20)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadDetail()
        }
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoSection: some View {
        if let urlStr = detail?.imageUrl, !urlStr.isEmpty, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    placeholderPhoto
                default:
                    Color.secondary.opacity(0.1)
                        .overlay(ProgressView())
                }
            }
        } else {
            placeholderPhoto
        }
    }

    private var placeholderPhoto: some View {
        Color.orange.opacity(0.08)
            .overlay(
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.orange.opacity(0.4))
            )
    }

    // MARK: - Folklore

    private var folkloreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("이 곳에 깃든 이야기")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.orange)
            }

            ForEach(place.folklorePins) { pin in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(pin.sourceTypeLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.8))
                            .clipShape(Capsule())
                        Text(pin.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                    }
                    if !pin.summary.isEmpty {
                        Text(pin.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Data

    private func loadDetail() async {
        isLoading = true
        failed = false
        do {
            detail = try await PlaceAPI.detail(name: place.name, lat: place.lat, lng: place.lng)
        } catch {
            failed = true
        }
        isLoading = false
    }
}

// MARK: - Preview

#Preview {
    let mockPin = Pin(
        codeNo: "001",
        title: "용두암 전설",
        sourceType: "legend",
        summary: "용이 승천하려다 굳어버린 바위라는 전설이 전해진다.",
        lat: 33.516, lng: 126.505,
        primaryPlace: "용두암", distanceM: 30
    )
    let place = CoursePlace(
        name: "용두암", lat: 33.5160, lng: 126.5059,
        day: 1, folklorePins: [mockPin]
    )
    PlaceDetailSheet(place: place)
}
