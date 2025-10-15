import SwiftUI

struct BillsChatView: View {
    @ObservedObject var viewModel: BillsChatViewModel
    let monthKey: String

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                        if viewModel.isSending {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(16)
                }
                .background(Color(.systemGroupedBackground))
                .onChange(of: viewModel.messages) { _ in
                    if let last = viewModel.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask about your bills…", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await viewModel.send(monthKey: monthKey) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
            }
            .padding(.all, 16)
            .background(.thinMaterial)
        }
        .navigationTitle("BillsGPT")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear") {
                    viewModel.reset()
                }
                .disabled(viewModel.messages.isEmpty)
            }
        }
        .alert(item: $viewModel.error) { info in
            Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 48)
            } else {
                Spacer(minLength: 48)
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.text)
                .font(.body)
                .foregroundStyle(message.role == .assistant ? Color.primary : .white)
            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle((message.role == .assistant ? Color.primary : .white).opacity(0.7))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(message.role == .assistant ? Color(.systemGray5) : Color.accentColor)
        )
    }
}
