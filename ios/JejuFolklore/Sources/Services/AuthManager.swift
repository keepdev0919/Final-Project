import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import GoogleSignIn
import UIKit

/// Firebase Auth + Google/Apple Sign-In 통합 관리자.
///
/// - 앱 시작 시 `JejuFolkloreApp.init()`에서 `FirebaseApp.configure()`가 호출되어야 한다.
/// - SwiftUI `EnvironmentObject`로 주입하여 `LoginSheet`/`ProfileSheet` 등에서 사용한다.
/// - 로그인/로그아웃 시 `currentUser`가 자동으로 갱신되며, `isLoggedIn`으로 분기할 수 있다.
@MainActor
final class AuthManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var currentUser: User?

    var isLoggedIn: Bool { currentUser != nil }

    // MARK: - 계정 삭제

    /// 계정과 관련 데이터를 모두 삭제한다. **되돌릴 수 없다.**
    ///
    /// 애플은 로그인 기능이 있는 앱에 앱 내 계정 삭제 경로를 요구하고, 없으면
    /// 앱스토어 심사에서 거절한다.
    ///
    /// ## 순서 — Auth 삭제를 서버 삭제보다 먼저 한다
    ///
    /// 1. ID 토큰 확보 (Auth 삭제 후에도 서버 인증에 쓴다)
    /// 2. `stopListening()` — 리스너가 살아 있으면 삭제 중 로컬에 다시 쓸 수 있다
    /// 3. Firestore 삭제 — 보안 규칙이 `request.auth.uid`를 보므로 Auth가 살아 있어야 한다
    /// 4. **Firebase Auth 삭제** ← 실패하면 여기서 중단한다
    /// 5. 서버 삭제 — 1에서 받은 토큰을 쓴다
    ///
    /// **4를 5보다 먼저 두는 이유:** `user.delete()`는 마지막 로그인이 오래되면
    /// `requiresRecentLogin`으로 실패한다. 서버·Firestore를 먼저 다 지우고 4에서
    /// 실패하면 **데이터는 사라졌는데 계정만 남고, 재시도해도 지울 것이 없어**
    /// 되돌릴 수 없는 반쪽 상태가 된다.
    ///
    /// 순서를 바꾸면 4에서 실패해도 계정과 서버 데이터가 남아 **재시도가 실제로
    /// 의미를 갖는다.** 3은 멱등하므로 재시도해도 문제없다.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        let deviceId = DeviceIdentity.shared.id

        // 1. Auth 삭제 뒤에도 서버를 호출할 수 있도록 토큰을 미리 받는다
        let idToken = try await user.getIDToken()

        // 2. 삭제 중 원격 변경이 로컬로 되돌아오지 않게 리스너를 끊는다
        FirestoreSyncService.shared.stopListening()

        // 3. Firestore — Auth가 살아 있어야 권한이 있다
        do {
            try await FirestoreSyncService.shared.deleteAllUserData(uid: uid)
        } catch {
            print("[AuthManager] Firestore 삭제 실패(계속 진행): \(error.localizedDescription)")
        }

        // 4. Auth 레코드. 실패하면 throw되어 아래 서버 삭제까지 가지 않는다
        try await user.delete()

        // 5. 서버 데이터 — 미리 받아둔 토큰으로 인증한다
        do {
            struct Body: Encodable { let deviceId: String }
            try await APIClient.shared.delete(
                "/account",
                body: Body(deviceId: deviceId),
                bearerToken: idToken
            )
        } catch {
            print("[AuthManager] 서버 데이터 삭제 실패: \(error.localizedDescription)")
        }

        currentUser = nil
    }

    // MARK: - 심사용 ID/PW 로그인

    /// 심사용 계정으로 로그인한다.
    ///
    /// 공모전 요건상 심사위원이 지정 형식 계정으로 로그인해 서비스 전체를 확인할 수
    /// 있어야 하고, 로그인 실패 시 심사에서 제외된다. 같은 계정을 애플 앱스토어
    /// 심사용 로그인 정보로도 제출한다.
    ///
    /// 백엔드가 자격 증명을 확인하고 Firebase 커스텀 토큰을 발급한다 — 그 뒤는
    /// 소셜 로그인 사용자와 완전히 같은 경로를 타므로 Firestore 동기화와 향후
    /// 결제 기간 기록이 별도 분기 없이 동작한다.
    func signInWithReviewAccount(userId: String, password: String) async throws {
        // APIClient의 인코더는 convertToSnakeCase, 디코더는 convertFromSnakeCase다.
        // 따라서 Swift 쪽은 camelCase로 써야 한다 —
        // userId → user_id (전송), custom_token → customToken (수신).
        struct Body: Encodable {
            let userId: String
            let password: String
        }
        struct Response: Decodable {
            let customToken: String
        }

        let response: Response = try await APIClient.shared.post(
            "/auth/local",
            body: Body(userId: userId, password: password)
        )
        _ = try await Auth.auth().signIn(withCustomToken: response.customToken)
    }

    // MARK: - Apple Sign-In 임시 상태

    /// Apple 로그인 콜백에서 사용할 raw nonce. 요청 직전에 새로 생성된다.
    private var currentNonce: String?

    /// Apple 로그인 비동기 콜백을 async/await 으로 잇기 위한 continuation.
    private var appleSignInContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Lifecycle

    override init() {
        super.init()
        // Firebase가 구성된 경우에만 listener를 등록한다.
        // (테스트/미구성 환경에서 크래시 방지)
        if FirebaseAuth.Auth.auth().app != nil {
            Auth.auth().addStateDidChangeListener { [weak self] _, user in
                Task { @MainActor in
                    self?.currentUser = user
                }
            }
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() async throws {
        guard let presentingVC = Self.topPresentingViewController() else {
            throw AuthError.noPresentingViewController
        }

        // GoogleService-Info.plist의 CLIENT_ID로부터 GIDConfiguration이 자동 구성되어야 한다.
        // Firebase 구성 후 GIDSignIn.sharedInstance.configuration 가 nil 이면 수동 설정한다.
        if GIDSignIn.sharedInstance.configuration == nil {
            if let clientID = FirebaseAuth.Auth.auth().app?.options.clientID {
                GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            }
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingIDToken
        }
        let accessToken = result.user.accessToken.tokenString

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )
        _ = try await Auth.auth().signIn(with: credential)
    }

    // MARK: - Apple Sign-In

    func signInWithApple() async throws {
        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.appleSignInContinuation = continuation
            controller.performRequests()
        }
    }

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    // MARK: - Helpers

    /// 현재 활성 윈도우 씬의 rootViewController를 가져온다.
    static func topPresentingViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let keyWindow = activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    /// Apple Sign-In 용 랜덤 nonce 생성 (RFC 7636 권장 길이).
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case noPresentingViewController
    case missingIDToken
    case appleInvalidCredential
    case appleMissingNonce

    var errorDescription: String? {
        switch self {
        case .noPresentingViewController: return "로그인 화면을 표시할 수 없습니다."
        case .missingIDToken: return "ID 토큰을 가져오지 못했습니다."
        case .appleInvalidCredential: return "Apple 로그인 정보를 처리할 수 없습니다."
        case .appleMissingNonce: return "Apple 로그인 nonce가 누락되었습니다."
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let continuation = self.appleSignInContinuation else { return }
            self.appleSignInContinuation = nil

            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                continuation.resume(throwing: AuthError.appleInvalidCredential)
                return
            }
            guard let nonce = self.currentNonce else {
                continuation.resume(throwing: AuthError.appleMissingNonce)
                return
            }
            guard let identityTokenData = appleCredential.identityToken,
                  let idTokenString = String(data: identityTokenData, encoding: .utf8) else {
                continuation.resume(throwing: AuthError.missingIDToken)
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleCredential.fullName
            )

            do {
                _ = try await Auth.auth().signIn(with: credential)
                self.currentNonce = nil
                continuation.resume()
            } catch {
                self.currentNonce = nil
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            guard let continuation = self.appleSignInContinuation else { return }
            self.appleSignInContinuation = nil
            self.currentNonce = nil
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        // 메인 스레드에서 동기 조회. 일반적으로 호출 컨텍스트가 메인이므로 안전하다.
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                AuthManager.topPresentingViewController()?.view.window ?? UIWindow()
            }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                AuthManager.topPresentingViewController()?.view.window ?? UIWindow()
            }
        }
    }
}
