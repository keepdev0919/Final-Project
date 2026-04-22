import SwiftUI
import MapKit

struct PlaceDetailView: View {
    let place: CoursePlace
    @State private var detail: PlaceDetail?
    @State private var isLoading = true
    @State private var failed = false
    @State private var currentPhotoIndex = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                photoCarousel
                actionRow
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                Divider()
                if let detail {
                    overviewSection(detail)
                    folkloreSection
                    basicInfoSection(detail)
                    introSection(detail)
                } else if isLoading {
                    skeletonView
                } else {
                    failedView
                }
            }
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
    }

    // MARK: - Photo Carousel

    private var photoCarousel: some View {
        let images = detail?.images ?? []
        return ZStack(alignment: .topTrailing) {
            if images.isEmpty {
                placeholderPhoto
                    .frame(height: 260)
            } else {
                TabView(selection: $currentPhotoIndex) {
                    ForEach(Array(images.enumerated()), id: \.offset) { idx, urlStr in
                        AsyncImage(url: URL(string: urlStr)) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                placeholderPhoto
                            }
                        }
                        .clipped()
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 260)

                Text("\(currentPhotoIndex + 1)/\(images.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(12)
            }
        }
    }

    private var placeholderPhoto: some View {
        Color.orange.opacity(0.08)
            .overlay(
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.orange.opacity(0.35))
            )
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 0) {
            ShareLink(
                item: "\(place.name)\n\(detail?.address ?? "")"
            ) {
                VStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                    Text("공유하기")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.primary)
            }
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private func overviewSection(_ detail: PlaceDetail) -> some View {
        if !detail.overview.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(detail.overview)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineSpacing(5)
            }
            .padding(20)
            Divider()
        }
    }

    // MARK: - Folklore

    @ViewBuilder
    private var folkloreSection: some View {
        if !place.folklorePins.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text("이 곳에 깃든 이야기")
                        .font(.headline)
                        .foregroundColor(.orange)
                }

                ForEach(place.folklorePins) { pin in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(pin.sourceTypeLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.85))
                                .clipShape(Capsule())
                            Text(pin.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                        }
                        if !pin.summary.isEmpty {
                            Text(pin.summary)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineSpacing(4)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(20)
            Divider()
        }
    }

    // MARK: - Basic Info

    @ViewBuilder
    private func basicInfoSection(_ detail: PlaceDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("기본정보")
                .font(.headline)

            Map(coordinateRegion: .constant(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng),
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            )))
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(true)
            .onTapGesture { openInMaps() }

            if !detail.address.isEmpty {
                InfoRow(icon: "mappin", text: detail.address)
            }

            if !detail.tel.isEmpty {
                InfoRow(icon: "phone", text: detail.tel)
            }

            Button {
                openInMaps()
            } label: {
                Text("길찾기")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        Divider()
    }

    // MARK: - Intro (이용팁)

    @ViewBuilder
    private func introSection(_ detail: PlaceDetail) -> some View {
        let tips = [
            ("clock", "운영시간", detail.openTime),
            ("calendar.badge.minus", "휴무일", detail.restDate),
            ("wonsign.circle", "입장료", detail.useFee),
            ("car", "주차", detail.parking),
        ].filter { !$2.isEmpty }

        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("이용팁")
                    .font(.headline)
                ForEach(tips, id: \.1) { icon, label, value in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(value)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Skeleton / Failed

    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 16)
            }
        }
        .padding(20)
    }

    private var failedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange.opacity(0.6))
            Text("장소 정보를 불러오지 못했어요.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Helpers

    private func openInMaps() {
        let url = URL(string: "maps://?daddr=\(place.lat),\(place.lng)&dirflg=d")!
        UIApplication.shared.open(url)
    }

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

// MARK: - InfoRow

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
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
        PlaceDetailView(place: place)
    }
}
