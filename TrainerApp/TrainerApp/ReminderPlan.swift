import Foundation

struct SessionReminder: Equatable, Identifiable {
    let sessionID: UUID
    let start: Date
    let fireDate: Date
    let minutesBefore: Int
    var id: String { "session-reminder.\(sessionID.uuidString).\(Int64(start.timeIntervalSince1970 * 1000)).\(minutesBefore)" }
    static func plan(ledger: Ledger, minutesBefore: Int, now: Date = Date(), limit: Int = 60) -> [SessionReminder] {
        ledger.sessions.compactMap { session -> SessionReminder? in
            let lead = session.reminderMinutes ?? minutesBefore
            guard session.status == .scheduled, session.start > now, lead >= 0 else { return nil }
            let desired = session.start.addingTimeInterval(-Double(lead * 60))
            // A late booking still gets an alert at session start.
            return SessionReminder(sessionID: session.id, start: session.start, fireDate: desired > now ? desired : session.start, minutesBefore: lead)
        }.sorted {
            $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate
        }.prefix(max(0, limit)).map { $0 }
    }
}
