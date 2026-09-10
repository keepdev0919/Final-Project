import SwiftUI
import SwiftData

/// 담아 둔 코스 목록. **프로필 탭 안의 한 섹션으로 들어간다** (2026-09-09 이동).
///
/// 전에는 코스 탭 위쪽 「코스 만들기 / 내 코스」 세그먼트의 한쪽이었다. 코스 탭은
/// 「어디 갈지 고르는 곳」이고 담아 둔 것을 보는 일은 성격이 달라서, 기록을 모으는
/// 프로필 탭으로 옮겼다.
///
/// ⚠️ `NavigationStack` 을 자체적으로 만들지 않는다 — 탭마다 이미 하나씩 있고,
/// 겹치면 뒤로가기와 화면 전환이 어긋난다.
///
/// **로그인 없이도 남는다.** `SavedCourse` 는 SwiftData 모델이라 기기 안에 저장된다.
/// 2026-09-09에 걷어낸 Firestore 동기화는 「다른 기기에서도 같은 코스 보기」였을 뿐이다.
struct MyCourseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedCourse.savedAt, order: .reverse) private var courses: [SavedCourse]
    @State private var selectedCourse: SavedCourse?

    var body: some View {
        Group {
            if courses.isEmpty {
                // ContentUnavailableView는 SF Symbol 이름(String)만 받아
                // 도트 아이콘을 넣을 수 없다. 그래서 직접 그린다.
                VStack(spacing: PixelSpacing.s) {
                    PixelIcon(.map, size: 32, color: PixelColor.inkWeak)
                    Text("담아 둔 코스가 없어요")
                        .font(PixelFont.body)
                        .foregroundStyle(PixelColor.ink)
                    Text("코스 탭에서 마음에 드는 코스를 담아보세요")
                        .font(PixelFont.labelSmall)
                        .foregroundStyle(PixelColor.inkWeak)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, PixelSpacing.xxl)
            } else {
                // ⚠️ `List` 를 쓰지 않는다. 프로필 탭의 스크롤 안에 들어가므로
                // 스크롤이 두 겹이 되고, 시스템 행 스타일이 픽셀 카드와도 어긋난다.
                LazyVStack(spacing: PixelSpacing.cardGap) {
                    ForEach(courses) { course in
                        Button { selectedCourse = course } label: {
                            SavedCourseRow(course: course)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(PixelSpacing.cardPadding)
                                .background(PixelColor.surface)
                                .pixelBorder()
                                .pixelShadow(PixelSpacing.shadowCard)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $selectedCourse) { course in
            SavedCourseDetailView(course: course)
        }
    }
}

struct SavedCourseRow: View {
    let course: SavedCourse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.title)
                .font(PixelFont.body)
            HStack {
                Label { Text("\(course.durationDays)일") } icon: { PixelIcon(.calendar, size: 16) }
                Label { Text("\(course.places.count)개 장소") } icon: { PixelIcon(.mapPin, size: 16) }
            }
            .font(PixelFont.labelSmall)
            .foregroundColor(PixelColor.inkWeak)
        }
        .padding(.vertical, 4)
    }
}

/// 담아 둔 코스를 여는 화면.
///
/// **코스 탭에서 보던 상세 화면과 같은 것을 띄운다** (2026-09-09 조익준님 결정).
/// 전에는 여기만 따로 만든 화면이라 지도도 날짜별 목록도 없이 「탐험 시작」 버튼만
/// 있었다. 같은 코스인데 어디서 열었느냐에 따라 다른 화면이 나올 이유가 없다.
///
/// 다른 점은 하나뿐이다 — 「담기」를 숨긴다. 이미 담아 둔 코스다.
struct SavedCourseDetailView: View {
    @Bindable var course: SavedCourse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showEditTitle = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            CoursePreviewView(
                course: Course(
                    id: course.id,
                    title: course.title,
                    durationDays: course.durationDays,
                    places: course.places,
                    estimatedMinutes: course.estimatedMinutes,
                    sourceCourseId: course.sourceCourseId ?? ""
                ),
                showsSaveButton: false,
                onRename: { showEditTitle = true },
                onDelete: { confirmDelete = true }
            )
        }
        .sheet(isPresented: $showEditTitle) {
            EditCourseTitleSheet(course: course)
        }
        // 삭제는 되돌릴 수 없으므로 한 번 묻는다.
        .alert("이 코스를 뺄까요?", isPresented: $confirmDelete) {
            Button("취소", role: .cancel) {}
            Button("빼기", role: .destructive) {
                modelContext.delete(course)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("「\(course.title)」이 내 코스에서 사라져요. 코스 탭에서 다시 담을 수 있어요.")
        }
    }
}

struct EditCourseTitleSheet: View {
    @Bindable var course: SavedCourse
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("코스 이름") {
                    TextField("코스 이름", text: $draft)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }
            }
            .navigationTitle("코스 이름 변경")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        course.title = trimmed
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || trimmed == course.title)
                }
            }
            .onAppear { draft = course.title }
        }
        .presentationDetents([.medium])
    }
}
