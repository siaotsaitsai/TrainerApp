import SwiftUI
import UniformTypeIdentifiers

struct FormButtons: ToolbarContent {
    @EnvironmentObject var store: TrainerStore
    @Environment(\.dismiss) var dismiss
    var saveTitle: String? = nil
    let save: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button(store.t("Cancel")) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button(saveTitle ?? store.t("Save"), action: save).bold() }
    }
}
struct ClientForm: View {
    @EnvironmentObject var store: TrainerStore
    @Environment(\.dismiss) var dismiss
    var existing: Client? = nil
    @State private var lifecycleAction = ""
    @State private var confirmLifecycle = false
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var goal = ""
    @State private var notes = ""
    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Client information")) {
                    TextField(store.t("Full name"), text: $name).textContentType(.name)
                    TextField(store.t("Email"), text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField(store.t("Phone"), text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                }
                Section(store.t("Training")) {
                    TextField(store.t("Training goal (optional)"), text: $goal, axis: .vertical)
                    TextField(store.t("Notes"), text: $notes, axis: .vertical).lineLimit(3...8)
                }
                if let client = existing {
                    Section {
                        Button(store.t(client.isArchived ? "Restore client" : "Archive client")) {
                            lifecycleAction = client.isArchived ? "restore" : "archive"; confirmLifecycle = true
                        }
                        if !store.ledger.hasClientPayments(client.id) {
                            Button(store.t("Delete client"), role: .destructive) { lifecycleAction = "delete"; confirmLifecycle = true }
                        }
                    } footer: { Text(store.t("Archiving keeps all records and frees a client slot. Clients with payments can only be archived.")) }
                }
            }.confirmationDialog(store.t(lifecycleAction == "delete" ? "Delete this client permanently?" : lifecycleAction == "restore" ? "Restore client?" : "Archive client?"), isPresented: $confirmLifecycle, titleVisibility: .visible) {
                Button(store.t(lifecycleAction == "delete" ? "Delete client" : lifecycleAction == "restore" ? "Restore client" : "Archive client"), role: lifecycleAction == "delete" ? .destructive : nil) {
                    if let client = existing, store.manageClient(client.id, action: lifecycleAction) { dismiss() }
                }
                Button(store.t("Cancel"), role: .cancel) {}
            } message: {
                Text(store.t(lifecycleAction == "delete" ? "This permanently deletes this client, their packages, sessions, notes and reminders. Calendar copies must be deleted separately." : lifecycleAction == "restore" ? "This client will return to your active list and use one client slot." : "All records will be kept. Cancel or complete upcoming sessions first. You can restore this client later."))
            }.navigationTitle(store.t(existing == nil ? "Add client" : "Edit client")).navigationBarTitleDisplayMode(.inline)
                .modifier(SheetValidation())
                .toolbar { FormButtons {
                    var client = existing ?? Client(name: name)
                    client.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    client.email = email; client.phone = phone; client.goal = goal; client.notes = notes
                    if store.change({ try $0.addClient(client) }) { dismiss() }
                } }
                .onAppear { if let c = existing { name = c.name; email = c.email; phone = c.phone; goal = c.goal; notes = c.notes } }
        }
    }
}
struct PackageForm: View {
    @EnvironmentObject var store: TrainerStore
    @Environment(\.dismiss) var dismiss
    let clientID: UUID
    @State private var name = ""
    @State private var count = "10"
    @State private var minutes = "60"
    @State private var price = ""
    @State private var paid = ""
    @State private var method = "Zelle"
    @State private var purchased = Date()
    @State private var hasExpiry = false
    @State private var expiry = Calendar.current.date(byAdding: .month, value: 3, to: Date())!
    private var automaticName: String {
        let quantity = Int(count) ?? 1
        return store.chinese ? "\(quantity) 节课" : "\(quantity) " + (quantity == 1 ? "session" : "sessions")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Session sale")) {
                    TextField(store.t("Sale name"), text: Binding(get: { name.isEmpty ? automaticName : name }, set: { name = $0 }))
                    LabeledContent(store.t("Number of sessions")) { TextField("10", text: $count).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    LabeledContent(store.t("Minutes per session")) { TextField("60", text: $minutes).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    MoneyInput(title: store.t("Total price (USD)"), text: $price)
                    DatePicker(store.t("Purchased"), selection: $purchased, in: ...Date(), displayedComponents: .date)
                    Toggle(store.t("Set expiration"), isOn: $hasExpiry)
                    if hasExpiry { DatePicker(store.t("Expiry date"), selection: $expiry, in: purchased..., displayedComponents: .date) }
                }
                Section {
                    MoneyInput(title: store.t("Payment received (USD)"), text: $paid)
                    PaymentMethodPicker(method: $method)
                } header: { Text(store.t("Initial payment")) } footer: { Text(store.t("Sell one session or multiple sessions to book later. Leave payment at zero if unpaid, or enter a partial payment. Gifted sessions can have a zero price.")) }
            }.navigationTitle(store.t("Sell sessions")).navigationBarTitleDisplayMode(.inline)
                .modifier(SheetValidation())
                .toolbar { FormButtons {
                    guard let sessions = Int(count), let duration = Int(minutes), let cents = parseCents(price.isEmpty ? "0" : price), let initial = parseCents(paid.isEmpty ? "0" : paid) else {
                        store.error = "Enter valid numbers. Use at most two decimal places for USD."; return
                    }
                    let p = Package(clientID: clientID, name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? automaticName : name, sessions: sessions, minutes: duration, priceCents: cents, purchased: Calendar.current.startOfDay(for: purchased), expires: hasExpiry ? expiry : nil)
                    if store.change({ try $0.addPackage(p, initialCents: initial, method: method) }) { dismiss() }
                } }

        }
    }
}
struct PaymentMethodPicker: View {
    @EnvironmentObject var store: TrainerStore
    @Binding var method: String
    var body: some View { Picker(store.t("Method"), selection: $method) { ForEach(["Cash", "Zelle", "Venmo", "Card", "Other"], id: \.self) { Text(store.t($0)).tag($0) } } }
}
struct PaymentForm: View {
    @EnvironmentObject var store: TrainerStore
    @Environment(\.dismiss) var dismiss
    let clientID: UUID
    var initialSessionID: UUID? = nil
    var prefillBalance = false
    @State private var source = "single"
    @State private var packageID: UUID?
    @State private var sessionID: UUID?
    @State private var amount = ""
    @State private var price = ""
    @State private var minutes = "60"
    @State private var start = Date().addingTimeInterval(3600)
    @State private var method = "Zelle"
    @State private var refund = false
    @State private var date = Date()
    @State private var note = ""
    private var packages: [Package] { store.ledger.packages.filter { $0.clientID == clientID } }
    private var singles: [Session] { store.ledger.sessions.filter { $0.packageID == nil && $0.clientID == clientID && !$0.isTrial }.sorted { $0.start > $1.start } }
    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Payment for")) {
                    Picker(store.t("Payment for"), selection: $source) {
                        Text(store.t("Single session")).tag("single")
                        if !packages.isEmpty { Text(store.t("Package")).tag("package") }
                    }
                    if source == "package" {
                        Picker(store.t("Package"), selection: $packageID) {
                            Text(store.t("Choose package")).tag(UUID?.none)
                            ForEach(packages) { p in Text("\(p.name) · \(store.date(p.purchased))").tag(Optional(p.id)) }
                        }
                    } else {
                        Picker(store.t("Session"), selection: $sessionID) {
                            Text(store.t("New single session")).tag(UUID?.none)
                            ForEach(singles) { s in Text("\(store.date(s.start)) · \(store.time(s.start)) · \(store.money(store.ledger.sessionBalance(s))) \(store.t("due"))").tag(Optional(s.id)) }
                        }
                        if sessionID == nil {
                            DatePicker(store.t("Starts"), selection: $start)
                            LabeledContent(store.t("Duration (minutes)")) { TextField("60", text: $minutes).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                            MoneyInput(title: store.t("Session price (USD)"), text: $price, placeholder: store.t("Same as payment"))
                            Text(store.t("Creates a single-session booking with this payment. No package needed.")).font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }
                if let balance = currentBalance {
                    Section {
                        LabeledContent(store.t("Collected before this entry"), value: store.money(balance.paid))
                        LabeledContent(store.t("Outstanding before this entry"), value: store.money(balance.due))
                    } header: { Label(store.t("Current account summary"), systemImage: "info.circle") }
                    footer: { Text(store.t("Summary only. Enter the new payment or refund below.")) }
                }
                Section {
                    if source == "package" || sessionID != nil { Toggle(store.t("Record a refund"), isOn: $refund) }
                    MoneyInput(title: store.t(refund ? "Refund amount (USD)" : "Amount received this time (USD)"), text: $amount)
                    Text(store.t(refund ? "Enter only the amount returned to the client this time." : "Enter only the money received from the client this time.")).font(.caption).foregroundStyle(Palette.muted)
                    PaymentMethodPicker(method: $method)
                    DatePicker(store.t(refund ? "Refund date" : "Payment date"), selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField(store.t("Notes"), text: $note, axis: .vertical)
                } header: { Text(store.t(refund ? "New refund" : "New payment")) }
                footer: { Text(store.t("Record payments made outside the app. No money is transferred. Refunds do not change session credits.")) }
            }.navigationTitle(store.t(refund ? "Record refund" : "Record payment")).navigationBarTitleDisplayMode(.inline)
                .modifier(SheetValidation())
                .toolbar { FormButtons(saveTitle: store.t(refund ? "Record refund" : "Record payment")) { save() } }
                .onAppear {
                    packageID = packages.first?.id
                    sessionID = initialSessionID ?? singles.first(where: { store.ledger.sessionBalance($0) > 0 })?.id
                    source = initialSessionID != nil || packages.isEmpty ? "single" : "package"
                    if prefillBalance, let balance = currentBalance { amount = String(format: "%.2f", Double(balance.due) / 100) }
                }
                .onChange(of: source) { _, _ in refund = false }
                .onChange(of: sessionID) { _, _ in refund = false }
        }
    }
    private var currentBalance: (paid: Int, due: Int)? {
        if source == "package", let id = packageID {
            return (store.ledger.paid(id), store.ledger.balance(id))
        }
        if source == "single", let s = singles.first(where: { $0.id == sessionID }) {
            return (store.ledger.sessionPaid(s.id), store.ledger.sessionBalance(s))
        }
        return nil
    }
    private func save() {
        guard let cents = parseCents(amount), cents > 0 else { store.error = "Enter a valid amount."; return }
        let saved = store.change { ledger in
            if source == "package" {
                guard let id = packageID else { throw LedgerError(key: "Choose a package or paid single session.") }
                try ledger.addPayment(Payment(packageID: id, cents: refund ? -cents : cents, date: date, method: method, note: note))
            } else {
                let target: UUID
                if let id = sessionID { target = id }
                else {
                    guard let fee = parseCents(price.isEmpty ? amount : price), fee > 0, let duration = Int(minutes) else { throw LedgerError(key: "Choose a client and enter a valid session price.") }
                    let session = Session(clientID: clientID, feeCents: fee, start: start, minutes: duration)
                    try ledger.book(session)
                    target = session.id
                }
                try ledger.addPayment(Payment(sessionID: target, cents: sessionID != nil && refund ? -cents : cents, date: date, method: method, note: note))
            }
        }
        if saved { dismiss() }
    }
}
struct BookingForm: View {
    @EnvironmentObject var store: TrainerStore
    @Environment(\.dismiss) var dismiss
    var clientID: UUID? = nil
    var initialDate: Date = Date()
    var existing: Session? = nil
    @State private var selectedClient: UUID?
    @State private var packageID: UUID?
    @State private var kind = "single"
    @State private var price = ""
    @State private var recordPaymentNow = false
    @State private var paymentAmount = ""
    @State private var paymentMethod = "Zelle"
    @State private var paymentDate = Date()
    @State private var start = Date()
    @State private var minutes = "60"
    @State private var location = ""
    @State private var notes = ""
    @State private var reminder = -2
    private var packages: [Package] { store.ledger.packages.filter { $0.clientID == selectedClient }.sorted { $0.purchased < $1.purchased } }
    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Who & when")) {
                    Picker(store.t("Client"), selection: $selectedClient) {
                        Text(store.t("Choose client")).tag(UUID?.none)
                        ForEach(store.ledger.activeClients.sorted { $0.name < $1.name }) { Text($0.name).tag(Optional($0.id)) }
                    }.disabled(existing != nil)
                    Picker(store.t("Session type"), selection: $kind) {
                        Text(store.t("New single session")).tag("single")
                        Text(store.t("Free trial")).tag("trial")
                        if !packages.isEmpty { Text(store.t("Use purchased session")).tag("package") }
                    }.disabled(existing != nil)
                    if kind == "package" {
                        Picker(store.t("Purchased sessions"), selection: $packageID) {
                            Text(store.t("Choose purchased sessions")).tag(UUID?.none)
                            ForEach(packages) { p in Text("\(p.name) · \(store.date(p.purchased)) · \(store.ledger.available(p.id, excluding: existing?.id)) \(store.t("available"))").tag(Optional(p.id)) }
                        }
                    } else if kind == "single" {
                        MoneyInput(title: store.t("Session price (USD)"), text: $price)
                    } else { LabeledContent(store.t("Session price"), value: store.money(0)) }
                    DatePicker(store.t("Starts"), selection: $start)
                    LabeledContent(store.t("Duration (minutes)")) { TextField("60", text: $minutes).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                }
                if kind == "single" && existing == nil {
                    Section {
                        Toggle(store.t("Record payment now"), isOn: $recordPaymentNow)
                        if recordPaymentNow {
                            MoneyInput(title: store.t("Amount received (USD)"), text: $paymentAmount)
                            PaymentMethodPicker(method: $paymentMethod)
                            DatePicker(store.t("Payment date"), selection: $paymentDate, in: ...Date(), displayedComponents: .date)
                        }
                    } footer: { Text(store.t("Record money already received. Partial payments are welcome; the remainder stays outstanding. No money is charged by the app.")) }
                }
                BookingReminderPicker(value: $reminder)
                Section {
                    TextField(store.t("Location"), text: $location)
                    TextField(store.t("Session notes"), text: $notes, axis: .vertical).lineLimit(3...8)
                } footer: {
                    Text(store.t(kind == "package" ? "Each booking reserves 1 package credit and reduces credits left. After the session ends, booked becomes used without deducting a second credit." : (kind == "trial" ? "Free trials never charge money or deduct package credits." : "No package needed. Record payment now or after the session from the client page.")))
                }
            }.navigationTitle(store.t(existing == nil ? "Book session" : "Edit session")).navigationBarTitleDisplayMode(.inline)
                .modifier(SheetValidation())
                .toolbar { FormButtons { save() } }
                .onAppear {
                    if let s = existing {
                        selectedClient = store.ledger.client(for: s)?.id; packageID = s.packageID
                        kind = s.packageID != nil ? "package" : (s.isTrial ? "trial" : "single")
                        reminder = s.reminderMinutes ?? -2
                        price = String(format: "%.2f", Double(s.feeCents ?? 0) / 100)
                        start = s.start; minutes = String(s.minutes); location = s.location; notes = s.notes
                    } else {
                        selectedClient = clientID ?? store.ledger.activeClients.first?.id
                        selectPackage()
                        start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: initialDate) ?? initialDate
                        if Calendar.current.isDateInToday(initialDate) { start = Date().addingTimeInterval(3600) }
                    }
                }
                .onChange(of: recordPaymentNow) { _, enabled in if enabled && paymentAmount.isEmpty { paymentAmount = price } }
                .onChange(of: price) { old, new in if paymentAmount.isEmpty || paymentAmount == old { paymentAmount = new } }
                .onChange(of: selectedClient) { _, _ in if existing == nil { selectPackage() } }
                .onChange(of: packageID) { _, id in if existing == nil, kind == "package", let id, let p = store.ledger.package(id) { minutes = String(p.minutes) } }
                .onChange(of: kind) { _, _ in if existing == nil, kind == "package", let p = store.ledger.package(packageID) { minutes = String(p.minutes) } }
        }
    }
    private func save() {
        guard let client = selectedClient, let duration = Int(minutes) else { store.error = "Choose a client and valid duration."; return }
        var s = existing ?? Session(start: start, minutes: duration)
        if kind == "package" {
            guard let id = packageID else { store.error = "Choose a package and valid duration."; return }
            s.packageID = id; s.clientID = nil; s.feeCents = nil
        } else {
            guard let fee = kind == "trial" ? 0 : parseCents(price), kind == "trial" || fee > 0 else { store.error = "Enter a price above zero, or choose Free trial."; return }
            s.packageID = nil; s.clientID = client; s.feeCents = fee
        }
        s.start = start; s.minutes = duration; s.location = location; s.notes = notes
        s.reminderMinutes = reminder == -2 ? nil : reminder
        var initialPayment: Payment?
        if kind == "single", existing == nil, recordPaymentNow {
            guard let cents = parseCents(paymentAmount), cents > 0 else { store.error = "Enter a valid amount."; return }
            initialPayment = Payment(sessionID: s.id, cents: cents, date: paymentDate, method: paymentMethod)
        }
        if store.change({ try $0.recordBooking(s, payment: initialPayment) }) { dismiss() }
    }
    private func selectPackage() {
        let candidates = packages.filter { !store.ledger.expired($0) && store.ledger.available($0.id) > 0 }
        packageID = candidates.first?.id
        kind = candidates.isEmpty ? "single" : "package"
        if let p = candidates.first { minutes = String(p.minutes) }
    }
}
struct InlineSessionPayment: View {
    @EnvironmentObject var store: TrainerStore
    let session: Session
    let requiresSessionSave: Bool
    @State private var amount = ""
    @State private var method = "Zelle"
    @State private var date = Date()
    @State private var recorded = false
    private var balance: Int { store.ledger.sessionBalance(session) }
    var body: some View {
        Section {
            MoneyInput(title: store.t("Amount received this time (USD)"), text: $amount)
            PaymentMethodPicker(method: $method)
            DatePicker(store.t("Payment date"), selection: $date, in: ...Date(), displayedComponents: .date)
            if requiresSessionSave { Text(store.t("Save session changes before recording payment.")).font(.caption).foregroundStyle(Palette.muted) }
            Button {
                guard let client = store.ledger.client(for: session), store.canManageClient(client.id) else { store.showSubscription = true; return }
                guard let cents = parseCents(amount), cents > 0 else { store.error = "Enter a valid amount."; return }
                if store.change({ try $0.addPayment(Payment(sessionID: session.id, cents: cents, date: date, method: method)) }) {
                    recorded = true
                    amount = String(format: "%.2f", Double(balance) / 100)
                }
            } label: {
                Label(store.t("Record payment"), systemImage: "checkmark.circle").frame(maxWidth: .infinity)
            }.buttonStyle(PrimaryActionStyle()).disabled(requiresSessionSave)
            if recorded { Label(store.t("Payment recorded"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.ink) }
        } header: { Text(store.t("Record payment")) }
        footer: { Text(store.t("Record payments made outside the app. No money is transferred. Refunds do not change session credits.")) }
        .onAppear { if amount.isEmpty { amount = String(format: "%.2f", Double(balance) / 100) } }
    }
}
struct SessionDetail: View {
    @EnvironmentObject var store: TrainerStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var deletionBlocked = false
    let sessionID: UUID
    @State private var start = Date()
    @State private var minutes = "60"
    @State private var location = ""
    @State private var packageID: UUID?
    @State private var price = ""
    @State private var reminder = -2
    @State private var payment = false
    @State private var calendarDraft: CalendarAppointment?
    @State private var confirmCalendarCopy = false
    @State private var status: SessionStatus = .scheduled
    @State private var charge = false
    @State private var notes = ""
    @State private var saved = false
    @State private var loaded = false
    @FocusState private var notesFocused: Bool
    var body: some View {
        Group {
            if let s = store.ledger.sessions.first(where: { $0.id == sessionID }) {
                Form {
                    Section {
                        HStack { Avatar(name: store.ledger.client(for: s)?.name ?? ""); VStack(alignment: .leading, spacing: 5) { Text(store.ledger.client(for: s)?.name ?? "").font(.headline); Text(store.ledger.package(s.packageID)?.name ?? store.t(s.kindKey)).font(.caption).foregroundStyle(Palette.muted) } }
                        DatePicker(store.t("Date"), selection: $start, displayedComponents: .date)
                        DatePicker(store.t("Time"), selection: $start, displayedComponents: .hourAndMinute)
                        LabeledContent(store.t("Duration (minutes)")) { TextField("60", text: $minutes).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                        TextField(store.t("Location"), text: $location)
                        if let client = store.ledger.client(for: s), s.packageID != nil {
                            Picker(store.t("Package"), selection: $packageID) {
                                ForEach(store.ledger.packages.filter { $0.clientID == client.id }.sorted { $0.purchased < $1.purchased }) { p in
                                    Text(p.name + " · " + store.date(p.purchased)).tag(Optional(p.id))
                                }
                            }
                        }
                        if s.packageID != nil { LabeledContent(store.t("Sessions left"), value: "\(store.ledger.available(s.packageID))") }
                        else {
                            LabeledContent(store.t("Session type"), value: store.t(s.kindKey))
                            if s.isTrial { LabeledContent(store.t("Session price"), value: store.money(0)) }
                            else { MoneyInput(title: store.t("Session price (USD)"), text: $price) }
                            if !s.isTrial {
                                LabeledContent(store.t("Payments received"), value: store.money(store.ledger.sessionPaid(s.id)))
                                LabeledContent(store.t("Outstanding balance"), value: store.money(store.ledger.sessionBalance(s)))
                                if store.ledger.sessionPaid(s.id) > 0 { Button(store.t("Payment history & refunds")) { payment = true } }
                            }
                        }
                    }
                    if s.packageID == nil && !s.isTrial && store.ledger.sessionBalance(s) > 0 {
                        InlineSessionPayment(session: s, requiresSessionSave: hasUnsavedChanges)
                    }
                    BookingReminderPicker(value: $reminder)
                    Section {
                        let appointment = CalendarAppointment(session: s, clientName: store.ledger.client(for: s)?.name ?? store.t("Client"), kind: store.t(s.kindKey))
                        Button {
                            notesFocused = false
                            if let id = store.ledger.client(for: s)?.id, !store.canManageClient(id) { store.showSubscription = true; return }
                            if s.calendarAddedAt != nil { confirmCalendarCopy = true }
                            else { calendarDraft = appointment }
                        } label: {
                            Label(store.t(s.calendarAddedAt == nil ? "Add to calendar" : (s.calendarAddedSignature == appointment.signature ? "Add another calendar copy" : "Add updated calendar copy")), systemImage: "calendar.badge.plus")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.borderless)
                            .disabled(s.status == .clientCancelled || s.status == .trainerCancelled || s.status == .noShow)
                        if let date = s.calendarAddedAt {
                            Label("\(store.t("Last added")) · \(store.date(date))", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.muted)
                        }
                        if s.status == .clientCancelled || s.status == .trainerCancelled || s.status == .noShow {
                            Text(store.t("Cancelled and no-show sessions cannot be added to Calendar.")).font(.caption).foregroundStyle(Palette.muted)
                        }
                    } header: { Text(store.t("Your calendar")) }
                    footer: { Text(store.t("Choose a calendar and confirm in the next screen. Exports the saved session. Calendar copies do not sync with later edits or cancellations.")) }
                    Section {
                        Picker(store.t("Status"), selection: $status) { ForEach(SessionStatus.allCases, id: \.self) { Text(store.t($0.key)).tag($0) } }
                        if !s.isTrial && (status == .clientCancelled || status == .noShow) { Toggle(store.t(s.packageID != nil ? "Deduct 1 session" : "Charge session fee"), isOn: $charge) }
                        if s.packageID != nil { LabeledContent(store.t("Credits used"), value: (status == .completed || ((status == .clientCancelled || status == .noShow) && charge)) ? "1" : "0") }
                        if s.isTrial { Text(store.t("Free trials never charge money or deduct package credits.")).font(.caption).foregroundStyle(Palette.muted) }
                        TextField(store.t("Session notes"), text: $notes, axis: .vertical).lineLimit(3...10).focused($notesFocused)
                    } header: { Text(store.t("Session status & notes")) } footer: { Text(store.t(s.packageID != nil ? "Sessions complete automatically after their end time when the app is open or reopened. You can change the status anytime. Used and booked sessions both reserve package credits. A past session you manually set to Scheduled stays scheduled." : "Sessions complete automatically after their end time when the app is open or reopened. You can change the status anytime. Single sessions never use package credits or automatically record payments. A past session you manually set to Scheduled stays scheduled.")) }
                    Section {
                        Button(role: .destructive) {
                            notesFocused = false
                            if let client = store.ledger.client(for: s), !store.canManageClient(client.id) { store.showSubscription = true; return }
                            if store.ledger.hasSessionPayments(s.id) { deletionBlocked = true }
                            else { confirmDelete = true }
                        } label: { Label(store.t("Delete session"), systemImage: "trash").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                            .buttonStyle(.borderless).foregroundStyle(.red)
                    } footer: { Text(store.t("For bookings created by mistake. Sessions with payment or refund records must be kept. Deleting a package session restores its credit and leaves package payments unchanged.")) }

                }.scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 6) {
                        Button { saveSession() } label: {
                            Label(store.t("Save session update"), systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity, minHeight: 28).contentShape(Rectangle())
                        }.buttonStyle(PrimaryActionStyle())
                        if saved {
                            Label(store.t("Changes saved"), systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium)).foregroundStyle(.green)
                                .accessibilityIdentifier("session-save-confirmation")
                        }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(.regularMaterial)
                    }
                    .onAppear { if !loaded { load(s) } }
                    .onChange(of: s.status) { old, new in
                        if status == old { status = new; charge = s.charged }
                    }
                    .onChange(of: start) { _, _ in if hasUnsavedChanges { saved = false } }
                    .onChange(of: minutes) { _, _ in if hasUnsavedChanges { saved = false } }
                    .onChange(of: location) { _, _ in if hasUnsavedChanges { saved = false } }
                    .onChange(of: packageID) { _, _ in if hasUnsavedChanges { saved = false } }
                    .onChange(of: price) { _, _ in if hasUnsavedChanges { saved = false } }
                    .onChange(of: reminder) { _, _ in if hasUnsavedChanges { saved = false } }
                    .onChange(of: status) { _, _ in if hasUnsavedChanges { saved = false } }
                    .onChange(of: charge) { _, _ in if hasUnsavedChanges { saved = false } }
                    .onChange(of: notes) { _, _ in if hasUnsavedChanges { saved = false } }
                    .sheet(item: $calendarDraft) { appointment in
                        CalendarEditor(appointment: appointment) { added in
                            calendarDraft = nil
                            if added {
                                _ = store.change { ledger in
                                    guard let index = ledger.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                                    ledger.sessions[index].calendarAddedAt = Date()
                                    ledger.sessions[index].calendarAddedSignature = appointment.signature
                                }
                            }
                        }.ignoresSafeArea()
                    }
                    .confirmationDialog(store.t("Add another calendar copy?"), isPresented: $confirmCalendarCopy, titleVisibility: .visible) {
                        Button(store.t("Continue to calendar")) {
                            calendarDraft = CalendarAppointment(session: s, clientName: store.ledger.client(for: s)?.name ?? store.t("Client"), kind: store.t(s.kindKey))
                        }
                        Button(store.t("Cancel"), role: .cancel) {}
                    } message: { Text(store.t("This session was previously added. A new copy will not update or remove the old calendar event.")) }
                    .sheet(isPresented: $payment) { if let id = store.ledger.client(for: s)?.id { PaymentForm(clientID: id, initialSessionID: s.id) } }
            } else { ContentUnavailableView(store.t("Session not found."), systemImage: "calendar.badge.exclamationmark") }
        }.navigationTitle(store.t("Session details")).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(store.t("Delete this session?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(store.t("Delete session"), role: .destructive) {
                    if store.change({ try $0.deleteSession(sessionID) }) { dismiss() }
                }
                Button(store.t("Cancel"), role: .cancel) {}
            } message: {
                Text(store.t("This permanently removes this session and its notes, releases any package credit and removes its reminder. Other sessions in a recurring booking are kept.") + (store.ledger.sessions.first(where: { $0.id == sessionID })?.calendarAddedAt != nil ? "\n\n" + store.t("A copy was added to Calendar. Delete that event separately in your calendar app.") : ""))
            }
            .alert(store.t("Cannot delete this session"), isPresented: $deletionBlocked) {
                Button(store.t("OK"), role: .cancel) {}
            } message: { Text(store.t("This session has payment or refund records. Keep it and use a cancellation status to preserve your financial history.")) }

    }
    private var hasUnsavedChanges: Bool {
        guard let s = store.ledger.sessions.first(where: { $0.id == sessionID }) else { return false }
        return start != s.start || minutes != String(s.minutes) || location != s.location || notes != s.notes || packageID != s.packageID || price != String(format: "%.2f", Double(s.feeCents ?? 0) / 100) || reminder != (s.reminderMinutes ?? -2) || status != s.status || charge != s.charged
    }
    private func load(_ session: Session) {
        loaded = true
        start = session.start; minutes = String(session.minutes); location = session.location
        packageID = session.packageID; price = String(format: "%.2f", Double(session.feeCents ?? 0) / 100)
        reminder = session.reminderMinutes ?? -2
        status = session.status; charge = session.charged; notes = session.notes
    }
    private func saveSession() {
        notesFocused = false
        saved = false
        guard let original = store.ledger.sessions.first(where: { $0.id == sessionID }), let duration = Int(minutes) else { store.error = "Choose a client and valid duration."; return }
        var draft = original
        draft.start = start; draft.minutes = duration; draft.location = location
        draft.notes = notes; draft.status = status; draft.charged = charge
        draft.reminderMinutes = reminder == -2 ? nil : reminder
        if original.packageID != nil {
            guard let packageID else { store.error = "Choose a package and valid duration."; return }
            draft.packageID = packageID
        } else if !original.isTrial {
            guard let fee = parseCents(price), fee > 0 else { store.error = "Enter a price above zero, or choose Free trial."; return }
            draft.feeCents = fee
        }
        if store.change({ try $0.saveSessionEdits(draft, statusWasChanged: status != original.status) }) {
            if let updated = store.ledger.sessions.first(where: { $0.id == sessionID }) { load(updated) }
            saved = true
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: TrainerStore
    @Environment(\.dismiss) var dismiss
    @State private var exporting = false
    @State private var demo = false
    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Preferences")) {
                    Picker(store.t("Language"), selection: $store.language) { Text(store.t("System default")).tag("system"); Text("English").tag("en"); Text("简体中文").tag("zh-Hans") }
                    Toggle(store.t("24-hour time"), isOn: $store.use24Hours)
                    LabeledContent(store.t("Currency"), value: "USD ($)")
                }
                SubscriptionSettings(subscription: store.subscriptions)
                ReminderSettings(service: store.reminders)
                Section {
                    Button { exporting = true } label: { Label(store.t("Export backup (JSON)"), systemImage: "square.and.arrow.up") }
                    if !store.isDemo { Button { demo = true } label: { Label(store.t("Try sample data"), systemImage: "sparkles") } }
                } header: { Text(store.t("Your data")) } footer: { Text(store.t("Saved on this device. No account or cloud sync. Export a backup regularly; deleting the app may remove local data.")) }
                Section(store.t("About")) {
                    LabeledContent("Session Book", value: "1.0")
                    Text(store.t("Built for independent trainers. One place for your clients, sessions and payments.")).font(.subheadline)
                }
            }.navigationTitle(store.t("Settings")).modifier(SheetValidation()).toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("Done")) { dismiss() } } }
                .fileExporter(isPresented: $exporting, document: BackupDocument(data: store.exportData()), contentType: .json, defaultFilename: "SessionBook-\(Date().formatted(.iso8601.year().month().day()))") { result in
                    if case .failure = result { store.error = "Could not export the backup. Please try again." }
                }
                .alert(store.t("Try sample data?"), isPresented: $demo) {
                    Button(store.t("Cancel"), role: .cancel) {}
                    Button(store.t("Load samples")) { store.startDemo() }
                } message: { Text(store.t("Explore fictional clients. Sample changes stay in memory; exit samples to return to your real workspace.")) }
        }
    }
}

struct SheetValidation: ViewModifier {
    @EnvironmentObject var store: TrainerStore
    func body(content: Content) -> some View {
        content
            .onAppear { Task { @MainActor in store.sheetDepth += 1 } }
            .onDisappear { Task { @MainActor in store.sheetDepth = max(0, store.sheetDepth - 1) } }
            .sheet(isPresented: Binding(get: { store.showSubscription && store.sheetDepth > 0 }, set: { store.showSubscription = $0 })) {
                SubscriptionView(subscription: store.subscriptions).environmentObject(store)
            }
            .alert(store.t("Something needs attention"), isPresented: Binding(get: { store.error != nil && store.sheetDepth > 0 }, set: { if !$0 { Task { @MainActor in store.error = nil } } })) {
                Button(store.t("OK")) { store.error = nil }
            } message: { Text(store.t(store.error ?? "")) }
    }
}

/// Gives every amount a full-width tap target instead of a placeholder-sized trailing field.
struct MoneyInput: View {
    @EnvironmentObject var store: TrainerStore
    let title: String
    @Binding var text: String
    var placeholder = "0.00"
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
            HStack(spacing: 12) {
                Text("USD $").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                TextField(placeholder, text: $text)
                    .font(.title3.weight(.medium)).foregroundStyle(Palette.ink)
                    .keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .multilineTextAlignment(.leading).focused($focused)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityLabel(title)
                    .accessibilityHint(store.t("Tap to enter an amount in US dollars."))
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? Palette.ink : Palette.muted.opacity(0.3), lineWidth: focused ? 2 : 1))
        }
        .padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle()).onTapGesture { focused = true }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focused { Spacer(); Button(store.t("Done")) { focused = false } }
            }
        }
    }
}
