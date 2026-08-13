import SwiftUI
import FirebaseAuth

/// 개인정보 처리방침 URL.
///
/// ⚠️ **배포 전에 실제 주소로 교체할 것.** example.com을 그대로 두고 제출하면
/// 앱스토어에서 거절된다. 원문은 `docs/legal/privacy-policy.md`에 있다.
private let privacyPolicyURL = URL(string: "https://example.com/privacy")!

/// "내 것" 탭이 품는 프로필 블록. 시트로도 쓸 수 있게 화면과 분리했다.
struct ProfileSection: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var showLoginSheet = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.l) {
            if let user = authManager.currentUser {
                loggedIn(user: user)
            } else {
                loggedOut
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(PixelFont.longform(14))
                    .foregroundStyle(PixelColor.locked)
            }

            Link(destination: privacyPolicyURL) {
                Text("개인정보 처리방침")
                    .pixelFont(PixelFont.badge)
                    .foregroundStyle(PixelColor.primary)
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginSheet().environmentObject(authManager)
        }
        .alert("계정을 삭제할까요?", isPresented: $showDeleteConfirm) {
            Button("삭제", role: .destructive) { Task { await deleteAccount() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장한 코스와 남긴 리뷰가 모두 지워집니다. 되돌릴 수 없어요.")
        }
        .overlay { if isDeleting { ProgressView() } }
    }

    // MARK: - 로그인 상태

    @ViewBuilder
    private func loggedIn(user: FirebaseAuth.User) -> some View {
        PixelCard {
            VStack(alignment: .leading, spacing: PixelSpacing.m) {
                HStack(spacing: PixelSpacing.m) {
                    // 원형 프로필 사진은 반경 0 규칙과 어긋난다. 사각 프레임에 넣는다.
                    Group {
                        if let url = user.photoURL {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                PixelIcon(.person, size: 32, color: PixelColor.inkWeak)
                            }
                        } else {
                            PixelIcon(.person, size: 32, color: PixelColor.inkWeak)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipped()
                    .pixelBorder(PixelColor.ink, width: PixelSpacing.borderThin)

                    VStack(alignment: .leading, spacing: PixelSpacing.xs) {
                        Text(user.displayName ?? "이름 없음")
                            .pixelFont(PixelFont.cardTitle)
                            .foregroundStyle(PixelColor.ink)
                        if let email = user.email {
                            Text(email)
                                .pixelFont(PixelFont.badge)
                                .foregroundStyle(PixelColor.inkWeak)
                        }
                    }
                }

                PixelButton(title: "로그아웃", style: .plain) { signOut() }

                // 애플은 로그인 있는 앱에 앱 내 계정 삭제 경로를 요구한다.
                // 없으면 앱스토어 심사에서 거절된다.
                Button {
                    showDeleteConfirm = true
                } label: {
                    Text("계정 삭제")
                        .pixelFont(PixelFont.badge)
                        .foregroundStyle(PixelColor.locked)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
            }
            .padding(PixelSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 비로그인 상태

    private var loggedOut: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: PixelSpacing.m) {
                Text("아직 로그인하지 않았어요")
                    .pixelFont(PixelFont.cardTitle)
                    .foregroundStyle(PixelColor.ink)
                Text("로그인하면 다른 기기에서도\n같은 코스를 볼 수 있어요")
                    .pixelFont(PixelFont.badge)
                    .foregroundStyle(PixelColor.inkWeak)
                PixelButton(title: "로그인", style: .primary) { showLoginSheet = true }
            }
            .padding(PixelSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 동작

    private func deleteAccount() async {
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await authManager.deleteAccount()
        } catch {
            // 마지막 로그인이 오래되면 Firebase가 requiresRecentLogin으로 거부한다.
            // deleteAccount는 Auth 삭제를 서버 삭제보다 먼저 하므로, 이 실패 시점에
            // 계정과 서버 데이터가 남아 있다 — 재시도가 실제로 의미를 갖는다.
            errorMessage = "계정 삭제에 실패했어요. 로그아웃 후 다시 로그인한 뒤 시도해주세요."
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

/// 기존 진입 경로(시트)를 유지하기 위한 얇은 껍데기.
struct ProfileSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ProfileSection()
                    .environmentObject(authManager)
                    .padding(PixelSpacing.screenMargin)
            }
            .background(PixelColor.background.ignoresSafeArea())
            .navigationTitle("내 프로필")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
