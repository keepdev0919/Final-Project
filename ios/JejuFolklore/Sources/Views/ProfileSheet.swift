import SwiftUI
import FirebaseAuth

/// 프로필/로그인 진입 시트.
///
/// - 로그인 상태: 프로필 사진/이름/이메일/로그아웃 버튼 노출.
/// - 비로그인 상태: 로그인 안내 + 버튼 → `LoginSheet` 표시.
struct ProfileSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var showLoginSheet = false
    @State private var errorMessage: String?

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
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
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

    private func signOut() {
        errorMessage = nil
        do {
            try authManager.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
