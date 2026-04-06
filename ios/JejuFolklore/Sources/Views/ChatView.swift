import SwiftUI

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    var courseId: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                inputBar
            }
            .navigationTitle("설화 챗봇")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { vm.courseId = courseId }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: vm.messages.count) { _ in
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("설화에 대해 물어보세요", text: $vm.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(vm.isStreaming)
            Button {
                Task { await vm.send() }
            } label: {
                Image(systemName: vm.isStreaming ? "ellipsis.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(vm.inputText.isEmpty || vm.isStreaming ? .secondary : .orange)
            }
            .disabled(vm.inputText.isEmpty || vm.isStreaming)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .top)
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(message.content.isEmpty ? "..." : message.content)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.orange : Color(.secondarySystemBackground))
                .foregroundColor(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer(minLength: 60) }
        }
    }
}
