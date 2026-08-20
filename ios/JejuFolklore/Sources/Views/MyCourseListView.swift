import SwiftUI
import SwiftData

struct MyCourseListView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedCourse.savedAt, order: .reverse) private var courses: [SavedCourse]
    @Query(filter: #Predicate<SavedCourse> { $0.userId == nil })
    private var anonymousCourses: [SavedCourse]
    @State private var selectedCourse: SavedCourse?
    /// 방금 완료된 코스 ID — 비어있지 않으면 해당 셀 배경을 1.5초간 하이라이트.
    @State private var highlightedCourseId: String? = nil
    @State private var showProfile = false
    @State private var showLogin = false
    @State private var showMigrationDialog = false
    @State private var pendingMigrationUid: String?

    var body: some View {
        NavigationStack {
            Group {
                if courses.isEmpty {
                    // ContentUnavailableView는 SF Symbol 이름(String)만 받아
                    // 도트 아이콘을 넣을 수 없다. 그래서 직접 그린다.
                    VStack(spacing: PixelSpacing.l) {
                        PixelIcon(.map, size: 48, color: PixelColor.inkWeak)
                        Text("저장된 코스가 없어요")
                            .font(PixelFont.sectionTitle)
                            .foregroundStyle(PixelColor.ink)
                        Text("코스를 추천받고 저장해보세요")
                            .font(PixelFont.body)
                            .foregroundStyle(PixelColor.inkWeak)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PixelColor.background)
                } else {
                    ScrollViewReader { proxy in
                        List(courses) { course in
                            SavedCourseRow(course: course)
                                .listRowBackground(
                                    highlightedCourseId == course.id
                                        ? PixelColor.primary.opacity(0.18)
                                        : PixelColor.surface
                                )
                                .listRowSeparatorTint(PixelColor.ink)
                                .id(course.id)
                                .onTapGesture { selectedCourse = course }
                        }
                        // .insetGrouped는 행을 둥글게 만든다 — 모서리를 굴리지 않는다(§5).
                        // scrollContentBackground를 숨겨야 시스템 회색 바탕이 사라진다.
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(PixelColor.background)
                        .animation(.easeInOut(duration: 0.35), value: highlightedCourseId)
                        .onAppear { consumeJustCompletedCourse(scrollProxy: proxy) }
                    }
                }
            }
            .navigationTitle("내 코스")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    profileButton
                }
            }
            .sheet(item: $selectedCourse) { course in
                SavedCourseDetailView(course: course)
            }
            .sheet(isPresented: $showProfile) {
                ProfileSheet()
            }
            .sheet(isPresented: $showLogin) {
                LoginSheet()
            }
            .onChange(of: authManager.isLoggedIn) { _, isLoggedIn in
                handleLoginChange(isLoggedIn: isLoggedIn)
            }
            .confirmationDialog(
                "기존 \(anonymousCourses.count)개 코스를 계정에 연결할까요?",
                isPresented: $showMigrationDialog,
                titleVisibility: .visible
            ) {
                Button("연결하기") {
                    runMigration()
                }
                Button("나중에", role: .cancel) {
                    pendingMigrationUid = nil
                }
            } message: {
                Text("연결하면 다른 기기에서도 코스를 볼 수 있어요.")
            }
        }
    }

    @ViewBuilder
    private var profileButton: some View {
        Button {
            if authManager.isLoggedIn {
                showProfile = true
            } else {
                showLogin = true
            }
        } label: {
            if authManager.isLoggedIn, let url = authManager.currentUser?.photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        // 도트 아이콘은 비트맵이라 resizable/scaledToFit이 없다.
                        // 크기는 size:로 정한다.
                        PixelIcon(.person, size: 20, color: PixelColor.inkWeak)
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(Rectangle())
            } else {
                PixelIcon(.person, size: 16)
                    .foregroundColor(PixelColor.inkWeak)
            }
        }
        .accessibilityLabel(authManager.isLoggedIn ? "프로필" : "로그인")
    }

    /// 로그인 상태가 변할 때 익명 코스 마이그레이션 다이얼로그 노출 판단.
    private func handleLoginChange(isLoggedIn: Bool) {
        guard isLoggedIn,
              let uid = authManager.currentUser?.uid,
              !anonymousCourses.isEmpty else {
            return
        }
        pendingMigrationUid = uid
        showMigrationDialog = true
    }

    private func runMigration() {
        guard let uid = pendingMigrationUid else { return }
        let target = anonymousCourses
        pendingMigrationUid = nil
        Task { @MainActor in
            do {
                try await FirestoreSyncService.shared
                    .migrateAnonymousCourses(to: uid, courses: target)
                try? modelContext.save()
            } catch {
                print("[MyCourseListView] migration failed: \(error.localizedDescription)")
            }
        }
    }

    /// AppStorage("just_completed_course_id")를 한 번 소비:
    /// 1) 해당 셀로 스크롤,
    /// 2) 1.5초간 배경 하이라이트,
    /// 3) 키 제거 (중복 트리거 방지).
    private func consumeJustCompletedCourse(scrollProxy: ScrollViewProxy) {
        let key = "just_completed_course_id"
        guard let courseId = UserDefaults.standard.string(forKey: key),
              !courseId.isEmpty,
              courses.contains(where: { $0.id == courseId }) else {
            return
        }

        UserDefaults.standard.removeObject(forKey: key)

        // 다음 runloop에서 스크롤 (List 셀 mount 완료 후)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(courseId, anchor: .center)
            }
            withAnimation(.easeInOut(duration: 0.35)) {
                highlightedCourseId = courseId
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    highlightedCourseId = nil
                }
            }
        }
    }
}

struct SavedCourseRow: View {
    let course: SavedCourse

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()

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

            if course.hasExploration {
                HStack(spacing: 6) {
                    Text("🎨 탐험 완료")
                        .font(PixelFont.labelSmall)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(PixelColor.primary.opacity(0.15))
                        .foregroundColor(PixelColor.primary)
                        .clipShape(Rectangle())
                    if let exploredAt = course.exploredAt {
                        Text(Self.dateFormatter.string(from: exploredAt))
                            .font(PixelFont.labelSmall)
                            .foregroundColor(PixelColor.inkWeak)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SavedCourseDetailView: View {
    @Bindable var course: SavedCourse
    @State private var startExplore = false
    @State private var showEditTitle = false
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일"
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 탐험 기록 (있을 때만)
                    if course.hasExploration {
                        explorationSection
                    }

                    // 탐험 시작 — 아직 한 곳도 방문하지 않은 코스에만 노출.
                    // (탐험 완료 코스의 "다시 탐험하기" 기능은 제거됨)
                    //
                    // 게이트가 hasExploration이 아니라 hasVisitedAnyPlace인 이유는
                    // SavedCourse의 해당 주석 참조 — 실수로 "탐험 마치기"를 누른
                    // 경우를 영구 잠금으로 만들지 않기 위함이다.
                    if !course.hasVisitedAnyPlace {
                        Button("탐험 시작") {
                            startExplore = true
                        }
                        .buttonStyle(PixelButtonStyle(.primary))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle(course.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showEditTitle = true
                        } label: {
                            Label { Text("코스 이름 변경") } icon: { PixelIcon(.edit, size: 16) }
                        }
                    } label: {
                        PixelIcon(.more)
                    }
                }
            }
            .navigationDestination(isPresented: $startExplore) {
                ExploreView(
                    course: Course(
                        id: course.id,
                        title: course.title,
                        durationDays: course.durationDays,
                        places: course.places,
                        estimatedMinutes: course.estimatedMinutes
                    ),
                    transport: "car"
                )
            }
            .sheet(isPresented: $showEditTitle) {
                EditCourseTitleSheet(course: course)
            }
        }
        // 탐험 완료 시 sheet 자체를 닫아 MyCourseList(탭 root)로 복귀.
        // sheet 내부의 NavigationStack에서 ExploreView dismiss만으로는 sheet가 닫히지 않음.
        .onReceive(NotificationCenter.default.publisher(for: .exploreDidComplete)) { _ in
            startExplore = false
            dismiss()
        }
    }

    private var explorationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("탐험 기록")
                    .font(PixelFont.label)
                Spacer()
                if let exploredAt = course.exploredAt {
                    Text(Self.dateFormatter.string(from: exploredAt))
                        .font(PixelFont.labelSmall)
                        .foregroundColor(PixelColor.inkWeak)
                }
            }
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                // 방문한 장소들
                if let visited = course.visitedPlaceNames, !visited.isEmpty {
                    Divider()
                    Text("방문한 장소")
                        .font(PixelFont.body)
                        .foregroundColor(PixelColor.inkWeak)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(visited, id: \.self) { name in
                            HStack(spacing: 8) {
                                PixelIcon(.check, size: 12, color: PixelColor.primary)
                                Text(name)
                                    .font(PixelFont.body)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(PixelColor.surfaceLow)
            .clipShape(Rectangle())
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Edit Sheets

struct EditCourseTitleSheet: View {
    @Bindable var course: SavedCourse
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
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
                        syncToFirestore()
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || trimmed == course.title)
                }
            }
            .onAppear { draft = course.title }
        }
        .presentationDetents([.medium])
    }

    private func syncToFirestore() {
        guard let uid = authManager.currentUser?.uid else { return }
        Task { @MainActor in
            try? await FirestoreSyncService.shared.pushSavedCourse(course, uid: uid)
        }
    }
}
