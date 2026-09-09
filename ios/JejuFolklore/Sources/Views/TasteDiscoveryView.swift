import SwiftUI

// MARK: - 코스 탭의 색 쓰임
//
// 전에는 **선택된 것이 전부 초록**이었다 — 권역 버튼도, 기간 칩도, 코스 카드 배지도,
// 탭바도. 다 같은 색이면 화면에서 아무것도 강조가 아니게 되고, 무엇이 입력이고
// 무엇이 결과인지 색이 알려주지 못한다. 게다가 배경 픽셀 지도가 초록·파랑이라
// 초록 버튼은 그림에 묻힌다.
//
// 그래서 초록이 겸하던 세 가지 역할을 쪼갰다 (2026-09-09 조익준님 결정).
//
//     고르는 것 (기간)        금색   지도의 초록·파랑과 겹치지 않아 확실히 떠오른다
//     결과 (코스 카드)        파랑   내가 고른 것이 아니라 받아 본 것
//     실행 (플레이·탐험 시작)  초록   앱의 브랜드색. 진짜 행동에만 남긴다
//
// **권역만 금색에서 빠졌다** (2026-09-09 조익준님 결정). 권역은 「고르는 자리」이기
// 전에 **이름**이라, 앱 전체에서 권역마다 제 색을 갖는다 — 동부 주황, 서부 보라,
// 북부 파랑, 남부 청록, 전체 잉크. 코스 카드 배지·이 화면의 권역 버튼·지도 탭
// 권역 칩이 같은 색을 쓴다. 색 값과 배정 이유는 `PixelColor` 에 있다.
// 기간 칩은 이름이 아니라 조건이라 금색으로 남는다.
//
// 금색은 팔레트에 이미 「강조 — 스티커 배지·CTA」로 용도가 적혀 있었는데
// (`PixelColor.accent`) 이 화면에서 한 번도 쓰이지 않고 있었다.

// MARK: - TasteDiscoveryView

struct TasteDiscoveryView: View {
    @StateObject private var vm = CourseRecommendViewModel()
    @State private var selectedRegion = ""
    @State private var selectedDays: Int?
    @State private var navigateToList = false
    /// 둘러보기 카드로 들어간 코스. 추천 결과 목록을 거치지 않고 바로 상세로 간다.
    @State private var navigateToFeatured = false

    /// 라벨은 "박N일" — 데이터는 `duration_days`(여행 일수)라 1 = 당일치기다.
    /// 백엔드가 ±1일 오차를 허용해서, "3박4일 이상" 하나가 4~6일 코스를 다 담는다.
    private let durationOptions: [(days: Int, label: String)] = [
        (1, "당일치기"), (2, "1박2일"), (3, "2박3일"), (5, "3박4일 이상"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PixelSpacing.sectionGap) {
                    header
                    selectSection
                    featuredSection
                }
                .padding(.horizontal, PixelSpacing.screenMargin)
                .padding(.top, PixelSpacing.xl)
                .padding(.bottom, PixelSpacing.xxxl)
            }
            .background(PixelColor.background.ignoresSafeArea())
            .navigationBarHidden(true)
            // 당겨서 새로고침 = 둘러보기 목록 갈아 끼우기. 홈 탭과 같은 방식이다.
            .refreshable { await vm.loadFeatured() }
            .task { if vm.featured.isEmpty { await vm.loadFeatured() } }
            .navigationDestination(isPresented: $navigateToList) {
                CourseListView(vm: vm)
                    .onDisappear {
                        if vm.courseList.isEmpty { vm.reset() }
                    }
            }
            .navigationDestination(isPresented: $navigateToFeatured) {
                if let course = vm.selectedCourse {
                    CoursePreviewView(course: course)
                }
            }
            // 둘러보기 상세에서 돌아오면 고른 코스를 비운다. 남겨두면 나중에
            // 권역·기간으로 들어간 추천 목록이 「이미 코스를 고른 상태」로 오해한다.
            .onChange(of: navigateToFeatured) {
                if !navigateToFeatured { vm.selectedCourse = nil }
            }
        }
    }

    // MARK: - Header

    /// 이 화면이 무엇을 하는 곳인지 말하는 자리.
    ///
    /// 퀘스트 탭 인트로 카드와 **같은 문법**이되 배치를 뒤집었다 — 퀘스트는 아이콘이
    /// 제목 위에 있고 여기는 옆에 있다 (2026-09-09 조익준님 결정). 같은 앱으로 보이면서
    /// 화면끼리 구분은 되게 하려는 것이다.
    private var header: some View {
        // 강조 낱말은 **쨍한 금색**이다. 흰 바탕 위 대비는 1.57:1 로 낮지만,
        // 강조는 장식이고 뜻은 검은 글자가 이미 다 전한다.
        // (권역 버튼도 한때 이 금색이었지만 지금은 권역마다 제 색을 쓴다.)
        PixelIntroCard(
            // 나침반은 아래 섹션 머리로 내려갔다. 여기는 「걷는 사람」 —
            // 바로 아래 문장이 먼저 다녀간 사람들의 발자국 얘기다.
            icon: .walk,
            iconColor: PixelColor.accent,
            // 「탐험」을 여기서 쓰지 않는다 (2026-09-09 조익준님 결정). 탐험이 실제로
            // 시작되는 자리는 코스를 고른 뒤(`CourseListView` — 「골라 탐험을 시작해보세요」)
            // 이고, 이 화면은 아직 떠나기 전이다. 진입에서 미리 써버리면 정작 시작
            // 지점에서 힘이 빠졌다. 세 탭이 같은 세계의 다른 단계를 말하게 나눴다.
            //
            //     홈    관광지를 플레이하세요   현장에서 실행
            //     지도  (지도 탭 참조)          섬에 무엇이 열려 있나
            //     코스  어느 쪽으로 떠날까요     아직 떠나기 전
            //
            // 아이콘이 나침반(`.compass`)이라 「어느 쪽」과 그림이 맞는다.
            title: Text("어느 쪽으로 ")
                + Text("떠날까요").foregroundColor(PixelColor.accent),
            // 「발자국」은 지어낸 설정이 아니라 사실 그대로다 — 실제로 제주를 다녀간
            // 사람들의 여행 일정이 이 화면의 데이터다. 게임 말이면서 거짓말이 아니다.
            //
            // ⚠️ 「천여 건」은 `curated_courses` 1,255개다 — 원본 여행 일정 9,134개에서
            // 중복 장소·빈 날짜를 걷어내고 남은 수. **「9천 건」이라고 쓰면 거짓말이 된다.**
            // **「여행자 천 명」이라고도 쓰지 않는다** — 코스 1,255개는 사람 1,255명이
            // 아니다. 「검증된 경로」도 쓰지 않는다 — 우리가 검증한 게 아니라 실제 기록이다.
            //
            // 「여행자들의」를 뺐다 (2026-09-09) — 넣었더니 실제 화면에서 줄바꿈이
            // 「…발자국 천여 / 건에서」로 떨어져 수와 단위가 갈라졌다. 누구의
            // 발자국인지는 「먼저 다녀간」이 이미 말한다.
            message: Text("먼저 다녀간 ")
                + Text("발자국 천여 건").foregroundColor(PixelColor.accent)
                + Text("에서 길을 찾아드려요")
        )
    }

    // MARK: - 권역 & 기간 선택

    /// 지도·기간 칩·「코스 찾기」가 **한 섹션**이다 (2026-09-09 조익준님 결정).
    ///
    /// 전에는 「권역」·「기간」이라는 작은 회색 라벨이 각각 따로 붙어 있었다. 둘은
    /// 서로 다른 일이 아니라 **한 질문의 두 칸**이고, 그 답을 확정하는 버튼까지가
    /// 한 덩어리다. 머리 모양은 퀘스트 탭과 같은 제목 + 잉크 4px 밑줄이다.
    private var selectSection: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
            // 나침반이 인트로 카드에서 여기로 내려왔다 (2026-09-09 조익준님 결정).
            // 퀘스트 탭 헤더에는 초록 아이콘이 있는데 코스 탭만 맨 글자라 허전했다.
            // 인트로 카드는 대신 「걷는 사람」을 쓴다 — 서브텍스트가 발자국 얘기다.
            //
            // 아이콘 색은 **쨍한 금색**(`accent`)이다 — 인트로 카드의 잉크 블록 위
            // 아이콘, 기간 칩과 같은 금색으로 맞춘다 (2026-09-09 조익준님 결정).
            // 흰 바탕 대비는 낮지만 아이콘은 장식이고 뜻은 제목이 다 전한다.
            PixelSectionHeader(title: "권역 & 기간 선택",
                               icon: .compass,
                               iconColor: PixelColor.accent,
                               underline: PixelSpacing.borderHeavy)

            JejuOverworldPicker(selected: selectedRegion) { region in
                selectedRegion = region
            }

            durationChips
            searchButton
        }
    }

    /// 기간 칩은 **2×2** 다 (2026-09-09 조익준님 결정). 한 줄에 넷을 밀어 넣으면
    /// 「3박4일 이상」이 칸에 겨우 들어가 글자를 작게 유지할 수밖에 없었고,
    /// 그래서 이 줄만 화면에서 급이 낮아 보였다. 두 줄로 풀어 글자를 키웠다.
    private var durationChips: some View {
        VStack(spacing: PixelSpacing.s) {
            ForEach(Array(durationOptions.chunked(2).enumerated()), id: \.offset) { _, row in
                HStack(spacing: PixelSpacing.s) {
                    ForEach(row, id: \.days) { option in
                        let on = selectedDays == option.days
                        Button {
                            selectedDays = option.days
                        } label: {
                            Text(option.label)
                                .font(PixelFont.label)
                                .multilineTextAlignment(.center)
                                .foregroundColor(on ? PixelColor.onAccent : PixelColor.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: PixelSpacing.buttonHeight)
                                .background(on ? PixelColor.accent : PixelColor.surface)
                                .pixelBorder(PixelColor.ink,
                                             width: on ? PixelSpacing.borderHeavy : PixelSpacing.border)
                                .pixelShadow(on ? PixelSpacing.shadowCard : PixelSpacing.shadowSmall)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                }
            }
        }
    }

    // MARK: - 이런 코스는 어때요?

    /// 권역·기간을 고르기 전에도 볼 게 있어야 한다. 「추천」이라고 부르지 않는다 —
    /// 사용자 취향을 반영하지 않고 큐레이션 목록에서 무작위로 뽑은 것이라,
    /// 추천이라고 쓰면 실제로 하는 일과 다른 말이 된다.
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
            // 위 「권역 & 기간 선택」과 **같은 머리**다 — 제목 + 잉크 4px 밑줄.
            // 결과는 파랑이다 — 이 화면의 색 규칙(고르는 것 금색 / 결과 파랑 /
            // 실행 초록)을 섹션 아이콘에도 그대로 쓴다.
            PixelSectionHeader(title: "이런 코스는 어때요?",
                               icon: .star,
                               iconColor: PixelColor.secondary,
                               underline: PixelSpacing.borderHeavy) {
                // 권역 버튼과 같은 모양 — 흰 면에 잉크 테두리와 각진 그림자.
                // 전에는 테두리 없는 맨 글자라 눌리는 것인지 설명인지 구분이 안 됐다.
                Button {
                    Task { await vm.loadFeatured() }
                } label: {
                    HStack(spacing: PixelSpacing.xs) {
                        PixelIcon(.refresh, size: 14)
                        Text("다른 코스")
                    }
                    .font(PixelFont.labelSmall)
                    .foregroundColor(PixelColor.ink)
                    .padding(.horizontal, PixelSpacing.s)
                    .padding(.vertical, PixelSpacing.xs)
                    .background(PixelColor.surface)
                    .pixelBorder()
                    .pixelShadow(PixelSpacing.shadowSmall)
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoadingFeatured)
            }

            if vm.featured.isEmpty {
                Text(vm.isLoadingFeatured ? "코스를 가져오는 중이에요" : "코스를 가져오지 못했어요. 당겨서 새로고침해 주세요.")
                    .font(PixelFont.body)
                    .foregroundColor(PixelColor.inkWeak)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, PixelSpacing.xl)
            } else {
                LazyVStack(spacing: PixelSpacing.cardGap) {
                    ForEach(vm.featured) { course in
                        CourseCard(course: course) {
                            Task { await openFeatured(course) }
                        }
                    }
                }
                .opacity(vm.isLoadingFeatured ? 0.5 : 1)
            }
        }
    }

    private func openFeatured(_ course: CourseListItem) async {
        await vm.fetchDetail(courseId: course.id)
        if vm.selectedCourse != nil { navigateToFeatured = true }
    }

    // MARK: - 코스 찾기 버튼

    /// 권역·기간이 **둘 다** 채워져야 켜진다.
    ///
    /// 전에는 둘째 칸을 채우는 순간 화면이 저절로 넘어갔다 (2026-09-09 조익준님 결정으로
    /// 걷어냄). 고르는 도중에 화면이 바뀌어서, 기간을 먼저 눌러 보고 권역을 고민하거나
    /// 고른 걸 바꿔 보는 일이 안 됐다 — 마지막 한 번의 탭이 곧 되돌릴 수 없는 이동이었다.
    /// 고르는 일과 떠나는 일을 갈라놓는다.
    private var searchButton: some View {
        let ready = !selectedRegion.isEmpty && selectedDays != nil
        return Button {
            guard let days = selectedDays else { return }
            Task { await startSearch(days: days) }
        } label: {
            Text(buttonTitle)
                .font(PixelFont.label)
                // 실행은 초록이다 — 이 화면에서 진짜 「간다」는 행동은 이것 하나뿐이다.
                .foregroundColor(ready ? PixelColor.onPrimary : PixelColor.inkWeak)
                .frame(maxWidth: .infinity)
                .frame(height: PixelSpacing.buttonHeight)
                .background(ready ? PixelColor.primary : PixelColor.surface)
                .pixelBorder(ready ? PixelColor.ink : PixelColor.outlineVariant)
                // 꺼져 있을 때는 그림자도 없다. 눌리는 것과 안 눌리는 것이
                // 색만이 아니라 **떠 있는 정도**로도 갈린다.
                .pixelShadow(ready ? PixelSpacing.shadowButton : 0, downOnly: true)
        }
        .buttonStyle(.plain)
        // ⚠️ `.disabled` 를 쓰지 않는다. SwiftUI 가 버튼 **전체**를 흐리게 덮어서
        // 흰 면 + 회색 테두리로 그린 꺼짐 상태가 잿빛 덩어리가 된다 — 픽셀 톤에서
        // 제일 눈에 걸리는 모양이다. 누름만 막고 색은 우리가 직접 정한다.
        .allowsHitTesting(ready)
        .accessibilityAddTraits(ready ? [] : [.isButton])
        .accessibilityHint(ready ? "" : "권역과 기간을 모두 고르면 눌러 코스를 찾을 수 있어요")
    }

    /// 꺼져 있을 때는 **무엇이 비었는지** 말한다. 「코스 찾기」를 회색으로만 두면
    /// 왜 안 눌리는지 사용자가 화면을 훑어 스스로 찾아내야 한다.
    private var buttonTitle: String {
        switch (selectedRegion.isEmpty, selectedDays == nil) {
        case (true, true):   return "권역과 기간을 골라주세요"
        case (true, false):  return "권역을 골라주세요"
        case (false, true):  return "기간을 골라주세요"
        case (false, false): return "코스 찾기"
        }
    }

    // MARK: - Actions

    private func startSearch(days: Int) async {
        vm.selectedRegion = selectedRegion
        vm.durationDays = days
        navigateToList = true
        await vm.fetchList()
    }
}

// MARK: - 픽셀 제주 지도 권역 선택

/// 그림 한 장 위에 권역 버튼을 얹은 지도.
///
/// 전에는 애플 지도(MKMapView)에 권역 사각형을 색칠하고 탭 좌표로 판별했다.
/// 「고르는 화면은 픽셀」(CLAUDE.md 세 축)이라 그림으로 바꿨다 — 실사 지도가
/// 필요한 곳은 현장에서 대조하는 화면이지 여행 전 고르는 화면이 아니다.
///
/// 권역 경계 판별은 더 이상 좌표로 하지 않는다. 버튼을 직접 누르므로
/// `JejuRegionDef.contains` 같은 GPS 판별이 이 화면에는 필요 없다
/// (그 정의는 지도 탭이 계속 쓴다).
struct JejuOverworldPicker: View {
    /// 「제주 전역」. 백엔드가 받는 값 그대로다 (`region = "전체"`).
    static let wholeIslandID = "전체"

    let selected: String
    let onSelect: (String) -> Void

    /// 그림 원본 1200×896. 비율이 어긋나면 버튼이 엉뚱한 데 붙는다.
    private static let imageAspect: CGFloat = 1200.0 / 896.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Image("jeju-overworld")
                    .resizable()
                    // ⚠️ 픽셀아트는 보간을 끈다. 켜두면 도트가 뭉개져 흐린 그림이 된다.
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                ForEach(RegionSpot.all, id: \.id) { spot in
                    // 네 버튼의 **너비를 묶는다** (2026-09-09 조익준님 결정).
                    // 글자 길이대로 두면 「제주시」와 「성산·구좌」의 폭이 달라
                    // 지도 위에서 크기가 들쭉날쭉해 보인다. 화면 폭에 비례시켜
                    // 작은 기기에서도 글자가 안 잘리게 한다.
                    button(for: spot, width: geo.size.width * 0.21)
                        .position(x: geo.size.width * spot.x,
                                  y: geo.size.height * spot.y)
                }
            }
        }
        .aspectRatio(Self.imageAspect, contentMode: .fit)
        .pixelBorder(width: PixelSpacing.borderHeavy)
    }

    /// 표식은 **평소 흰 바탕, 고른 것만 그 권역의 색**이다
    /// (2026-09-09 조익준님 결정).
    ///
    /// 다섯을 늘 색칠해 봤더니 픽셀 그림 위에 색 덩어리 다섯 개가 얹혀 그림을
    /// 이겨버렸다. 흰 표식은 그림 위에 얹힌 이름표로 읽히고, 고른 하나만 색이
    /// 들어오면 「지금 여기」가 한눈에 잡힌다.
    ///
    /// 「전역」도 같은 규칙이다 — 혼자만 늘 검으면 이미 골라진 것처럼 보인다.
    private func button(for spot: RegionSpot, width: CGFloat) -> some View {
        let on = selected == spot.id
        let c = JejuRegionDef.colors(for: spot.id)
        return Button {
            onSelect(spot.id)
        } label: {
            VStack(spacing: 1) {
                Text(spot.label)
                    .font(PixelFont.labelSmall)
                    .foregroundColor(on ? c.on : PixelColor.ink)
                Text(spot.sublabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(on ? c.on : PixelColor.inkWeak)
            }
            .frame(width: width)
            .padding(.vertical, PixelSpacing.xs)
            .background(on ? c.fill : PixelColor.surface)
            .pixelBorder()
            .pixelShadow(PixelSpacing.shadowSmall)
        }
        .buttonStyle(.plain)
        .pixelBob(delay: spot.bobDelay)
        .accessibilityLabel("\(spot.label) \(spot.sublabel)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// 그림 위에서 버튼이 앉는 자리. 가로·세로 **비율**이라 화면 크기가 달라져도 안 밀린다.
///
/// ⚠️ 눈으로 잡은 값이다. 배경 그림(`jeju-overworld`)을 바꾸면 이 값도 같이 봐야 한다.
/// 마을·숲·화산을 피해 빈 초원에 앉히는 것이 기준이다 — 그림을 가리지 않으려고.
private struct RegionSpot {
    let id: String
    let label: String
    let sublabel: String
    let x: CGFloat
    let y: CGFloat
    /// 떠다니기 시작을 어긋나게 하는 시간(초). 넷이 같이 오르내리면 살아 있다기보다
    /// 화면이 흔들리는 것처럼 보인다.
    let bobDelay: Double

    /// ⚠️ 「전역」이 다섯 번째 표식으로 **그림 안 우하단 바다**에 앉는다
    /// (2026-09-09 조익준님 결정). 전에는 그림 아래에 가로로 긴 흰 막대였는데,
    /// 그게 픽셀 그림을 깔고 앉아 지도 카드가 「그림」도 「컨트롤」도 아닌 물건이
    /// 됐다. 이제 다섯 개가 같은 크기·같은 문법의 표식이다.
    ///
    /// 라벨이 「전역 / 제주 전체」인 것은 네 권역과 **줄 수를 맞추기 위해서**다.
    /// 「제주 전역」 한 줄로 두면 이 표식만 높이가 달라진다.
    static let all: [RegionSpot] = [
        RegionSpot(id: "북부", label: "북부", sublabel: "제주시",    x: 0.44, y: 0.20, bobDelay: 0.0),
        RegionSpot(id: "동부", label: "동부", sublabel: "성산·구좌", x: 0.82, y: 0.44, bobDelay: 0.45),
        RegionSpot(id: "서부", label: "서부", sublabel: "한림·애월", x: 0.16, y: 0.46, bobDelay: 0.9),
        RegionSpot(id: "남부", label: "남부", sublabel: "서귀포",    x: 0.46, y: 0.72, bobDelay: 1.35),
        RegionSpot(id: JejuRegionDef.wholeIslandID,
                   label: "전역", sublabel: "제주 전체",             x: 0.85, y: 0.82, bobDelay: 1.8),
    ]
}


private extension Array {
    /// `n` 개씩 묶는다. 기간 칩을 2×2 로 놓을 때 쓴다.
    func chunked(_ n: Int) -> [[Element]] {
        stride(from: 0, to: count, by: n).map { Array(self[$0..<Swift.min($0 + n, count)]) }
    }
}
