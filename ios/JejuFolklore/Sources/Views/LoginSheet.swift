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

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)

                Text("로그인하면 다른 기기에서도\n같은 코스를 볼 수 있어요")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("코스, 여행 기록이 안전하게 보관됩니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(isWorking)

                Button(action: { Task { await performGoogleSignIn() } }) {
                    HStack(spacing: 10) {
                        Image(systemName: "g.circle.fill")
                            .font(.title3)
                        Text("Google로 계속하기")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(.white)
                    .background(Color(.sRGB, red: 0.26, green: 0.52, blue: 0.96, opacity: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isWorking)
            }
            .padding(.horizontal, 24)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button("건너뛰기") {
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Actions

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
