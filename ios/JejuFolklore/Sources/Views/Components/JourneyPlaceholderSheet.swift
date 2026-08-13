import SwiftUI

/// 묶음 B에서 여정 소개 화면(미리 듣기·미리 받아두기)으로 교체된다.
/// 눌렀는데 아무 일도 없으면 "고장난 앱"으로 보이므로 최소한의 안내를 둔다.
struct JourneyPlaceholderSheet: View {
    let journey: Journey
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: PixelSpacing.l) {
            Text(journey.title)
                .pixelFont(PixelFont.screenTitle)
                .foregroundStyle(PixelColor.ink)
                .multilineTextAlignment(.center)

            Text(journey.theme)
                .font(PixelFont.longform(15))
                .foregroundStyle(PixelColor.inkWeak)
                .multilineTextAlignment(.center)

            Text("이야기 재생은 준비 중이에요")
                .pixelFont(PixelFont.badge)
                .foregroundStyle(PixelColor.inkWeak)

            PixelButton(title: "닫기", style: .plain) { dismiss() }
                .padding(.horizontal, PixelSpacing.xl)
        }
        .padding(PixelSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PixelColor.background)
    }
}
