import Foundation

/// Cash received, by payment date. Refunds are negative; no earned revenue is counted twice.
enum IncomeCSV {
    static func payments(in ledger: Ledger, year: Int, calendar: Calendar = .current) -> [Payment] {
        ledger.payments.filter { calendar.component(.year, from: $0.date) == year }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
    }
    static func amount(_ cents: Int) -> String {
        let magnitude = cents.magnitude
        return "\(cents < 0 ? "-" : "")\(magnitude / 100).\(String(format: "%02d", Int(magnitude % 100)))"
    }
    static func cell(_ value: String, userText: Bool = false) -> String {
        // Quoting alone does not stop spreadsheet formulas in client names/notes.
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = userText && (first.map { "=+-@".contains($0) } == true || value.first == "\t" || value.first == "\r") ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    static func data(ledger: Ledger, year: Int, calendar: Calendar = .current) -> Data {
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.calendar = calendar
        date.timeZone = calendar.timeZone
        date.dateFormat = "yyyy-MM-dd"
        let instant = ISO8601DateFormatter()
        var rows = [["Payment ID", "Payment date", "Payment timestamp UTC", "Reporting time zone", "Client", "Type", "Package or session", "Session date", "Payment method", "Currency", "Amount", "Notes"].map { cell($0) }.joined(separator: ",")]
        for p in payments(in: ledger, year: year, calendar: calendar) {
            let session = ledger.sessions.first { $0.id == p.sessionID }
            let package = ledger.package(p.packageID)
            let fields = [cell(p.id.uuidString), cell(date.string(from: p.date)), cell(instant.string(from: p.date)), cell(calendar.timeZone.identifier), cell(ledger.client(for: p)?.name ?? "", userText: true), cell(p.cents < 0 ? "Refund" : "Payment"), cell(package?.name ?? (session == nil ? "" : "Single session"), userText: true), cell(session.map { date.string(from: $0.start) } ?? ""), cell(p.method, userText: true), cell("USD"), amount(p.cents), cell(p.note, userText: true)]
            rows.append(fields.joined(separator: ","))
        }
        // BOM lets spreadsheet applications recognize Chinese names and notes as UTF-8.
        return Data(("\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n").utf8)
    }
}
