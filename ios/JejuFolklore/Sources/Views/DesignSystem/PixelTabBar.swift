import SwiftUI

/// 시안 스타일 탭바.
///
/// **왜 직접 만드나.** SwiftUI `TabView`의 탭바는 4px 테두리·어긋난 그림자·선택 탭 채움을
/// 넣을 수 없다. 시안의 탭바가 화면에서 늘 보이는 부분이라 여기만 기본 모양이면 눈에 띈다.
///
/// 위 테두리 4px + **위쪽으로만** 그림자. 선택된 탭은 주색으로 채우고 테두리·작은 그림자를 준다.
struct PixelTabBar: View {
    struct Item {
        let tab: AppTab
        let title: String
        let icon: PixelIcon.Glyph
    }

    let items: [Item]
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                Button {
                    selection = item.tab
                } label: {
                    let on = selection == item.tab
                    VStack(spacing: PixelSpacing.xs) {
                        PixelIcon(item.icon, size: 24,
                                  color: on ? PixelColor.onPrimary : PixelColor.inkWeak)
                        Text(item.title)
                            .font(PixelFont.labelSmall)
                            .foregroundStyle(on ? PixelColor.onPrimary : PixelColor.inkWeak)
                    }
                    .padding(.vertical, PixelSpacing.s)
                    // ⚠️ 폭을 **칠하기 전에** 벌린다. 순서가 뒤집히면 선택 탭의 초록 상자가
                    // 글자 길이만큼만 커져서 「퀘스트」와 「코스」의 상자 너비가 달라진다
                    // (늘어나는 건 터치 영역뿐이었다).
                    .frame(maxWidth: .infinity)
                    .background(on ? PixelColor.primary : Color.clear)
                    .modifier(SelectedTabChrome(on: on))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selection == item.tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, PixelSpacing.s)
        .padding(.top, PixelSpacing.s)
        // ⚠️ 하단 세이프에어리어를 직접 넣는다. 없으면 선택된 탭의 채운 사각형이
        // 홈 인디케이터 영역까지 흘러내린다(2026-08-20에 실제로 겪음).
        .padding(.bottom, PixelSpacing.s)
        .frame(maxWidth: .infinity)
        .background(PixelColor.surfaceMid)
        .overlay(alignment: .top) {
            // 위 테두리만 4px. 아래는 세이프에어리어로 이어진다.
            PixelColor.ink.frame(height: PixelSpacing.borderHeavy)
        }
        .background(alignment: .top) {
            // 그림자는 위쪽으로만 던진다 — 탭바는 화면 아래에 붙어 있다.
            PixelColor.ink
                .frame(height: PixelSpacing.shadowCard)
                .offset(y: -PixelSpacing.shadowCard)
        }
        // 세이프에어리어 아래까지 배경을 이어 준다. 색만 채우고 탭은 위에 남는다.
        .background(PixelColor.surfaceMid.ignoresSafeArea(edges: .bottom))
    }
}

/// 선택된 탭에만 테두리와 작은 그림자를 준다.
private struct SelectedTabChrome: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content
                .pixelBorder()
                .pixelShadow(PixelSpacing.shadowSmall)
        } else {
            content
        }
    }
}

/// 시안 스타일 상단바 — 아래 테두리 4px + 그림자.
struct PixelTopBar<Trailing: View>: View {
    let title: String
    /// 앱 이름일 때만 갈무리 픽셀 폰트를 쓴다.
    var isAppName: Bool = false
    var accent: Color = PixelColor.primary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(isAppName ? PixelFont.logo(size: 22) : PixelFont.screenTitle)
                .foregroundStyle(accent)
            Spacer()
            trailing
        }
        .padding(.horizontal, PixelSpacing.screenMargin)
        .padding(.vertical, PixelSpacing.m)
        .frame(maxWidth: .infinity)
        .background(PixelColor.background)
        .overlay(alignment: .bottom) {
            PixelColor.ink.frame(height: PixelSpacing.borderHeavy)
        }
    }
}

extension PixelTopBar where Trailing == EmptyView {
    init(title: String, isAppName: Bool = false, accent: Color = PixelColor.primary) {
        self.init(title: title, isAppName: isAppName, accent: accent) { EmptyView() }
    }
}
