import Foundation

/// A user-reviewed calendar copy, separate from the trainer's billing ledger.
struct CalendarAppointment: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let start: Date
    let end: Date
    let location: String
    let notes: String
    init(session: Session, clientName: String, kind: String) {
        id = session.id
        title = "\(kind) · \(clientName)"
        start = session.start
        end = session.end
        location = session.location
        notes = session.notes.isEmpty ? "Session Book" : "Session Book\n\n\(session.notes)"
    }
    var signature: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self).base64EncodedString()) ?? ""
    }
}
