import SwiftUI
import AuthenticationServices

/// 로그인 안내 시트.
///
/// - Apple/Google 로그인 옵션과 "건너뛰기"를 제공.
/// - 로그인 성공 시 자동으로 dismiss.
struct LoginSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var isWorking: Bool = false

    // 심사·테스트 계정 로그인. 일반 사용자에게 권하는 경로가 아니라 접혀 있다.
    @State private var showReviewLogin = false
    @State private var reviewId = ""
    @State private var reviewPw = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            VStack(spacing: 12) {
                PixelIcon(.person, size: 56)
                    .foregroundStyle(PixelColor.primary)

                Text("로그인하면 다른 기기에서도\n같은 코스를 볼 수 있어요")
                    .font(PixelFont.bodyLarge)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("코스, 여행 기록이 안전하게 보관됩니다.")
                    .font(PixelFont.body)
                    .foregroundStyle(PixelColor.inkWeak)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { _ in
                    // 시스템 콜백 결과는 AuthManager 내부 delegate에서 처리되므로
                    // 여기서는 비동기 트리거만 시도한다.
                    Task { await performAppleSignIn() }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(Rectangle())
                .disabled(isWorking)

                Button(action: { Task { await performGoogleSignIn() } }) {
                    // 아이콘을 넣지 않는다. 우리 도트 아이콘 중에 Google을 뜻하는 게
                    // 없고, 사람 모양을 쓰면 위 헤더 아이콘과 같은 그림이 두 번 나오면서
                    // "Google"이라는 뜻은 어디에도 남지 않는다.
                    Text("Google로 계속하기")
                    .font(PixelFont.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    // Google 파랑은 고정 브랜드색이다. 적응색(surface)을 올리면
                    // 다크 모드에서 글자가 어두워져 4.27:1로 흐려진다.
                    .foregroundStyle(Color.white)
                    .background(Color(.sRGB, red: 0.26, green: 0.52, blue: 0.96, opacity: 1))
                    .clipShape(Rectangle())
                }
                .disabled(isWorking)
            }
            .padding(.horizontal, 24)

            reviewLoginSection

            if let errorMessage {
                Text(errorMessage)
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.locked)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button("건너뛰기") {
                dismiss()
            }
            .font(PixelFont.body)
            .foregroundStyle(PixelColor.inkWeak)
            .padding(.bottom, 12)
        }
        .padding(.top, 24)
        .interactiveDismissDisabled(isWorking)
        .onChange(of: authManager.isLoggedIn) { _, newValue in
            if newValue { dismiss() }
        }
        .overlay {
            if isWorking {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(24)
                    .background(PixelColor.surfaceLow)
            }
        }
    }

    // MARK: - Actions

    // MARK: - 심사·테스트 계정 로그인

    /// 공모전 심사위원과 애플 앱스토어 심사자가 쓰는 경로.
    ///
    /// 요건상 지정 형식 계정으로 로그인이 되어야 하고, 실패 시 심사에서 제외된다.
    /// 일반 사용자에게 권하는 방식이 아니므로 기본으로 접어 둔다.
    private var reviewLoginSection: some View {
        DisclosureGroup("심사·테스트 계정으로 로그인", isExpanded: $showReviewLogin) {
            VStack(spacing: 8) {
                TextField("아이디", text: $reviewId)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)

                SecureField("비밀번호", text: $reviewPw)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)

                Button("로그인") {
                    Task { await performReviewSignIn() }
                }
                .buttonStyle(PixelButtonStyle(.primary))
                .frame(maxWidth: .infinity)
                .disabled(reviewId.isEmpty || reviewPw.isEmpty || isWorking)
            }
            .padding(.top, 8)
        }
        .font(PixelFont.labelSmall)
        .foregroundStyle(PixelColor.inkWeak)
        .padding(.horizontal, 24)
    }

    private func performReviewSignIn() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await authManager.signInWithReviewAccount(userId: reviewId, password: reviewPw)
            dismiss()
        } catch {
            errorMessage = "아이디 또는 비밀번호를 확인해주세요."
        }
    }

    private func performAppleSignIn() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await authManager.signInWithApple()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performGoogleSignIn() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await authManager.signInWithGoogle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
