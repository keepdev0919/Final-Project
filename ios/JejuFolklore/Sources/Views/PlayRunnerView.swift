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

    init(play: Play) {
        self.play = play
        _vm = StateObject(wrappedValue: RunnerViewModel(play: play))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                ScrollView {
                    VStack(alignment: .leading, spacing: PixelSpacing.l) {
                        switch vm.phase {
                        case .pointIntro:  pointIntroBody
                        case .mission:     missionBody
                        case .discovery:   discoveryBody
                        case .story:       storyBody
                        case .finalStage:  finalBody
                        case .clear:       clearBody
                        }
                    }
                    .padding(PixelSpacing.screenMargin)
                    .padding(.bottom, PixelSpacing.xxl)
                }
            }
            .background(PixelColor.background.ignoresSafeArea())
            .navigationTitle(vm.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("나가기") { showQuit = true }
                        .foregroundStyle(PixelColor.inkWeak)
                }
            }
            .confirmationDialog("PLAY 를 그만할까요?", isPresented: $showQuit,
                                titleVisibility: .visible) {
                Button("나가기 (진행은 저장돼요)") { dismiss() }
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
        }
        .onAppear {
            location.requestCurrentLocationOnce()
            // 지난번에 못 보낸 신고가 있으면 지금 보낸다.
            Task { await MissionReportStore.shared.flush() }
        }
        .onDisappear { audio.stop() }
    }

    // MARK: - 진행도

    /// 「생활기록 4 / 6」. XP 가 아니라 **이번 PLAY 에서 실제로 모으는 것**을 센다.
    private var progressBar: some View {
        VStack(spacing: PixelSpacing.s) {
            HStack {
                Text(play.progressLabel.isEmpty ? "진행" : play.progressLabel)
                    .font(PixelFont.label)
                    .foregroundStyle(PixelColor.ink)
                Spacer()
                Text("\(vm.progress.discoveredRecordIds.count) / \(play.progressRecords.count)")
                    .font(PixelFont.label)
                    .foregroundStyle(PixelColor.primary)
            }
            HStack(spacing: PixelSpacing.xs) {
                ForEach(play.progressRecords) { record in
                    let done = vm.progress.discoveredRecordIds.contains(record.id)
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(done ? PixelColor.primary : PixelColor.surfaceMid)
                            .frame(height: 8)
                        Text(record.label)
                            .font(PixelFont.labelSmall)
                            .foregroundStyle(done ? PixelColor.ink : PixelColor.inkWeak)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
        }
        .padding(.horizontal, PixelSpacing.screenMargin)
        .padding(.vertical, PixelSpacing.m)
        .background(PixelColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PixelColor.outlineVariant).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(play.progressLabel) \(vm.progress.discoveredRecordIds.count)개 중 "
            + "\(play.progressRecords.count)개 복원")
    }

    // MARK: - Point 도착

    @ViewBuilder
    private var pointIntroBody: some View {
        if let point = vm.currentPoint {
            VStack(alignment: .leading, spacing: PixelSpacing.l) {
                Text("POINT \(vm.pointNumber) / \(play.points.count)")
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
                Text(point.title)
                    .font(PixelFont.screenTitle)
                    .foregroundStyle(PixelColor.ink)
                if !point.objective.isEmpty {
                    Text(point.objective)
                        .font(PixelFont.bodyLarge)
                        .foregroundStyle(PixelColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !point.navigationText.isEmpty {
                    HStack(alignment: .top, spacing: PixelSpacing.s) {
                        PixelIcon(.mapPin, size: 18, color: PixelColor.inkWeak)
                        Text(point.navigationText)
                            .font(PixelFont.body)
                            .foregroundStyle(PixelColor.inkWeak)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                distanceRow(to: point)

                VStack(spacing: PixelSpacing.m) {
                    PixelButton(title: "길찾기", style: .plain) { openNavigation(to: point) }
                    PixelButton(title: "도착했어요", style: .primary) { vm.arrivedAtPoint() }
                }
                .padding(.top, PixelSpacing.m)
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
                PixelIcon(.target, size: 16, color: PixelColor.primary)
                Text(meters < 1000
                     ? String(format: "여기서 약 %.0fm", meters)
                     : String(format: "여기서 약 %.1fkm", meters / 1000))
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.primary)
            }
        }
    }

    // MARK: - Mission

    @ViewBuilder
    private var missionBody: some View {
        if let mission = vm.currentMission, let step = vm.currentStep {
            VStack(alignment: .leading, spacing: PixelSpacing.l) {
                Text(vm.currentPoint?.title ?? "")
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
                Text(mission.title)
                    .font(PixelFont.sectionTitle)
                    .foregroundStyle(PixelColor.ink)

                // 미션 전체 안내는 첫 Step 에서만. 뒤 Step 은 자기 질문만 보여준다 —
                // 같은 글을 세 번 읽게 하면 현실을 볼 시간이 줄어든다.
                if vm.stepIndex == 0, !mission.prompt.isEmpty {
                    Text(mission.prompt)
                        .font(PixelFont.bodyLarge)
                        .foregroundStyle(PixelColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !step.prompt.isEmpty {
                    Text(step.prompt)
                        .font(PixelFont.body)
                        .foregroundStyle(vm.stepIndex == 0 ? PixelColor.inkWeak : PixelColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                    .background(PixelColor.surfaceHigh)
                    .pixelBorder()
                }

                MissionStepInput(step: step) { vm.submit($0) }

                revealedHints(mission)
                helpRow(mission)
            }
        }
    }

    @ViewBuilder
    private func revealedHints(_ mission: Mission) -> some View {
        if vm.hintLevel > 0 {
            VStack(alignment: .leading, spacing: PixelSpacing.s) {
                ForEach(Array(mission.hints.prefix(vm.hintLevel).enumerated()), id: \.offset) { i, hint in
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

    /// 힌트 · 건너뛰기 · 신고. **모든 Main Mission 에서 항상 있다.**
    @ViewBuilder
    private func helpRow(_ mission: Mission) -> some View {
        VStack(spacing: PixelSpacing.s) {
            if vm.hintLevel < mission.hints.count {
                Button {
                    vm.showNextHint()
                } label: {
                    Text(vm.hintLevel == 0 ? "힌트 보기" : "힌트 하나 더")
                        .font(PixelFont.label)
                        .foregroundStyle(PixelColor.primary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: PixelSpacing.l) {
                Button("정답과 이야기 보기") { vm.skipMission() }
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
                Button("현장에서 찾을 수 없어요") { showReport = true }
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, PixelSpacing.m)
    }

    // MARK: - Discovery

    @ViewBuilder
    private var discoveryBody: some View {
        if let d = vm.pendingDiscovery {
            VStack(alignment: .leading, spacing: PixelSpacing.l) {
                Text(vm.lastSkipped ? "정답" : "NEW DISCOVERY")
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.onAccent)
                    .padding(.horizontal, PixelSpacing.s)
                    .padding(.vertical, PixelSpacing.xs)
                    .background(PixelColor.accent)
                    .pixelBorder()
                // 제목은 이름 있는 사물(정주석·물팡·호령창)에만 있다.
                // 없는 발견은 본문만 보여준다 — 없는 이름을 지어내지 않는다.
                if !d.title.isEmpty {
                    Text(d.title)
                        .font(PixelFont.screenTitle)
                        .foregroundStyle(PixelColor.ink)
                }
                if !d.body.isEmpty {
                    Text(d.body)
                        .font(d.title.isEmpty ? PixelFont.sectionTitle : PixelFont.bodyLarge)
                        .foregroundStyle(PixelColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let record = vm.justEarnedRecord {
                    HStack(spacing: PixelSpacing.s) {
                        PixelIcon(.check, size: 18, color: PixelColor.done)
                        Text("\(record) 기록 복원 ✓")
                            .font(PixelFont.label)
                            .foregroundStyle(PixelColor.ink)
                    }
                    .padding(PixelSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PixelColor.surfaceHigh)
                    .pixelBorder()
                }
                PixelButton(title: "계속", style: .primary) { vm.afterDiscovery() }
                    .padding(.top, PixelSpacing.m)
            }
        }
    }

    // MARK: - Story

    /// 발견 뒤에 오는 의미. **놀멍봅서가 직접 쓴 문장이다** — 오디 대본이 아니다.
    @ViewBuilder
    private var storyBody: some View {
        if let story = vm.pendingStory {
            VStack(alignment: .leading, spacing: PixelSpacing.l) {
                if !story.title.isEmpty {
                    Text(story.title)
                        .font(PixelFont.sectionTitle)
                        .foregroundStyle(PixelColor.ink)
                }

                storyAudioButton(story)
                // 픽셀 폰트를 쓰지 않는다 — 긴 글은 읽기가 먼저다 (DESIGN.md §3).
                Text(story.script)
                    .font(PixelFont.bodyLarge)
                    .foregroundStyle(PixelColor.ink)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)

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
                    .padding(.top, PixelSpacing.s)
                }

                PixelButton(title: vm.isLastMission ? "마지막으로" : "다음", style: .primary) {
                    // 다음 화면으로 넘어가면 소리를 끊는다. 미션 화면에서 앞
                    // 이야기가 계속 흐르면 현실을 보는 데 방해가 된다.
                    audio.stop()
                    vm.afterStory()
                }
                .padding(.top, PixelSpacing.m)
            }
        }
    }

    /// 이야기를 소리로 듣는 버튼.
    ///
    /// **이어폰을 끼면 화면을 안 보고 현실을 볼 수 있어야 한다** (콘텐츠.md §10 —
    /// 오디오가 주인, 글자는 자막). 다만 소리가 안 나도 자막은 그대로 있고
    /// **진행은 막지 않는다** — 현장은 통신이 불안하다.
    @ViewBuilder
    private func storyAudioButton(_ story: PlayStory) -> some View {
        let active = audio.isActive(story.id)
        Button {
            if active { audio.stop() }
            else { audio.play(playId: play.id, storyId: story.id) }
        } label: {
            HStack(spacing: PixelSpacing.s) {
                if audio.currentStoryId == story.id && audio.state == .loading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    PixelIcon(active ? .pause : .play, size: 18,
                              color: PixelColor.onPrimary)
                }
                Text(audioLabel(story))
                    .font(PixelFont.label)
                    .foregroundStyle(PixelColor.onPrimary)
                Spacer(minLength: 0)
            }
            .padding(PixelSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelColor.primary)
            .pixelBorder()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active ? "이야기 멈추기" : "이야기 듣기")
    }

    private func audioLabel(_ story: PlayStory) -> String {
        guard audio.currentStoryId == story.id else { return "이야기 듣기" }
        switch audio.state {
        case .loading: return "소리를 준비하고 있어요…"
        case .playing: return "멈추기"
        case .failed:  return "소리를 못 불러왔어요 (자막으로 읽으세요)"
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

    // MARK: - FINAL

    @ViewBuilder
    private var finalBody: some View {
        if let final = play.final {
            VStack(alignment: .leading, spacing: PixelSpacing.l) {
                Text("FINAL")
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.onPrimary)
                    .padding(.horizontal, PixelSpacing.s)
                    .padding(.vertical, PixelSpacing.xs)
                    .background(PixelColor.primary)
                    .pixelBorder()
                Text(final.title)
                    .font(PixelFont.sectionTitle)
                    .foregroundStyle(PixelColor.ink)
                if !final.prompt.isEmpty {
                    Text(final.prompt)
                        .font(PixelFont.body)
                        .foregroundStyle(PixelColor.inkWeak)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    // MARK: - CLEAR

    @ViewBuilder
    private var clearBody: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.l) {
            Text("CLEAR")
                .font(PixelFont.screenTitle)
                .foregroundStyle(PixelColor.onPrimary)
                .padding(.horizontal, PixelSpacing.l)
                .padding(.vertical, PixelSpacing.s)
                .background(PixelColor.primary)
                .pixelBorder()

            Text(play.clear?.title ?? play.title)
                .font(PixelFont.sectionTitle)
                .foregroundStyle(PixelColor.ink)

            Text("\(play.progressRecords.count) / \(play.progressRecords.count) RESTORED")
                .font(PixelFont.label)
                .foregroundStyle(PixelColor.primary)

            HStack(spacing: PixelSpacing.l) {
                statBox("\(vm.progress.completedMissionIds.count) / \(play.missionCount)", "완료 미션")
                if !vm.progress.skippedMissionIds.isEmpty {
                    statBox("\(vm.progress.skippedMissionIds.count)", "건너뛴 미션")
                }
                statBox(vm.elapsedText, "걸린 시간")
            }

            if let body = play.clear?.body {
                Text(body)
                    .font(PixelFont.bodyLarge)
                    .foregroundStyle(PixelColor.ink)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PixelButton(title: "PLAY 종료", style: .primary) { dismiss() }
                .padding(.top, PixelSpacing.l)
        }
    }

    private func statBox(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(PixelFont.label).foregroundStyle(PixelColor.ink)
            Text(label).font(PixelFont.labelSmall).foregroundStyle(PixelColor.inkWeak)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PixelSpacing.m)
        .background(PixelColor.surface)
        .pixelBorder()
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

    enum Phase { case pointIntro, mission, discovery, story, finalStage, clear }

    @Published private(set) var phase: Phase = .pointIntro
    @Published private(set) var missionIndex = 0
    @Published private(set) var stepIndex = 0
    @Published private(set) var hintLevel = 0
    @Published private(set) var wrongMessage: String?
    @Published private(set) var pendingDiscovery: MissionDiscovery?
    @Published private(set) var pendingStory: PlayStory?
    @Published private(set) var justEarnedRecord: String?
    @Published private(set) var lastSkipped = false
    @Published private(set) var progress: PlayProgress

    let play: Play
    private var flat: [(point: PlayPoint, mission: Mission)]
    /// 이미 안내를 마친 Point. 같은 Point 의 두 번째 미션에서 또 도착 화면을 띄우지 않는다.
    private var introducedPointIds: Set<String> = []

    init(play: Play) {
        self.play = play
        self.flat = play.orderedMissions

        // 저장된 진행이 있으면 이어받는다.
        if let saved = PlayProgressStore.shared.load(playId: play.id), !saved.isFinished {
            self.progress = saved
            let idx = flat.firstIndex { $0.mission.id == saved.currentMissionId } ?? 0
            self.missionIndex = idx
            self.stepIndex = min(saved.currentStepIndex, max(0, (flat[safe: idx]?.mission.steps.count ?? 1) - 1))
            // 이어서 할 때는 Point 안내부터 — 어디에 서 있어야 하는지 다시 알려준다.
            self.phase = .pointIntro
        } else {
            self.progress = PlayProgress(play: play)
        }
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
        save()
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
        if stepIndex + 1 < mission.steps.count {
            stepIndex += 1
            save()
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
        if let reward = mission.progressReward,
           !progress.discoveredRecordIds.contains(reward) {
            progress.discoveredRecordIds.append(reward)
            justEarnedRecord = play.progressRecords.first { $0.id == reward }?.label
        }
        pendingDiscovery = mission.discovery
        pendingStory = play.story(after: mission.id)
        hintLevel = 0
        stepIndex = 0
        save()

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
            save()
        } else if play.final != nil {
            phase = .finalStage
            save()
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
        save()
    }

    private func save() {
        progress.currentMissionId = currentMission?.id ?? progress.currentMissionId
        progress.currentPointId = currentPoint?.id ?? progress.currentPointId
        progress.currentStepIndex = stepIndex
        PlayProgressStore.shared.save(progress)
    }
}

// MARK: - 안전한 인덱스

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
