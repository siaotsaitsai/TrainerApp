import Foundation

@main struct LedgerTests {
    static func main() throws {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            guard condition() else { fatalError(message) }
        }
        func rejects(_ message: String, _ operation: () throws -> Void) {
            assertions += 1
            do { try operation(); fatalError("Should reject: \(message)") } catch { }
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let bought = cal.date(byAdding: .day, value: -40, to: today)!
        var ledger = Ledger()
        let client = Client(name: "Alex")
        try ledger.addClient(client)
        rejects("blank client") { try ledger.addClient(Client(name: "  ")) }
        let p = Package(clientID: client.id, name: "10 pack", sessions: 3, minutes: 60, priceCents: 10000, purchased: bought)
        try ledger.addPackage(p, initialCents: 4000, method: "Cash")
        check(ledger.balance(p.id) == 6000, "Partial payment balance")
        check(ledger.remaining(p.id) == 3, "Purchase adds credits")
        rejects("overpay") { try ledger.addPayment(Payment(packageID: p.id, cents: 6001, method: "Cash")) }
        rejects("overrefund") { try ledger.addPayment(Payment(packageID: p.id, cents: -4001, method: "Cash")) }
        try ledger.addPayment(Payment(packageID: p.id, cents: 6000, method: "Venmo"))
        check(ledger.balance(p.id) == 0, "Fully paid")
        try ledger.addPayment(Payment(packageID: p.id, cents: -1000, method: "Cash"))
        check(ledger.paid(p.id) == 9000 && ledger.balance(p.id) == 1000, "Refund balance")
        check(ledger.remaining(p.id) == 3, "Refund preserves credits")
        let past = cal.date(byAdding: .day, value: -10, to: today)!
        let s = Session(packageID: p.id, start: past, minutes: 75)
        try ledger.book(s, repeats: 2)
        check(ledger.remaining(p.id) == 3, "Booking doesn't deduct")
        check(ledger.reserved(p.id) == 2, "Weekly reservations")
        rejects("collision") { try ledger.book(Session(packageID: p.id, start: past.addingTimeInterval(60), minutes: 20)) }
        rejects("capacity") { try ledger.book(Session(packageID: p.id, start: today, minutes: 60), repeats: 2) }
        let original = ledger
        rejects("atomic repeats") { try ledger.book(Session(packageID: p.id, start: past.addingTimeInterval(-7 * 86400), minutes: 60), repeats: 2) }
        check(ledger == original, "Failed recurrence does not partially book")
        try ledger.updateSession(s.id, status: .completed, charge: true, notes: "Good")
        check(ledger.remaining(p.id) == 2, "Custom length consumes one")
        try ledger.updateSession(s.id, status: .completed, charge: true, notes: "Again")
        check(ledger.remaining(p.id) == 2, "Idempotent completion")
        try ledger.updateSession(s.id, status: .scheduled, charge: true, notes: "")
        check(ledger.remaining(p.id) == 3 && ledger.reserved(p.id) == 2, "Undo restores credit")
        try ledger.updateSession(s.id, status: .clientCancelled, charge: false, notes: "")
        check(ledger.remaining(p.id) == 3, "Free cancellation")
        try ledger.updateSession(s.id, status: .noShow, charge: true, notes: "")
        check(ledger.remaining(p.id) == 2, "Charged no-show")
        try ledger.updateSession(s.id, status: .trainerCancelled, charge: true, notes: "")
        check(ledger.remaining(p.id) == 3, "Trainer cancellation never charges")
        try ledger.updateSession(s.id, status: .completed, charge: true, notes: "")
        let other = ledger.sessions.first { $0.id != s.id }!
        try ledger.updateSession(other.id, status: .completed, charge: true, notes: "")
        let third = Session(packageID: p.id, start: today.addingTimeInterval(-3600), minutes: 30)
        try ledger.book(third)
        try ledger.updateSession(third.id, status: .completed, charge: true, notes: "")
        check(ledger.remaining(p.id) == 0, "Full consumption")
        check(ledger.sessions.reduce(0) { $0 + ledger.earnedCents(for: $1) } == 10000, "Revenue allocation sums exactly to package price")
        rejects("exhausted") { try ledger.book(Session(packageID: p.id, start: today, minutes: 60)) }
        let futurePackage = Package(clientID: client.id, name: "Future", sessions: 4, minutes: 60, priceCents: 0, purchased: bought, expires: today)
        try ledger.addPackage(futurePackage, initialCents: 0, method: "Cash")
        rejects("expired booking") { try ledger.book(Session(packageID: futurePackage.id, start: today.addingTimeInterval(86400), minutes: 60)) }
        let future = Session(packageID: futurePackage.id, start: Date().addingTimeInterval(60), minutes: 30)
        if cal.isDateInToday(future.start) {
            try ledger.book(future)
            rejects("future completion") { try ledger.updateSession(future.id, status: .completed, charge: true, notes: "") }
        }
        check(parseCents("12.34") == 1234, "USD precision")
        check(parseCents("0") == 0, "Free package")
        check(parseCents("1.234") == nil && parseCents("-1") == nil && parseCents("NaN") == nil, "Invalid amounts")
        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(Ledger.self, from: data)
        check(decoded == ledger, "Persistence roundtrip")
        var reservedLedger = Ledger()
        try reservedLedger.addClient(client)
        let last = Package(clientID: client.id, name: "Last credit", sessions: 1, minutes: 60, priceCents: 100, purchased: bought)
        try reservedLedger.addPackage(last, initialCents: 0, method: "Cash")
        let cancelled = Session(packageID: last.id, start: past, minutes: 60)
        try reservedLedger.book(cancelled)
        try reservedLedger.updateSession(cancelled.id, status: .clientCancelled, charge: false, notes: "")
        let replacement = Session(packageID: last.id, start: today, minutes: 60)
        try reservedLedger.book(replacement)
        rejects("retroactive charge must respect booked credits") { try reservedLedger.updateSession(cancelled.id, status: .clientCancelled, charge: true, notes: "") }
        rejects("restoring cancelled session must respect capacity") { try reservedLedger.updateSession(cancelled.id, status: .scheduled, charge: false, notes: "") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TrainerApp-checks-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let persistence = LedgerPersistence(file: folder.appendingPathComponent("ledger.json"))
        let empty = try persistence.load()
        check(empty.clients.isEmpty, "New data starts empty")
        try persistence.save(ledger)
        let loaded = try persistence.load()
        check(loaded == ledger, "Disk persistence preserves all records")
        try persistence.save(reservedLedger)
        let prior = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: folder.appendingPathComponent("ledger.previous.json")))
        check(prior == ledger, "Previous snapshot is preserved")
        try Data("invalid JSON".utf8).write(to: persistence.file)
        rejects("corrupt data is not silently replaced") { _ = try persistence.load() }
        var unsupported = ledger; unsupported.version = 2
        try JSONEncoder().encode(unsupported).write(to: persistence.file)
        rejects("unknown version") { _ = try persistence.load() }
        var singles = Ledger()
        try singles.addClient(client)
        let trial = Session(clientID: client.id, feeCents: 0, start: past, minutes: 30)
        try singles.book(trial)
        check(singles.packages.isEmpty && singles.sessions.count == 1, "Trial needs no package")
        try singles.updateSession(trial.id, status: .completed, charge: true, notes: "Trial completed")
        check(!singles.sessions[0].charged && singles.earnedCents(for: singles.sessions[0]) == 0, "Free trial never charges or earns revenue")
        rejects("trial payment") { try singles.addPayment(Payment(sessionID: trial.id, cents: 100, method: "Cash")) }
        let oneOff = Session(clientID: client.id, feeCents: 9000, start: past.addingTimeInterval(3600), minutes: 45)
        try singles.book(oneOff)
        check(singles.balanceForClient(client.id) == 9000, "Single session creates receivable")
        try singles.addPayment(Payment(sessionID: oneOff.id, cents: 4000, method: "Cash"))
        check(singles.sessionBalance(oneOff) == 5000 && singles.totalBalance == 5000, "Partial single payment")
        rejects("single overpayment") { try singles.addPayment(Payment(sessionID: oneOff.id, cents: 5001, method: "Cash")) }
        try singles.addPayment(Payment(sessionID: oneOff.id, cents: 5000, method: "Zelle"))
        try singles.updateSession(oneOff.id, status: .completed, charge: true, notes: "")
        try singles.updateSession(oneOff.id, status: .completed, charge: true, notes: "Again")
        let completedSingle = singles.sessions.first { $0.id == oneOff.id }!
        check(singles.earnedCents(for: completedSingle) == 9000 && singles.packages.isEmpty, "Single revenue without credits")
        check(singles.balanceForClient(client.id) == 0, "Single fully paid")
        try singles.updateSession(oneOff.id, status: .clientCancelled, charge: false, notes: "Waived")
        let waived = singles.sessions.first { $0.id == oneOff.id }!
        check(singles.sessionBalance(waived) == 0 && singles.earnedCents(for: waived) == 0, "Waived single earns zero")
        try singles.addPayment(Payment(sessionID: oneOff.id, cents: -9000, method: "Cash"))
        check(singles.sessionPaid(oneOff.id) == 0, "Single refund supported")
        rejects("single overrefund") { try singles.addPayment(Payment(sessionID: oneOff.id, cents: -1, method: "Cash")) }
        try singles.updateSession(oneOff.id, status: .noShow, charge: true, notes: "")
        check(singles.totalBalance == 9000, "Charged single no-show owes fee")
        let recurringTrial = Session(clientID: client.id, feeCents: 0, start: today.addingTimeInterval(7200), minutes: 20)
        try singles.book(recurringTrial, repeats: 3)
        check(singles.sessions.count == 5 && singles.remainingForClient(client.id) == 0, "Standalone recurrence never uses credits")
        rejects("cross-type overlap") { try singles.book(Session(clientID: client.id, feeCents: 500, start: recurringTrial.start, minutes: 20)) }
        let standaloneData = try JSONEncoder().encode(singles)
        let standaloneRestored = try JSONDecoder().decode(Ledger.self, from: standaloneData)
        check(standaloneRestored == singles, "Standalone payment and session persistence")
        // All new fields are optional. Decode an original v1 session/payment with none of them.
        let legacyJSON = """
        {"version":1,"clients":[],"packages":[],"payments":[{"id":"00000000-0000-0000-0000-000000000001","packageID":"00000000-0000-0000-0000-000000000002","cents":100,"date":0,"method":"Cash","note":""}],"sessions":[{"id":"00000000-0000-0000-0000-000000000003","packageID":"00000000-0000-0000-0000-000000000002","start":0,"minutes":60,"location":"","notes":"","status":"scheduled","charged":false}]}
        """
        let legacy = try JSONDecoder().decode(Ledger.self, from: Data(legacyJSON.utf8))
        check(legacy.sessions[0].packageID != nil && legacy.sessions[0].clientID == nil && legacy.payments[0].sessionID == nil, "Existing v1 data stays readable")
        let reminderNow = today.addingTimeInterval(3600)
        var reminderLedger = Ledger()
        reminderLedger.clients = [client]
        let upcoming = Session(clientID: client.id, feeCents: 0, start: reminderNow.addingTimeInterval(3600), minutes: 30)
        reminderLedger.sessions = [upcoming]
        let defaultPlan = SessionReminder.plan(ledger: reminderLedger, minutesBefore: 30, now: reminderNow)
        check(defaultPlan.count == 1 && defaultPlan[0].fireDate == upcoming.start.addingTimeInterval(-1800), "Default 30-minute reminder")
        check(defaultPlan[0].sessionID == upcoming.id, "Reminder links to session")
        reminderLedger.sessions[0].reminderMinutes = 15
        let customPlan = SessionReminder.plan(ledger: reminderLedger, minutesBefore: 30, now: reminderNow)
        check(customPlan[0].fireDate == upcoming.start.addingTimeInterval(-900) && customPlan[0].id != defaultPlan[0].id, "Per-session override replaces old reminder")
        reminderLedger.sessions[0].reminderMinutes = -1
        check(SessionReminder.plan(ledger: reminderLedger, minutesBefore: 30, now: reminderNow).isEmpty, "Per-session reminder off")
        reminderLedger.sessions[0].reminderMinutes = nil
        reminderLedger.sessions[0].start = reminderNow.addingTimeInterval(300)
        check(SessionReminder.plan(ledger: reminderLedger, minutesBefore: 30, now: reminderNow)[0].fireDate == reminderLedger.sessions[0].start, "Late booking alerts at start")
        reminderLedger.sessions[0].status = .clientCancelled
        check(SessionReminder.plan(ledger: reminderLedger, minutesBefore: 30, now: reminderNow).isEmpty, "Cancellation removes reminder")
        reminderLedger.sessions[0].status = .completed
        check(SessionReminder.plan(ledger: reminderLedger, minutesBefore: 30, now: reminderNow).isEmpty, "Completed session has no reminder")
        reminderLedger.sessions[0].status = .scheduled
        reminderLedger.sessions[0].start = reminderNow.addingTimeInterval(-60)
        check(SessionReminder.plan(ledger: reminderLedger, minutesBefore: 30, now: reminderNow).isEmpty, "Past session has no reminder")
        reminderLedger.sessions = (1...70).map { n in Session(clientID: client.id, feeCents: 100, start: reminderNow.addingTimeInterval(Double(n) * 3600), minutes: 30) }
        let queue = SessionReminder.plan(ledger: reminderLedger, minutesBefore: 30, now: reminderNow)
        check(queue.count == 60 && queue.first?.sessionID == reminderLedger.sessions[0].id && queue.last?.sessionID == reminderLedger.sessions[59].id, "Queue caps nearest 60 reminders")
        let beforeEdit = queue[0]
        reminderLedger.sessions[0].start.addTimeInterval(60)
        let afterEdit = SessionReminder.plan(ledger: reminderLedger, minutesBefore: 30, now: reminderNow)[0]
        check(beforeEdit.id != afterEdit.id && beforeEdit.fireDate != afterEdit.fireDate, "Rescheduling changes reminder identity and delivery time")
        reminderLedger.sessions[0].reminderMinutes = 5
        let reminderData = try JSONEncoder().encode(reminderLedger)
        let reminderRestored = try JSONDecoder().decode(Ledger.self, from: reminderData)
        check(reminderRestored.sessions[0].reminderMinutes == 5 && legacy.sessions[0].reminderMinutes == nil, "Reminder preference persists and legacy sessions inherit default")
        var calendarSession = upcoming
        calendarSession.location = "Studio A"
        calendarSession.notes = "Practice footwork before strength work"
        let appointment = CalendarAppointment(session: calendarSession, clientName: "Alex", kind: "Free trial")
        check(appointment.title == "Free trial · Alex", "Calendar title identifies client and session type")
        check(appointment.start == calendarSession.start && appointment.end.timeIntervalSince(appointment.start) == 1800, "Calendar preserves date and duration")
        check(appointment.location == "Studio A" && appointment.notes.contains(calendarSession.notes), "Calendar includes saved location and notes")
        check(CalendarAppointment(session: calendarSession, clientName: "Alex", kind: "Free trial").signature == appointment.signature, "Calendar signature is stable")
        calendarSession.notes = "Updated training plan"
        check(CalendarAppointment(session: calendarSession, clientName: "Alex", kind: "Free trial").signature != appointment.signature, "Calendar detects changed notes")
        calendarSession.start.addTimeInterval(3600)
        check(CalendarAppointment(session: calendarSession, clientName: "Alex", kind: "Free trial").signature != appointment.signature, "Calendar detects changed appointment time")
        calendarSession.calendarAddedAt = Date()
        calendarSession.calendarAddedSignature = appointment.signature
        let exportedSessionData = try JSONEncoder().encode(calendarSession)
        let exportedSessionRestored = try JSONDecoder().decode(Session.self, from: exportedSessionData)
        check(exportedSessionRestored == calendarSession && legacy.sessions[0].calendarAddedAt == nil, "Calendar export history persists with legacy compatibility")
        var free = Ledger()
        let first = Client(name: "First", created: bought)
        let second = Client(name: "Second", created: bought.addingTimeInterval(60))
        let thirdClient = Client(name: "Third", created: bought.addingTimeInterval(120))
        var firstAdded = free; try firstAdded.addClient(first)
        check(ClientAccessPolicy.canApply(before: free, after: firstAdded, isPro: false), "Free first client allowed")
        free = firstAdded; var secondAdded = free; try secondAdded.addClient(second)
        check(ClientAccessPolicy.canApply(before: free, after: secondAdded, isPro: false), "Free second client allowed")
        free = secondAdded; var thirdAdded = free; try thirdAdded.addClient(thirdClient)
        check(ClientAccessPolicy.canApply(before: free, after: thirdAdded, isPro: false), "Free third client allowed")
        let fourthClient = Client(name: "Fourth", created: bought.addingTimeInterval(180))
        var fourthAdded = thirdAdded; try fourthAdded.addClient(fourthClient)
        check(!ClientAccessPolicy.canApply(before: thirdAdded, after: fourthAdded, isPro: false), "Free fourth client requires Pro")
        check(ClientAccessPolicy.canApply(before: thirdAdded, after: fourthAdded, isPro: true), "Pro fourth client allowed")
        check(ClientAccessPolicy.canApply(before: free, after: thirdAdded, isPro: true), "Verified Pro allows third client")
        var thirdEdited = fourthAdded; thirdEdited.clients[3].notes = "New plan"
        check(!ClientAccessPolicy.canApply(before: fourthAdded, after: thirdEdited, isPro: false), "Expired Pro keeps extra clients read-only")
        check(ClientAccessPolicy.canApply(before: fourthAdded, after: thirdEdited, isPro: true), "Renewal unlocks existing extras")
        var firstEdited = fourthAdded; firstEdited.clients[0].notes = "Still editable"
        check(ClientAccessPolicy.canApply(before: fourthAdded, after: firstEdited, isPro: false), "First three remain editable after expiry")
        check(fourthAdded.clients.count == 4 && ClientAccessPolicy.freeClientIDs(in: fourthAdded) == Set([first.id, second.id, thirdClient.id]), "No records are deleted after expiry")
        let extraSession = Session(clientID: fourthClient.id, feeCents: 5000, start: past, minutes: 30)
        var extraBooked = fourthAdded; try extraBooked.book(extraSession)
        check(!ClientAccessPolicy.canApply(before: fourthAdded, after: extraBooked, isPro: false), "Bookings cannot bypass extra-client limit")
        let freeSession = Session(clientID: first.id, feeCents: 5000, start: past, minutes: 30)
        var freeBooked = fourthAdded; try freeBooked.book(freeSession)
        check(ClientAccessPolicy.canApply(before: fourthAdded, after: freeBooked, isPro: false), "Free clients can still book and bill")
        var extraPaid = extraBooked; try extraPaid.addPayment(Payment(sessionID: extraSession.id, cents: 5000, method: "Cash"))
        check(!ClientAccessPolicy.canApply(before: extraBooked, after: extraPaid, isPro: false), "Payments cannot bypass extra-client limit")
        check(ClientAccessPolicy.canApply(before: fourthAdded, after: fourthAdded, isPro: false), "Read-only no-op does not alter entitlement")
        var csvLedger = Ledger()
        var csvCalendar = Calendar(identifier: .gregorian)
        csvCalendar.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        let csvDate = ISO8601DateFormatter().date(from: "2026-01-01T03:00:00Z")!
        let csvClient = Client(name: "王, \"Alex\"".replacingOccurrences(of: "\\", with: ""))
        csvLedger.clients = [csvClient]
        let csvPackage = Package(clientID: csvClient.id, name: "=SUM(1,2)", sessions: 5, minutes: 60, priceCents: 10000)
        csvLedger.packages = [csvPackage]
        csvLedger.payments = [Payment(packageID: csvPackage.id, cents: 12345, date: csvDate, method: "Cash", note: "line one\nline two"), Payment(packageID: csvPackage.id, cents: -2345, date: csvDate, method: "Cash", note: "@unsafe")]
        check(IncomeCSV.payments(in: csvLedger, year: 2025, calendar: csvCalendar).count == 2 && IncomeCSV.payments(in: csvLedger, year: 2026, calendar: csvCalendar).isEmpty, "CSV uses local payment year at midnight boundary")
        let csv = String(decoding: IncomeCSV.data(ledger: csvLedger, year: 2025, calendar: csvCalendar), as: UTF8.self)
        check(csv.hasPrefix("\u{FEFF}") && csv.contains("王, \"\"Alex\"\""), "CSV preserves Chinese and escapes quotes")
        check(csv.contains(",123.45,") && csv.contains(",-23.45,") && csv.contains("Refund"), "CSV amounts are numeric and refunds negative")
        check(csv.contains("'@unsafe") && csv.contains("'=SUM(1,2)"), "CSV neutralizes user-entered spreadsheet formulas")
        check(csv.contains("\"line one\nline two\"") && csv.contains("2025-12-31"), "CSV quotes multiline notes and includes local date")
        check(IncomeCSV.amount(0) == "0.00" && IncomeCSV.amount(-1) == "-0.01", "CSV exact cents avoid floating point rounding")
        var deletions = Ledger()
        let deleteClient = Client(name: "Deletion tests")
        try deletions.addClient(deleteClient)
        let deletePackage = Package(clientID: deleteClient.id, name: "Test package", sessions: 3, minutes: 60, priceCents: 30000, purchased: past.addingTimeInterval(-86400))
        try deletions.addPackage(deletePackage, initialCents: 30000, method: "Cash")
        let completedDelete = Session(packageID: deletePackage.id, start: past, minutes: 60, status: .completed, charged: true)
        deletions.sessions.append(completedDelete)
        let originalPackagePayments = deletions.payments
        try deletions.deleteSession(completedDelete.id)
        check(deletions.remaining(deletePackage.id) == 3 && deletions.used(deletePackage.id) == 0 && deletions.payments == originalPackagePayments, "Deleting a package session restores credit without altering package payments")
        let scheduledDelete = Session(packageID: deletePackage.id, start: Date().addingTimeInterval(86400), minutes: 60)
        try deletions.book(scheduledDelete, repeats: 2)
        let otherBooking = deletions.sessions.first { $0.id != scheduledDelete.id }!
        try deletions.deleteSession(scheduledDelete.id)
        check(deletions.reserved(deletePackage.id) == 1 && deletions.sessions == [otherBooking], "Deletion releases reservation and keeps other recurring sessions")
        check(!SessionReminder.plan(ledger: deletions, minutesBefore: 30).contains { $0.sessionID == scheduledDelete.id }, "Deleted session has no reminder")
        let paidDelete = Session(clientID: deleteClient.id, feeCents: 5000, start: past, minutes: 30)
        deletions.sessions.append(paidDelete)
        try deletions.addPayment(Payment(sessionID: paidDelete.id, cents: 5000, method: "Cash"))
        let beforeDeletePaid = deletions
        rejects("Cannot delete a paid session") { try deletions.deleteSession(paidDelete.id) }
        check(deletions == beforeDeletePaid, "Blocked deletion preserves the entire ledger")
        try deletions.addPayment(Payment(sessionID: paidDelete.id, cents: -5000, method: "Cash"))
        rejects("Cannot delete a fully refunded session with net zero") { try deletions.deleteSession(paidDelete.id) }
        let freeDelete = Session(clientID: deleteClient.id, feeCents: 0, start: past, minutes: 30)
        deletions.sessions.append(freeDelete)
        try deletions.deleteSession(freeDelete.id)
        check(!deletions.sessions.contains { $0.id == freeDelete.id }, "Free trials can be deleted")
        rejects("Deleted session cannot be deleted again") { try deletions.deleteSession(freeDelete.id) }
        let deletedRoundtrip = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(deletions))
        check(deletedRoundtrip == deletions, "Deletion persists through save and reload")
        var lifecycle = Ledger()
        try lifecycle.addClient(client)
        let lifecycleNow = Date()
        let lifecyclePackage = Package(clientID: client.id, name: "10 sessions", sessions: 10, minutes: 60, priceCents: 100000, purchased: lifecycleNow.addingTimeInterval(-86400))
        try lifecycle.addPackage(lifecyclePackage, initialCents: 100000, method: "Cash")
        let lifecycleSession = Session(packageID: lifecyclePackage.id, start: lifecycleNow.addingTimeInterval(-1800), minutes: 60, notes: "Keep these notes")
        try lifecycle.book(lifecycleSession)
        check(lifecycle.available(lifecyclePackage.id) == 9 && lifecycle.remainingForClient(client.id) == 9 && lifecycle.used(lifecyclePackage.id) == 0 && lifecycle.reserved(lifecyclePackage.id) == 1, "10-pack booking shows 9 left, 0 used, 1 booked")
        check(lifecycle.available(lifecyclePackage.id, excluding: lifecycleSession.id) == 10, "Editing a reservation does not count it twice")
        check(lifecycle.completeElapsedSessions(at: lifecycleNow) == 0, "An ongoing session does not complete at its start time")
        let lifecycleEnd = lifecycleSession.end
        let unchangedPayments = lifecycle.payments
        check(lifecycle.completeElapsedSessions(at: lifecycleEnd) == 1, "Completion triggers at the exact end time")
        check(lifecycle.available(lifecyclePackage.id) == 9 && lifecycle.used(lifecyclePackage.id) == 1 && lifecycle.reserved(lifecyclePackage.id) == 0, "Automatic completion converts booked to used without reducing left again")
        check(lifecycle.sessions[0].notes == "Keep these notes" && lifecycle.payments == unchangedPayments, "Automatic completion preserves notes and never records payments")
        check(lifecycle.completeElapsedSessions(at: lifecycleEnd.addingTimeInterval(1)) == 0 && lifecycle.used(lifecyclePackage.id) == 1, "Repeated foreground refresh does not deduct twice")
        try lifecycle.updateSession(lifecycleSession.id, status: .scheduled, charge: false, notes: "Manual correction", now: lifecycleEnd)
        check(lifecycle.completeElapsedSessions(at: lifecycleEnd.addingTimeInterval(60)) == 0 && lifecycle.reserved(lifecyclePackage.id) == 1 && lifecycle.used(lifecyclePackage.id) == 0, "Manual past Scheduled override survives automatic refresh")
        let lifecycleData = try JSONEncoder().encode(lifecycle)
        var lifecycleReloaded = try JSONDecoder().decode(Ledger.self, from: lifecycleData)
        check(lifecycleReloaded.completeElapsedSessions(at: lifecycleEnd.addingTimeInterval(120)) == 0, "Manual override survives save and relaunch")
        try lifecycle.updateSession(lifecycleSession.id, status: .clientCancelled, charge: false, notes: "Cancelled", now: lifecycleEnd)
        check(lifecycle.available(lifecyclePackage.id) == 10 && lifecycle.completeElapsedSessions(at: lifecycleEnd.addingTimeInterval(120)) == 0, "Uncharged cancellation releases the reservation and never auto-completes")
        try lifecycle.updateSession(lifecycleSession.id, status: .noShow, charge: true, notes: "Charged no-show", now: lifecycleEnd)
        check(lifecycle.available(lifecyclePackage.id) == 9 && lifecycle.reserved(lifecyclePackage.id) == 0 && lifecycle.completeElapsedSessions(at: lifecycleEnd.addingTimeInterval(120)) == 0, "Charged no-show stays used and is not overwritten")
        var lifecycleSingles = Ledger()
        try lifecycleSingles.addClient(client)
        lifecycleSingles.sessions = [Session(clientID: client.id, feeCents: 9000, start: lifecycleNow.addingTimeInterval(-7200), minutes: 60), Session(clientID: client.id, feeCents: 0, start: lifecycleNow.addingTimeInterval(-14400), minutes: 30)]
        check(lifecycleSingles.completeElapsedSessions(at: lifecycleNow) == 2 && lifecycleSingles.sessions[0].charged && !lifecycleSingles.sessions[1].charged && lifecycleSingles.payments.isEmpty, "Paid singles and free trials complete with correct charge rules and no invented receipts")
        var capacityLifecycle = Ledger()
        try capacityLifecycle.addClient(client)
        let oneCredit = Package(clientID: client.id, name: "One", sessions: 1, minutes: 60, priceCents: 1000, purchased: lifecycleNow.addingTimeInterval(-86400))
        try capacityLifecycle.addPackage(oneCredit, initialCents: 0, method: "Cash")
        try capacityLifecycle.book(Session(packageID: oneCredit.id, start: lifecycleNow.addingTimeInterval(-7200), minutes: 60))
        check(capacityLifecycle.available(oneCredit.id) == 0 && capacityLifecycle.completeElapsedSessions(at: lifecycleNow) == 1 && capacityLifecycle.available(oneCredit.id) == 0, "A fully reserved package still completes its own booked session")
        var movedBooking = lifecycleReloaded.sessions[0]
        movedBooking.start = lifecycleNow.addingTimeInterval(86400)
        try lifecycleReloaded.book(movedBooking)
        check(lifecycleReloaded.sessions[0].automaticCompletionSuppressed == false && lifecycleReloaded.completeElapsedSessions(at: movedBooking.end) == 1, "Rescheduling a manually retained past session into the future resumes automatic completion")
        var directEdits = Ledger()
        try directEdits.addClient(client)
        let directNow = Date()
        let directPack = Package(clientID: client.id, name: "Inline", sessions: 2, minutes: 60, priceCents: 20000, purchased: directNow.addingTimeInterval(-30 * 86400))
        try directEdits.addPackage(directPack, initialCents: 20000, method: "Cash")
        let backfilled = Session(packageID: directPack.id, start: directNow.addingTimeInterval(-7200), minutes: 60, notes: "Forgot to enter")
        let receiptsBeforeBackfill = directEdits.payments
        try directEdits.recordBooking(backfilled, now: directNow)
        check(directEdits.sessions[0].status == .completed && directEdits.used(directPack.id) == 1 && directEdits.reserved(directPack.id) == 0 && directEdits.available(directPack.id) == 1, "Backdated booking completes immediately in the saving transaction")
        check(directEdits.payments == receiptsBeforeBackfill, "Backfilling does not invent receipts")
        var inline = directEdits.sessions[0]
        inline.minutes = 45; inline.location = "Updated studio"; inline.notes = "Updated notes"; inline.reminderMinutes = 10
        try directEdits.saveSessionEdits(inline, now: directNow)
        check(directEdits.sessions[0].minutes == 45 && directEdits.sessions[0].location == "Updated studio" && directEdits.sessions[0].notes == "Updated notes" && directEdits.used(directPack.id) == 1, "Completed sessions can be edited directly without another deduction")
        inline = directEdits.sessions[0]; inline.start = directNow.addingTimeInterval(3600)
        try directEdits.saveSessionEdits(inline, now: directNow)
        check(directEdits.sessions[0].status == .scheduled && directEdits.used(directPack.id) == 0 && directEdits.reserved(directPack.id) == 1, "Moving a completed session into the future restores Scheduled and reserves its credit")
        inline = directEdits.sessions[0]; inline.start = directNow.addingTimeInterval(-10800)
        try directEdits.saveSessionEdits(inline, now: directNow)
        check(directEdits.sessions[0].status == .completed && directEdits.used(directPack.id) == 1, "Directly backdating an existing booking completes it immediately")
        inline = directEdits.sessions[0]; inline.status = .scheduled; inline.charged = false
        try directEdits.saveSessionEdits(inline, statusWasChanged: true, now: directNow)
        check(directEdits.sessions[0].status == .scheduled && directEdits.completeElapsedSessions(at: directNow) == 0, "Inline manual Scheduled override stays scheduled")
        inline = directEdits.sessions[0]; inline.notes = "Preserve override"
        try directEdits.saveSessionEdits(inline, now: directNow)
        check(directEdits.sessions[0].automaticCompletionSuppressed == true && directEdits.sessions[0].status == .scheduled, "Editing notes preserves a manual override")
        let occupied = Session(packageID: directPack.id, start: directNow.addingTimeInterval(86400), minutes: 60)
        try directEdits.recordBooking(occupied, now: directNow)
        inline = directEdits.sessions[0]; inline.start = occupied.start
        let beforeOverlapEdit = directEdits
        rejects("Inline overlap edit is rejected") { try directEdits.saveSessionEdits(inline, now: directNow) }
        check(directEdits == beforeOverlapEdit, "Failed inline edit is atomic")
        inline = directEdits.sessions[0]; inline.notes = "Full package, own reserved credit"
        try directEdits.saveSessionEdits(inline, now: directNow)
        check(directEdits.available(directPack.id) == 0, "Inline edits exclude their own reservation even in a fully booked package")
        var paidInline = Ledger(); try paidInline.addClient(client)
        let paidInlineSession = Session(clientID: client.id, feeCents: 10000, start: directNow.addingTimeInterval(-7200), minutes: 60)
        try paidInline.recordBooking(paidInlineSession, now: directNow)
        try paidInline.addPayment(Payment(sessionID: paidInlineSession.id, cents: 8000, method: "Cash"))
        var pricedEdit = paidInline.sessions[0]; pricedEdit.feeCents = 7000
        rejects("Inline price cannot drop below existing receipts") { try paidInline.saveSessionEdits(pricedEdit, now: directNow) }
        pricedEdit.feeCents = 12000; pricedEdit.minutes = 50
        let paidReceipts = paidInline.payments
        try paidInline.saveSessionEdits(pricedEdit, now: directNow)
        check(paidInline.sessionBalance(paidInline.sessions[0]) == 4000 && paidInline.payments == paidReceipts, "Inline paid session edits preserve receipts and recalculate its balance")
        var repeatedBackfill = Ledger(); try repeatedBackfill.addClient(client)
        let recurringBackfill = Session(clientID: client.id, feeCents: 0, start: directNow.addingTimeInterval(-86400), minutes: 30)
        try repeatedBackfill.recordBooking(recurringBackfill, repeats: 2, now: directNow)
        check(repeatedBackfill.sessions[0].status == .completed && repeatedBackfill.sessions[1].status == .scheduled && repeatedBackfill.payments.isEmpty, "Mixed past and future recurrence completes only elapsed occurrences")
        var clientLifecycle = Ledger()
        let archiveTarget = Client(name: "Archive")
        try clientLifecycle.addClient(archiveTarget)
        let nextSession = Session(clientID: archiveTarget.id, feeCents: 0, start: directNow.addingTimeInterval(3600), minutes: 30)
        try clientLifecycle.recordBooking(nextSession, now: directNow)
        rejects("Archive refuses upcoming sessions") { try clientLifecycle.archiveClient(archiveTarget.id, now: directNow) }
        try clientLifecycle.updateSession(nextSession.id, status: .trainerCancelled, charge: false, notes: "", now: directNow)
        try clientLifecycle.archiveClient(archiveTarget.id, now: directNow)
        check(clientLifecycle.activeClients.isEmpty && clientLifecycle.sessions.count == 1, "Archive frees slot and preserves history")
        check(!ClientAccessPolicy.freeClientIDs(in: clientLifecycle).contains(archiveTarget.id), "Archived client does not use free slot")
        let roundTrip = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(clientLifecycle))
        check(roundTrip.client(archiveTarget.id)?.isArchived == true, "Archive survives persistence")
        try clientLifecycle.deleteClient(archiveTarget.id)
        check(clientLifecycle.clients.isEmpty && clientLifecycle.sessions.isEmpty, "Delete removes dependent sessions")
        let paidClientID = paidInline.client(for: paidInline.sessions[0])!.id
        let beforeDelete = paidInline
        rejects("Payments block client deletion") { try paidInline.deleteClient(paidClientID) }
        check(paidInline == beforeDelete, "Blocked deletion keeps ledger intact")
        var bookingPaymentLedger = Ledger(); try bookingPaymentLedger.addClient(client)
        let paidBooking = Session(clientID: client.id, feeCents: 9000, start: directNow.addingTimeInterval(7200), minutes: 60)
        let deposit = Payment(sessionID: paidBooking.id, cents: 3000, date: directNow, method: "Cash")
        try bookingPaymentLedger.recordBooking(paidBooking, now: directNow, payment: deposit)
        check(bookingPaymentLedger.sessions.count == 1 && bookingPaymentLedger.sessionBalance(paidBooking) == 6000 && bookingPaymentLedger.payments == [deposit], "Booking with deposit saves both and leaves unpaid balance")
        var failedBookingLedger = Ledger(); try failedBookingLedger.addClient(client)
        let failedBookingBefore = failedBookingLedger
        let excessive = Payment(sessionID: paidBooking.id, cents: 10000, date: directNow, method: "Cash")
        rejects("Overpayment at booking rejected") { try failedBookingLedger.recordBooking(paidBooking, now: directNow, payment: excessive) }
        check(failedBookingLedger == failedBookingBefore, "Invalid payment creates neither booking nor receipt")
        let fullReceipt = Payment(sessionID: paidBooking.id, cents: 9000, date: directNow, method: "Zelle")
        try failedBookingLedger.recordBooking(paidBooking, now: directNow, payment: fullReceipt)
        check(failedBookingLedger.sessionBalance(paidBooking) == 0, "Full payment at booking clears balance")
        var combinedSales = Ledger(); try combinedSales.addClient(client)
        let combinedPackage = Package(clientID: client.id, name: "10 sessions", sessions: 10, minutes: 60, priceCents: 80000, purchased: directNow.addingTimeInterval(-86400 * 7))
        try combinedSales.addPackage(combinedPackage, initialCents: 80000, method: "Cash")
        try combinedSales.recordBooking(Session(packageID: combinedPackage.id, start: directNow.addingTimeInterval(86400), minutes: 60), now: directNow)
        try combinedSales.recordBooking(Session(clientID: client.id, feeCents: 9000, start: directNow.addingTimeInterval(-7200), minutes: 60), now: directNow)
        try combinedSales.recordBooking(Session(clientID: client.id, feeCents: 0, start: directNow.addingTimeInterval(86400 * 2), minutes: 30), now: directNow)
        let combinedTotals = combinedSales.sessionTotals(for: client.id)
        check(combinedTotals.purchased == 11 && combinedTotals.used == 1 && combinedTotals.booked == 1 && combinedTotals.available == 9, "Unified totals combine sales, exclude trials and avoid double counting")
        check(combinedSales.payments.count == 1 && combinedSales.totalBalance == 9000, "Unified overview preserves payments and balances")
        check(bookingPaymentLedger.paymentFollowUps(at: directNow).isEmpty, "Future unpaid booking not yet a payment follow-up")
        let afterPaidBooking = paidBooking.end.addingTimeInterval(1)
        check(bookingPaymentLedger.paymentFollowUps(at: afterPaidBooking).map(\.id) == [paidBooking.id], "Elapsed partially paid booking stays in follow-ups")
        try bookingPaymentLedger.addPayment(Payment(sessionID: paidBooking.id, cents: 6000, date: afterPaidBooking, method: "Cash"))
        check(bookingPaymentLedger.paymentFollowUps(at: afterPaidBooking).isEmpty, "Full receipt removes payment follow-up")
        check(combinedSales.paymentFollowUps(at: directNow).count == 1, "Only elapsed paid-type unpaid sessions enter follow-ups, excluding trials and packages")
        print("PASS: \(assertions) ledger checks")
    }
}
