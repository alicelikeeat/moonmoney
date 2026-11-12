import SwiftUI
import UIKit

// MARK: - Money

enum Money {
    static func decimal(_ cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    static func cents(_ value: Decimal) -> Int {
        var scaled = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func cents(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }

    /// "¥1,234.56"
    static func format(_ cents: Int, code: String = AppSettings.shared.baseCurrency) -> String {
        decimal(cents).formatted(.currency(code: code).presentation(.narrow))
    }

    /// "+¥12.00" / "-¥12.00"
    static func signed(_ cents: Int, code: String = AppSettings.shared.baseCurrency) -> String {
        let body = format(abs(cents), code: code)
        if cents > 0 { return "+" + body }
        if cents < 0 { return "-" + body }
        return body
    }

    /// Compact form for tight spaces such as calendar cells: "1.2万", "860".
    static func compact(_ cents: Int) -> String {
        let value = Double(abs(cents)) / 100
        let sign = cents < 0 ? "-" : ""
        switch value {
        case 100_000_000...: return sign + String(format: "%.1f亿", value / 100_000_000)
        case 10_000...: return sign + String(format: "%.1f万", value / 10_000)
        case 1_000...: return sign + String(format: "%.0f", value)
        default:
            return sign + (value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value))
        }
    }

    /// Plain number without currency symbol: "1,234.56"
    static func plain(_ cents: Int) -> String {
        decimal(cents).formatted(.number.precision(.fractionLength(2)))
    }

    static func symbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.currencySymbol ?? code
    }
}

// MARK: - Colors

extension Color {
    static let expense = Color(red: 1.0, green: 0.36, blue: 0.33)
    static let income = Color(red: 0.19, green: 0.78, blue: 0.47)
    static let transfer = Color(red: 0.35, green: 0.55, blue: 1.0)

    init(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: string).scanHexInt64(&value)
        let r, g, b: Double
        if string.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        let resolved = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func clamp(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

enum Palette {
    static let swatches: [String] = [
        "#FF453A", "#FF6B6B", "#FF9F0A", "#FFD60A", "#C7A36B", "#30D158",
        "#34C759", "#00C7BE", "#64D2FF", "#0A84FF", "#5E5CE6", "#BF5AF2",
        "#FF375F", "#FF2D92", "#AC8E68", "#8E8E93",
    ]
}

// MARK: - Dates

extension Date {
    /// Formats with a localized template, e.g. `date.zh("MMMd")` → "11月11日".
    func zh(_ template: String) -> String {
        DateFormatterCache.formatter(for: template).string(from: self)
    }

    var dayHeaderTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "今天" }
        if cal.isDateInYesterday(self) { return "昨天" }
        if cal.isDate(self, equalTo: .now, toGranularity: .year) {
            return zh("MMMd EEEE")
        }
        return zh("yMMMd EEEE")
    }
}

enum DateFormatterCache {
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    static func formatter(for template: String) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[template] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate(template)
        cache[template] = formatter
        return formatter
    }
}
