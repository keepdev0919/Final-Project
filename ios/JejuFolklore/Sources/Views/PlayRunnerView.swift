import SwiftUI
import UIKit
import CoreLocation

/// 현장 진행 화면 — PLAY 를 실제로 하는 곳.
///
///     Point 도착 → Mission → Step 1..N → Discovery → Story → 다음 → FINAL → CLEAR
///
/// ## 지키는 것
///
/// - **GPS 는 정답 판정기가 아니다.** 거리를 보여줄 뿐이고, 진행은 `[도착했어요]` 가 한다.
///   성읍은 Point 사이가 52m 라 GPS(±10~30m)로는 구분할 수 없다.
/// - **위치 권한이 없어도 끝까지 갈 수 있다.** 거리 줄이 안 뜰 뿐이다.
/// - **Mission 하나 때문에 관광이 막히지 않는다.** 힌트 2단계 → 건너뛰기가 항상 있다.
/// - **못 찾는 것과 없는 것은 다르다.** 현장이 자료와 다르면 신고할 수 있다 —
///   현장 답사를 하지 않기로 했으므로(2026-09-02) 이 경로가 콘텐츠 QA 의 눈이다.
struct PlayRunnerView: View {
    let play: Play

    @StateObject private var vm: RunnerViewModel
    @StateObject private var location = LocationService.shared
    @StateObject private var audio = StoryAudioPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showQuit = false
    @State private var showReport = false
    /// 곱딱이가 말을 다 했는지. 미션 칸을 언제 띄울지 이걸로 정한다.
    @State private var speechDone = false

    init(play: Play) {
        self.play = play
        _vm = StateObject(wrappedValue: RunnerViewModel(play: play))
    }

    /// 화자 이름. **곱딱이** (2026-09-03 조익준님 결정).
    /// 초상화는 앱 아이콘의 픽셀 감귤이다.
    private static let speaker = "곱딱이"

    var body: some View {
        VStack(spacing: 0) {
            topHUD
            // 내용이 짧으면 아래에 붙어 있고, 길면(미션 보기 3개·긴 이야기)
            // 이 안에서 스크롤한다. 대화상자를 화면 위로 키우지 않는다.
            ScrollView {
                sceneBottom
            }
            .defaultScrollAnchor(.bottom)
            .scrollBounceBehavior(.basedOnSize)
        }
        // 배경은 `.background` 로 깐다 — ZStack 형제로 두면 그림이 화면 크기를
        // 정해 버려서 위에 얹은 것들이 밖으로 밀려난다.
        .background { PixelSceneBackground(imageName: play.placeKey) }
        .confirmationDialog("PLAY 를 그만할까요?", isPresented: $showQuit,
                            titleVisibility: .visible) {
            // ⚠️ 진행을 저장하지 않으므로 **여기서 나가면 사라진다.**
            // 「저장돼요」라고 써 두면 거짓말이 된다 (2026-09-04).
            Button("나가기 (진행은 사라져요)", role: .destructive) { dismiss() }
            Button("계속하기", role: .cancel) {}
        }
        .sheet(isPresented: $showReport) {
            MissionReportSheet(
                playId: play.id,
                playTitle: play.title,
                missionId: vm.currentMission?.id ?? play.final?.id ?? "",
                missionTitle: vm.currentMission?.title ?? play.final?.title ?? ""
            ) { showReport = false }
        }
        .onAppear {
            location.requestCurrentLocationOnce()
            // 지난번에 못 보낸 신고가 있으면 지금 보낸다.
            Task { await MissionReportStore.shared.flush() }
        }
        .onDisappear { audio.stop() }
    }

    // MARK: - 상단 HUD

    /// 배경 위에 떠 있는 세 칸 — 나가기 · 진행도 · 길찾기.
    ///
    /// **길찾기가 여기 있다** (2026-09-03 조익준님 결정). 전에는 「가는 중」 화면의
    /// 버튼 두 개 중 하나였는데, 시안에 이미 지도 버튼 자리가 있어서 옮겼다.
    /// 아래 버튼은 `[도착했어요]` 하나만 남아 무엇을 눌러야 하는지가 분명해진다.
    ///
    /// 성읍은 시작점 좌표가 아직 없고 Point 4개가 마을 안쪽 초가집이라,
    /// **외부 지도 길찾기가 「대장간집이 어디야」의 유일한 답이다.** 없애면 안 된다.
    private var topHUD: some View {
        HStack(spacing: PixelSpacing.s) {
            PixelHudButton(glyph: .back, label: "나가기") { showQuit = true }
            Spacer(minLength: 0)
            PixelHudProgress(
                label: play.progressLabel.isEmpty ? "진행" : play.progressLabel,
                total: play.progressRecords.count,
                done: vm.progress.discoveredRecordIds.count)
            Spacer(minLength: 0)
            if let point = vm.currentPoint, point.coordinate != nil {
                PixelHudButton(glyph: .map, label: "길찾기") { openNavigation(to: point) }
            } else {
                // 자리를 비워 둔다 — 없애면 가운데 진행도가 옆으로 밀린다.
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, PixelSpacing.xl)
        .padding(.top, PixelSpacing.s)
    }

    // MARK: - 아래 (정보판 + 말풍선 + 버튼)

    /// **대화창에는 곱딱이가 말하는 것만 넣는다** (2026-09-04 조익준님 결정).
    ///
    ///     [ 배지 ]        자기 색이 채워져 있어 그림 위에 그냥 둬도 읽힌다
    ///     ┌ 정보판 ┐      나머지 전부. 가라앉은 바탕 · 2px 테두리
    ///     ┌ 대화창 ┐      초상화 · 이름 · 대사 · ▼. 흰 바탕 · 4px · 귀퉁이 점
    ///     [ 버튼 ]
    ///
    /// 전에는 단계마다 대화창 안에 든 것이 달라서 크기가 들쭉날쭉했다. 곱딱이
    /// 목소리만 남기면 **대화창은 언제나 같은 모양**이고, 바뀌는 것은 그 위다.
    ///
    /// 글자가 있는 것은 반드시 상자에 담는다 — 배경 그림 위에 그냥 얹으면
    /// 하늘에서는 읽히고 돌담에서는 사라진다.
    private var sceneBottom: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.m) {
            if showsTask { infoSection }
            PixelDialogueBox(showsNext: waitsForSpeech ? !speechDone : true) {
                VStack(alignment: .leading, spacing: PixelSpacing.m) {
                    speechSection
                }
            }
            if showsTask { actionRow }
        }
        // 말이 바뀌면 다시 기다린다. 대장간집 미션은 Step 이 둘이라 두 번째
        // 질문도 곱딱이가 말하고 나서 보기가 뜬다.
        .onChange(of: speechKey) { speechDone = false }
        .padding(.horizontal, PixelSpacing.l)
        .padding(.top, PixelSpacing.xl)
        .padding(.bottom, PixelSpacing.xl)
    }

    /// **곱딱이 말이 끝난 뒤에 위 칸이 나타나는 단계**
    /// (2026-09-04 조익준님 결정).
    ///
    /// 말하는 중에 보기 버튼이 이미 떠 있으면 눈이 두 곳으로 갈려서, 글을 다
    /// 안 읽고 누르게 된다. 기다리는 동안에는 `▼` 가 깜빡여 「누르면 다 나온다」를
    /// 알려주고, 말이 끝나면 `▼` 가 사라지며 칸이 나타난다.
    ///
    /// 미션·FINAL 은 **답을 넣어야 해서** 그렇고, 발견은 이유가 다르다 —
    /// 곱딱이가 무엇을 찾았는지 설명하는 동안 `NEW DISCOVERY` 배지가 이미 떠
    /// 있으면 **상이 설명보다 먼저 온다.** 설명이 끝나고 나서 배지가 떠야
    /// 「이래서 이걸 찾은 거였구나」가 된다.
    ///
    /// 가는 중·이야기·CLEAR 는 그대로 같이 띄운다 — 그쪽 위 칸은 목적지 이름이나
    /// 제목·참고자료·통계라서 곱딱이 말과 **같이 봐야** 이해된다.
    private var waitsForSpeech: Bool {
        vm.phase == .mission || vm.phase == .finalStage || vm.phase == .discovery
    }

    private var showsTask: Bool { !waitsForSpeech || speechDone }

    /// 말이 바뀌었는지 알아보는 열쇠. 단계·미션·Step 중 하나만 바뀌어도 달라진다.
    private var speechKey: String {
        "\(vm.phase)-\(vm.currentMission?.id ?? "")-\(vm.stepIndex)"
    }

    /// 대화창 **위** — 곱딱이 말이 아닌 모든 것.
    @ViewBuilder
    private var infoSection: some View {
        switch vm.phase {
        case .pointIntro:   pointIntroInfo
        case .mission:      missionInfo
        case .stepFeedback: stepFeedbackInfo
        case .discovery:    discoveryInfo
        case .story:        storyInfo
        case .finalStage:   finalInfo
        case .clear:        clearInfo
        }
    }

    /// 대화창 **안** — 곱딱이가 말하는 것.
    @ViewBuilder
    private var speechSection: some View {
        switch vm.phase {
        case .pointIntro:
            if let point = vm.currentPoint {
                speech(point.navigationText.isEmpty ? point.objective : point.navigationText)
            }
        case .mission:
            if let mission = vm.currentMission, let step = vm.currentStep {
                speech(missionSpeech(mission, step))
            }
        case .stepFeedback:
            if let text = vm.pendingSuccess { speech(text) }
        case .discovery:
            if let d = vm.pendingDiscovery { speech(d.body) }
        case .story:
            if let story = vm.pendingStory { speech(story.script, story: story) }
        case .finalStage:
            if let final = play.final { speech(final.prompt) }
        case .clear:
            if let body = play.clear?.body, !body.isEmpty { speech(body) }
        }
    }

    /// 정보판의 겉모양. 대화창과 **일부러 다르게** 한다 —
    /// 테두리가 얇고(2px), 바탕이 가라앉았고, 귀퉁이 점이 없다.
    private func infoFrame<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: PixelSpacing.m) {
            content()
        }
        .padding(PixelSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixelColor.surfaceLow)
        .pixelBorder(width: PixelSpacing.border)
        .pixelShadow(PixelSpacing.shadowCard)
    }

    /// 곱딱이가 말하는 줄 — 초상화 · 이름 · (소리) · 한 글자씩 나타나는 글.
    ///
    /// `story` 를 주면 이름 옆에 소리 버튼이 붙는다. 소리가 없는 단계에서는
    /// 안 그린다.
    @ViewBuilder
    private func speech(_ text: String, story: PlayStory? = nil) -> some View {
        HStack(alignment: .top, spacing: PixelSpacing.l) {
            PixelPortrait()
            VStack(alignment: .leading, spacing: PixelSpacing.s) {
                HStack(spacing: PixelSpacing.s) {
                    Text(Self.speaker)
                        .font(PixelFont.label)
                        .foregroundStyle(PixelColor.primary)
                        .tracking(2)
                    Spacer(minLength: 0)
                    if let story { soundButton(story) }
                }
                PixelTypewriter(text: text, isFinished: $speechDone)
            }
        }
    }

    private func soundButton(_ story: PlayStory) -> some View {
        let active = audio.isActive(story.id)
        return PixelSoundButton(
            isPlaying: active,
            isLoading: audio.currentStoryId == story.id && audio.state == .loading,
            label: audioLabel(story)
        ) {
            if active { audio.stop() }
            else { audio.play(playId: play.id, storyId: story.id) }
        }
    }

    // MARK: - 「가는 중」 정보판

    /// **도착한 뒤가 아니라 아직 안 갔을 때** 뜨는 화면이다.
    /// 「대장간집으로 가세요」 → 걸어가서 → `[도착했어요]`.
    @ViewBuilder
    private var pointIntroInfo: some View {
        if let point = vm.currentPoint {
            infoFrame {
                HStack {
                    Text("POINT \(vm.pointNumber) / \(play.points.count)")
                        .font(PixelFont.labelSmall)
                        .foregroundStyle(PixelColor.inkWeak)
                    Spacer(minLength: 0)
                    distanceRow(to: point)
                }
                Text(point.title)
                    .font(PixelFont.sectionTitle)
                    .foregroundStyle(PixelColor.ink)
                if !point.navigationText.isEmpty, !point.objective.isEmpty {
                    Text(point.objective)
                        .font(PixelFont.body)
                        .foregroundStyle(PixelColor.inkWeak)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 거리 한 줄. **위치를 못 잡으면 그냥 안 뜬다** — 진행을 막지 않는다.
    @ViewBuilder
    private func distanceRow(to point: PlayPoint) -> some View {
        if let here = location.currentLocation, let c = point.coordinate {
            let meters = here.distance(from: CLLocation(latitude: c.latitude,
                                                        longitude: c.longitude))
            HStack(spacing: PixelSpacing.xs) {
                PixelIcon(.target, size: 14, color: PixelColor.primary)
                Text(meters < 1000
                     ? String(format: "약 %.0fm", meters)
                     : String(format: "약 %.1fkm", meters / 1000))
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.primary)
            }
        }
    }

    // MARK: - Mission 정보판

    /// ⚠️ 미션 화면은 시안(3)을 그대로 못 쓴다. 시안은 「읽고 → 다음」 한 장면인데
    /// 미션은 **답을 넣어야** 한다 (보기 고르기 8 · 확인 3 · 방향 1).
    /// 미션 전용 시안이 오면 다시 짠다.
    @ViewBuilder
    private var missionInfo: some View {
        if let mission = vm.currentMission, let step = vm.currentStep {
            infoFrame {
                HStack {
                    Text(vm.currentPoint?.title ?? "")
                        .font(PixelFont.labelSmall)
                        .foregroundStyle(PixelColor.inkWeak)
                    Spacer(minLength: 0)
                    Text("MISSION")
                        .font(PixelFont.labelSmall)
                        .foregroundStyle(PixelColor.inkWeak)
                }
                Text(mission.title)
                    .font(PixelFont.sectionTitle)
                    .foregroundStyle(PixelColor.ink)

                if let wrong = vm.wrongMessage {
                    HStack(alignment: .top, spacing: PixelSpacing.s) {
                        PixelIcon(.refresh, size: 16, color: PixelColor.locked)
                        Text(wrong)
                            .font(PixelFont.body)
                            .foregroundStyle(PixelColor.locked)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(PixelSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PixelColor.surface)
                    .pixelBorder()
                }

                MissionStepInput(step: step) { vm.submit($0) }
                revealedHints(mission)
                escapeRow(mission)
            }
        }
    }

    /// 맞혔을 때 — 어느 미션을 맞혔는지만 남기고, 칭찬은 곱딱이가 한다.
    @ViewBuilder
    private var stepFeedbackInfo: some View {
        if let mission = vm.currentMission {
            infoFrame {
                Text(mission.title)
                    .font(PixelFont.sectionTitle)
                    .foregroundStyle(PixelColor.ink)
            }
        }
    }

    /// 첫 Step 에서는 미션 안내 + 질문, 뒤 Step 은 질문만.
    /// **같은 글을 세 번 읽게 하면 현실을 볼 시간이 줄어든다.**
    private func missionSpeech(_ mission: Mission, _ step: MissionStep) -> String {
        if vm.stepIndex == 0, !mission.prompt.isEmpty {
            return step.prompt.isEmpty ? mission.prompt
                                       : mission.prompt + "\n\n" + step.prompt
        }
        return step.prompt.isEmpty ? mission.prompt : step.prompt
    }

    @ViewBuilder
    private func revealedHints(_ mission: Mission) -> some View {
        if vm.hintLevel > 0 {
            VStack(alignment: .leading, spacing: PixelSpacing.s) {
                ForEach(Array(mission.hints.prefix(vm.hintLevel).enumerated()),
                        id: \.offset) { i, hint in
                    HStack(alignment: .top, spacing: PixelSpacing.s) {
                        Text("힌트 \(i + 1)")
                            .font(PixelFont.labelSmall)
                            .foregroundStyle(PixelColor.onAccent)
                            .padding(.horizontal, PixelSpacing.xs)
                            .padding(.vertical, 2)
                            .background(PixelColor.accent)
                        Text(hint.text)
                            .font(PixelFont.body)
                            .foregroundStyle(PixelColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(PixelSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelColor.surface)
            .pixelBorder()
        }
    }

    /// **막히면 나갈 길이 항상 있다.** 미션 하나 때문에 관광이 멈추지 않는다.
    ///
    /// 정보판 **안**에 둔다 — 밖은 배경 그림 위라 작은 글자가 안 읽힌다.
    ///
    /// ## `정답과 이야기 보기` 는 힌트를 다 본 뒤에만 나온다
    ///
    /// 2026-09-04 조익준님 결정. 이 버튼은 답을 못 맞혀도 발견·이야기를 열고
    /// 다음으로 넘어간다 (진행도 칸도 채워지지만 「건너뛴 미션」으로 따로 세어
    /// CLEAR 에서 구분한다).
    ///
    /// 전에는 보기 버튼 바로 아래에 **처음부터** 있었다. 그러면 한 번도 안
    /// 풀어본 사람이 그냥 눌러서, 현실을 보고 발견하는 경험이 글 읽기로
    /// 바뀐다 — 성읍의 대표 미션(호령창)도 그렇게 넘어갈 수 있었다.
    ///
    /// 힌트를 다 본 뒤에 열면 「막히면 안 갇힌다」(CLAUDE.md)는 지키면서 답을
    /// 먼저 보는 길만 한 칸 뒤로 미룬다. 힌트가 없는 미션은 바로 열린다 —
    /// 열어 볼 힌트가 없는데 막아두면 갇힌다.
    ///
    /// `현장에서 찾을 수 없어요` 는 **항상** 있다. 콘텐츠 신고이고, 현장 답사를
    /// 하지 않기로 했으므로(2026-09-02) 이 경로가 콘텐츠 QA 의 눈이다.
    private func escapeRow(_ mission: Mission) -> some View {
        HStack(spacing: PixelSpacing.l) {
            if vm.hintLevel >= mission.hints.count {
                Button("정답과 이야기 보기") { vm.skipMission() }
            }
            Button("현장에서 찾을 수 없어요") { showReport = true }
            Spacer(minLength: 0)
        }
        .font(PixelFont.labelSmall)
        .foregroundStyle(PixelColor.inkWeak)
        .buttonStyle(.plain)
    }

    // MARK: - Discovery 정보판

    @ViewBuilder
    private var discoveryInfo: some View {
        if let d = vm.pendingDiscovery {
            sceneBadge(vm.lastSkipped ? "정답" : "NEW DISCOVERY",
                       fill: PixelColor.accent, label: PixelColor.onAccent)
            // 제목은 이름 있는 사물(정주석·물팡·호령창)에만 있다.
            // 없는 발견은 본문만 보여준다 — 없는 이름을 지어내지 않는다.
            if !d.title.isEmpty || vm.justEarnedRecord != nil {
                infoFrame {
                    if !d.title.isEmpty {
                        Text(d.title)
                            .font(PixelFont.sectionTitle)
                            .foregroundStyle(PixelColor.ink)
                    }
                    if let record = vm.justEarnedRecord {
                        HStack(spacing: PixelSpacing.s) {
                            PixelIcon(.check, size: 18, color: PixelColor.primary)
                            Text("\(record) 기록 복원")
                                .font(PixelFont.label)
                                .foregroundStyle(PixelColor.ink)
                        }
                        .padding(PixelSpacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PixelColor.surface)
                        .pixelBorder()
                    }
                }
            }
        }
    }

    // MARK: - Story 정보판

    /// 발견 뒤에 오는 의미. **놀멍봅서가 직접 쓴 문장이다** — 오디 대본이 아니다.
    ///
    /// 소리는 곱딱이 이름 옆 스피커 버튼이 맡는다. 예전에는 초록 막대 버튼이
    /// 따로 있었는데, 상단에도 소리 표시를 두려니 켜는 곳이 두 개가 됐다 —
    /// **소리는 한 곳으로 몰았다** (2026-09-03 조익준님 지적).
    @ViewBuilder
    private var storyInfo: some View {
        if let story = vm.pendingStory, !story.title.isEmpty || !story.sources.isEmpty {
            infoFrame {
                if !story.title.isEmpty {
                    Text(story.title)
                        .font(PixelFont.sectionTitle)
                        .foregroundStyle(PixelColor.ink)
                }
                if !story.sources.isEmpty {
                    VStack(alignment: .leading, spacing: PixelSpacing.xs) {
                        Text("참고 자료")
                            .font(PixelFont.labelSmall)
                            .foregroundStyle(PixelColor.inkWeak)
                        ForEach(Array(story.sources.enumerated()), id: \.offset) { _, s in
                            Text("· \(sourceLabel(s))")
                                .font(PixelFont.labelSmall)
                                .foregroundStyle(PixelColor.inkWeak)
                        }
                    }
                }
            }
        }
    }

    private func audioLabel(_ story: PlayStory) -> String {
        guard audio.currentStoryId == story.id else { return "이야기 듣기" }
        switch audio.state {
        case .loading: return "소리를 준비하고 있어요"
        case .playing: return "이야기 멈추기"
        case .failed:  return "소리를 못 불러왔어요 (글로 읽으세요)"
        case .idle:    return "이야기 듣기"
        }
    }

    /// 출처 한 줄. 공지가 지정한 형식은 텍스트만 허용한다 — 로고·CI 는 금지다.
    private func sourceLabel(_ s: StorySource) -> String {
        switch s.kind {
        case "odii", "kto": return "출처: ⓒ한국관광공사" + (s.ref.isEmpty ? "" : " (\(s.ref))")
        case "encykorea":   return "한국민족문화대백과사전 \(s.ref)"
        case "heritage":    return "국가유산 공식자료 \(s.ref)"
        default:            return s.ref.isEmpty ? s.kind : "\(s.kind) \(s.ref)"
        }
    }

    // MARK: - FINAL 정보판

    @ViewBuilder
    private var finalInfo: some View {
        if let final = play.final {
            sceneBadge("FINAL", fill: PixelColor.primary, label: PixelColor.onPrimary)
            infoFrame {
                Text(final.title)
                    .font(PixelFont.sectionTitle)
                    .foregroundStyle(PixelColor.ink)
                if let wrong = vm.wrongMessage {
                    Text(wrong)
                        .font(PixelFont.body)
                        .foregroundStyle(PixelColor.locked)
                        .fixedSize(horizontal: false, vertical: true)
                }
                MissionStepInput(step: final.step) { vm.submitFinal($0) }
            }
        }
    }

    // MARK: - CLEAR 정보판

    @ViewBuilder
    private var clearInfo: some View {
        sceneBadge("CLEAR", fill: PixelColor.primary, label: PixelColor.onPrimary)
        infoFrame {
            Text(play.clear?.title ?? play.title)
                .font(PixelFont.sectionTitle)
                .foregroundStyle(PixelColor.ink)
            HStack(spacing: PixelSpacing.m) {
                statBox("\(vm.progress.completedMissionIds.count) / \(play.missionCount)", "완료 미션")
                if !vm.progress.skippedMissionIds.isEmpty {
                    statBox("\(vm.progress.skippedMissionIds.count)", "건너뛴 미션")
                }
                statBox(vm.elapsedText, "걸린 시간")
            }
        }
    }

    private func statBox(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(PixelFont.label).foregroundStyle(PixelColor.ink)
            Text(label).font(PixelFont.labelSmall).foregroundStyle(PixelColor.inkWeak)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PixelSpacing.s)
        .background(PixelColor.surface)
        .pixelBorder()
    }

    private func sceneBadge(_ text: String, fill: Color, label: Color) -> some View {
        Text(text)
            .font(PixelFont.labelSmall)
            .foregroundStyle(label)
            .padding(.horizontal, PixelSpacing.s)
            .padding(.vertical, PixelSpacing.xs)
            .background(fill)
            .pixelBorder()
            .pixelShadow(PixelSpacing.shadowSmall)
    }

    // MARK: - 아래 버튼

    /// 시안: 가로 두 칸. 단계마다 하나만 필요하면 **한 칸이 폭을 다 쓴다** —
    /// 억지로 뭘 채워 넣지 않는다.
    @ViewBuilder
    private var actionRow: some View {
        switch vm.phase {
        case .pointIntro:
            sceneButton("도착했어요", filled: true) { vm.arrivedAtPoint() }
        case .mission:
            if let mission = vm.currentMission, vm.hintLevel < mission.hints.count {
                sceneButton(vm.hintLevel == 0 ? "힌트 보기" : "힌트 하나 더",
                            filled: false) { vm.showNextHint() }
            }
        case .stepFeedback:
            sceneButton("계속", filled: true) { vm.afterStepFeedback() }
        case .discovery:
            sceneButton("계속", filled: true) { vm.afterDiscovery() }
        case .story:
            sceneButton(vm.isLastMission ? "마지막으로" : "다음", filled: true) {
                // 다음 화면으로 넘어가면 소리를 끊는다. 미션 화면에서 앞
                // 이야기가 계속 흐르면 현실을 보는 데 방해가 된다.
                audio.stop()
                vm.afterStory()
            }
        case .finalStage:
            EmptyView()
        case .clear:
            sceneButton("PLAY 종료", filled: true) { dismiss() }
        }
    }

    private func sceneButton(_ title: String, filled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(PixelFont.sectionTitle)                 // 시안 headline-md 24
                .foregroundStyle(filled ? PixelColor.onPrimary : PixelColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PixelSpacing.m)           // p-3
                .background(filled ? PixelColor.primary : PixelColor.surfaceMid)
                .pixelBorder(width: PixelSpacing.border)
        }
        .buttonStyle(PixelPressStyle())
    }

    // MARK: - 길찾기

    private func openNavigation(to point: PlayPoint) {
        guard let c = point.coordinate else { return }
        let app = "comgooglemaps://?daddr=\(c.latitude),\(c.longitude)&directionsmode=walking"
        if let url = URL(string: app), UIApplication.shared.canOpenURL(url) {
            openURL(url); return
        }
        if let web = URL(string:
            "https://www.google.com/maps/dir/?api=1&destination=\(c.latitude),\(c.longitude)") {
            openURL(web)
        }
    }
}

// MARK: - 뷰모델

@MainActor
final class RunnerViewModel: ObservableObject {

    enum Phase { case pointIntro, mission, stepFeedback, discovery, story, finalStage, clear }

    @Published private(set) var phase: Phase = .pointIntro
    @Published private(set) var missionIndex = 0
    @Published private(set) var stepIndex = 0
    @Published private(set) var hintLevel = 0
    @Published private(set) var wrongMessage: String?
    /// 맞혔을 때 곱딱이가 해 주는 말. 원고가 적어 둔 Step 에만 있다.
    @Published private(set) var pendingSuccess: String?
    @Published private(set) var pendingDiscovery: MissionDiscovery?
    @Published private(set) var pendingStory: PlayStory?
    @Published private(set) var justEarnedRecord: String?
    @Published private(set) var lastSkipped = false
    @Published private(set) var progress: PlayProgress

    let play: Play
    private var flat: [(point: PlayPoint, mission: Mission)]
    /// 이미 안내를 마친 Point. 같은 Point 의 두 번째 미션에서 또 도착 화면을 띄우지 않는다.
    private var introducedPointIds: Set<String> = []

    /// **언제나 처음부터 시작한다** (2026-09-04 조익준님 결정).
    /// 저장된 진행을 이어받던 분기를 걷어냈다 — `PlayProgress` 주석 참조.
    init(play: Play) {
        self.play = play
        self.flat = play.orderedMissions
        self.progress = PlayProgress(play: play)
    }

    // MARK: 조회

    var currentPoint: PlayPoint? { flat[safe: missionIndex]?.point }
    var currentMission: Mission? { flat[safe: missionIndex]?.mission }
    var currentStep: MissionStep? { currentMission?.steps[safe: stepIndex] }
    var isLastMission: Bool { missionIndex >= flat.count - 1 }

    var pointNumber: Int {
        guard let p = currentPoint else { return 1 }
        return (play.points.firstIndex { $0.id == p.id } ?? 0) + 1
    }

    var navigationTitle: String {
        switch phase {
        case .clear: return "CLEAR"
        case .finalStage: return "FINAL"
        default: return play.title
        }
    }

    var elapsedText: String {
        let m = Int(Date().timeIntervalSince(progress.startedAt) / 60)
        return m < 60 ? "\(m)분" : "\(m / 60)시간 \(m % 60)분"
    }

    // MARK: 진행

    func arrivedAtPoint() {
        if let p = currentPoint { introducedPointIds.insert(p.id) }
        wrongMessage = nil
        phase = .mission
    }

    func showNextHint() {
        guard let m = currentMission else { return }
        hintLevel = min(hintLevel + 1, m.hints.count)
    }

    func submit(_ answer: MissionAnswer) {
        guard let step = currentStep, let mission = currentMission else { return }
        guard step.isCorrect(answer) else {
            wrongMessage = step.failureText
            return
        }
        wrongMessage = nil
        // **맞혔다는 말을 삼키지 않는다** (2026-09-04). 발견이 없는 Step 은
        // 정답을 눌러도 다음 화면으로 툭 넘어가서 맞았는지 알 수 없었다.
        // 원고가 성공 문구를 적어 둔 Step 은 그 말을 먼저 듣고 넘어간다.
        if !step.successFeedback.isEmpty {
            pendingSuccess = step.successFeedback
            phase = .stepFeedback
            return
        }
        proceedAfterStep(mission)
    }

    /// 성공 문구를 읽고 [계속] 을 눌렀을 때.
    func afterStepFeedback() {
        pendingSuccess = nil
        guard let mission = currentMission else { return }
        proceedAfterStep(mission)
    }

    private func proceedAfterStep(_ mission: Mission) {
        if stepIndex + 1 < mission.steps.count {
            stepIndex += 1
            phase = .mission
        } else {
            completeMission(mission, skipped: false)
        }
    }

    /// 건너뛰기 — 정답과 이야기를 열고 계속 간다. **진행이 막히지 않는다.**
    func skipMission() {
        guard let mission = currentMission else { return }
        if !progress.skippedMissionIds.contains(mission.id) {
            progress.skippedMissionIds.append(mission.id)
        }
        completeMission(mission, skipped: true)
    }

    private func completeMission(_ mission: Mission, skipped: Bool) {
        lastSkipped = skipped
        if !progress.completedMissionIds.contains(mission.id) {
            progress.completedMissionIds.append(mission.id)
        }
        // 진행도 칸. 모든 미션이 칸을 채우지는 않는다 — 앞 미션이 뒤 미션의
        // 발견을 준비하는 경우가 있다 (콘텐츠.md §13).
        justEarnedRecord = nil
        pendingSuccess = nil
        if let reward = mission.progressReward,
           !progress.discoveredRecordIds.contains(reward) {
            progress.discoveredRecordIds.append(reward)
            justEarnedRecord = play.progressRecords.first { $0.id == reward }?.label
        }
        pendingDiscovery = mission.discovery
        pendingStory = play.story(after: mission.id)
        hintLevel = 0
        stepIndex = 0

        // Discovery 가 없는 미션이 있다 — M01 처럼 다음 미션의 발견을 준비하는 것이다
        // (콘텐츠.md §13). 그때는 발견 화면을 건너뛰고 바로 다음으로 간다.
        if pendingDiscovery != nil {
            phase = .discovery
        } else if pendingStory != nil {
            phase = .story
        } else {
            advance()
        }
    }

    func afterDiscovery() {
        if pendingStory != nil { phase = .story } else { advance() }
    }

    func afterStory() { advance() }

    /// 다음 미션으로. 같은 Point 면 바로 미션, 다른 Point 면 도착 안내부터.
    private func advance() {
        pendingDiscovery = nil
        pendingStory = nil
        justEarnedRecord = nil

        if missionIndex + 1 < flat.count {
            missionIndex += 1
            stepIndex = 0
            hintLevel = 0
            let nextPoint = flat[missionIndex].point
            phase = introducedPointIds.contains(nextPoint.id) ? .mission : .pointIntro
        } else if play.final != nil {
            phase = .finalStage
        } else {
            finish()
        }
    }

    func submitFinal(_ answer: MissionAnswer) {
        guard let final = play.final else { finish(); return }
        guard final.step.isCorrect(answer) else {
            wrongMessage = final.step.failureText
            return
        }
        wrongMessage = nil
        if let story = final.story {
            pendingStory = story
            phase = .story
            return
        }
        finish()
    }

    private func finish() {
        progress.finalCleared = true
        phase = .clear
    }

}

// MARK: - 안전한 인덱스

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
