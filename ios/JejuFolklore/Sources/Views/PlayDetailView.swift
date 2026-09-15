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
/// ## 시안을 1:1로 옮긴 것이다 (2026-09-03)
///
/// `stitch_pixel_travel_quest (2)/code.html` 을 그대로 옮겼다. 홈에서 배운 것을
/// 따른다 — **크기를 우리 토큰 이름으로 "번역"하지 않고 시안에 적힌 px 를 쓴다.**
///
///     div.border-4.p-4.pixel-shadow              큰 카드 하나가 화면 전체를 감싼다
///       div.aspect-[1.34].border-4               커버
///       div.bg-surface-container-low.border-2    설명
///       grid-cols-2 gap-4                        예상시간 · 거리 · 난이도 · Missions
///       div.bg-surface-container-low.border-2    탐험 경로 안내
///     fixed bottom                               [장소 정보 보기] · [복원 시작]
///
/// 색은 시안 클래스 → 우리 토큰으로 **관계를 지켜서** 옮겼다. 시안의 `surface`
/// (#fbf8ff)를 우리 `background` 로 읽고 카드를 `surface` 로 두면 다크 모드에서
/// 종이와 바탕이 뒤집힌다. 「바탕 = background · 종이 = surface · 종이 안의 상자
/// = surfaceLow」로 맞췄다 — 홈이 쓰는 짝과 같다.
///
/// ## 시안에서 바꾼 것 (2026-09-03 조익준님 결정)
///
/// 1. 머리를 다시 배치했다 — 커버 위에 제목 카드가 걸쳐 올라온다.
/// 2. 제목 위 소제목 「성읍민속마을」을 뺐다. 상단 내비게이션 바가 이미 그 이름이다.
/// 3. 시안의 빈 노란 배지를 `MAIN QUEST` 배지로 바꿨다.
/// 4. 경로 상자의 픽셀 그림을 **실제 지도**로 바꿨다 (`PlayRouteMap`).
/// 5. 「시작 전에 꼭 읽어주세요」를 뺐고, `[장소 정보 보기]` 를 아래 고정 바로 올렸다.
struct PlayDetailView: View {
    let playId: String

    @StateObject private var vm = PlayDetailViewModel()
    @State private var showRunner = false
    @State private var showResetConfirm = false

    /// 커버 비율. 시안은 1.34 였는데 **첫 화면에 스탯 4개까지 들어오게** 납작하게
    /// 눌렀다 (2026-09-03 조익준님 요청). 위쪽 하늘이 조금 잘리고, 아래 3분의 1은
    /// 어차피 제목 카드가 덮는다 — 마을 풍경은 그대로 남는다.
    private let coverAspect: CGFloat = 1.75

    /// 이 화면에서는 탭바를 숨긴다 — 아래 바가 두 겹으로 쌓여 화면의 4분의 1을 먹었다.
    /// 다른 탭으로 갈 화면이 아니고, 뒤로 가는 길은 위쪽 `Back` 이 갖고 있다.
    @Environment(\.tabBarVisibility) private var tabBar

    var body: some View {
        ScrollView {
            if let play = vm.play {
                PixelCard {
                    // 시안은 32 였다. 첫 화면 높이를 맞추려고 16 으로 조였다.
                    VStack(spacing: PixelSpacing.l) {
                        heroBlock(play)
                        descriptionBox(play)
                        statsGrid(play)
                        routeBox(play)
                        placeInfoBox(play)
                    }
                    .padding(PixelSpacing.cardPadding)       // p-4
                }
                .padding(.horizontal, PixelSpacing.l)        // px-4
                .padding(.top, PixelSpacing.m)
                .padding(.bottom, PixelSpacing.xxl)
            } else if vm.failed {
                failedView
            } else {
                ProgressView().padding(PixelSpacing.xxxl).frame(maxWidth: .infinity)
            }
        }
        .background(PixelColor.background)
        // 상단바를 통째로 걷어내고 픽셀 뒤로가기 버튼을 커버 그림 위에 얹는다.
        // 버튼이 그림 안에 들어가도록 「위 여백 + 카드 테두리 + 카드 안 여백 + 8」 만큼 내린다.
        .pixelFloatingBack(topInset: PixelSpacing.m + PixelSpacing.borderHeavy
                                     + PixelSpacing.cardPadding + PixelSpacing.s,
                           leadingInset: PixelSpacing.l + PixelSpacing.borderHeavy
                                     + PixelSpacing.cardPadding + PixelSpacing.s)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let play = vm.play { bottomBar(play) }
        }
        .onAppear { tabBar?.hide() }
        .onDisappear { tabBar?.show() }
        .task { await vm.load(playId: playId) }
        .fullScreenCover(isPresented: $showRunner) {
            if let play = vm.play {
                PlayRunnerView(play: play)
            }
        }
        // 현장에서 돌아오면 버튼 문구를 새로 읽는다 — 미션을 하나라도 끝냈으면
        // 「플레이하기」가 「이어서 하기」로 바뀐다.
        .onChange(of: showRunner) { if !showRunner { vm.refreshProgress(playId: playId) } }
    }

    // MARK: - 머리 (커버 + 걸쳐 올라온 제목 카드)

    /// 제목 카드는 **커버 그림의 정가운데**에 놓인다 (2026-09-03 조익준님 결정).
    ///
    /// 두 번 옮겼다. 처음엔 커버 아래 테두리를 넘어 걸쳐 나와 있었고, 다음엔
    /// 커버 안쪽 아래에 붙였다 — 위에 풍경이 130 이고 아래가 12 라 한쪽으로 쏠렸다.
    /// 가운데로 두면 위아래로 마을 풍경이 고르게 남는다.
    @ViewBuilder
    private func heroBlock(_ play: Play) -> some View {
        cover(play)
            .overlay(alignment: .center) {
                titleCard(play)
                    .padding(.horizontal, PixelSpacing.m)
            }
    }

    /// 시안 `div.aspect-[1.34].border-4`. 픽셀 커버가 1.34 비율(512×382)로 그려져 있다.
    ///
    /// **픽셀 커버가 있으면 그것을, 없으면 KTO 실사 사진을 쓴다** — 홈 카드와 같은 규칙.
    /// ⚠️ 픽셀아트는 `.interpolation(.none)` 이다. 기본 보간은 도트를 뭉갠다.
    @ViewBuilder
    private func cover(_ play: Play) -> some View {
        // 사진이 없을 때는 **놀멍봅서 기본 그림**을 깐다 (2026-09-10 조익준님 결정).
        // 회색 사진 아이콘은 「못 불러왔다」로 읽히는데, 대개는 KTO 에 등록되지
        // 않아 처음부터 없는 것이다. 코스 카드·장소 상세와 같은 장면을 쓴다.
        ZStack {
            PixelColor.secondaryContainer
            if let image = UIImage(named: play.placeKey) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFill()
            } else if let s = vm.thumbnail, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: Color.clear.overlay { PixelPlaceholderScene() }
                    default: PixelColor.secondaryContainer
                    }
                }
            } else {
                Color.clear.overlay { PixelPlaceholderScene() }
            }
        }
        .aspectRatio(coverAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .pixelBorder(width: PixelSpacing.borderHeavy)        // border-4
        .accessibilityHidden(true)
    }

    private func titleCard(_ play: Play) -> some View {
        VStack(spacing: PixelSpacing.s) {
            // 시안은 28(`headline-lg-mobile`)인데 「성읍 생활기록 복원작전」이 303pt 라
            // 두 줄로 접혔다. 24 에서 260pt — 한 줄에 들어간다.
            //
            // **26·25 로 두지 않는다.** 갈무리는 em 이 12 라 12·24 에서만 도트가 딱
            // 떨어지고, 그 사이 크기는 iOS 가 갈아 그려서 글자가 번진다.
            //
            // iPhone SE(375pt) 에서는 24 로도 5pt 가 부족해 `minimumScaleFactor` 가
            // 그때만 조금 줄인다. 그 밖의 기종은 24 그대로 선명하다.
            Text(play.title)
                .font(PixelFont.sectionTitle)                // headline-md 24
                .foregroundStyle(PixelColor.ink)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            mainQuestBadge
        }
        // 16 이면 글자 자리가 257pt 로 3pt 부족했다. 12 로 줄여 273pt 를 만든다.
        .padding(PixelSpacing.m)
        .frame(maxWidth: .infinity)
        .background(PixelColor.surface)
        .pixelBorder(width: PixelSpacing.border)
        .pixelShadow(PixelSpacing.shadowSmall)
    }

    /// ⚠️ 아직 **콘텐츠 데이터가 아니다.** `Play` 에 퀘스트 종류 항목이 없어서 문구를
    /// 여기 박아 뒀다. 서브 퀘스트가 생기면 데이터로 올려야 한다.
    private var mainQuestBadge: some View {
        Text("MAIN QUEST")
            .font(PixelFont.labelSmall)                      // label-sm 12
            .foregroundStyle(PixelColor.primary)
            .padding(.horizontal, PixelSpacing.s)
            .padding(.vertical, PixelSpacing.xs)
            .background(PixelColor.surfaceLow)
            .pixelBorder(width: PixelSpacing.border)
    }

    // MARK: - 설명

    /// 시안 `div.bg-surface-container-low.border-2.p-4.pixel-shadow` —
    /// 목표 한 문장(18).
    private func descriptionBox(_ play: Play) -> some View {
        VStack(alignment: .leading, spacing: PixelSpacing.l) {   // mb-4
            if !play.objective.isEmpty {
                // 시안은 18(`body-lg`)이었다. 첫 화면 높이를 맞추려고 16 으로 내렸다 —
                    // 다섯 줄이 네 줄로 접힌다.
                Text(play.objective)
                    .font(PixelFont.body)                        // 16
                    .foregroundStyle(PixelColor.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(PixelSpacing.cardPadding)                       // p-4
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixelColor.surfaceLow)
        .pixelBorder(width: PixelSpacing.border)
        .pixelShadow(PixelSpacing.shadowCard)
    }

    // MARK: - 스탯 2×2

    /// 시안 `grid grid-cols-2 gap-4`. 폰 폭에서는 두 칸씩 두 줄이다.
    private func statsGrid(_ play: Play) -> some View {
        VStack(spacing: PixelSpacing.m) {
            HStack(spacing: PixelSpacing.m) {
                statBox(.clock, play.durationText, "예상 시간", PixelColor.primary)
                // 시안은 `route` 아이콘인데 클래식 Material Icons 에 없다.
                // 걷는 사람으로 둔다 — 홈 카드의 거리 표시와 같은 아이콘이다.
                statBox(.walk, play.distanceText, "거리", PixelColor.secondary)
            }
            HStack(spacing: PixelSpacing.m) {
                statBox(.star, play.difficulty, "난이도", PixelColor.tertiary)
                statBox(.check, "\(play.missionCount)", "Missions", PixelColor.error)
            }
        }
    }

    /// 장소 관광정보(KTO)로 가는 문. **탐험 경로 안내 아래**에 둔다
    /// (2026-09-03 조익준님 결정).
    ///
    /// 두 번 옮겼다. 아래 고정 바에서는 `플레이하기` 와 같은 자리를 다퉈 눌리지
    /// 않았고, 스탯 격자에 넣으니 「사실 값」 네 칸 사이에 「이동」 한 칸이 섞였다.
    /// 지도와 주차장 이름이 있는 경로 상자 다음이 「이 장소 자체」로 관심이 넘어가는
    /// 지점이다.
    ///
    /// 문구는 장소 이름을 쓴다 — 「장소 정보 보기」는 어느 장소인지 안 말해준다.
    private func placeInfoBox(_ play: Play) -> some View {
        NavigationLink {
            PlaceDetailView(place: CoursePlace(
                name: play.placeName,
                lat: play.startCoordinate?.latitude ?? 0,
                lng: play.startCoordinate?.longitude ?? 0,
                day: 0
            ))
        } label: {
            // 앞에 아이콘을 두지 않는다 (2026-09-03 조익준님 결정). 책 아이콘도
            // 픽셀 커서 ▶ 도 걸쳐 봤는데, 「누를 수 있다」는 이미 **채운 파랑 ·
            // 아래로만 던지는 그림자 · 누르면 가라앉기 · 「보러가기」라는 동작 문구**
            // 네 가지가 말하고 있다. 글자만 가운데 두는 쪽이 조용하다.
            HStack(spacing: PixelSpacing.s) {
                Text("\(play.placeName) 정보 보러가기")
                    .font(PixelFont.bodyLargeBold)               // 스탯 숫자와 같은 18 볼드
                    .foregroundStyle(PixelColor.onSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(PixelSpacing.m)
            // **파랑을 채운다** (2026-09-03 조익준님 결정).
            //
            // 가라앉은 흰 바탕은 바로 위 경로 상자와 색이 같아서 상자 무리에
            // 섞여 보였다. 팔레트에서 파랑은 「이동」이다 — 초록(`플레이하기`)이
            // 이 화면의 주 행동이고, 파랑은 다른 화면으로 가는 문이다.
            .background(PixelColor.secondary)
            .pixelBorder(width: PixelSpacing.border)
        }
        // **버튼 문법을 쓴다** — 그림자를 아래로만 던지고, 누르면 그림자 속으로
        // 가라앉는다. 이 화면의 다른 상자(설명·스탯·경로)는 카드라서 그림자를
        // 대각선으로 던진다. 그 차이가 「이건 누를 수 있다」를 형태로 말해준다.
        .buttonStyle(PixelPressStyle())
    }

    private func statBox(_ icon: PixelIcon.Glyph, _ value: String,
                         _ label: String, _ tint: Color) -> some View {
        VStack(spacing: PixelSpacing.xs) {
            PixelIcon(icon, size: 30, color: tint)               // text-3xl
            Text(value)
                .font(PixelFont.sectionTitle)                    // headline-md 24
                .foregroundStyle(PixelColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(PixelFont.labelSmall)                      // label-sm 12
                .foregroundStyle(PixelColor.inkWeak)
        }
        .frame(maxWidth: .infinity)
        .padding(PixelSpacing.s)
        .background(PixelColor.surface)
        .pixelBorder(width: PixelSpacing.border)
        .pixelShadow(PixelSpacing.shadowCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }

    // MARK: - 탐험 경로 안내

    private func routeBox(_ play: Play) -> some View {
        VStack(alignment: .leading, spacing: PixelSpacing.l) {   // gap-4
            // 시안: 아이콘만 초록, 제목은 잉크, 밑줄은 잉크 2px.
            // `PixelSectionHeader` 를 쓰지 않는다 — 그쪽은 아이콘·제목·밑줄이 한 색이다.
            VStack(spacing: 0) {
                HStack(spacing: PixelSpacing.s) {                // gap-2
                    PixelIcon(.map, size: 24, color: PixelColor.primary)
                    Text("퀘스트 경로 안내")
                        .font(PixelFont.sectionTitle)            // headline-md 24
                        .foregroundStyle(PixelColor.ink)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, PixelSpacing.m)                // pb-3
                Rectangle()
                    .fill(PixelColor.ink)
                    .frame(height: PixelSpacing.border)          // border-b-2
            }

            // 시안은 이 자리에 커버와 똑같은 픽셀 마을 그림을 넣어 뒀다.
            // 실제로 어디를 도는지 보여주지 못하므로 지도로 바꿨다.
            PlayRouteMap(play: play)
                .frame(height: 200)
                .pixelBorder(width: PixelSpacing.border)

            VStack(spacing: PixelSpacing.s) {                    // gap-2
                RouteListRow(marker: "START", text: play.startName, kind: .terminal)
                ForEach(Array(play.points.enumerated()), id: \.element.id) { i, point in
                    RouteListRow(marker: "\(i + 1)", text: point.title, kind: .step)
                }
                RouteListRow(marker: "FINISH", text: play.finishName, kind: .terminal)
            }
        }
        .padding(PixelSpacing.cardPadding)                       // p-4
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixelColor.surfaceLow)
        .pixelBorder(width: PixelSpacing.border)
        .pixelShadow(PixelSpacing.shadowCard)
    }

    // MARK: - 아래 고정 바

    /// 시안대로 **버튼 하나만** 고정한다 (2026-09-03 조익준님 결정).
    ///
    /// 한동안 `[장소 정보 보기]` 를 위에 얹어 뒀는데, 같은 자리에서 `[플레이하기]` 와
    /// 경쟁하니 눌리지 않았다. 그 문은 스탯 격자의 다섯째 칸으로 옮겼다.
    ///
    /// **진행 중일 때만, 버튼 아래에 「처음부터 다시 하기」를 작게 둔다**
    /// (2026-09-07 결정). 이어하기는 서비스 기본값으로 그대로 두되, 심사위원처럼
    /// 짧은 기간에 같은 PLAY 를 여러 번 훑어보는 사람에게 탈출구를 준다 — 안
    /// 그러면 진행 중엔 "이어서 하기"만 뜨고 처음부터 다시 볼 길이 앱 삭제뿐이었다.
    private func bottomBar(_ play: Play) -> some View {
        VStack(spacing: PixelSpacing.s) {
            startButton(play)
            if vm.hasProgress && !vm.isFinished {
                Button("처음부터 다시 하기") { showResetConfirm = true }
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
                    .buttonStyle(.plain)
            }
        }
        .padding(PixelSpacing.l)                                 // p-4
        .frame(maxWidth: .infinity)
        // 탭바를 숨겼으니 홈 인디케이터 자리까지 이 바가 채운다.
        // 안 하면 버튼 아래에 바탕색 띠가 남는다.
        .background(PixelColor.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            PixelColor.ink.frame(height: PixelSpacing.borderHeavy)   // border-t-4
        }
        .confirmationDialog("지금까지 진행한 게 사라져요. 처음부터 다시 할까요?",
                            isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("처음부터 다시 하기", role: .destructive) {
                PlayProgressStore.shared.clear(playId: playId)
                vm.refreshProgress(playId: playId)
                showRunner = true
            }
            Button("계속 이어서 하기", role: .cancel) {}
        }
    }

    private func startButton(_ play: Play) -> some View {
        Button {
            showRunner = true
        } label: {
            HStack(spacing: PixelSpacing.s) {
                PixelIcon(.play, size: 24, color: PixelColor.onPrimary)
                Text(vm.isFinished ? "다시 하기" : (vm.hasProgress ? play.resumeLabel : play.startLabel))
                    .font(PixelFont.sectionTitle)                // headline-md 24
                    .foregroundStyle(PixelColor.onPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // 옛 게임의 「PRESS START」 처럼 **화살표까지 한 덩어리로** 깜빡인다
            // (2026-09-03 조익준님 결정 — 떠오르던 bobbing 을 이것으로 바꿨다).
            // 초록 바탕과 테두리는 가만히 있고 안쪽 글자만 사라진다.
            .pixelBlink()
        }
        .buttonStyle(StartCTAStyle())
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

// MARK: - 시작 버튼 모양

/// 시안 `button.w-full.bg-primary.py-3.border-4.pixel-btn-shadow`.
///
/// `PixelButton` 을 쓰지 않는다 — 그쪽은 높이 48 에 글자가 14 라 시안(24)의 절반이다.
private struct StartCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, PixelSpacing.m)                  // py-3
            .background(PixelColor.primary)
            .pixelBorder(width: PixelSpacing.borderHeavy)        // border-4
            .pixelShadow(PixelSpacing.shadowButton, isPressed: configuration.isPressed)
    }
}

// MARK: - 경로 목록 줄

/// START·번호·FINISH 표. PLAY 상세의 경로 안내와 러너의 진행 지도
/// (`PlayRunnerView` 의 `ProgressMapSheet`)가 같이 쓴다.
enum RouteMarkerKind {
    case terminal   // START · FINISH
    case step       // 1 · 2 · 3 …

    /// 시안 `bg-amber-500` 은 Tailwind 기본 팔레트라 우리 테마에 없다.
    /// 별점 색처럼 이 자리에만 둔다.
    static let stepFill = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
    /// 시안은 주황 위에 흰 글자(`text-on-primary`)를 얹는데 대비가 2:1 밖에 안 된다.
    /// 시안 팔레트의 `on-tertiary-fixed`(#231B00)로 바꿨다 — 8:1 이 넘는다.
    static let stepLabel = Color(red: 0x23 / 255, green: 0x1B / 255, blue: 0x00 / 255)

    var fill: Color {
        switch self {
        case .terminal: return PixelColor.primary
        case .step:     return Self.stepFill
        }
    }
    var label: Color {
        switch self {
        case .terminal: return PixelColor.onPrimary
        case .step:     return Self.stepLabel
        }
    }
    /// 번호는 정사각형에 가깝게 맞춘다. START·FINISH 는 글자 길이만큼 늘어난다.
    var minWidth: CGFloat? {
        switch self {
        case .terminal: return nil
        case .step:     return 20
        }
    }
}

/// `done` 을 주면 완료색으로 칠하고 체크를 붙인다 — 러너 진행 지도가
/// "몇 번째까지 클리어했는지"를 보여줄 때 쓴다 (2026-09-07 추가).
struct RouteListRow: View {
    let marker: String
    let text: String
    let kind: RouteMarkerKind
    var done: Bool = false

    var body: some View {
        HStack(spacing: PixelSpacing.m) {                        // gap-3
            Text(marker)
                .font(PixelFont.labelSmall)                      // text-xs 12
                .foregroundStyle(done ? PixelColor.onDone : kind.label)
                .frame(minWidth: kind.minWidth)
                .padding(.horizontal, PixelSpacing.s)
                .padding(.vertical, 2)
                .background(done ? PixelColor.done : kind.fill)
                .pixelBorder(width: PixelSpacing.border)
                .pixelShadow(PixelSpacing.shadowSmall)
            Text(text.isEmpty ? "—" : text)
                .font(PixelFont.bodySmall)                       // text-sm 14
                .foregroundStyle(PixelColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if done {
                PixelIcon(.check, size: 18, color: PixelColor.primary)
            }
        }
        .padding(PixelSpacing.m)                                 // p-2.5 → 4의 배수로 12
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixelColor.surface)
        .pixelBorder(width: PixelSpacing.border)
        .accessibilityElement(children: .combine)
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
    /// 이미 CLEAR 한 기록이 있는지. 버튼 문구를 「이어서」 대신 「다시」로 바꾼다.
    @Published var isFinished = false

    func load(playId: String) async {
        if play != nil { refreshProgress(playId: playId); return }
        do {
            play = try await PlayAPI.detail(id: playId)
            // 사진은 목록 응답에만 있다. 상세를 무겁게 만들지 않으려고 따로 가져온다.
            // 픽셀 커버가 번들에 있으면 이건 안 쓰인다 — 없는 장소의 대비책이다.
            thumbnail = try? await PlayAPI.list().first { $0.id == playId }?.thumbnail
        } catch {
            failed = true
        }
        refreshProgress(playId: playId)
    }

    func refreshProgress(playId: String) {
        let saved = PlayProgressStore.shared.load(playId: playId)
        hasProgress = saved != nil
        isFinished = saved?.isFinished ?? false
    }
}
