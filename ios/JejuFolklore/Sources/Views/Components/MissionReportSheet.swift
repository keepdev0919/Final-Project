import SwiftUI

/// 「현장에서 찾을 수 없어요」 — 콘텐츠가 현실과 어긋났을 때 알리는 곳.
///
/// ## 왜 이게 필수인가
///
/// 제주 5곳을 직접 답사하지 않기로 했다(2026-09-02). 웹 자료로 검증했지만
/// **일반 관람객 시야에서 실제로 보이는지까지는 확정하지 못한 미션이 있다**
/// (성읍 M04 마당 배치 · M07 물팡).
///
/// 그래서 "출시 후 사용자 리뷰로 잡는다"고 정했는데, **이 신고 경로가 없으면
/// 그건 리뷰 보정이 아니라 그냥 「검증 안 함」이다.** 이 화면이 그 전략을 성립시킨다.
///
/// ## 못 보내도 잃지 않는다
///
/// 현장은 통신이 불안하다. 서버로 못 보내면 **단말에 쌓아두고 다음에 다시 보낸다.**
/// 사용자에게는 어느 쪽이든 "기록했어요"라고 말한다 — 신고한 사람 입장에서는
/// 지금 전송됐는지가 중요하지 않고, 우리가 잃지 않는 것이 중요하다.
struct MissionReportSheet: View {
    let playId: String
    let playTitle: String
    let missionId: String
    let missionTitle: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: MissionReport.Reason?
    @State private var note = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PixelSpacing.l) {
                    if sent {
                        sentBody
                    } else {
                        formBody
                    }
                }
                .padding(PixelSpacing.screenMargin)
            }
            .background(PixelColor.background.ignoresSafeArea())
            .navigationTitle("현장과 다른가요?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") { onDone(); dismiss() }
                }
            }
        }
    }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.l) {
            Text(missionTitle)
                .font(PixelFont.sectionTitle)
                .foregroundStyle(PixelColor.ink)
            Text("무엇이 달랐나요?")
                .font(PixelFont.body)
                .foregroundStyle(PixelColor.inkWeak)

            VStack(spacing: PixelSpacing.s) {
                ForEach(MissionReport.Reason.allCases, id: \.self) { r in
                    Button { reason = r } label: {
                        HStack {
                            Text(r.label)
                                .font(PixelFont.body)
                                .foregroundStyle(PixelColor.ink)
                            Spacer(minLength: 0)
                            if reason == r {
                                PixelIcon(.check, size: 18, color: PixelColor.primary)
                            }
                        }
                        .padding(PixelSpacing.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(reason == r ? PixelColor.surfaceHigh : PixelColor.surface)
                        .pixelBorder()
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(reason == r ? [.isSelected] : [])
                }
            }

            VStack(alignment: .leading, spacing: PixelSpacing.s) {
                Text("더 알려주실 것이 있나요? (선택)")
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
                TextField("예: 문이 닫혀 있어서 안 보였어요", text: $note, axis: .vertical)
                    .lineLimit(3...5)
                    .font(PixelFont.body)
                    .padding(PixelSpacing.m)
                    .background(PixelColor.surface)
                    .pixelBorder()
            }

            PixelButton(title: "보내기", style: .primary) {
                guard let reason else { return }
                let report = MissionReport(
                    playId: playId, playTitle: playTitle,
                    missionId: missionId, missionTitle: missionTitle,
                    reason: reason, note: note)
                // 화면은 기다리지 않는다. 보내는 동안 사용자를 붙잡아두면
                // 통신이 느린 현장에서 화면이 멈춘 것처럼 보인다.
                sent = true
                Task { await MissionReportStore.shared.submit(report) }
            }
            .opacity(reason == nil ? 0.4 : 1)
            .disabled(reason == nil)

            Text("보내주신 내용은 콘텐츠를 고치는 데만 씁니다. 위치나 사진은 함께 보내지 않습니다.")
                .font(PixelFont.labelSmall)
                .foregroundStyle(PixelColor.inkWeak)
        }
    }

    private var sentBody: some View {
        VStack(spacing: PixelSpacing.l) {
            PixelIcon(.check, size: 48, color: PixelColor.done)
            Text("기록했어요")
                .font(PixelFont.sectionTitle)
                .foregroundStyle(PixelColor.ink)
            Text("이 미션을 다시 살펴보겠습니다.\n건너뛰고 계속 진행하셔도 됩니다.")
                .font(PixelFont.body)
                .foregroundStyle(PixelColor.inkWeak)
                .multilineTextAlignment(.center)
            PixelButton(title: "닫기", style: .primary) { onDone(); dismiss() }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, PixelSpacing.xxl)
    }
}

// MARK: - 모델 · 저장소

struct MissionReport: Codable, Identifiable {
    enum Reason: String, Codable, CaseIterable {
        case notVisible, blocked, mismatch, other

        var label: String {
            switch self {
            case .notVisible: return "대상이 보이지 않아요"
            case .blocked:    return "공사·통제 중이에요"
            case .mismatch:   return "설명과 실제 장소가 달라요"
            case .other:      return "기타"
            }
        }
    }

    var id = UUID()
    let playId: String
    let playTitle: String
    let missionId: String
    let missionTitle: String
    let reason: Reason
    let note: String
    var reportedAt = Date()
}

/// 신고를 서버로 보내고, 못 보낸 것은 단말에 쌓아 다음에 다시 보낸다.
@MainActor
final class MissionReportStore {
    static let shared = MissionReportStore()

    /// 아직 못 보낸 것만 담는다. 보낸 것은 서버에 있으므로 단말에 남기지 않는다.
    private let key = "mission_reports_pending_v1"

    private struct Payload: Encodable {
        let playId: String
        let missionId: String
        let reason: String
        let note: String
    }

    private struct Ack: Decodable { let id: String }

    private init() {}

    /// 보낸다. 실패하면 쌓아둔다.
    func submit(_ report: MissionReport) async {
        if await send(report) { return }
        var pending = loadPending()
        pending.append(report)
        savePending(pending)
    }

    /// 쌓인 것을 다시 보낸다. 앱을 켤 때 한 번 부른다.
    func flush() async {
        var pending = loadPending()
        guard !pending.isEmpty else { return }
        var left: [MissionReport] = []
        for report in pending {
            if await send(report) == false { left.append(report) }
        }
        pending = left
        savePending(pending)
    }

    private func send(_ report: MissionReport) async -> Bool {
        let body = Payload(playId: report.playId, missionId: report.missionId,
                           reason: report.reason.rawValue, note: report.note)
        do {
            let _: Ack = try await APIClient.shared.post("/report/mission", body: body)
            return true
        } catch {
            return false
        }
    }

    private func loadPending() -> [MissionReport] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([MissionReport].self, from: data)
        else { return [] }
        return all
    }

    private func savePending(_ all: [MissionReport]) {
        if all.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
