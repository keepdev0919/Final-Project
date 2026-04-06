import SwiftUI
import SwiftData

@main
struct JejuFolkloreApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedCourse.self)
    }
}
