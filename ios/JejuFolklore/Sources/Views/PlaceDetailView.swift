import SwiftUI
import UIKit
import MapKit
import CoreLocation

/// 장소 상세 — **읽는 것과 이용하는 것을 두 탭으로 가른다** (2026-09-10 조익준님 결정).
///
///     [대표 사진]
///     이름 · 주소 · 전화
///     [소개글] [장소 정보]        ← 기본은 소개글
///
/// 전에는 사진·소개·지도·이용팁·반응을 한 화면에 세로로 다 쌓았다. 소개글은
/// 여행 전에 읽고, 지도·화장실·주차·무장애는 현장에서 찾는 정보라 쓰이는 때가
/// 다르다. 한 화면에 두면 현장에서 화장실을 찾으려고 소개글을 지나쳐 내려야 했다.
///
/// KTO 에 소개할 거리(사진·소개글)가 없으면 소개글 탭을 아예 두지 않는다.
/// 빈 탭에 「없어요」를 띄우는 것보다 있는 것만 보여주는 게 낫다.
struct PlaceDetailView: View {
    let place: CoursePlace
    @Environment(\.openURL) private var openURL
    @State private var detail: PlaceDetail?
    @State private var isLoading = true
    @State private var failed = false
    @State private var nearby: PlaceNearby? = nil
    @State private var tab: DetailTab = .intro
    /// KTO 가 주소를 안 주는 장소에 쓸, 좌표로 기기 안에서 찾은 주소.
    @State private var geocodedAddress = ""
    /// 전체 화면으로 보고 있는 사진의 번호. nil 이면 닫힌 상태.
    @State private var viewerIndex: PhotoStart?

    /// `fullScreenCover(item:)` 이 요구하는 Identifiable 껍데기.
    private struct PhotoStart: Identifiable { let id: Int }

    /// PLAY 상세와 같이 탭바를 숨긴다 — 장소 하나를 보는 화면이라 다른 탭으로 갈 일이 없고,
    /// 뒤로 가는 길은 위쪽 화살표가 갖고 있다.
    @Environment(\.tabBarVisibility) private var tabBar

    enum DetailTab { case intro, info }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                titleBlock
                if let detail {
                    let showsIntro = detail.hasIntroduction
                    if showsIntro { tabPicker }
                    if showsIntro && tab == .intro {
                        introTab(detail)
                        if hasKTOData(detail) { ktoAttribution }
                    } else {
                        // 장소 정보 탭은 자기 안의 출처 구역(sourcesSection)으로 맨 아래를 맺는다 —
                        // 여기서 다시 ktoAttribution 을 붙이면 출처가 두 번 나온다.
                        infoTab(detail, standalone: !showsIntro)
                    }
                } else if isLoading {
                    skeletonView
                } else {
                    failedView
                }
            }
        }
        .background(PixelColor.background)
        // PLAY 상세와 같다 — 상단바를 걷어내고 픽셀 뒤로가기 버튼을 사진 위에 얹는다.
        // 사진이 화면 맨 위에서 시작하므로 기본 여백(8)이면 사진 안에 들어간다.
        .pixelFloatingBack()
        .fullScreenCover(item: $viewerIndex) { start in
            PhotoViewer(images: detail?.images ?? [], start: start.id)
        }
        .onAppear { tabBar?.hide() }
        .onDisappear { tabBar?.show() }
        .task {
            async let detailTask: () = loadDetail()
            async let geocodeTask: () = loadGeocodedAddress()
            async let nearbyTask: () = loadNearby()
            _ = await (detailTask, geocodeTask, nearbyTask)
        }
    }

    // MARK: - Hero

    /// 대표 사진 한 장. KTO 사진이 없으면 놀멍봅서 기본 그림.
    private var hero: some View {
        Group {
            if let first = detail?.images.first, let url = URL(string: first) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default:                placeholderPhoto
                    }
                }
            } else {
                placeholderPhoto
            }
        }
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            if detail?.images.isEmpty == false { viewerIndex = PhotoStart(id: 0) }
        }
    }

    /// KTO 에 사진이 없거나 못 불러왔을 때 까는 **놀멍봅서 기본 그림**
    /// (2026-09-10 조익준님 결정). 코스 카드가 쓰는 것과 같은 장면이다.
    ///
    /// 전에는 옅은 판에 회색 사진 아이콘이었다. 그건 「사진을 못 불러왔다」로
    /// 읽히는데, 실제로는 KTO 에 등록되지 않아 **처음부터 없는** 경우가 대부분이다.
    /// 그림이 깔려 있으면 그 자체로 화면이 완성돼 보인다.
    ///
    /// ⚠️ `ZStack` 으로 쌓지 않는다. 안쪽 그림이 `scaledToFill` 이라 제 크기를
    /// 크게 부르는데, `ZStack` 은 가장 큰 아이를 따라 커진다. 그러면 이 자리가
    /// 화면보다 넓어지고 **아래 내용이 통째로 옆으로 밀려** 제목과 뒤로가기가
    /// 화면 밖으로 나갔다 (2026-09-10에 실제로 겪음). 크기를 정하는 것은 **색**이어야
    /// 한다. 색은 제 크기가 없어서 주어진 자리를 그대로 받고, 그림은 그 위에 얹힌다.
    private var placeholderPhoto: some View {
        PixelColor.secondaryContainer
            .overlay { PixelPlaceholderScene() }
            .clipped()
    }

    // MARK: - Title

    /// 이름, 주소, 전화. 주소는 KTO 것을 먼저, 없으면 좌표로 찾은 것을 쓴다 —
    /// KTO 에 없는 장소도 주소는 항상 있다.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.s) {
            Text(place.name)
                .font(PixelFont.sectionTitle)
                .foregroundColor(PixelColor.ink)
            let address = detail?.address.isEmpty == false ? detail!.address : geocodedAddress
            if !address.isEmpty {
                InfoRow(icon: .mapPin, text: address)
            }
            if let tel = detail?.tel, !tel.isEmpty {
                InfoRow(icon: .phone, text: tel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PixelSpacing.xl)
        .padding(.top, PixelSpacing.l)
        .padding(.bottom, PixelSpacing.l)
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabButton("소개글", .intro)
            tabButton("장소 정보", .info)
        }
        .padding(.horizontal, PixelSpacing.xl)
        .padding(.bottom, PixelSpacing.l)
    }

    /// 고른 탭은 잉크로 채우고, 나머지는 흰 바탕. 둘이 붙어 있어 한 벌로 읽힌다.
    private func tabButton(_ title: String, _ value: DetailTab) -> some View {
        let selected = tab == value
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { tab = value }
        } label: {
            Text(title)
                .font(PixelFont.label)
                .foregroundColor(selected ? PixelColor.surface : PixelColor.inkWeak)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(selected ? PixelColor.ink : PixelColor.surface)
                .pixelBorder(width: PixelSpacing.border)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 소개글 탭

    @ViewBuilder
    private func introTab(_ detail: PlaceDetail) -> some View {
        if detail.images.count > 1 {
            photoStrip(detail.images)
        }
        if !detail.overview.isEmpty {
            Text(detail.overview)
                .font(PixelFont.body)
                .foregroundColor(PixelColor.ink)
                .lineSpacing(5)
                .padding(.horizontal, PixelSpacing.xl)
                .padding(.vertical, PixelSpacing.l)
        }
    }

    /// 사진 여러 장을 가로로 넘겨 본다. 첫 장은 위 대표 사진이 이미 보여주고 있어
    /// 여기서는 그다음 장부터 둔다.
    private func photoStrip(_ images: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PixelSpacing.s) {
                ForEach(Array(images.dropFirst().enumerated()), id: \.offset) { offset, urlStr in
                    AsyncImage(url: URL(string: urlStr)) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default:                PixelColor.surfaceMid
                        }
                    }
                    .frame(width: 150, height: 110)
                    .clipped()
                    .pixelBorder(width: PixelSpacing.border)
                    .contentShape(Rectangle())
                    // dropFirst 로 한 장 밀렸으니 전체 목록 번호는 +1.
                    .onTapGesture { viewerIndex = PhotoStart(id: offset + 1) }
                }
            }
            .padding(.horizontal, PixelSpacing.xl)
        }
    }

    // MARK: - 장소 정보 탭

    /// `standalone` — 소개글 탭이 없어 이 탭만 있을 때. 반응 섹션이 여기로 온다.
    @ViewBuilder
    private func infoTab(_ detail: PlaceDetail, standalone: Bool) -> some View {
        // 소개글 탭이 없을 때 「한국관광공사에 등록된 소개가 없는 곳이에요」를 띄우던
        // 줄을 뺐다 (2026-09-10 조익준님 결정). 없는 것을 알리는 말보다 있는 정보를
        // 바로 보여주는 게 낫다.
        mapBlock

        // 칩·카드와 타일 — 어떻게 가르는지는 PlaceInfoSections.swift 에.
        let usage = usageRows(detail)
        if !usage.isEmpty {
            PlaceUsageSection(rows: usage)
        }
        if !detail.accessibility.isEmpty {
            // KTO 무장애 여행정보. 장애인 주차·화장실·휠체어 대여처럼 현장에서
            // 미리 알아야 움직일 수 있는 것들이다.
            PlaceAccessibilitySection(rows: detail.accessibility)
        }
        if let nearby, !nearby.isEmpty {
            nearbySection(nearby)
        }
        // 이 탭에서 쓰인 출처를 전부 모아 맨 아래 한 번만 — 무장애 정보 뒤·주변 시설 뒤에
        // 따로따로 적지 않는다 (2026-09-10 조익준님 결정).
        sourcesSection(detail)
    }

    private var mapBlock: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.m) {
            GoogleMapPreview(
                lat: place.lat,
                lng: place.lng,
                zoom: 15.0,
                markerTitle: place.name
            )
            .frame(height: 150)
            .clipShape(Rectangle())
            .pixelBorder(width: PixelSpacing.border)
            .onTapGesture { openInMaps() }

            Button {
                openInMaps()
            } label: {
                Text("길찾기")
                    .font(PixelFont.label)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle(.primary))
        }
        .padding(.horizontal, PixelSpacing.xl)
        .padding(.bottom, PixelSpacing.l)
    }

    /// 이용팁(운영시간·휴무일·입장료·주차)과 반복정보(화장실·주차요금·해설 안내)를
    /// **한 목록**으로 합친다. 같은 것을 두 군데서 말하지 않도록, 이용팁에 입장료가
    /// 있으면 반복정보의 입장료는 뺀다.
    private func usageRows(_ detail: PlaceDetail) -> [PlaceInfoRow] {
        var rows: [PlaceInfoRow] = [
            PlaceInfoRow(label: "운영시간", value: detail.openTime),
            PlaceInfoRow(label: "휴무일",   value: detail.restDate),
            PlaceInfoRow(label: "입장료",   value: detail.useFee),
            PlaceInfoRow(label: "주차",     value: detail.parking),
        ].filter { !$0.value.isEmpty }
        // KTO 반복정보는 같은 이름표를 두 번 주기도 한다. 같은 줄이 둘이면 SwiftUI 가
        // `ForEach(id: \.self)` 에서 경고를 내고 갱신이 어긋나므로 이름표당 하나만.
        var taken = Set(rows.map(\.label))
        for row in detail.info where taken.insert(row.label).inserted {
            rows.append(row)
        }
        return rows
    }

    // MARK: - 주변 시설

    /// 관광지 주변 1km 의 공중화장실과 버스정류장. 젠트립의 같은 자리를 참고했다
    /// (2026-09-10 조익준님 결정). 줄을 누르면 지도 앱에서 그 자리로 길을 찾는다.
    ///
    /// 화장실은 **제주시 관할만** 있다 — 서귀포시는 공공데이터포털에 API 가 없다.
    /// 그래서 없는 쪽은 묶음째 뺀다. 「없음」이라고 적으면 서귀포에 화장실이 없다는
    /// 말로 읽힌다.
    private func nearbySection(_ nearby: PlaceNearby) -> some View {
        VStack(alignment: .leading, spacing: PixelSpacing.m) {
            // 제목·밑줄은 잉크, 아이콘만 파랑 — 같은 탭의 이용 정보·무장애 정보와 맞춘다.
            PixelSectionHeader(title: "주변 시설", icon: .mapPin, iconColor: PixelColor.secondary)

            if !nearby.toilets.isEmpty {
                facilityGroup(title: "공중화장실", rows: nearby.toilets, icon: .wc, tint: PixelColor.secondary) { row in
                    var bits = [row.distanceText]
                    if let open = row.openTime, !open.isEmpty { bits.append(open) }
                    if row.accessible == true { bits.append("장애인용") }
                    return bits.joined(separator: " · ")
                }
            }
            if !nearby.busStops.isEmpty {
                facilityGroup(title: "버스정류장", rows: nearby.busStops, icon: .bus, tint: PixelColor.primary) { $0.distanceText }
            }
        }
        .padding(.horizontal, PixelSpacing.xl)
        .padding(.vertical, PixelSpacing.l)
    }

    /// 줄마다 잉크 테두리·그림자를 가진 낱장 카드 (2026-09-10 조익준님 결정, 시안 C).
    /// 이용 정보·무장애 정보의 카드·타일과 같은 말투를 쓴다. 아이콘은 시설 종류를
    /// 알려주는 색칠된 사각 배지에 — 화장실은 파랑, 정류장은 초록.
    private func facilityGroup(title: String, rows: [NearbyFacility], icon: PixelIcon.Glyph, tint: Color,
                               subtitle: @escaping (NearbyFacility) -> String) -> some View {
        VStack(alignment: .leading, spacing: PixelSpacing.s) {
            Text(title)
                .font(PixelFont.labelSmall)
                .foregroundColor(PixelColor.inkWeak)
            ForEach(rows, id: \.self) { row in
                Button {
                    openInMaps(lat: row.lat, lng: row.lng)
                } label: {
                    HStack(spacing: PixelSpacing.s) {
                        PixelIcon(icon, size: 20, color: tint)
                            .frame(width: 34, height: 34)
                            .background(tint.opacity(0.14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(PixelFont.body)
                                .foregroundColor(PixelColor.ink)
                                .multilineTextAlignment(.leading)
                            Text(subtitle(row))
                                .font(PixelFont.labelSmall)
                                .foregroundColor(PixelColor.inkWeak)
                        }
                        Spacer(minLength: 0)
                        PixelIcon(.forward, size: 18, color: PixelColor.inkWeak)
                    }
                    .padding(PixelSpacing.m)
                    .background(PixelColor.surface)
                    .pixelBorder()
                    .pixelShadow(PixelSpacing.shadowSmall)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 출처

    /// 이 화면의 사진·개요·주소가 KTO OpenAPI 에서 온다. **소개글 탭 전용** — 장소 정보
    /// 탭은 이용 정보·무장애 정보·주변 시설을 한데 모은 `sourcesSection` 을 따로 쓴다
    /// (2026-09-10 조익준님 결정: 출처를 여러 군데 흩어 적지 않고 한 구역으로).
    ///
    /// ⚠️ 공지가 지정한 유일한 형식이다. 텍스트만 허용되고 공사 CI/BI 로고는 금지다.
    /// KTO 개요 본문에 이미 「(출처 : ○○ 홈페이지)」가 들어 있는 장소가 있어,
    /// 그것과 섞이지 않도록 **화면 맨 아래**에 따로 둔다.
    private var ktoAttribution: some View {
        Text("관광정보 출처: ⓒ한국관광공사")
            .font(PixelFont.labelSmall)
            .foregroundStyle(PixelColor.inkWeak)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PixelSpacing.xl)
            .padding(.top, PixelSpacing.l)
            .padding(.bottom, 28)
    }

    /// 장소 정보 탭의 출처 — 이용 정보·무장애 정보·주변 시설이 실제로 쓴 것만 한 구역에
    /// 모은다 (2026-09-10 조익준님 결정). KTO 문구는 공지가 지정한 형식 그대로 둔다.
    @ViewBuilder
    private func sourcesSection(_ detail: PlaceDetail) -> some View {
        let lines = sourceLines(detail)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(PixelColor.ink)
                    .frame(height: PixelSpacing.border)
                VStack(alignment: .leading, spacing: 4) {
                    Text("출처")
                        .font(PixelFont.labelSmall)
                        .foregroundStyle(PixelColor.inkWeak)
                        .padding(.bottom, PixelSpacing.xs)
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(PixelFont.labelSmall)
                            .foregroundStyle(PixelColor.inkWeak)
                    }
                }
                .padding(.top, PixelSpacing.l)
            }
            .padding(.horizontal, PixelSpacing.xl)
            .padding(.top, PixelSpacing.xxl)
            .padding(.bottom, 28)
        }
    }

    private func sourceLines(_ detail: PlaceDetail) -> [String] {
        var lines: [String] = []
        if hasKTOData(detail) { lines.append("관광정보 출처: ⓒ한국관광공사") }
        if let nearby, !nearby.toilets.isEmpty { lines.append("화장실 출처: 제주특별자치도 제주시") }
        if let nearby, !nearby.busStops.isEmpty { lines.append("정류장 출처: 국토교통부(TAGO)") }
        return lines
    }

    /// KTO 에서 받은 것이 하나라도 있는가. 하나도 없으면 출처를 적을 이유가 없다 —
    /// 지도와 주소는 우리 좌표와 기기에서 나온 것이다.
    private func hasKTOData(_ d: PlaceDetail) -> Bool {
        d.hasIntroduction || !d.address.isEmpty || !d.tel.isEmpty
            || !d.openTime.isEmpty || !d.restDate.isEmpty || !d.useFee.isEmpty
            || !d.parking.isEmpty || !d.info.isEmpty || !d.accessibility.isEmpty
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
        openInMaps(lat: place.lat, lng: place.lng)
    }

    /// 주변 시설은 걸어가는 거리라 도보로, 관광지 자체는 차로 길을 찾는다.
    private func openInMaps(lat: Double, lng: Double) {
        let walking = lat != place.lat || lng != place.lng
        let mode = walking ? "walking" : "driving"
        // 1순위: 구글맵 앱 (comgooglemaps://)
        let googleAppURLString =
            "comgooglemaps://?daddr=\(lat),\(lng)&directionsmode=\(mode)"
        if let appURL = URL(string: googleAppURLString),
           UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
            return
        }
        // 2순위: 구글맵 웹 길찾기 폴백
        let webURLString =
            "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lng)&travelmode=\(mode)"
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

    /// 주변 화장실·정류장. **관광지 좌표**로 묻는다 — 사용자 위치를 넘기지 않는다.
    private func loadNearby() async {
        nearby = try? await PlaceAPI.nearby(lat: place.lat, lng: place.lng)
    }

    /// 좌표 → 주소. **기기 안에서** 한다 — 서버로 보내는 것은 관광지 좌표뿐이고,
    /// 이것도 관광지 좌표라 개인위치정보가 아니다.
    private func loadGeocodedAddress() async {
        let location = CLLocation(latitude: place.lat, longitude: place.lng)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
        let parts = [mark.administrativeArea, mark.locality, mark.subLocality,
                     mark.thoroughfare, mark.subThoroughfare]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        geocodedAddress = parts.filter { seen.insert($0).inserted }.joined(separator: " ")
    }
}

// MARK: - PhotoViewer

/// 사진을 **전체 화면**으로 넘겨 본다 (2026-09-10 조익준님 결정).
/// 검은 바탕에 좌우로 넘기고, 두 손가락으로 키울 수 있다. 닫기는 왼쪽 위 픽셀 버튼.
private struct PhotoViewer: View {
    let images: [String]
    let start: Int
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.offset) { idx, urlStr in
                    ZoomableImage(url: URL(string: urlStr))
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            HStack {
                Button { dismiss() } label: {
                    PixelIcon(.close, size: 20, color: PixelColor.ink)
                        .frame(width: 36, height: 36)
                        .background(PixelColor.surface)
                        .pixelBorder(width: PixelSpacing.border)
                        .pixelShadow(PixelSpacing.shadowSmall)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")

                Spacer()

                Text("\(index + 1)/\(images.count)")
                    .font(PixelFont.labelSmall)
                    .foregroundColor(PixelColor.ink)
                    .padding(.horizontal, PixelSpacing.s)
                    .frame(height: 36)
                    .background(PixelColor.surface)
                    .pixelBorder(width: PixelSpacing.border)
                    .pixelShadow(PixelSpacing.shadowSmall)
            }
            .padding(.horizontal, PixelSpacing.xl)
            .padding(.top, PixelSpacing.s)
        }
        .onAppear { index = min(max(start, 0), max(images.count - 1, 0)) }
    }
}

/// 두 손가락으로 키우고, 두 번 두드리면 원래 크기로.
private struct ZoomableImage: View {
    let url: URL?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFit()
            case .failure:
                PixelIcon(.warn, size: 40, color: PixelColor.surface)
            default:
                ProgressView().tint(.white)
            }
        }
        .scaleEffect(scale)
        .gesture(
            MagnificationGesture()
                .onChanged { value in scale = max(1, lastScale * value) }
                .onEnded { _ in lastScale = scale }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                scale = 1
                lastScale = 1
            }
        }
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
