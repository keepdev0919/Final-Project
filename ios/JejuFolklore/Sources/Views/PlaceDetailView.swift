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
            _ = await (detailTask, reviewTask)
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
                    .font(PixelFont.labelSmall)
                    .foregroundColor(PixelColor.surface)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PixelColor.ink.opacity(0.55))
                    .clipShape(Rectangle())
                    .padding(12)
            }
        }
    }

    private var placeholderPhoto: some View {
        PixelColor.primary.opacity(0.08)
            .overlay(
                PixelIcon(.photo, size: 16)
                    .foregroundColor(PixelColor.outlineVariant)
            )
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 0) {
            ShareLink(
                item: "\(place.name)\n\(detail?.address ?? "")"
            ) {
                VStack(spacing: 6) {
                    PixelIcon(.share, size: 16)
                    Text("공유하기")
                        .font(PixelFont.labelSmall)
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(PixelColor.ink)
            }
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private func overviewSection(_ detail: PlaceDetail) -> some View {
        if !detail.overview.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(detail.overview)
                    .font(PixelFont.body)
                    .foregroundColor(PixelColor.ink)
                    .lineSpacing(5)
            }
            .padding(20)
            Divider()
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
            PixelSectionHeader(title: "기본정보", icon: .mapPin,
                               accent: PixelColor.secondary)

            GoogleMapPreview(
                lat: place.lat,
                lng: place.lng,
                zoom: 15.0,
                markerTitle: place.name
            )
            .frame(height: 150)
            .clipShape(Rectangle())
            .allowsHitTesting(true)
            .onTapGesture { openInMaps() }

            if !detail.address.isEmpty {
                InfoRow(icon: .mapPin, text: detail.address)
            }

            if !detail.tel.isEmpty {
                InfoRow(icon: .phone, text: detail.tel)
            }

            Button {
                openInMaps()
            } label: {
                Text("길찾기")
                    .font(PixelFont.body)
                    .foregroundColor(PixelColor.surface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PixelColor.primary)
                    .clipShape(Rectangle())
            }
        }
        .padding(20)
        Divider()
    }

    // MARK: - Intro (이용팁)

    @ViewBuilder
    private func introSection(_ detail: PlaceDetail) -> some View {
        let tips: [(PixelIcon.Glyph, String, String)] = [
            (.clock, "운영시간", detail.openTime),
            (.calendar, "휴무일", detail.restDate),
            (.coin, "입장료", detail.useFee),
            (.car, "주차", detail.parking),
        ].filter { !$2.isEmpty }

        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PixelSectionHeader(title: "이용팁", icon: .clock,
                                   accent: PixelColor.secondary)
                ForEach(tips, id: \.1) { icon, label, value in
                    HStack(alignment: .top, spacing: 10) {
                        PixelIcon(icon, size: 20, color: PixelColor.inkWeak)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label)
                                .font(PixelFont.labelSmall)
                                .foregroundColor(PixelColor.inkWeak)
                            Text(value)
                                .font(PixelFont.body)
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
                Rectangle()
                    .fill(PixelColor.inkWeak.opacity(0.12))
                    .frame(height: 16)
            }
        }
        .padding(20)
    }

    private var failedView: some View {
        VStack(spacing: 8) {
            PixelIcon(.warn, size: 16)
                .foregroundColor(PixelColor.primary)
            Text("장소 정보를 불러오지 못했어요.")
                .font(PixelFont.body)
                .foregroundColor(PixelColor.inkWeak)
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


    // MARK: - Community

    private func communitySection(reviews: PlaceReviewsResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PixelSectionHeader(title: "다른 여행자들의 반응", icon: .person)
            Text("총 \(reviews.total)명")
                .font(PixelFont.labelSmall)
                .foregroundColor(PixelColor.inkWeak)

            let sortedTags = reviews.tagCounts
                .filter { $0.value > 0 }
                .sorted { $0.value > $1.value }

            ForEach(sortedTags, id: \.key) { tag, count in
                let pct = Double(count) / Double(reviews.total)
                HStack(spacing: 8) {
                    Text(tag)
                        .font(PixelFont.labelSmall)
                        .frame(width: 90, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(PixelColor.surfaceMid)
                            Rectangle()
                                .fill(PixelColor.primary)
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(height: 8)
                    Text("\(Int(pct * 100))%")
                        .font(PixelFont.labelSmall)
                        .foregroundColor(PixelColor.inkWeak)
                        .frame(width: 30, alignment: .trailing)
                }
            }

            if !reviews.recentNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(reviews.recentNotes, id: \.self) { note in
                        Text("\u{201C}\(note)\u{201D}")
                            .font(PixelFont.labelSmall)
                            .foregroundColor(PixelColor.inkWeak)
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
    let icon: PixelIcon.Glyph
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PixelIcon(icon, size: 20, color: PixelColor.inkWeak)
            Text(text)
                .font(PixelFont.body)
                .foregroundColor(PixelColor.ink)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlaceDetailView(
            place: CoursePlace(name: "용두암", lat: 33.5160, lng: 126.5059, day: 1)
        )
    }
}
