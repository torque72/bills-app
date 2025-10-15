import Foundation

extension NumberFormatter {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale.current
        return formatter
    }()
}

extension Double {
    func currencyString() -> String {
        let number = NSNumber(value: self)
        return NumberFormatter.currency.string(from: number) ?? String(format: "$%.2f", self)
    }
}
