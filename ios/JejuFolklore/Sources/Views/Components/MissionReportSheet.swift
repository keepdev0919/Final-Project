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
/// ⚠️ 아직 서버로 보내지 않는다. 단말에 쌓아두고 다음 묶음에서 보낸다 —
/// **보내는 척하지 않는다.** 사용자에게도 "기록됐다"까지만 말한다.
struct MissionReportSheet: View {
    let playTitle: String
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
                MissionReportStore.shared.add(MissionReport(
                    playTitle: playTitle, missionTitle: missionTitle,
                    reason: reason, note: note))
                sent = true
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
    let playTitle: String
    let missionTitle: String
    let reason: Reason
    let note: String
    var reportedAt = Date()
}

/// 단말에 쌓아두는 신고. 서버 전송은 다음 묶음이다.
@MainActor
final class MissionReportStore {
    static let shared = MissionReportStore()
    private let key = "mission_reports_v1"
    private init() {}

    func add(_ report: MissionReport) {
        var all = load()
        all.append(report)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> [MissionReport] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([MissionReport].self, from: data)
        else { return [] }
        return all
    }
}
