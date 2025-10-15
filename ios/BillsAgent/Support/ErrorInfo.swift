import Foundation

struct ErrorInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String = "Error", message: String) {
        self.title = title
        self.message = message
    }
}
