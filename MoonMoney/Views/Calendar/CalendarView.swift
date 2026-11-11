import SwiftData
import SwiftUI

/// Month calendar with a spending heat map; tap a day to see its records.
struct CalendarView: View {
    @Environment(AppSettings.self) private var settings
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    var body: some View {
        CalendarContent(month: month, ledgerID: settings.currentLedgerID, selectedDay: $selectedDay, onShift: shift)
            .id("\(month.timeIntervalSince1970)-\(settings.currentLedgerID?.uuidString ?? "")")
            .navigationTitle(month.zh("yMMMM"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("今天") {
                        withAnimation(.smooth) {
                            month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
                            selectedDay = Calendar.current.startOfDay(for: .now)
                        }
                    }
                }
            }
    }

    private func shift(_ value: Int) {
        Haptics.tap()
        withAnimation(.smooth) {
            month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
            selectedDay = month
        }
    }
}

private struct CalendarContent: View {
    @Environment(Router.self) private var router
    @Query private var records: [Record]
    let month: Date
    @Binding var selectedDay: Date
    var onShift: (Int) -> Void

    init(month: Date, ledgerID: UUID?, selectedDay: Binding<Date>, onShift: @escaping (Int) -> Void) {
        self.month = month
        _selectedDay = selectedDay
        self.onShift = onShift
        let start = month
        let end = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
        _records = Query(
            filter: #Predicate<Record> { $0.date >= start && $0.date < end && $0.ledgerID == ledgerID },
            sort: \Record.date,
            order: .reverse
        )
    }

    private var calendar: Calendar { AppSettings.shared.calendar }

    var body: some View {
        let totals = Stats.dailyTotals(records)
        let maxExpense = totals.values.map(\.expense).max() ?? 0
        let dayRecords = records.filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
        let monthSummary = Stats.summary(records)

        List {
            Group {
                VStack(spacing: 12) {
                    HStack {
                        Button { onShift(-1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.inCard(circle: true))
                        Spacer()
                        VStack(spacing: 2) {
                            Text("支出 \(Money.format(monthSummary.expense))")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                            Text("收入 \(Money.format(monthSummary.income))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.income)
                        }
                        Spacer()
                        Button { onShift(1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.inCard(circle: true))
                    }

                    weekdayHeader
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                        ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                            if let day {
                                DayCell(
                                    day: day,
                                    summary: totals[day],
                                    intensity: maxExpense > 0 ? Double(totals[day]?.expense ?? 0) / Double(maxExpense) : 0,
                                    isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                                    isToday: calendar.isDateInToday(day)
                                )
                                .onTapGesture {
                                    withAnimation(.snappy) { selectedDay = day }
                                    Haptics.tap()
                                }
                            } else {
                                Color.clear.frame(height: 52)
                            }
                        }
                    }
                }
                .glassCard(cornerRadius: 30, padding: 14)
                .plainListRow(top: 8, bottom: 8)

                Section {
                    if dayRecords.isEmpty {
                        Text("这天没有记录")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(dayRecords) { record in
                        NavigationLink(value: record) {
                            RecordRow(record: record)
                        }
                    }
                } header: {
                    HStack {
                        Text(selectedDay.dayHeaderTitle)
                        Spacer()
                        Button {
                            router.newRecord(date: dateForNewRecord)
                        } label: {
                            Label("补记", systemImage: "plus")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    .textCase(nil)
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground() }
    }

    /// Picks the selected day, keeping the current time of day.
    private var dateForNewRecord: Date {
        let time = calendar.dateComponents([.hour, .minute], from: .now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: selectedDay) ?? selectedDay
    }

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let ordered = Array(symbols[first...] + symbols[..<first])
        return HStack(spacing: 4) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Days of the month padded with nils so the first day lands on the right weekday.
    private var gridDays: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: month) ?? 1..<31
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            days.append(calendar.date(byAdding: .day, value: offset, to: month))
        }
        return days
    }
}

private struct DayCell: View {
    let day: Date
    let summary: PeriodSummary?
    let intensity: Double
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.callout.weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)
            if let summary, summary.expense > 0 {
                Text(Money.compact(summary.expense))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if let summary, summary.income > 0 {
                Text("+" + Money.compact(summary.income))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.income)
                    .lineLimit(1)
            } else {
                Text(" ").font(.system(size: 9))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.expense.opacity(intensity > 0 ? 0.08 + intensity * 0.35 : 0))
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(.rect)
    }
}
