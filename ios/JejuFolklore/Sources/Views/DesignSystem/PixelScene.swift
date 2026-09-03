import SwiftUI
import UIKit

/// 현장 진행 화면(`PlayRunnerView`)의 부품들.
///
/// **왜 따로 두나.** 이 부품들은 「문서 같은 화면」이 아니라 **게임 장면**을 만든다 —
/// 화면을 꽉 채운 픽셀 배경, 그 위에 떠 있는 HUD, 아래에서 올라오는 대화상자.
/// 카드·버튼·칩(`PixelComponents`)과 쓰이는 곳이 다르다.
///
/// 시안: `stitch_pixel_travel_quest (3)/code.html` (2026-09-03)

// MARK: - 장면 배경

/// 화면을 꽉 채우는 픽셀 배경 + 아래로 갈수록 어두워지는 겹.
///
/// ⚠️ 가진 그림이 **가로형**(성읍 커버 512×382)이라 세로 화면에 채우면 폭의 34%만
/// 보이고 2.3배로 확대된다. 픽셀아트라 확대해도 흐려지지 않고 도트만 굵어진다 —
/// `.interpolation(.none)` 을 빼면 흐린 그림이 된다.
///
/// 세로형 그림을 따로 받으면 잘리는 부분 없이 다 보인다.
struct PixelSceneBackground: View {
    /// 픽셀 그림 파일 이름 (= place_key). 없으면 가라앉은 면만 깐다.
    let imageName: String?

    var body: some View {
        // ⚠️ `Color.clear` 를 바닥에 깔고 그림을 **덧그린다.**
        //
        // `scaledToFill()` 한 그림을 ZStack 에 그냥 넣으면, 그림이 「나는 이만큼
        // 커야 한다」고 보고해서 **화면보다 넓은 크기가 부모에게 전해진다.**
        // 그러면 위에 얹은 HUD 와 대화상자가 화면 밖으로 밀려난다
        // (2026-09-03에 실제로 겪음). 덧그리면 그림은 크기를 못 정한다.
        Color.clear
            .overlay {
                ZStack {
                    PixelColor.surfaceDim
                    if let imageName, let image = UIImage(named: imageName) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFill()
                    }
                    // 아래가 어두워야 그림 위에 얹힌 것들이 읽힌다. 시안의
                    // `bg-gradient-to-t from-on-background/80` 이다.
                    LinearGradient(
                        colors: [PixelColor.ink.opacity(0.75), .clear],
                        startPoint: .bottom, endPoint: .center)
                }
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

// MARK: - HUD (배경 위에 떠 있는 것들)

/// 배경 위 정사각 픽셀 버튼. 36×36.
struct PixelHudButton: View {
    let glyph: PixelIcon.Glyph
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PixelIcon(glyph, size: 20, color: PixelColor.ink)
                .frame(width: 36, height: 36)
                .background(PixelColor.surfaceMid)
                .pixelBorder(width: PixelSpacing.border)
        }
        .buttonStyle(PixelPressStyle(offset: PixelSpacing.shadowSmall))
        .accessibilityLabel(label)
    }
}

/// 배경 위 진행도 칩 — 「생활기록 ▓▓▒▒▒▒ 2/6」.
///
/// **상단 가운데에 둔다** (2026-09-03 조익준님 결정). 이번 PLAY 에서 실제로 모으는
/// 것을 센다 — XP 나 점수 같은 범용 숫자를 쓰지 않는다.
struct PixelHudProgress: View {
    let label: String
    let total: Int
    let done: Int

    var body: some View {
        HStack(spacing: PixelSpacing.s) {
            Text(label)
                .font(PixelFont.labelSmall)
                .foregroundStyle(PixelColor.ink)
            HStack(spacing: 2) {
                ForEach(0..<max(total, 1), id: \.self) { i in
                    Rectangle()
                        .fill(i < done ? PixelColor.primary : PixelColor.surfaceVariant)
                        .frame(width: 8, height: 8)
                }
            }
            Text("\(done)/\(total)")
                .font(PixelFont.labelSmall)
                .foregroundStyle(PixelColor.primary)
        }
        .padding(.horizontal, PixelSpacing.s)
        .frame(height: 36)
        .background(PixelColor.surface)
        .pixelBorder(width: PixelSpacing.border)
        .pixelShadow(PixelSpacing.shadowSmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(total)개 중 \(done)개")
    }
}

// MARK: - 대화상자

/// RPG 대화상자. 4px 테두리 + 4px 그림자 + **네 귀퉁이에 삐져나온 잉크 점**.
///
/// 귀퉁이 점은 시안 `absolute -top-1 -left-1 w-2 h-2 bg-on-background` 다.
/// 8pt 사각형을 4pt 밖으로 빼서 모서리가 톡 튀어나온다.
///
/// ⚠️ 예전에 `PixelCard` 에서 걷어낸 귀퉁이 점과 **다른 것이다.** 그쪽 시안은
/// 점이 테두리에 정확히 겹쳐 화면에서 안 보였다. 이 시안은 실제로 삐져나온다.
struct PixelDialogueBox<Content: View>: View {
    /// 오른쪽 아래에 「더 있다」는 표시를 깜빡일지.
    var showsNext: Bool = true
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(PixelSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelColor.surface)
            .pixelBorder(width: PixelSpacing.borderHeavy)
            .overlay(alignment: .bottomTrailing) {
                if showsNext {
                    PixelIcon(.caret, size: 16, color: PixelColor.ink)
                        .padding(PixelSpacing.xs)
                        .pixelBlink()
                }
            }
            .overlay { cornerNubs }
            .pixelShadow(PixelSpacing.shadowCard)
    }

    private var cornerNubs: some View {
        let nub = Rectangle().fill(PixelColor.ink).frame(width: 8, height: 8)
        return ZStack {
            VStack {
                HStack { nub; Spacer(); nub }
                Spacer()
                HStack { nub; Spacer(); nub }
            }
            .padding(-PixelSpacing.xs)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 화자

/// 대화상자 왼쪽의 64×64 초상화. **곱딱이**다 (2026-09-03 조익준님 결정).
///
/// 앱 아이콘의 픽셀 감귤을 16배 줄여 만들었다 — 원본 도트 격자가 64칸이라
/// 정수 배수로 줄어들어 도트가 갈리지 않는다. 바깥 흰 여백만 투명으로 뚫어서
/// 초상화 칸의 배경색이 비친다.
///
/// 지금 그림은 **전신**이다. 얼굴 위주로 다시 그린 초상화가 있으면 더 좋다.
struct PixelPortrait: View {
    var name: String = "gamgyul"
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            PixelColor.surfaceHigh
            if let image = UIImage(named: name) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .pixelBorder(width: PixelSpacing.border)
        .accessibilityHidden(true)
    }
}

/// 소리 켜기·끄기. **대화상자 안 화자 이름 옆에 둔다**
/// (2026-09-03 조익준님 결정).
///
/// 소리의 주인은 말하는 사람이다. 상단 HUD 에 두면 「화면 전체의 소리」처럼
/// 읽혀서 무엇을 읽어주는지 모른다. 소리가 없는 단계에서는 이 버튼을 아예
/// 안 그린다 — 회색으로 떠 있으면 「고장났나」로 읽힌다.
struct PixelSoundButton: View {
    let isPlaying: Bool
    let isLoading: Bool
    let label: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                if isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    PixelIcon(isPlaying ? .soundOff : .sound, size: 16,
                              color: PixelColor.ink)
                }
            }
            .frame(width: 28, height: 28)
            .background(PixelColor.surfaceMid)
            .pixelBorder(width: PixelSpacing.border)
        }
        .buttonStyle(PixelPressStyle(offset: PixelSpacing.shadowSmall))
        .accessibilityLabel(label)
    }
}

// MARK: - 타이핑 효과

/// 글자가 **한 글자씩** 나타난다. 옛 게임 대화상자가 그랬다.
///
/// 누르면 **즉시 전부 나타난다** — 읽는 속도를 강요하지 않는다. 빨리 읽는
/// 사람에게 기다리게 하는 것은 재미가 아니라 방해다.
///
/// 자리는 처음부터 다 잡아 둔다. 글자가 늘면서 상자가 커지면 아래 버튼이
/// 흔들려서 누르려던 것을 놓친다.
///
/// ⚠️ 설정에서 **「동작 줄이기」**를 켠 사용자에게는 처음부터 다 보인다.
struct PixelTypewriter: View {
    let text: String
    var font: Font = PixelFont.bodyLarge
    var color: Color = PixelColor.ink
    /// 1초에 몇 글자.
    var charsPerSecond: Double = 26

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        // 다 나온 글을 투명하게 깔아 높이를 먼저 잡는다.
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .overlay(alignment: .topLeading) {
                Text(String(text.prefix(shown)))
                    .font(font)
                    .foregroundStyle(color)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture { shown = text.count }
            .task(id: text) { await type() }
            .accessibilityLabel(text)
    }

    private func type() async {
        guard !reduceMotion else { shown = text.count; return }
        shown = 0
        let step = UInt64(1_000_000_000 / max(charsPerSecond, 1))
        while shown < text.count {
            try? await Task.sleep(nanoseconds: step)
            if Task.isCancelled { return }
            shown += 1
        }
    }
}
