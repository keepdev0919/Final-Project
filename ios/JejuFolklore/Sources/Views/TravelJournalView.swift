// ios/JejuFolklore/Sources/Views/TravelJournalView.swift
import SwiftUI

struct TravelJournalView: View {
    let journalText: String
    let imageURL: URL?
    let visitedPlaces: [String]
    let companion: CompanionCharacter
    let onDone: () -> Void

    @State private var showShareSheet = false

    private var shareText: String {
        """
        제주 설화 여행 일지

        \(companion.emoji) \(companion.displayName)와 함께한 제주 여행
        방문: \(visitedPlaces.joined(separator: ", "))

        \(journalText)
        """
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 민화 헤더 이미지 (있을 때만)
                    if let url = imageURL {
                        MinhwaHeaderImage(url: url)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

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
                    .padding(.top, imageURL == nil ? 8 : 0)

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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료", action: onDone)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(text: shareText)
            }
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Minhwa header image

private struct MinhwaHeaderImage: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray5))
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(1.1)
                        Text("민화 그리는 중...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            case .success(let img):
                img
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            case .failure:
                EmptyView()
            @unknown default:
                EmptyView()
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
            Text("\(companion.displayName)이(가) 여행과 민화도 함께 그리고 있어요...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text("잠시만 기다려 주세요 (약 25~30초)")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(40)
    }
}
