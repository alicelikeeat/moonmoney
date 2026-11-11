import Foundation
import SwiftUI

struct CategorySlice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let symbol: String
    let color: Color
    let cents: Int
    let count: Int
    var share: Double
}

struct TimeBucket: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let expense: Int
    let income: Int
}

struct PeriodSummary {
    var expense = 0
    var income = 0
    var count = 0
    var net: Int { income - expense }
}

/// Pure aggregation helpers. All amounts are base-currency cents.
enum Stats {
    static func counted(_ records: [Record]) -> [Record] {
        records.filter { !$0.excludedFromStats && $0.kind != .transfer }
    }

    static func summary(_ records: [Record]) -> PeriodSummary {
        var result = PeriodSummary()
        for record in counted(records) {
            result.count += 1
            if record.kind == .expense { result.expense += record.baseAmountCents }
            else { result.income += record.baseAmountCents }
        }
        return result
    }

    static func slices(_ records: [Record], kind: RecordKind) -> [CategorySlice] {
        let filtered = counted(records).filter { $0.kind == kind }
        let total = filtered.reduce(0) { $0 + $1.baseAmountCents }
        let unknownID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        var buckets: [UUID: (BillCategory?, Int, Int)] = [:]
        for record in filtered {
            let key = record.category?.uuid ?? unknownID
            let current = buckets[key] ?? (record.category, 0, 0)
            buckets[key] = (current.0, current.1 + record.baseAmountCents, current.2 + 1)
        }
        return buckets.map { key, value in
            CategorySlice(
                id: key,
                name: value.0?.name ?? "未分类",
                symbol: value.0?.symbol ?? "questionmark",
                color: value.0?.color ?? .gray,
                cents: value.1,
                count: value.2,
                share: total > 0 ? Double(value.1) / Double(total) : 0
            )
        }
        .sorted { $0.cents > $1.cents }
    }

    /// Daily buckets for week/month, monthly buckets for year.
    static func buckets(_ records: [Record], interval: DateInterval, kind: PeriodKind) -> [TimeBucket] {
        let cal = Periods.calendar
        let counted = counted(records)
        if kind == .year {
            return Periods.months(in: interval).map { month in
                let end = cal.date(byAdding: .month, value: 1, to: month) ?? month
                let inMonth = counted.filter { $0.date >= month && $0.date < end }
                return TimeBucket(
                    date: month,
                    expense: inMonth.filter { $0.kind == .expense }.reduce(0) { $0 + $1.baseAmountCents },
                    income: inMonth.filter { $0.kind == .income }.reduce(0) { $0 + $1.baseAmountCents }
                )
            }
        }
        var byDay: [Date: (Int, Int)] = [:]
        for record in counted {
            let day = cal.startOfDay(for: record.date)
            let current = byDay[day] ?? (0, 0)
            if record.kind == .expense {
                byDay[day] = (current.0 + record.baseAmountCents, current.1)
            } else {
                byDay[day] = (current.0, current.1 + record.baseAmountCents)
            }
        }
        return Periods.days(in: interval).map { day in
            let value = byDay[day] ?? (0, 0)
            return TimeBucket(date: day, expense: value.0, income: value.1)
        }
    }

    static func dailyTotals(_ records: [Record]) -> [Date: PeriodSummary] {
        let cal = Calendar.current
        var result: [Date: PeriodSummary] = [:]
        for record in counted(records) {
            let day = cal.startOfDay(for: record.date)
            var summary = result[day] ?? PeriodSummary()
            summary.count += 1
            if record.kind == .expense { summary.expense += record.baseAmountCents }
            else { summary.income += record.baseAmountCents }
            result[day] = summary
        }
        return result
    }

    static func groupedByDay(_ records: [Record]) -> [(day: Date, records: [Record])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: records) { cal.startOfDay(for: $0.date) }
        return groups
            .map { (day: $0.key, records: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    static func percentChange(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return nil }
        return Double(current - previous) / Double(previous)
    }
}
