import SwiftUI

/// 풀스크린 인스타 스토리 느낌 뷰어 (Lv3).
/// 좌우 스와이프로 페이지 이동, 상단 X 로 닫기.
struct StoryViewerView: View {
    let pin: Pin
    let placeName: String

    @Environment(\.dismiss) private var dismiss
    @State private var pages: [StoryPage] = []
    @State private var currentIndex: Int = 0
    @State private var isLoading: Bool = true
    @State private var failed: Bool = false

    /// 메모리 캐시 — codeNo+place → pages
    private static var cache: [String: [StoryPage]] = [:]

    private var cacheKey: String { pin.codeNo + "|" + placeName }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else if failed || pages.isEmpty {
                fallbackView
            } else {
                contentView
            }

            VStack {
                topBar
                Spacer()
            }
        }
        .task { await loadStory() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 8) {
            // 페이지 인디케이터
            HStack(spacing: 4) {
                ForEach(0..<max(pages.count, 1), id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(idx <= currentIndex ? Color.white : Color.white.opacity(0.3))
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.sourceTypeLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.85))
                        .clipShape(Capsule())
                    Text(pin.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Content

    private var contentView: some View {
        ZStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, page in
                    pageView(page: page)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            // 인스타 스토리 UX: 좌측 1/3 탭 = 이전, 우측 2/3 탭 = 다음(마지막에선 닫기)
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .onTapGesture { goToPrev() }
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .onTapGesture { goToNext() }
            }
            .padding(.top, 80)
            .padding(.bottom, 60)
        }
    }

    private func goToPrev() {
        guard currentIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            currentIndex -= 1
        }
    }

    private func goToNext() {
        if currentIndex < pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.22)) {
                currentIndex += 1
            }
        } else {
            dismiss()
        }
    }

    private func pageView(page: StoryPage) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer().frame(height: 80)

            Text(page.title)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)

            ScrollView {
                Text(page.body)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.92))
                    .lineSpacing(8)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // TTS placeholder (Lv3 에서는 SKIP)
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                Text("음성으로 듣기 (준비 중)")
                    .font(.caption)
            }
            .foregroundColor(.white.opacity(0.4))
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var fallbackView: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.5))
            Text("아직 이야기를 가져올 수 없어요.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            if !pin.summary.isEmpty {
                Text(pin.summary)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Loading

    private func loadStory() async {
        if let cached = Self.cache[cacheKey] {
            self.pages = cached
            self.isLoading = false
            return
        }
        isLoading = true
        failed = false
        do {
            let fetched = try await PinsAPI.story(codeNo: pin.codeNo, place: placeName)
            Self.cache[cacheKey] = fetched
            pages = fetched
        } catch {
            failed = true
        }
        isLoading = false
    }
}

#Preview {
    StoryViewerView(
        pin: Pin(
            codeNo: "C_M_001",
            title: "C_M_001 각시당본풀이",
            sourceType: "legend",
            summary: "각시당의 본풀이.",
            lat: 33.5, lng: 126.5,
            primaryPlace: "각시당",
            distanceM: 30,
            hook: "사라진 신부가 본향당이 된 이야기"
        ),
        placeName: "각시당"
    )
}
