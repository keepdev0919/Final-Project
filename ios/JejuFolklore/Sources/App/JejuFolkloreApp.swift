import SwiftUI
import SwiftData
import GoogleMaps
import FirebaseCore
import GoogleSignIn

@main
struct JejuFolkloreApp: App {
    @StateObject private var authManager = AuthManager()

    init() {
        // Firebase 구성. GoogleService-Info.plist가 번들에 없으면 호출을 건너뛴다.
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        } else {
            #if DEBUG
            print("[Firebase] GoogleService-Info.plist 가 번들에 없습니다. Firebase 초기화를 건너뜁니다.")
            #endif
        }

        // Google Maps API 키는 환경변수 GOOGLE_MAPS_API_KEY 로 주입한다.
        // Xcode > Edit Scheme > Run > Arguments > Environment Variables 에서 설정하거나,
        // Info.plist 의 GOOGLE_MAPS_API_KEY 키를 사용한다.
        let envKey = ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"] ?? ""
        let plistKey = (Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String) ?? ""
        let apiKey = !envKey.isEmpty ? envKey : plistKey
        if !apiKey.isEmpty {
            GMSServices.provideAPIKey(apiKey)
        } else {
            #if DEBUG
            print("[GoogleMaps] API 키가 설정되지 않았습니다. GOOGLE_MAPS_API_KEY 환경변수를 설정하세요.")
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(for: SavedCourse.self)
    }
}
