import Foundation

enum PeriodKind: String, CaseIterable, Identifiable {
    case week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "周"
        case .month: "月"
        case .year: "年"
        }
    }
}

/// Date ranges that respect the user's custom month start day and week start.
enum Periods {
    static var calendar: Calendar { AppSettings.shared.calendar }

    static func interval(_ kind: PeriodKind, containing date: Date) -> DateInterval {
        switch kind {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
        case .month:
            return month(containing: date)
        case .year:
            return calendar.dateInterval(of: .year, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 365 * 86_400)
        }
    }

    /// A "financial month" that starts on `monthStartDay`.
    static func month(containing date: Date) -> DateInterval {
        let cal = calendar
        let startDay = AppSettings.shared.monthStartDay
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        let day = comps.day ?? 1
        comps.day = startDay
        var start = cal.date(from: comps) ?? cal.startOfDay(for: date)
        if day < startDay {
            start = cal.date(byAdding: .month, value: -1, to: start) ?? start
        }
        start = cal.startOfDay(for: start)
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(30 * 86_400)
        return DateInterval(start: start, end: end)
    }

    static func shift(_ interval: DateInterval, kind: PeriodKind, by value: Int) -> DateInterval {
        let component: Calendar.Component = switch kind {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        let moved = calendar.date(byAdding: component, value: value, to: interval.start) ?? interval.start
        // Re-derive from a date safely inside the target period.
        return self.interval(kind, containing: moved.addingTimeInterval(3_600))
    }

    static func title(_ interval: DateInterval, kind: PeriodKind) -> String {
        let cal = calendar
        switch kind {
        case .week:
            let last = interval.end.addingTimeInterval(-1)
            return "\(interval.start.zh("MMMd")) – \(last.zh("MMMd"))"
        case .month:
            if AppSettings.shared.monthStartDay == 1 {
                let sameYear = cal.isDate(interval.start, equalTo: .now, toGranularity: .year)
                return interval.start.zh(sameYear ? "MMMM" : "yMMMM")
            }
            let last = interval.end.addingTimeInterval(-1)
            return "\(interval.start.zh("MMMd")) – \(last.zh("MMMd"))"
        case .year:
            return interval.start.zh("y")
        }
    }

    /// Every day in the interval (start of day).
    static func days(in interval: DateInterval) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Every month start in the interval.
    static func months(in interval: DateInterval) -> [Date] {
        var result: [Date] = []
        var month = interval.start
        while month < interval.end {
            result.append(month)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return result
    }

    /// Number of days elapsed in the interval up to now (at least 1).
    static func elapsedDays(in interval: DateInterval) -> Int {
        let now = Date.now
        let end = min(max(now, interval.start), interval.end)
        let days = calendar.dateComponents([.day], from: interval.start, to: end).day ?? 0
        return max(1, now >= interval.end ? totalDays(in: interval) : days + 1)
    }

    static func totalDays(in interval: DateInterval) -> Int {
        max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
    }

    static func remainingDays(in interval: DateInterval) -> Int {
        let now = Date.now
        guard now < interval.end else { return 0 }
        guard now >= interval.start else { return totalDays(in: interval) }
        let today = calendar.startOfDay(for: now)
        return max(1, calendar.dateComponents([.day], from: today, to: interval.end).day ?? 1)
    }
}
