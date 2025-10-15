import Foundation

extension Date {
    func monthKey(calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: self)
        let year = components.year ?? 0
        let month = components.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }
}
