import SwiftUI

struct CourseListView: View {
    @ObservedObject var vm: CourseRecommendViewModel
    @State private var navigateToPreview = false
    @State private var shouldLoadNext = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PixelColor.background.ignoresSafeArea()

            if vm.isLoadingList {
                loadingView
            } else if let err = vm.errorMessage, !vm.isLoadingDetail {
                errorView(err)
            } else if vm.courseList.isEmpty {
                emptyView
            } else {
                courseListContent
            }

            if vm.isLoadingDetail {
                LoadingOverlay(step: vm.loadingStep)
            }
        }
        // 시스템 상단바를 걷어낸다 — 회색 띠에 영어 "Back" 이 붙어 이 앱에서 혼자 이질적이다
        // (PLAY 상세·장소 상세와 같은 방식). 화면 제목은 아래 「당신을 위한 N가지 코스」가 한다.
        .pixelFloatingBack()
        .navigationDestination(isPresented: $navigateToPreview) {
            if let course = vm.selectedCourse {
                CoursePreviewView(
                    course: course,
                    hasNext: vm.hasNextCourse,
                    onNext: { shouldLoadNext = true },
                    onReset: { vm.reset() }
                )
            }
        }
        .onChange(of: navigateToPreview) {
            // 사용자가 PreviewView에서 뒤로 가면 selectedCourse 비워서 리스트 화면 복귀
            if !navigateToPreview {
                if shouldLoadNext {
                    shouldLoadNext = false
                    Task { await vm.advanceToNextCourse() }
                } else {
                    vm.selectedCourse = nil
                }
            }
        }
        .onChange(of: vm.selectedCourse) {
            if vm.selectedCourse != nil {
                navigateToPreview = true
            }
        }
        .alert("코스를 가져오지 못했어요", isPresented: Binding(
            get: { vm.errorMessage != nil && !vm.isLoadingList },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "다시 시도해주세요.")
        }
        // 탐험 완료 시 자신도 pop → TasteDiscoveryView(NavigationStack root)까지 연쇄적으로 복귀.
        .onReceive(NotificationCenter.default.publisher(for: .exploreDidComplete)) { _ in
            navigateToPreview = false
            dismiss()
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4)
            Text("AI가 코스를 추천하고 있어요...")
                .font(PixelFont.body)
                .foregroundColor(PixelColor.inkWeak)
        }
    }

    private func errorView(_ err: String) -> some View {
        VStack(spacing: 12) {
            PixelIcon(.warn, size: 48, color: PixelColor.locked)
            Text(err)
                .font(PixelFont.body)
                .multilineTextAlignment(.center)
                .foregroundColor(PixelColor.inkWeak)
            Button("다시 시도") {
                Task { await vm.fetchList() }
            }
            .buttonStyle(PixelButtonStyle(.primary))
        }
        .padding(32)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Text("추천 코스가 없어요.")
                .font(PixelFont.body)
                .foregroundColor(PixelColor.inkWeak)
            Button("처음으로") { vm.reset() }
                .buttonStyle(PixelButtonStyle(.primary))
        }
        .padding(32)
    }

    // MARK: - Top 3 List

    private var courseListContent: some View {
        VStack(spacing: 0) {
            // 헤더
            VStack(alignment: .leading, spacing: 4) {
                Text("당신을 위한 \(vm.courseList.count)가지 코스")
                    .font(PixelFont.sectionTitle)
                Text("마음에 드는 코스를 골라 탐험을 시작해보세요")
                    .font(PixelFont.body)
                    .foregroundColor(PixelColor.inkWeak)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            // 떠 있는 뒤로가기 버튼(8 + 36)이 제목을 덮지 않을 만큼 내린다.
            .padding(.top, PixelSpacing.xxxl + PixelSpacing.s)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(Array(vm.courseList.enumerated()), id: \.element.id) { index, course in
                        CourseCard(
                            course: course,
                            rank: index + 1,
                            onTap: {
                                Task { await vm.selectCourse(at: index) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            // 처음으로 버튼 (하단)
            Button {
                vm.reset()
            } label: {
                HStack(spacing: 6) {
                    PixelIcon(.refresh, size: 16)
                    Text("취향 다시 고르기")
                }
                .font(PixelFont.body)
                .foregroundColor(PixelColor.inkWeak)
                .padding(.vertical, 8)
            }
            .padding(.bottom, 12)
        }
    }
}

// MARK: - CourseCard

/// 코스 한 장. 추천 결과 목록(순위 있음)과 코스 탭 첫 화면의
/// 「이런 코스는 어때요?」(순위 없음)가 같이 쓴다.
struct CourseCard: View {
    let course: CourseListItem
    /// 추천 결과에서의 순위. 첫 화면 둘러보기는 순위가 없으므로 `nil` 이다 —
    /// 무작위로 뽑은 코스에 1·2·3 을 붙이면 순위가 있다고 거짓말하게 된다.
    var rank: Int? = nil
    let onTap: () -> Void

    /// 카드 맨 위 사진. **제목에 뜨는 그 장소**의 KTO 대표사진이다
    /// (2026-09-09 조익준님 결정) — 카드가 「곽지해수욕장 외 5곳」이라고 말하는데
    /// 사진이 딴 데면 카드가 두 말을 한다. 어느 장소인지는 서버가 정한다
    /// (`services/course_thumbnail.py`).
    ///
    /// 사진이 없으면 **권역색 한 판**을 깐다. 빈 회색 네모를 두면 「사진을 못
    /// 불러왔다」로 읽히는데, 실제로는 KTO 에 등록되지 않은 장소라 처음부터 없는
    /// 것이다. 색이 깔려 있으면 그 자체로 카드가 완성돼 보이고, 권역색이라
    /// 아래 배지와 같은 말을 한다.
    /// 사진 없을 때 깔 색. 권역색을 쓰되 **「전체」만 예외**다 —
    /// 「전체」의 권역색은 잉크(검정)라 배지 한 칸에서는 멀쩡하지만 120pt 짜리
    /// 판으로 깔면 카드가 검은 덩어리가 된다. 목록의 3할이 「전체」라 더 그렇다.
    /// 대신 가라앉은 면 색을 쓴다 — 「색을 안 정한 곳」이라는 뜻은 그대로다.
    private var coverColors: (fill: Color, on: Color) {
        let region = course.regionOrAll
        guard region != JejuRegionDef.wholeIslandID else {
            return (PixelColor.surfaceVariant, PixelColor.inkWeak)
        }
        return JejuRegionDef.colors(for: region)
    }

    @ViewBuilder
    private var cover: some View {
        let c = coverColors
        ZStack {
            c.fill
            if let url = course.thumbnail, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure:            PixelIcon(.mapPin, size: 32, color: c.on)
                    default:                  Color.clear
                    }
                }
            } else {
                PixelIcon(.mapPin, size: 32, color: c.on)
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .clipped()
        .pixelBorder(width: PixelSpacing.border)
        .accessibilityHidden(true)
    }

    // 코스에서 보여줄 대표 장소 최대 3개 (day 1 우선)
    private var previewPlaceNames: [String] {
        let day1 = course.places.filter { $0.day == 1 }
        let pool = day1.isEmpty ? course.places : day1
        return Array(pool.prefix(3)).map { $0.name }
    }

    /// 순위 배지는 **파랑**이다 — 초록은 「플레이·탐험 시작」 같은 실행에만 쓴다.
    /// 코스 카드는 내가 고른 것이 아니라 받아 본 결과라, 고르는 자리(금색)와도 구분한다.
    private var rankColor: Color {
        switch rank {
        case 1: return PixelColor.secondary
        case 2: return PixelColor.secondary.opacity(0.75)
        default: return PixelColor.secondary.opacity(0.55)
        }
    }

    /// 카드 왼쪽 배지. **화면에 따라 뜻이 다르다.**
    ///
    ///     추천 결과 목록   1·2·3   순위 (권역은 이미 내가 골랐으니 다시 말하지 않는다)
    ///     둘러보기 목록    서부    권역 (순위가 없으니 이 자리가 권역 이름표가 된다)
    ///
    /// 전에는 순위가 없을 때 **뜻 없는 핀 아이콘**이 들어갔다. 자리만 차지하고
    /// 아무것도 알려주지 않았다 (2026-09-09 조익준님 결정).
    @ViewBuilder
    private var leadingBadge: some View {
        if let rank {
            badgeBox(text: "\(rank)",
                     fill: rankColor,
                     on: rank == 1 ? PixelColor.onSecondary : PixelColor.ink)
        } else {
            let region = course.regionOrAll
            let c = JejuRegionDef.colors(for: region)
            badgeBox(text: region, fill: c.fill, on: c.on)
        }
    }

    /// 순위든 권역이든 **같은 높이**다. 두 목록을 오갈 때 카드 왼쪽 줄이 안 흔들린다.
    private func badgeBox(text: String, fill: Color, on: Color) -> some View {
        Text(text)
            .font(PixelFont.labelSmall)
            .foregroundColor(on)
            .lineLimit(1)
            .frame(minWidth: 28)
            .padding(.horizontal, PixelSpacing.xs + 1)
            .frame(height: 28)
            .background(fill)
            .clipShape(Rectangle())
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                cover

                // 헤더: 순위 + 제목
                HStack(alignment: .top, spacing: 10) {
                    leadingBadge

                    VStack(alignment: .leading, spacing: 2) {
                        // 제목에서 「서부 2일 · 」 접두사를 뗀다 — 권역은 왼쪽 배지가,
                        // 일수는 아래 줄이 이미 말한다. 세 곳에서 같은 말을 하고 있었다.
                        Text(course.title.isEmpty ? "이름 없는 코스" : course.placeHeadline)
                            .font(PixelFont.label)
                            .foregroundColor(PixelColor.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        // 곳수는 제목의 「외 N곳」이 이미 말한다. 여기서 또 세지 않는다.
                        HStack(spacing: 6) {
                            PixelIcon(.calendar, size: 14)
                            Text("\(course.durationDays)일 일정")
                        }
                        .font(PixelFont.labelSmall)
                        .foregroundColor(PixelColor.inkWeak)
                    }

                    Spacer()

                    PixelIcon(.forward, size: 16)
                        .foregroundColor(PixelColor.inkWeak)
                }

                // 대표 장소 칩
                if !previewPlaceNames.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(previewPlaceNames, id: \.self) { name in
                            Text(name)
                                .font(PixelFont.labelSmall)
                                .foregroundColor(PixelColor.ink)
                                .lineLimit(1)
                                .padding(.horizontal, PixelSpacing.s)
                                .padding(.vertical, PixelSpacing.xs + 1)
                                .background(PixelColor.surfaceLow)
                                .pixelBorder(PixelColor.outlineVariant)
                        }
                        if course.places.count > previewPlaceNames.count {
                            Text("+\(course.places.count - previewPlaceNames.count)")
                                .font(PixelFont.labelSmall)
                                .foregroundColor(PixelColor.inkWeak)
                                .padding(.horizontal, 8)
                        }
                        Spacer()
                    }
                }
            }
            .padding(PixelSpacing.cardPadding)
            // 시안의 카드다 — 얇은 회색 선이 아니라 잉크 테두리 + 각진 그림자.
            // 코스 탭 첫 화면에서 픽셀 버튼·칩과 나란히 서기 때문에 여기가 어긋나면
            // 카드만 다른 앱에서 가져온 것처럼 보인다.
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelColor.surface)
            .pixelBorder()
            .pixelShadow(PixelSpacing.shadowCard)
        }
        .buttonStyle(.plain)
    }
}
