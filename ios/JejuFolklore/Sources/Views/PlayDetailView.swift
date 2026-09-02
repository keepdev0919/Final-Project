import SwiftUI
import UIKit
import MapKit

/// PLAY 상세 — **시작 전에 무엇을 하게 되는지 알려주는 화면**이다.
///
/// 두 가지 질문에 답한다 (`콘텐츠/성읍민속마을.md` §3).
///
/// 1. 여기서 내가 어떤 PLAY 를 하게 되는가?
/// 2. 어디서 시작해서 어디를 탐험하게 되는가?
///
/// 관광정보(운영시간·입장료·주차)는 여기서 **요약만** 보여주고, 전체는
/// `[장소 정보 보기]` 로 Place Detail 에 넘긴다. 이 화면의 주인공은 게임이다.
struct PlayDetailView: View {
    let playId: String

    @StateObject private var vm = PlayDetailViewModel()
    @Environment(\.openURL) private var openURL
    @State private var showRunner = false

    var body: some View {
        ScrollView {
            if let play = vm.play {
                VStack(alignment: .leading, spacing: 0) {
                    header(play)
                    fantasySection(play)
                    metaSection(play)
                    routeSection(play)
                    cautionSection(play)
                    placeInfoLink(play)
                    ctaSection(play)
                }
            } else if vm.failed {
                failedView
            } else {
                ProgressView().padding(PixelSpacing.xxxl).frame(maxWidth: .infinity)
            }
        }
        .background(PixelColor.background)
        .navigationTitle(vm.play?.placeName ?? "PLAY")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(playId: playId) }
        .fullScreenCover(isPresented: $showRunner) {
            if let play = vm.play {
                PlayRunnerView(play: play)
            }
        }
    }

    // MARK: - 머리

    @ViewBuilder
    private func header(_ play: Play) -> some View {
        ZStack {
            PixelColor.surfaceHigh
            if let s = vm.thumbnail, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: PixelIcon(.photo, size: 48, color: PixelColor.outlineVariant)
                    }
                }
            } else {
                PixelIcon(.photo, size: 48, color: PixelColor.outlineVariant)
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipped()

        VStack(alignment: .leading, spacing: PixelSpacing.xs) {
            Text(play.title)
                .font(PixelFont.screenTitle)
                .foregroundStyle(PixelColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(play.placeName)
                .font(PixelFont.labelSmall)
                .foregroundStyle(PixelColor.inkWeak)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PixelSpacing.screenMargin)
        .padding(.top, PixelSpacing.l)
    }

    // MARK: - Game Fantasy

    @ViewBuilder
    private func fantasySection(_ play: Play) -> some View {
        VStack(alignment: .leading, spacing: PixelSpacing.m) {
            if !play.role.isEmpty {
                HStack(spacing: PixelSpacing.s) {
                    Text("ROLE")
                        .font(PixelFont.labelSmall)
                        .foregroundStyle(PixelColor.inkWeak)
                    PixelChip(text: play.role, icon: .person,
                              fill: PixelColor.accent, label: PixelColor.onAccent)
                }
            }
            if !play.objective.isEmpty {
                Text(play.objective)
                    .font(PixelFont.bodyLarge)
                    .foregroundStyle(PixelColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !play.fantasy.isEmpty {
                Text(play.fantasy)
                    .font(PixelFont.body)
                    .foregroundStyle(PixelColor.inkWeak)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(PixelSpacing.screenMargin)
    }

    // MARK: - 메타

    @ViewBuilder
    private func metaSection(_ play: Play) -> some View {
        HStack(spacing: 0) {
            metaBox(.clock, play.durationText, "예상 시간")
            metaBox(.map, play.distanceText, "거리")
            metaBox(.target, play.difficulty, "난이도")
            metaBox(.check, "\(play.missionCount)", "Missions")
        }
        .padding(.horizontal, PixelSpacing.screenMargin)
    }

    private func metaBox(_ icon: PixelIcon.Glyph, _ value: String, _ label: String) -> some View {
        VStack(spacing: PixelSpacing.xs) {
            PixelIcon(icon, size: 18, color: PixelColor.inkWeak)
            Text(value)
                .font(PixelFont.label)
                .foregroundStyle(PixelColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(PixelFont.labelSmall)
                .foregroundStyle(PixelColor.inkWeak)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PixelSpacing.m)
    }

    // MARK: - 탐험 경로

    @ViewBuilder
    private func routeSection(_ play: Play) -> some View {
        VStack(alignment: .leading, spacing: PixelSpacing.m) {
            PixelSectionHeader(title: "탐험할 경로", icon: .mapPin,
                               accent: PixelColor.secondary)

            PlayRouteMap(play: play)
                .frame(height: 200)
                .pixelBorder()

            VStack(alignment: .leading, spacing: PixelSpacing.s) {
                routeRow(marker: "START", text: play.startName, highlight: true)
                ForEach(Array(play.points.enumerated()), id: \.element.id) { i, point in
                    routeRow(marker: "\(i + 1)", text: point.title, highlight: false)
                }
                routeRow(marker: "FINISH", text: play.finishName, highlight: true)
            }
        }
        .padding(PixelSpacing.screenMargin)
    }

    private func routeRow(marker: String, text: String, highlight: Bool) -> some View {
        HStack(spacing: PixelSpacing.m) {
            Text(marker)
                .font(PixelFont.labelSmall)
                .foregroundStyle(highlight ? PixelColor.onPrimary : PixelColor.onAccent)
                .frame(minWidth: 24)
                .padding(.horizontal, PixelSpacing.xs)
                .padding(.vertical, 2)
                .background(highlight ? PixelColor.primary : PixelColor.accent)
                .pixelBorder()
            Text(text.isEmpty ? "—" : text)
                .font(PixelFont.body)
                .foregroundStyle(PixelColor.ink)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 주의사항

    @ViewBuilder
    private func cautionSection(_ play: Play) -> some View {
        if !play.cautions.isEmpty {
            VStack(alignment: .leading, spacing: PixelSpacing.s) {
                PixelSectionHeader(title: "시작 전에 꼭 읽어주세요", icon: .warn,
                                   accent: PixelColor.locked)
                ForEach(play.cautions, id: \.self) { line in
                    HStack(alignment: .top, spacing: PixelSpacing.s) {
                        Text("·").font(PixelFont.body).foregroundStyle(PixelColor.inkWeak)
                        Text(line)
                            .font(PixelFont.body)
                            .foregroundStyle(PixelColor.inkWeak)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(PixelSpacing.screenMargin)
        }
    }

    // MARK: - 장소 정보

    @ViewBuilder
    private func placeInfoLink(_ play: Play) -> some View {
        NavigationLink {
            PlaceDetailView(place: CoursePlace(
                name: play.placeName,
                lat: play.startCoordinate?.latitude ?? 0,
                lng: play.startCoordinate?.longitude ?? 0,
                day: 0
            ))
        } label: {
            HStack {
                PixelIcon(.book, size: 18, color: PixelColor.ink)
                Text("장소 정보 보기")
                    .font(PixelFont.body)
                    .foregroundStyle(PixelColor.ink)
                Text("운영시간 · 입장료 · 주차")
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
                Spacer(minLength: 0)
                PixelIcon(.forward, size: 16, color: PixelColor.inkWeak)
            }
            .padding(PixelSpacing.cardPadding)
            .background(PixelColor.surface)
            .pixelBorder()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, PixelSpacing.screenMargin)
    }

    // MARK: - CTA

    @ViewBuilder
    private func ctaSection(_ play: Play) -> some View {
        VStack(spacing: PixelSpacing.m) {
            PixelButton(title: "시작점으로 가기", style: .plain) {
                openNavigation(to: play)
            }
            PixelButton(title: vm.hasProgress ? "이어서 하기" : "PLAY 시작", style: .primary) {
                showRunner = true
            }
        }
        .padding(PixelSpacing.screenMargin)
        .padding(.bottom, PixelSpacing.xxl)
    }

    /// 외부 지도 앱으로 넘긴다. 우리가 길찾기를 만들지 않는다 —
    /// 검증된 보행 경로가 없으면 직선으로 이어 길처럼 보이게 하지 않는다(`데이터.md` §5).
    private func openNavigation(to play: Play) {
        guard let c = play.startCoordinate else { return }
        let app = "comgooglemaps://?daddr=\(c.latitude),\(c.longitude)&directionsmode=walking"
        if let url = URL(string: app), UIApplication.shared.canOpenURL(url) {
            openURL(url); return
        }
        if let web = URL(string:
            "https://www.google.com/maps/dir/?api=1&destination=\(c.latitude),\(c.longitude)") {
            openURL(web)
        }
    }

    private var failedView: some View {
        VStack(spacing: PixelSpacing.s) {
            PixelIcon(.warn, size: 40, color: PixelColor.locked)
            Text("PLAY 를 불러오지 못했어요.")
                .font(PixelFont.body)
                .foregroundStyle(PixelColor.inkWeak)
        }
        .frame(maxWidth: .infinity)
        .padding(PixelSpacing.xxxl)
    }
}

// MARK: - 경로 지도

/// PLAY 상세의 작은 지도. **지도 탭과 다른 물건이다** —
/// 저쪽은 "제주 어디서 할 수 있나", 이쪽은 "이 PLAY 는 어디를 도나".
///
/// ⚠️ Point 를 직선으로 잇지 않는다. 검증된 보행 경로가 없는데 선을 그으면
/// 걸을 수 있는 길처럼 읽힌다 (`데이터.md` §5).
struct PlayRouteMap: View {
    let play: Play

    private var region: MKCoordinateRegion {
        let coords = play.points.compactMap(\.coordinate)
        guard !coords.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 33.38, longitude: 126.55),
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
        }
        let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2)
        // 최소 범위를 줘야 Point 가 붙어 있는 성읍에서 지도가 과하게 확대되지 않는다.
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 2.2, 0.004),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 2.2, 0.004))
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: [.pan, .zoom]) {
            ForEach(Array(play.points.enumerated()), id: \.element.id) { i, point in
                if let c = point.coordinate {
                    Annotation(point.title, coordinate: c) {
                        Text("\(i + 1)")
                            .font(PixelFont.label)
                            .foregroundStyle(PixelColor.onPrimary)
                            .frame(width: 26, height: 26)
                            .background(PixelColor.primary)
                            .pixelBorder()
                    }
                }
            }
        }
    }
}

// MARK: - 뷰모델

@MainActor
final class PlayDetailViewModel: ObservableObject {
    @Published var play: Play?
    @Published var thumbnail: String?
    @Published var failed = false
    @Published var hasProgress = false

    func load(playId: String) async {
        if play != nil { refreshProgress(playId: playId); return }
        do {
            play = try await PlayAPI.detail(id: playId)
            // 사진은 목록 응답에만 있다. 상세를 무겁게 만들지 않으려고 따로 가져온다.
            thumbnail = try? await PlayAPI.list().first { $0.id == playId }?.thumbnail
        } catch {
            failed = true
        }
        refreshProgress(playId: playId)
    }

    private func refreshProgress(playId: String) {
        hasProgress = PlayProgressStore.shared.load(playId: playId) != nil
    }
}
