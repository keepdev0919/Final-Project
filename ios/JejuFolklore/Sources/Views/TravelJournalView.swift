// ios/JejuFolklore/Sources/Views/TravelJournalView.swift
import SwiftUI

struct TravelJournalView: View {
    let journalText: String
    let visitedPlaces: [String]
    let companion: CompanionCharacter
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(companion.emoji) \(companion.displayName)와 함께한 여행")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.orange)

                        Text("나의 제주 여행 일지")
                            .font(.title2.weight(.bold))

                        Text("방문: \(visitedPlaces.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Divider()
                        .padding(.horizontal, 20)

                    Text(journalText)
                        .font(.body)
                        .lineSpacing(6)
                        .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("여행 일지")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료", action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Loading state

struct JournalLoadingView: View {
    let companion: CompanionCharacter

    var body: some View {
        VStack(spacing: 20) {
            Text(companion.emoji)
                .font(.system(size: 56))
            ProgressView()
                .scaleEffect(1.3)
            Text("\(companion.displayName)이(가) 여행을 정리하고 있어요...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
