import Foundation

@MainActor
final class BillsChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var isSending = false
    @Published var error: ErrorInfo?

    private let api: BillsAPI

    init(api: BillsAPI) {
        self.api = api
    }

    func send(monthKey: String) async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let outgoing = ChatMessage(role: .user, text: trimmed)
        messages.append(outgoing)
        draft = ""
        isSending = true
        defer { isSending = false }
        do {
            let replyText = try await api.askBillsGPT(message: trimmed, monthKey: monthKey)
            messages.append(ChatMessage(role: .assistant, text: replyText))
        } catch {
            error = ErrorInfo(message: error.localizedDescription)
            messages.append(ChatMessage(role: .assistant, text: "I couldn't respond because of an error: \(error.localizedDescription)"))
        }
    }

    func reset() {
        messages.removeAll()
        draft = ""
    }
}
