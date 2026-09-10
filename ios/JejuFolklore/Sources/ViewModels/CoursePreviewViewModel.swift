import Foundation
import SwiftData

@MainActor
final class CoursePreviewViewModel: ObservableObject {
    let course: Course
    @Published var isSaved = false
    /// 화면 위에 잠깐 떴다 사라지는 알림. nil 이면 아무것도 안 뜬다.
    @Published var toastText: String?
    /// 실패 알림인지. 성공과 **다른 색**으로 띄운다.
    @Published var toastIsError = false

    init(course: Course) {
        self.course = course
    }

    /// 이미 담아 둔 코스인지 확인해 버튼 상태를 맞춘다.
    ///
    /// ⚠️ 화면에 들어올 때마다 부른다. `isSaved` 를 화면 안에서만 들고 있으면
    /// 뒤로 갔다 다시 들어왔을 때 「담기」가 되살아나 **같은 코스가 목록에 두 번**
    /// 쌓인다 (2026-09-09 조익준님 지적).
    func refreshSavedState(context: ModelContext) {
        isSaved = Self.alreadySaved(identityKey, in: context)
    }

    /// 이 코스의 신원. 서버가 상세마다 새 UUID 를 `id` 로 주므로 그것으로는
    /// 같은 코스인지 알 수 없다 — `sourceCourseId` 가 진짜 신원이다.
    private var identityKey: String {
        course.sourceCourseId.isEmpty ? course.id : course.sourceCourseId
    }

    func save(context: ModelContext) {
        guard !isSaved else { return }

        // 화면 상태만 믿지 않고 저장소를 다시 본다 — 다른 경로로 이미 담겼을 수 있다.
        if Self.alreadySaved(identityKey, in: context) {
            isSaved = true
            show("이미 담아 둔 코스예요")
            return
        }

        let saved = SavedCourse(from: course)
        context.insert(saved)
        do {
            try context.save()
        } catch {
            // ⚠️ 실패했는데 「저장됐어요」라고 말하지 않는다 (2026-09-09 조익준님 지적).
            // 전에는 `try?` 로 에러를 삼키고 곧바로 성공 알림을 띄워서, 실제로는
            // 안 담겼는데 화면은 담았다고 말했다. 담을 뻔한 것도 도로 뺀다.
            context.delete(saved)
            isSaved = false
            show("담지 못했어요. 잠시 후 다시 시도해 주세요", isError: true)
            return
        }
        isSaved = true
        show("코스가 저장됐어요!")
    }

    /// ⚠️ `#Predicate` 로 거르지 않는다. `FetchDescriptor(predicate:)` 로 짰더니
    /// 방금 담은 코스를 다시 열어도 못 찾아서 「담기」가 되살아났다. 담아 둔 코스는
    /// 많아야 수십 개라 전부 가져와 손으로 거르는 편이 확실하다 — `ExploreView`
    /// 도 같은 이유로 그렇게 한다 (2026-09-09).
    private static func alreadySaved(_ key: String, in context: ModelContext) -> Bool {
        let all = (try? context.fetch(FetchDescriptor<SavedCourse>())) ?? []
        return all.contains { $0.identityKey == key }
    }

    private func show(_ text: String, isError: Bool = false) {
        toastText = text
        toastIsError = isError
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            toastText = nil
        }
    }
}
