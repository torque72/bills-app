import Foundation

struct Bill: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var dueDay: Int
    var amount: Double
    var notes: String?
    var isPaid: Bool
}

struct BillTotals: Equatable {
    var total: Double
    var paid: Double
    var remaining: Double
}

struct PushNotificationSummary: Codable {
    var sent: Int
    var reason: String?
}
