import Foundation
import SwiftData

@MainActor
final class CoursePreviewViewModel: ObservableObject {
    let course: Course
    @Published var isSaved = false
    @Published var showSavedToast = false

    init(course: Course) {
        self.course = course
    }

    func save(context: ModelContext) {
        let saved = SavedCourse(from: course)
        context.insert(saved)
        try? context.save()
        isSaved = true
        showSavedToast = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSavedToast = false
        }
    }
}
