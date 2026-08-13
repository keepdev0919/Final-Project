import SwiftUI
import FirebaseAuth

/// 프로필/로그인 진입 시트.
///
/// - 로그인 상태: 프로필 사진/이름/이메일/로그아웃 버튼 노출.
/// - 비로그인 상태: 로그인 안내 + 버튼 → `LoginSheet` 표시.
/// 개인정보 처리방침 URL.
///
/// ⚠️ **배포 전에 실제 주소로 교체할 것.** example.com을 그대로 두고 제출하면
/// 앱스토어에서 거절된다. 원문은 `docs/legal/privacy-policy.md`에 있다.
private let privacyPolicyURL = URL(string: "https://example.com/privacy")!

struct ProfileSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var showLoginSheet = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            Group {
                if let user = authManager.currentUser {
                    loggedInContent(user: user)
                } else {
                    loggedOutContent
                }
            }
            .navigationTitle("내 프로필")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginSheet()
                .environmentObject(authManager)
        }
    }

    // MARK: - Logged In

    @ViewBuilder
    private func loggedInContent(user: FirebaseAuth.User) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 16)

            AsyncImage(url: user.photoURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.gray.opacity(0.5))
                @unknown default:
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.orange.opacity(0.4), lineWidth: 2))

            VStack(spacing: 4) {
                Text(user.displayName ?? "이름 없음")
                    .font(.title3.weight(.semibold))
                if let email = user.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            Button(role: .destructive) {
                signOut()
            } label: {
                Text("로그아웃")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 24)

            // 계정 삭제 — 애플은 로그인 있는 앱에 앱 내 삭제 경로를 요구한다.
            // 없으면 앱스토어 심사에서 거절된다.
            Button("계정 삭제") {
                showDeleteConfirm = true
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .disabled(isDeleting)
            .padding(.top, 4)

            // KTO 데이터 출처 표기. 공지가 지정한 형식만 허용된다 —
            // 텍스트만 가능하고 공사 CI/BI 로고는 사용 금지.
            // 앱스토어 제출에 처리방침 URL이 필수다.
            Link("개인정보 처리방침", destination: privacyPolicyURL)
                .font(.footnote)
                .padding(.top, 12)

            // KTO 데이터 출처 표기. 공지가 지정한 형식만 허용된다 —
            // 텍스트만 가능하고 공사 CI/BI 로고는 사용 금지.
            Text("출처: ⓒ한국관광공사")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .padding(.top, 16)
        .alert("계정을 삭제할까요?", isPresented: $showDeleteConfirm) {
            Button("삭제", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장한 코스와 남긴 리뷰가 모두 지워집니다. 되돌릴 수 없어요.")
        }
        .overlay {
            if isDeleting {
                ProgressView().progressViewStyle(.circular)
            }
        }
    }

    // MARK: - Logged Out

    private var loggedOutContent: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 16)

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            VStack(spacing: 6) {
                Text("아직 로그인하지 않았어요")
                    .font(.title3.weight(.semibold))
                Text("로그인하면 다른 기기에서도\n같은 코스를 볼 수 있어요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                showLoginSheet = true
            } label: {
                Text("로그인")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
    }

    // MARK: - Actions

    private func deleteAccount() async {
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await authManager.deleteAccount()
            dismiss()
        } catch {
            // 재인증이 필요한 경우(오래된 세션) 등에서 실패할 수 있다.
            errorMessage = "계정 삭제에 실패했어요. 다시 로그인한 뒤 시도해주세요."
        }
    }

    private func signOut() {
        errorMessage = nil
        do {
            try authManager.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
