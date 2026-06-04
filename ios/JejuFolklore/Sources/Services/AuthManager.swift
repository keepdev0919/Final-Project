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
