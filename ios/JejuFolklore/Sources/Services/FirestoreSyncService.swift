import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseStorage

/// Firestore와 SwiftData(SavedCourse) 간 양방향 동기화 서비스.
///
/// - Cloud Firestore의 오프라인 캐시 + 서버 타임스탬프 기반 Last-Write-Wins 전략을 활용한다.
/// - 로그인 사용자의 `users/{uid}/savedCourses/{courseId}` 컬렉션을 구독해
///   원격 변경분을 로컬 SwiftData로 upsert한다.
/// - 이미지(journalImageData)는 Storage `users/{uid}/journal-images/{courseId}.jpg`에
///   업로드 후 downloadURL을 `journalImageUrl`로 저장한다 (현 단계는 placeholder, 텍스트만 동작).
@MainActor
final class FirestoreSyncService: ObservableObject {
    static let shared = FirestoreSyncService()

    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Listener

    /// 지정한 사용자의 savedCourses 컬렉션을 구독한다.
    /// 호출 시 기존 listener는 자동으로 제거된다.
    func startListening(uid: String, modelContext: ModelContext) {
        stopListening()

        let ref = db.collection("users").document(uid).collection("savedCourses")
        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                print("[FirestoreSync] snapshot error: \(error.localizedDescription)")
                return
            }
            guard let snapshot else { return }

            Task { @MainActor in
                for change in snapshot.documentChanges {
                    let docId = change.document.documentID
                    switch change.type {
                    case .added, .modified:
                        let data = change.document.data()
                        SavedCourse.upsert(from: data, id: docId, into: modelContext)
                    case .removed:
                        self.deleteLocalCourse(id: docId, in: modelContext)
                    }
                }
                try? modelContext.save()
            }
        }
    }

    /// 활성 listener를 해제한다 (로그아웃 시 호출).
    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Push / Delete

    /// 로컬 SavedCourse를 Firestore에 upsert.
    func pushSavedCourse(_ course: SavedCourse, uid: String) async throws {
        let ref = db
            .collection("users").document(uid)
            .collection("savedCourses").document(course.id)

        var data = course.toFirestoreData()

        // 이미지 업로드: 데이터가 있고 아직 URL이 없을 때만 업로드 (placeholder 구현)
        if let imageData = course.journalImageData, course.journalImageUrl == nil {
            do {
                let url = try await uploadJournalImage(
                    data: imageData,
                    uid: uid,
                    courseId: course.id
                )
                data["journalImageUrl"] = url
                course.journalImageUrl = url
            } catch {
                // 이미지 업로드 실패해도 메타 데이터는 푸시
                print("[FirestoreSync] image upload failed: \(error.localizedDescription)")
            }
        }

        // userId가 비어있으면 현재 uid로 채워서 푸시
        if data["userId"] == nil {
            data["userId"] = uid
        }
        if course.userId == nil {
            course.userId = uid
        }

        try await ref.setData(data, merge: true)
    }

    /// Firestore에서 특정 코스 문서를 삭제.
    func deleteSavedCourse(id: String, uid: String) async throws {
        let ref = db
            .collection("users").document(uid)
            .collection("savedCourses").document(id)
        try await ref.delete()
    }

    // MARK: - Anonymous Migration

    /// 익명 상태에서 로컬에 저장된 코스들을 로그인 계정으로 이관.
    /// - 각 코스의 `userId`를 채우고 Firestore로 push.
    func migrateAnonymousCourses(to uid: String, courses: [SavedCourse]) async throws {
        for course in courses {
            course.userId = uid
            try await pushSavedCourse(course, uid: uid)
        }
    }

    // MARK: - Private helpers

    private func deleteLocalCourse(id: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<SavedCourse>(
            predicate: #Predicate<SavedCourse> { $0.id == id }
        )
        guard let existing = (try? context.fetch(descriptor))?.first else { return }
        context.delete(existing)
    }

    /// Journal 이미지를 Storage에 업로드하고 downloadURL을 반환한다.
    private func uploadJournalImage(
        data: Data,
        uid: String,
        courseId: String
    ) async throws -> String {
        let ref = storage.reference()
            .child("users/\(uid)/journal-images/\(courseId).jpg")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        return try await withCheckedThrowingContinuation { continuation in
            ref.putData(data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                ref.downloadURL { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let url else {
                        continuation.resume(throwing: NSError(
                            domain: "FirestoreSyncService",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "downloadURL missing"]
                        ))
                        return
                    }
                    continuation.resume(returning: url.absoluteString)
                }
            }
        }
    }
}
