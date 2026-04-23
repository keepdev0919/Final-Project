// ios/JejuFolklore/Sources/Views/CompanionChatView.swift
import SwiftUI

struct CompanionChatView: View {
    let place: CoursePlace
    let companion: CompanionCharacter
    let vm: ExploreViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var messages: [TravelChatMessage] = []
    @State private var streamingText = ""
    @State private var isStreaming = false
    @State private var streamingTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    private var folkloreSummaries: [String] {
        place.folklorePins.prefix(3).map { "\($0.title): \($0.summary)" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                companionHeader
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { msg in
                                ChatBubble(message: msg, companion: companion)
                                    .id(msg.id)
                            }
                            if isStreaming && !streamingText.isEmpty {
                                ChatBubble(
                                    message: TravelChatMessage(role: .assistant, content: streamingText),
                                    companion: companion
                                )
                                .id("streaming")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: streamingText) {
                        withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                    }
                }
                inputBar
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .onAppear {
            messages = vm.messages(for: place.name)
            if messages.isEmpty { sendGreeting() }
        }
        .onDisappear {
            streamingTask?.cancel()
        }
    }

    // MARK: - Companion Header

    private var companionHeader: some View {
        HStack(spacing: 12) {
            Text(companion.emoji)
                .font(.system(size: 36))
            VStack(alignment: .leading, spacing: 2) {
                Text(companion.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(place.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("동행자에게 말을 건네보세요", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming ? .secondary : .orange)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1), alignment: .top)
    }

    // MARK: - Streaming

    private func sendGreeting() {
        streamingTask = Task { await stream(message: "__GREETING__", history: []) }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""

        let userMsg = TravelChatMessage(role: .user, content: text)
        messages.append(userMsg)
        vm.appendMessage(userMsg, to: place.name)

        streamingTask = Task { await stream(message: text, history: messages.dropLast()) }
    }

    private func stream(message: String, history: some Collection<TravelChatMessage>) async {
        isStreaming = true
        streamingText = ""

        let historyArray = Array(history)
        let stream = TravelAPI.companionStream(
            placeName: place.name,
            folkloreSummaries: folkloreSummaries,
            companionType: companion.rawValue,
            message: message,
            history: historyArray
        )

        for await chunk in stream {
            guard !Task.isCancelled else { break }
            streamingText += chunk
        }

        if !streamingText.isEmpty && !Task.isCancelled {
            let assistantMsg = TravelChatMessage(role: .assistant, content: streamingText)
            messages.append(assistantMsg)
            vm.appendMessage(assistantMsg, to: place.name)
        }
        streamingText = ""
        isStreaming = false
    }
}

// MARK: - ChatBubble

private struct ChatBubble: View {
    let message: TravelChatMessage
    let companion: CompanionCharacter

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
            } else {
                Text(companion.emoji)
                    .font(.system(size: 24))
            }

            Text(message.content)
                .font(.body)
                .foregroundColor(isUser ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.orange : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isUser ? Color.clear : Color.orange.opacity(0.2), lineWidth: 1)
                )

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
