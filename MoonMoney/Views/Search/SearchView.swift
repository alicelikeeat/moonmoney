import SwiftData
import SwiftUI

enum SearchScope: Hashable {
    case all, expense, income, transfer

    var title: String {
        switch self {
        case .all: "全部"
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
        }
    }

    var kind: RecordKind? {
        switch self {
        case .all: nil
        case .expense: .expense
        case .income: .income
        case .transfer: .transfer
        }
    }
}

struct SearchView: View {
    @Environment(AppSettings.self) private var settings
    @State private var text = ""
    @State private var scope: SearchScope = .all
    @State private var allLedgers = false

    var body: some View {
        NavigationStack {
            SearchResults(text: text, scope: scope, ledgerID: allLedgers ? nil : settings.currentLedgerID)
                .navigationTitle("搜索")
                .searchable(text: $text, prompt: "备注、分类、账户、标签或金额")
                .searchScopes($scope, activation: .onSearchPresentation) {
                    ForEach([SearchScope.all, .expense, .income, .transfer], id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Toggle("搜索所有账本", systemImage: "books.vertical", isOn: $allLedgers)
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                        }
                    }
                }
                .navigationDestination(for: Record.self) { record in
                    RecordDetailView(record: record)
                }
        }
    }
}

private struct SearchResults: View {
    @Query(sort: \Record.date, order: .reverse) private var records: [Record]
    let text: String
    let scope: SearchScope
    let ledgerID: UUID?

    var body: some View {
        let results = filtered
        let summary = Stats.summary(results)

        List {
            Group {
                if text.isEmpty && scope == .all {
                    Section("最近记录") {
                        ForEach(results.prefix(30)) { record in
                            NavigationLink(value: record) { RecordRow(record: record, showDate: true) }
                        }
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: text)
                        .plainListRow()
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(results.count) 笔结果").font(.headline)
                            Text("支出 \(Money.format(summary.expense)) · 收入 \(Money.format(summary.income))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .glassCard(cornerRadius: 24, padding: 14)
                    .plainListRow(top: 4, bottom: 4)

                    ForEach(Stats.groupedByDay(Array(results.prefix(500))), id: \.day) { group in
                        Section(group.day.dayHeaderTitle) {
                            ForEach(group.records) { record in
                                NavigationLink(value: record) { RecordRow(record: record) }
                            }
                        }
                    }
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: .blue) }
    }

    private var filtered: [Record] {
        let query = text.trimmingCharacters(in: .whitespaces)
        let amountQuery = Decimal(string: query, locale: Locale(identifier: "en_US_POSIX")).map { Money.cents($0) }
        return records.filter { record in
            if let ledgerID, record.ledgerID != ledgerID { return false }
            if let kind = scope.kind, record.kind != kind { return false }
            guard !query.isEmpty else { return true }
            if let amountQuery, record.amountCents == amountQuery { return true }
            if record.note.localizedCaseInsensitiveContains(query) { return true }
            if record.category?.name.localizedCaseInsensitiveContains(query) == true { return true }
            if record.account?.name.localizedCaseInsensitiveContains(query) == true { return true }
            if record.toAccount?.name.localizedCaseInsensitiveContains(query) == true { return true }
            let tagQuery = query.hasPrefix("#") ? String(query.dropFirst()) : query
            if record.tags?.contains(where: { $0.name.localizedCaseInsensitiveContains(tagQuery) }) == true { return true }
            return false
        }
    }
}
