import SwiftUI

struct PlaceReviewSheet: View {
    let placeName: String
    let companion: CompanionCharacter
    let onDone: () -> Void

    private static let tags: [(key: String, display: String)] = [
        ("소름 돋아요", "👻 소름 돋아요"),
        ("감동이에요",  "🥹 감동이에요"),
        ("신기해요",   "🤔 신기해요"),
        ("무서워요",   "😱 무서워요"),
        ("역사적이에요","📜 역사적이에요"),
    ]

    @State private var selectedKeys: Set<String> = []
    @State private var note: String = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(placeName)")
                    .font(.title3.weight(.semibold))
                Text("어떤 설화 경험이었나요?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Self.tags, id: \.key) { tag in
                        Button {
                            if selectedKeys.contains(tag.key) {
                                selectedKeys.remove(tag.key)
                            } else {
                                selectedKeys.insert(tag.key)
                            }
                        } label: {
                            Text(tag.display)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    selectedKeys.contains(tag.key)
                                        ? companion.themeColor.opacity(0.15)
                                        : Color(.secondarySystemBackground)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            selectedKeys.contains(tag.key)
                                                ? companion.themeColor
                                                : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)
                    }
                }

                TextField("한 줄 감상 남기기 (선택, 200자)", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: note) {
                        if note.count > 200 { note = String(note.prefix(200)) }
                    }

                Spacer()

                HStack(spacing: 12) {
                    Button("건너뛰기") { onDone() }
                        .buttonStyle(.bordered)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)

                    Button(isSubmitting ? "저장 중..." : "남기기 →") {
                        Task { await submit() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(companion.themeColor)
                    .disabled(selectedKeys.isEmpty || isSubmitting)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func submit() async {
        isSubmitting = true
        await APIClient.shared.submitReview(
            placeName: placeName,
            tags: Array(selectedKeys),
            note: note.isEmpty ? nil : note
        )
        isSubmitting = false
        onDone()
    }
}
