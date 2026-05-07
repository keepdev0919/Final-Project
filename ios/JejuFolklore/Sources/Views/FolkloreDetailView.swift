import SwiftUI

struct FolkloreDetailView: View {
    let pin: Pin
    @StateObject private var audio = AudioPlayer.shared
    @State private var detail: PinDetail?
    @State private var isLoadingDetail = false
    @State private var isLoadingTTS = false
    @State private var placeReviews: PlaceReviewsResponse? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    Divider()
                    contentSection
                    if let reviews = placeReviews, reviews.total > 0 {
                        Divider()
                        communitySection(reviews: reviews)
                    }
                }
                .padding(20)
            }
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ttsButton
                }
            }
        }
        .task {
            async let detailTask: () = loadDetail()
            async let reviewTask: () = loadReviews()
            _ = await (detailTask, reviewTask)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(detail?.sourceTypeLabel ?? pin.sourceTypeLabel,
                      systemImage: pin.sourceType == "legend" ? "book.fill" : "mic.fill")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tagColor.opacity(0.15))
                    .foregroundColor(tagColor)
                    .clipShape(Capsule())

                if !pin.primaryPlace.isEmpty {
                    Label(pin.primaryPlace, systemImage: "mappin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(displayTitle)
                .font(.title2)
                .fontWeight(.bold)

            Text(detail?.summary ?? pin.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        Group {
            if isLoadingDetail {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.top, 40)
            } else if let fullText = detail?.fullText, !fullText.isEmpty {
                Text(fullText)
                    .font(.body)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(pin.summary)
                    .font(.body)
                    .lineSpacing(7)
            }
        }
    }

    // MARK: - TTS Button

    private var ttsButton: some View {
        Button {
            if audio.isPlaying {
                audio.stop()
            } else {
                Task { await playTTS() }
            }
        } label: {
            Image(systemName: audio.isPlaying ? "speaker.wave.3.fill" : "play.circle.fill")
                .foregroundColor(tagColor)
        }
        .disabled(isLoadingTTS)
    }

    // MARK: - Helpers

    private var displayTitle: String { pin.displayTitle }

    private var tagColor: Color {
        pin.sourceType == "legend" ? .orange : .purple
    }

    private func loadReviews() async {
        guard !pin.primaryPlace.isEmpty else { return }
        placeReviews = try? await APIClient.shared.fetchReviews(placeName: pin.primaryPlace)
    }

    private func communitySection(reviews: PlaceReviewsResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("다른 여행자들의 반응")
                    .font(.headline)
                Spacer()
                Text("총 \(reviews.total)명")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let sortedTags = reviews.tagCounts
                .filter { $0.value > 0 }
                .sorted { $0.value > $1.value }

            ForEach(sortedTags, id: \.key) { tag, count in
                let pct = Double(count) / Double(reviews.total)
                HStack(spacing: 8) {
                    Text(tag)
                        .font(.caption)
                        .frame(width: 90, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemFill))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(tagColor)
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(height: 8)
                    Text("\(Int(pct * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }

            if !reviews.recentNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(reviews.recentNotes, id: \.self) { note in
                        Text("\u{201C}\(note)\u{201D}")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func loadDetail() async {
        isLoadingDetail = true
        detail = try? await PinDetailAPI.fetch(codeNo: pin.codeNo)
        isLoadingDetail = false
    }

    private func playTTS() async {
        let text = detail?.fullText ?? pin.summary
        isLoadingTTS = true
        do {
            let data = try await TTSAPI.fetch(text: String(text.prefix(500)), pinId: pin.id)
            audio.play(data: data)
        } catch {}
        isLoadingTTS = false
    }
}
