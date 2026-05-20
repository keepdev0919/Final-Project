import SwiftUI
import UIKit
import MapKit

struct PlaceDetailView: View {
    let place: CoursePlace
    @Environment(\.openURL) private var openURL
    @State private var detail: PlaceDetail?
    @State private var isLoading = true
    @State private var failed = false
    @State private var currentPhotoIndex = 0
    @State private var placeReviews: PlaceReviewsResponse? = nil

    /// Lv2: codeNo → 장소-설화 연결 한 줄 캐시
    @State private var connections: [String: String] = [:]
    /// Lv3: 풀스크린 스토리 뷰어 트리거
    @State private var presentedStoryPin: Pin? = nil

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
                    if let reviews = placeReviews, reviews.total > 0 {
                        Divider()
                        communitySection(reviews: reviews)
                    }
                } else if isLoading {
                    skeletonView
                } else {
                    failedView
                }
            }
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let detailTask: () = loadDetail()
            async let reviewTask: () = loadReviews()
            async let connectionTask: () = loadConnections()
            _ = await (detailTask, reviewTask, connectionTask)
        }
        .fullScreenCover(item: $presentedStoryPin) { pin in
            StoryViewerView(pin: pin, placeName: place.name)
        }
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

    // MARK: - Folklore (Lv1 + Lv2 + Lv3)

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
                    folkloreCard(pin: pin)
                }
            }
            .padding(20)
            Divider()
        }
    }

    private func folkloreCard(pin: Pin) -> some View {
        let connection = connections[pin.codeNo]
        return VStack(alignment: .leading, spacing: 10) {
            // Lv2: 장소-설화 연결 한 줄 (있을 때만)
            if let connection, !connection.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 1)
                    Text(connection)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineSpacing(2)
                }
            }

            // 카테고리 배지 + Lv1: 코드 접두사 제거된 제목
            HStack(spacing: 6) {
                Text(pin.sourceTypeLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.85))
                    .clipShape(Capsule())
                Text(pin.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            // Lv1: 후크 한 줄 크게 (없으면 summary 의 첫 줄을 폴백)
            let hookText = (pin.hook?.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? firstLine(of: pin.summary)
            if let hookText, !hookText.isEmpty {
                Text(hookText)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Lv3: "이야기 보기" 버튼 → 풀스크린 스토리 뷰어
            Button {
                presentedStoryPin = pin
            } label: {
                HStack(spacing: 6) {
                    Text("이야기 보기")
                        .font(.footnote.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            presentedStoryPin = pin
        }
    }

    private func firstLine(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let newline = trimmed.firstIndex(where: { $0.isNewline }) {
            return String(trimmed[..<newline])
        }
        // 너무 길면 90자에서 자른다
        if trimmed.count > 90 {
            let idx = trimmed.index(trimmed.startIndex, offsetBy: 90)
            return String(trimmed[..<idx]) + "…"
        }
        return trimmed
    }

    // MARK: - Basic Info

    @ViewBuilder
    private func basicInfoSection(_ detail: PlaceDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("기본정보")
                .font(.headline)

            GoogleMapPreview(
                lat: place.lat,
                lng: place.lng,
                zoom: 15.0,
                markerTitle: place.name
            )
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(true)
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
        // 1순위: 구글맵 앱 (comgooglemaps://)
        let googleAppURLString =
            "comgooglemaps://?daddr=\(place.lat),\(place.lng)&directionsmode=driving"
        if let appURL = URL(string: googleAppURLString),
           UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
            return
        }
        // 2순위: 구글맵 웹 길찾기 폴백
        let webURLString =
            "https://www.google.com/maps/dir/?api=1&destination=\(place.lat),\(place.lng)"
        if let webURL = URL(string: webURLString) {
            openURL(webURL)
        }
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

    private func loadReviews() async {
        placeReviews = try? await APIClient.shared.fetchReviews(placeName: place.name)
    }

    /// Lv2: 각 핀별 장소-설화 연결 한 줄을 병렬로 불러온다.
    /// 백엔드 미구현이면 그냥 비어 있는 상태가 유지된다 (크래시 X).
    private func loadConnections() async {
        let pins = place.folklorePins
        let placeName = place.name
        guard !pins.isEmpty else { return }
        await withTaskGroup(of: (String, String?).self) { group in
            for pin in pins {
                let codeNo = pin.codeNo
                group.addTask {
                    let result = try? await PinsAPI.connection(
                        codeNo: codeNo,
                        place: placeName
                    )
                    return (codeNo, result)
                }
            }
            for await (codeNo, line) in group {
                if let line, !line.isEmpty {
                    connections[codeNo] = line
                }
            }
        }
    }

    // MARK: - Community

    private func communitySection(reviews: PlaceReviewsResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("다른 여행자들의 반응")
                    .font(.headline)
                Spacer()
                Text("총 \(reviews.total)명")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let sortedTags = reviews.tagCounts
                .filter { $0.value > 0 }
                .sorted { $0.value > $1.value }

            ForEach(sortedTags, id: \.key) { tag, count in
                let pct = Double(count) / Double(reviews.total)
                HStack(spacing: 8) {
                    Text(tag)
                        .font(.caption)
                        .frame(width: 90, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemFill))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.orange)
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(height: 8)
                    Text("\(Int(pct * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }

            if !reviews.recentNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(reviews.recentNotes, id: \.self) { note in
                        Text("\u{201C}\(note)\u{201D}")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
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
