import Foundation

struct Client: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var email = ""
    var phone = ""
    var goal = ""
    var notes = ""
    var archivedAt: Date? = nil
    var isArchived: Bool { archivedAt != nil }
    var created = Date()
}
struct Package: Identifiable, Codable, Equatable {
    var id = UUID()
    var clientID: UUID
    var name: String
    var sessions: Int
    var minutes: Int
    var priceCents: Int
    var purchased = Date()
    var expires: Date?
}
struct Payment: Identifiable, Codable, Equatable {
    var id = UUID()
    var packageID: UUID? = nil
    var sessionID: UUID? = nil
    var cents: Int
    var date = Date()
    var method: String
    var note = ""
}
enum SessionStatus: String, Codable, CaseIterable {
    case scheduled, completed, clientCancelled, trainerCancelled, noShow
    var key: String {
        switch self {
        case .scheduled: "Scheduled"
        case .completed: "Completed"
        case .clientCancelled: "Client cancelled"
        case .trainerCancelled: "Trainer cancelled"
        case .noShow: "No-show"
        }
    }
}
struct Session: Identifiable, Codable, Equatable {
    var id = UUID()
    var packageID: UUID? = nil
    var clientID: UUID? = nil
    var feeCents: Int? = nil
    /// nil inherits the global lead time; -1 disables this session reminder.
    var reminderMinutes: Int? = nil
    /// A manual return to Scheduled after the end time must survive automatic refreshes.
    var automaticCompletionSuppressed: Bool? = nil
    var calendarAddedAt: Date? = nil
    var calendarAddedSignature: String? = nil
    var start: Date
    var minutes: Int
    var location = ""
    var notes = ""
    var status: SessionStatus = .scheduled
    var charged = false
    var isTrial: Bool { packageID == nil && (feeCents ?? 0) == 0 }
    var kindKey: String { packageID != nil ? "Package session" : (isTrial ? "Free trial" : "Single session") }
    var end: Date { start.addingTimeInterval(Double(minutes * 60)) }
}
struct LedgerError: LocalizedError {
    let key: String
    var errorDescription: String? { key }
}
struct Ledger: Codable, Equatable {
    var version = 1
    var clients: [Client] = []
    var packages: [Package] = []
    var payments: [Payment] = []
    var sessions: [Session] = []
    func package(_ id: UUID?) -> Package? { packages.first { $0.id == id } }
    func client(_ id: UUID) -> Client? { clients.first { $0.id == id } }
    func client(for session: Session) -> Client? {
        if let p = package(session.packageID) { return client(p.clientID) }
        return session.clientID.flatMap { client($0) }
    }
    func client(for payment: Payment) -> Client? {
        if let p = package(payment.packageID) { return client(p.clientID) }
        return sessions.first { $0.id == payment.sessionID }.flatMap { client(for: $0) }
    }
    func sessionPaid(_ id: UUID) -> Int { payments.filter { $0.sessionID == id }.reduce(0) { $0 + $1.cents } }
    func sessionPrice(_ s: Session) -> Int {
        if s.status == .trainerCancelled || (s.status == .clientCancelled || s.status == .noShow) && !s.charged { return 0 }
        return s.feeCents ?? 0
    }
    func sessionBalance(_ s: Session) -> Int { max(0, sessionPrice(s) - sessionPaid(s.id)) }
    func balanceForClient(_ id: UUID) -> Int {
        packages.filter { $0.clientID == id }.reduce(0) { $0 + balance($1.id) } + sessions.filter { $0.packageID == nil && $0.clientID == id }.reduce(0) { $0 + sessionBalance($1) }
    }
    var totalBalance: Int { clients.reduce(0) { $0 + balanceForClient($1.id) } }
    func used(_ id: UUID) -> Int { sessions.filter { $0.packageID == id && $0.charged }.count }
    func reserved(_ id: UUID, excluding: UUID? = nil) -> Int {
        sessions.filter { $0.packageID == id && $0.status == .scheduled && $0.id != excluding }.count
    }
    func remaining(_ id: UUID?) -> Int { (package(id)?.sessions ?? 0) - (id.map { used($0) } ?? 0) }
    /// Credits still available to book, excluding both used and reserved sessions.
    func available(_ id: UUID?, excluding sessionID: UUID? = nil) -> Int {
        guard let id else { return 0 }
        return max(0, remaining(id) - reserved(id, excluding: sessionID))
    }
    func paid(_ id: UUID) -> Int { payments.filter { $0.packageID == id }.reduce(0) { $0 + $1.cents } }
    func balance(_ id: UUID) -> Int { max(0, (package(id)?.priceCents ?? 0) - paid(id)) }
    func paymentFollowUps(at now: Date = Date()) -> [Session] {
        sessions.filter { $0.packageID == nil && !$0.isTrial && $0.end <= now && sessionBalance($0) > 0 }
            .sorted { $0.start < $1.start }
    }
    func sessionTotals(for clientID: UUID) -> (purchased: Int, used: Int, booked: Int, available: Int) {
        let purchases = packages.filter { $0.clientID == clientID }
        let singles = sessions.filter { $0.clientID == clientID && $0.packageID == nil && !$0.isTrial }
        return (
            purchases.reduce(0) { $0 + $1.sessions } + singles.count,
            purchases.reduce(0) { $0 + used($1.id) } + singles.filter { $0.charged }.count,
            purchases.reduce(0) { $0 + reserved($1.id) } + singles.filter { $0.status == .scheduled }.count,
            purchases.reduce(0) { $0 + available($1.id) }
        )
    }
    func remainingForClient(_ id: UUID) -> Int { packages.filter { $0.clientID == id }.reduce(0) { $0 + available($1.id) } }
    func expired(_ package: Package, at date: Date = Date()) -> Bool {
        guard let expiry = package.expires else { return false }
        return Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: expiry)
    }
    /// Allocates every cent, including packages whose price is not divisible by session count.
    func earnedCents(for session: Session) -> Int {
        guard session.charged else { return 0 }
        guard let p = package(session.packageID) else { return session.feeCents ?? 0 }
        let charged = sessions.filter { $0.packageID == p.id && $0.charged }.sorted {
            $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start
        }
        let index = charged.firstIndex { $0.id == session.id } ?? 0
        return p.priceCents / p.sessions + (index < p.priceCents % p.sessions ? 1 : 0)
    }
    var activeClients: [Client] { clients.filter { !$0.isArchived } }
    func hasClientPayments(_ id: UUID) -> Bool {
        payments.contains { client(for: $0)?.id == id }
    }
    mutating func archiveClient(_ id: UUID, now: Date = Date()) throws {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        guard !sessions.contains(where: { client(for: $0)?.id == id && $0.status == .scheduled && $0.end > now }) else {
            throw LedgerError(key: "Cancel or complete upcoming sessions before archiving this client.")
        }
        clients[index].archivedAt = now
    }
    mutating func deleteClient(_ id: UUID) throws {
        guard !hasClientPayments(id) else { throw LedgerError(key: "Clients with payment or refund records can only be archived.") }
        let sessionIDs = Set(sessions.filter { client(for: $0)?.id == id }.map(\.id))
        sessions.removeAll { sessionIDs.contains($0.id) }
        packages.removeAll { $0.clientID == id }
        clients.removeAll { $0.id == id }
    }
    mutating func addClient(_ client: Client) throws {
        guard !client.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LedgerError(key: "Enter a client name.") }
        if let i = clients.firstIndex(where: { $0.id == client.id }) { clients[i] = client } else { clients.append(client) }
    }
    mutating func addPackage(_ p: Package, initialCents: Int, method: String) throws {
        guard client(p.clientID) != nil, !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              p.sessions > 0, p.sessions <= 1000, p.minutes > 0, p.minutes <= 1440,
              p.priceCents >= 0, p.priceCents <= 100_000_000, initialCents >= 0, initialCents <= p.priceCents else {
            throw LedgerError(key: "Check the package name, sessions, duration and amounts.")
        }
        if let expiry = p.expires, Calendar.current.startOfDay(for: expiry) < Calendar.current.startOfDay(for: p.purchased) {
            throw LedgerError(key: "Expiry must be on or after the purchase date.")
        }
        packages.append(p)
        if initialCents > 0 { payments.append(Payment(packageID: p.id, cents: initialCents, date: p.purchased, method: method)) }
    }
    mutating func addPayment(_ payment: Payment) throws {
        guard payment.cents != 0, payment.cents >= -100_000_000, payment.cents <= 100_000_000 else { throw LedgerError(key: "Enter a valid amount.") }
        let due: Int
        let received: Int
        if let packageID = payment.packageID, payment.sessionID == nil, let p = package(packageID) {
            due = balance(p.id); received = paid(p.id)
        } else if payment.packageID == nil, let id = payment.sessionID, let session = sessions.first(where: { $0.id == id }), !session.isTrial, session.packageID == nil {
            due = sessionBalance(session); received = sessionPaid(id)
        } else { throw LedgerError(key: "Choose a package or paid single session.") }
        guard payment.cents > 0 ? payment.cents <= due : -payment.cents <= received else {
            throw LedgerError(key: "Payment exceeds the balance, or refund exceeds payments received.")
        }
        payments.append(payment)
    }
    mutating func book(_ session: Session, repeats: Int = 1) throws {
        guard session.minutes > 0, session.minutes <= 1440, repeats > 0, repeats <= 52 else { throw LedgerError(key: "Choose a client and valid duration.") }
        if let id = session.packageID {
            guard let p = package(id) else { throw LedgerError(key: "Choose a package and valid duration.") }
            guard available(p.id, excluding: session.id) >= repeats else {
                throw LedgerError(key: "Not enough unbooked sessions. Add a package or release an existing booking.")
            }
        } else {
            guard let id = session.clientID, client(id) != nil, let fee = session.feeCents, fee >= 0, fee <= 100_000_000 else { throw LedgerError(key: "Choose a client and enter a valid session price.") }
        }
        if let old = sessions.first(where: { $0.id == session.id }), sessionPaid(old.id) > 0 {
            guard session.packageID == old.packageID, session.clientID == old.clientID, (session.feeCents ?? 0) >= sessionPaid(old.id) else {
                throw LedgerError(key: "Refund existing payments before reducing the session price.")
            }
        }
        var proposed: [Session] = []
        for week in 0..<repeats {
            var next = session
            if week > 0 { next.id = UUID() }
            guard let date = Calendar.current.date(byAdding: .weekOfYear, value: week, to: session.start) else { throw LedgerError(key: "Choose a valid date.") }
            next.start = date
            if let p = package(session.packageID), date < p.purchased || expired(p, at: date) { throw LedgerError(key: "The session must fall within the package dates.") }
            let others = sessions.filter { $0.id != session.id && ($0.status == .scheduled || $0.status == .completed) } + proposed
            guard !others.contains(where: { next.start < $0.end && next.end > $0.start }) else {
                throw LedgerError(key: "This time overlaps another booking. Choose a different time.")
            }
            proposed.append(next)
        }
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            guard sessions[i].status == .scheduled else { throw LedgerError(key: "Restore the session to scheduled before editing.") }
            sessions.remove(at: i)
        }
        // Moving a manually retained past booking into the future resumes automation.
        for index in proposed.indices where proposed[index].end > Date() {
            proposed[index].automaticCompletionSuppressed = false
        }
        sessions.append(contentsOf: proposed)
    }
    /// Save a new booking and its elapsed occurrences in one atomic write.
    mutating func recordBooking(_ session: Session, repeats: Int = 1, now: Date = Date(), payment: Payment? = nil) throws {
        var updated = self
        let priorIDs = Set(sessions.map(\.id))
        try updated.book(session, repeats: repeats)
        let affected = updated.sessions.filter { !priorIDs.contains($0.id) || $0.id == session.id }
        for occurrence in affected where occurrence.status == .scheduled && occurrence.end <= now && occurrence.automaticCompletionSuppressed != true {
            try updated.updateSession(occurrence.id, status: .completed, charge: true, notes: occurrence.notes, now: now, automatic: true)
        }
        if let payment {
            guard repeats == 1, !priorIDs.contains(session.id), session.packageID == nil, !session.isTrial,
                  payment.sessionID == session.id, payment.packageID == nil, payment.cents > 0,
                  payment.date <= now else { throw LedgerError(key: "Enter a valid amount and payment date.") }
            try updated.addPayment(payment)
        }
        self = updated
    }
    /// Edit any course directly while keeping payments, credits and history consistent.
    mutating func saveSessionEdits(_ edit: Session, statusWasChanged: Bool = false, now: Date = Date()) throws {
        guard let index = sessions.firstIndex(where: { $0.id == edit.id }) else { throw LedgerError(key: "Session not found.") }
        let original = sessions[index]
        guard edit.minutes > 0, edit.minutes <= 1440, edit.clientID == original.clientID,
              (edit.packageID != nil) == (original.packageID != nil), edit.isTrial == original.isTrial else {
            throw LedgerError(key: "Choose a client and valid duration.")
        }
        var candidate = original
        candidate.start = edit.start; candidate.minutes = edit.minutes
        candidate.location = edit.location; candidate.notes = edit.notes
        candidate.reminderMinutes = edit.reminderMinutes
        candidate.packageID = edit.packageID; candidate.feeCents = edit.feeCents
        candidate.status = edit.status
        let timingChanged = candidate.start != original.start || candidate.minutes != original.minutes
        if timingChanged && !statusWasChanged && candidate.status == .completed && candidate.start > now {
            candidate.status = .scheduled
        }
        candidate.automaticCompletionSuppressed = candidate.status == .scheduled && candidate.end <= now && (statusWasChanged || (!timingChanged && original.automaticCompletionSuppressed == true))
        if candidate.status == .scheduled && candidate.end <= now && candidate.automaticCompletionSuppressed != true {
            candidate.status = .completed
        }
        candidate.charged = !candidate.isTrial && (candidate.status == .completed || ((candidate.status == .clientCancelled || candidate.status == .noShow) && edit.charged))
        if (candidate.status == .completed || candidate.status == .noShow) && candidate.start > now {
            throw LedgerError(key: "Future sessions cannot be marked completed or no-show.")
        }
        let otherSessions = sessions.filter { $0.id != candidate.id }
        if candidate.status == .scheduled || candidate.status == .completed {
            guard !otherSessions.contains(where: { ($0.status == .scheduled || $0.status == .completed) && candidate.start < $0.end && candidate.end > $0.start }) else {
                throw LedgerError(key: "This time overlaps another booking. Choose a different time.")
            }
        }
        if let id = candidate.packageID {
            guard let p = package(id), p.clientID == package(original.packageID)?.clientID,
                  candidate.start >= p.purchased, !expired(p, at: candidate.start) else {
                throw LedgerError(key: "The session must fall within the package dates.")
            }
            var others = self; others.sessions = otherSessions
            if candidate.status == .scheduled || candidate.charged {
                guard others.available(id) > 0 else { throw LedgerError(key: "No unbooked sessions remaining in this package.") }
            }
        } else {
            guard let fee = candidate.feeCents, fee >= 0, fee <= 100_000_000 else { throw LedgerError(key: "Enter a valid amount.") }
            guard fee >= sessionPaid(candidate.id) else { throw LedgerError(key: "Refund existing payments before reducing the session price.") }
        }
        sessions[index] = candidate
    }
    func hasSessionPayments(_ id: UUID) -> Bool { payments.contains { $0.sessionID == id } }
    mutating func deleteSession(_ id: UUID) throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { throw LedgerError(key: "Session not found.") }
        // Keep the original session as the payment/refund's accounting reference,
        // even when the net amount is zero after a full refund.
        guard !hasSessionPayments(id) else { throw LedgerError(key: "This session has payment or refund records. Keep it and use a cancellation status to preserve your financial history.") }
        sessions.remove(at: index)
    }
    mutating func updateSession(_ id: UUID, status: SessionStatus, charge: Bool, notes: String, now: Date = Date(), automatic: Bool = false) throws {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { throw LedgerError(key: "Session not found.") }
        let s = sessions[i]
        let shouldCharge = !s.isTrial && (status == .completed || ((status == .clientCancelled || status == .noShow) && charge))
        if let packageID = s.packageID, shouldCharge && !s.charged && available(packageID, excluding: id) <= 0 { throw LedgerError(key: "No unbooked sessions remaining in this package.") }
        if (status == .completed || status == .noShow) && s.start > now { throw LedgerError(key: "Future sessions cannot be marked completed or no-show.") }
        if status == .completed && sessions.contains(where: { $0.id != id && ($0.status == .scheduled || $0.status == .completed) && s.start < $0.end && s.end > $0.start }) {
            throw LedgerError(key: "This time overlaps another booking. Choose a different time.")
        }
        if status == .scheduled && s.status != .scheduled {
            if let packageID = s.packageID {
                guard let p = package(packageID), !expired(p, at: s.start) else { throw LedgerError(key: "The session must fall within the package dates.") }
                let released = s.charged ? 1 : 0
                guard remaining(packageID) + released - reserved(packageID) > 0 else { throw LedgerError(key: "Not enough unbooked sessions. Add a package or release an existing booking.") }
            }
            guard !sessions.contains(where: { $0.id != id && ($0.status == .scheduled || $0.status == .completed) && s.start < $0.end && s.end > $0.start }) else {
                throw LedgerError(key: "This time overlaps another booking. Choose a different time.")
            }
        }
        sessions[i].status = status
        sessions[i].charged = shouldCharge
        sessions[i].notes = notes
        if !automatic { sessions[i].automaticCompletionSuppressed = status == .scheduled && s.end <= now }
    }
    /// Runs on launch, foreground and while the app is active; does not create payments.
    @discardableResult mutating func completeElapsedSessions(at now: Date = Date()) -> Int {
        let due = sessions.filter { $0.status == .scheduled && $0.end <= now && $0.automaticCompletionSuppressed != true }
            .sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start }
        var count = 0
        for session in due {
            do {
                try updateSession(session.id, status: .completed, charge: true, notes: session.notes, now: now, automatic: true)
                count += 1
            } catch { continue } // Preserve inconsistent legacy records for manual correction.
        }
        return count
    }
    static func demo() -> Ledger {
        var book = Ledger()
        let names = [("Alex Morgan", "Build strength & consistency"), ("Jamie Chen", "Half-marathon preparation"), ("Taylor Reed", "Move better, feel stronger")]
        let today = Calendar.current.startOfDay(for: Date())
        for (index, value) in names.enumerated() {
            let c = Client(name: value.0, goal: value.1)
            book.clients.append(c)
            let bought = Calendar.current.date(byAdding: .day, value: -21, to: today)!
            let p = Package(clientID: c.id, name: "Personal training", sessions: index == 2 ? 4 : 10, minutes: index == 1 ? 45 : 60, priceCents: index == 2 ? 36000 : 90000, purchased: bought)
            book.packages.append(p)
            book.payments.append(Payment(packageID: p.id, cents: index == 1 ? 45000 : p.priceCents, date: Calendar.current.date(byAdding: .day, value: -min(index * 3, Calendar.current.component(.day, from: today) - 1), to: today)!, method: "Zelle"))
            for n in 0..<(index == 2 ? 2 : 3) {
                let date = Calendar.current.date(byAdding: .day, value: -(n + 1) * 3, to: today)!
                book.sessions.append(Session(packageID: p.id, start: date, minutes: p.minutes, status: .completed, charged: true))
            }
            let date = Calendar.current.date(byAdding: .hour, value: 9 + index * 3, to: today)!
            book.sessions.append(Session(packageID: p.id, start: date, minutes: p.minutes, location: "Studio A"))
        }
        book.clients.append(Client(name: "Riley Park", goal: "First training session"))
        return book
    }
}

func parseCents(_ value: String) -> Int? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.range(of: "^[0-9]+([.][0-9]{1,2})?$", options: .regularExpression) != nil,
          let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), amount <= 1_000_000 else { return nil }
    return NSDecimalNumber(decimal: amount * 100).intValue
}
