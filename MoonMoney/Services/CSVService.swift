import Foundation
import SwiftData

/// CSV import / export. The format is compatible with most spreadsheet apps.
enum CSVService {
    static let header = ["日期", "类型", "金额", "币种", "分类", "账户", "转入账户", "手续费", "备注", "标签", "账本"]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    // MARK: Export

    @MainActor
    static func export(records: [Record], ledgers: [Ledger]) throws -> URL {
        let ledgerNames = Dictionary(ledgers.map { ($0.uuid, $0.name) }, uniquingKeysWith: { first, _ in first })
        var lines = [header.joined(separator: ",")]
        for record in records.sorted(by: { $0.date < $1.date }) {
            let fields: [String] = [
                dateFormatter.string(from: record.date),
                record.kind.title,
                Money.plain(record.amountCents).replacingOccurrences(of: ",", with: ""),
                record.currencyCode,
                record.category?.name ?? "",
                record.account?.name ?? "",
                record.toAccount?.name ?? "",
                record.feeCents > 0 ? Money.plain(record.feeCents).replacingOccurrences(of: ",", with: "") : "",
                record.note,
                record.sortedTags.map(\.name).joined(separator: "|"),
                record.ledgerID.flatMap { ledgerNames[$0] } ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        let stamp = Date.now.zh("yyyyMMdd")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MoonMoney-\(stamp).csv")
        // BOM so Excel opens Chinese text correctly.
        let content = "\u{FEFF}" + lines.joined(separator: "\n")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: Import

    struct ImportResult {
        var imported = 0
        var skipped = 0
    }

    @MainActor
    static func importCSV(from url: URL, into context: ModelContext) throws -> ImportResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        var text = try String(contentsOf: url, encoding: .utf8)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let rows = parse(text)
        guard let headerRow = rows.first else { return ImportResult() }

        func column(_ name: String) -> Int? { headerRow.firstIndex(of: name) }
        guard let dateCol = column("日期"), let amountCol = column("金额") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let kindCol = column("类型"), currencyCol = column("币种"), categoryCol = column("分类")
        let accountCol = column("账户"), toAccountCol = column("转入账户"), feeCol = column("手续费")
        let noteCol = column("备注"), tagCol = column("标签")

        var categories = (try? context.fetch(FetchDescriptor<BillCategory>())) ?? []
        var accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var tags = (try? context.fetch(FetchDescriptor<RecordTag>())) ?? []
        let ledgerID = AppSettings.shared.currentLedgerID
        let altFormatter = DateFormatter()
        altFormatter.locale = Locale(identifier: "en_US_POSIX")
        altFormatter.dateFormat = "yyyy-MM-dd"

        var result = ImportResult()
        for row in rows.dropFirst() {
            func value(_ col: Int?) -> String {
                guard let col, col < row.count else { return "" }
                return row[col].trimmingCharacters(in: .whitespaces)
            }
            let dateString = value(dateCol)
            guard let date = dateFormatter.date(from: dateString) ?? altFormatter.date(from: dateString),
                  let amount = Decimal(string: value(amountCol).replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
            else {
                result.skipped += 1
                continue
            }
            let kindText = value(kindCol)
            var kind: RecordKind = RecordKind.allCases.first { $0.title == kindText } ?? .expense
            var cents = Money.cents(amount)
            // Without a type column, follow the common "negative = expense" convention.
            if kindCol == nil { kind = cents < 0 ? .expense : .income }
            cents = abs(cents)

            let record = Record(kind: kind, amountCents: cents, date: date, note: value(noteCol), ledgerID: ledgerID)

            let accountName = value(accountCol)
            if !accountName.isEmpty {
                if let account = accounts.first(where: { $0.name == accountName }) {
                    record.account = account
                } else {
                    let account = Account(name: accountName, type: .cash, order: accounts.count)
                    context.insert(account)
                    accounts.append(account)
                    record.account = account
                }
            }
            let currency = value(currencyCol)
            record.currencyCode = currency.isEmpty ? (record.account?.currencyCode ?? AppSettings.shared.baseCurrency) : currency

            if kind == .transfer {
                let toName = value(toAccountCol)
                record.toAccount = accounts.first { $0.name == toName }
                if let fee = Decimal(string: value(feeCol)) { record.feeCents = Money.cents(fee) }
            } else {
                let categoryName = value(categoryCol)
                if !categoryName.isEmpty {
                    if let category = categories.first(where: { $0.name == categoryName && $0.kind == kind }) {
                        record.category = category
                    } else {
                        let category = BillCategory(name: categoryName, symbol: "tag.fill",
                                                    colorHex: Palette.swatches.randomElement() ?? "#8E8E93",
                                                    kind: kind, order: categories.count)
                        context.insert(category)
                        categories.append(category)
                        record.category = category
                    }
                }
            }

            let tagNames = value(tagCol).split(separator: "|").map { String($0) }.filter { !$0.isEmpty }
            var recordTags: [RecordTag] = []
            for name in tagNames {
                if let tag = tags.first(where: { $0.name == name }) {
                    recordTags.append(tag)
                } else {
                    let tag = RecordTag(name: name)
                    context.insert(tag)
                    tags.append(tag)
                    recordTags.append(tag)
                }
            }
            record.tags = recordTags

            context.insert(record)
            result.imported += 1
        }
        try context.save()
        return result
    }

    /// RFC 4180-ish parser that handles quoted fields with commas and newlines.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n", "\r":
                    row.append(field); field = ""
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row = []
                default: field.append(ch)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
