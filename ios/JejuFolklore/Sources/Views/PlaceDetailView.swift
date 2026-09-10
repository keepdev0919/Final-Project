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

    /// PLAY 상세와 같이 탭바를 숨긴다 — 장소 하나를 보는 화면이라 다른 탭으로 갈 일이 없고,
    /// 뒤로 가는 길은 위쪽 화살표가 갖고 있다.
    @Environment(\.tabBarVisibility) private var tabBar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                photoCarousel
                // 「공유하기」 줄을 걷어냈다(2026-09-03 조익준님 결정). 그 줄만 있던
                // 띠라 아래 구분선도 함께 없앴다 — 사진 바로 밑에 선만 남는다.
                if let detail {
                    overviewSection(detail)
                    basicInfoSection(detail)
                    introSection(detail)
                    if let reviews = placeReviews, reviews.total > 0 {
                        Divider()
                        communitySection(reviews: reviews)
                    }
                    ktoAttribution
                } else if isLoading {
                    skeletonView
                } else {
                    failedView
                }
            }
        }
        // PLAY 상세와 같다 — 상단바를 걷어내고 픽셀 뒤로가기 버튼을 사진 위에 얹는다.
        // 사진이 화면 맨 위에서 시작하므로 기본 여백(8)이면 사진 안에 들어간다.
        .pixelFloatingBack()
        .onAppear { tabBar?.hide() }
        .onDisappear { tabBar?.show() }
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
                    .background(Color.black.opacity(0.55))
                    .clipShape(Rectangle())
                    .padding(12)
            }
        }
    }

    /// KTO 에 사진이 없거나 못 불러왔을 때 까는 **놀멍봅서 기본 그림**
    /// (2026-09-10 조익준님 결정). 코스 카드가 쓰는 것과 같은 장면이다.
    ///
    /// 전에는 옅은 판에 회색 사진 아이콘이었다. 그건 「사진을 못 불러왔다」로
    /// 읽히는데, 실제로는 KTO 에 등록되지 않아 **처음부터 없는** 경우가 대부분이다.
    /// 그림이 깔려 있으면 그 자체로 화면이 완성돼 보인다.
    ///
    /// 권역이 없는 화면이라 색은 앱의 파랑을 쓴다 — 260pt 짜리 큰 자리라
    /// 곱딱이도 64의 두 배로 키운다(어중간한 배율은 도트를 가른다).
    /// 이 화면의 사진·개요·주소·이용정보가 전부 KTO OpenAPI 에서 온다.
    /// **출처는 그 데이터가 실제로 쓰이는 자리에 붙는다** (2026-09-10 조익준님 결정).
    /// 프로필 탭의 앱 전체 고지는 그대로 두고 여기에 나란히 적는다.
    ///
    /// ⚠️ 공지가 지정한 유일한 형식이다. 텍스트만 허용되고 공사 CI/BI 로고는 금지다.
    /// KTO 개요 본문에 이미 「(출처 : ○○ 홈페이지)」가 들어 있는 장소가 있어,
    /// 그것과 섞이지 않도록 **화면 맨 아래**에 따로 둔다.
    private var ktoAttribution: some View {
        Text("관광정보 출처: ⓒ한국관광공사")
            .font(PixelFont.labelSmall)
            .foregroundStyle(PixelColor.inkWeak)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 28)
    }

    private var placeholderPhoto: some View {
        // ⚠️ `ZStack` 으로 쌓지 않는다. 안쪽 그림이 `scaledToFill` 이라 제 크기를
        // 크게 부르는데, `ZStack` 은 가장 큰 아이를 따라 커진다. 그러면 이 자리가
        // 화면보다 넓어지고 **아래 내용이 통째로 옆으로 밀려** 제목과 뒤로가기가
        // 화면 밖으로 나갔다 (2026-09-10에 실제로 겪음).
        //
        // `clipped()` 로는 안 고쳐진다 — 그건 그려지는 것만 자르고 레이아웃 크기는
        // 그대로 둔다. 크기를 정하는 것은 **색**이어야 한다. 색은 제 크기가 없어서
        // 주어진 자리를 그대로 받고, 그림은 그 위에 얹혀 밖으로 못 나간다.
        PixelColor.secondaryContainer
            .overlay {
                PixelPlaceholderScene()
            }
            .clipped()
    }

    // MARK: - Action Row

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
                PixelSectionHeader(title: "이용팁", icon: .book,
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
            PixelIcon(.warn, size: 40, color: PixelColor.locked)
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
            PixelSectionHeader(title: "다른 여행자들의 반응", icon: .person) {
                Text("총 \(reviews.total)명")
                    .font(PixelFont.labelSmall)
                    .foregroundColor(PixelColor.inkWeak)
            }

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
