import SwiftUI
import Charts
import Combine

private struct NotificationSession: Identifiable { let id: UUID }
struct ContentView: View {
    @EnvironmentObject var store: TrainerStore
    @State private var selectedTab = 0
    @State private var notificationSession: NotificationSession?
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(openInsights: { selectedTab = 3 }).tag(0).tabItem { Label(store.t("Today"), systemImage: "square.grid.2x2") }
            ScheduleView().tag(1).tabItem { Label(store.t("Calendar"), systemImage: "calendar") }
            ClientsView().tag(2).tabItem { Label(store.t("Clients"), systemImage: "person.2") }
            InsightsView().tag(3).tabItem { Label(store.t("Insights"), systemImage: "chart.bar.xaxis") }
        }.foregroundStyle(Palette.ink)
            .onReceive(store.openedSessionPublisher) { id in
                if let id { notificationSession = NotificationSession(id: id) }
            }
            .sheet(item: $notificationSession, onDismiss: { store.clearOpenedNotification() }) { selected in
                NavigationStack {
                    SessionDetail(sessionID: selected.id)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Done")) { notificationSession = nil } } }
                }.modifier(SheetValidation())
            }
    }
}
struct DashboardView: View {
    var openInsights: () -> Void = {}
    @EnvironmentObject var store: TrainerStore
    @State private var settings = false
    @State private var booking = false
    @State private var addClient = false
    @State private var paymentSession: Session?
    private var today: [Session] {
        store.ledger.sessions.filter { Calendar.current.isDateInToday($0.start) }.sorted { $0.start < $1.start }
    }
    private var monthPayments: Int {
        let interval = Calendar.current.dateInterval(of: .month, for: Date())!
        return store.ledger.payments.filter { interval.contains($0.date) }.reduce(0) { $0 + $1.cents }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SampleBanner()
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(store.locale)).uppercased())
                                .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(Palette.muted)
                            Text(store.t("Every session. Every dollar.")).font(.system(size: 30, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        Button { settings = true } label: { Image(systemName: "slider.horizontal.3").padding(13).background(.white, in: Circle()) }.accessibilityLabel(store.t("Settings"))
                    }
                    Text(store.t("Stay on schedule. Keep payments in check."))
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Button(action: openInsights) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack { Text(store.t("THIS MONTH")).font(.caption.bold()).tracking(1.5); Spacer(); Image(systemName: "arrow.up.right") }
                        Text(store.money(monthPayments)).font(.system(size: 44, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                        HStack { Text(store.t("Payments received")); Spacer(); Text("USD").font(.caption.bold()) }.font(.subheadline)
                    }.padding(24).foregroundStyle(.white).background(Palette.ink, in: RoundedRectangle(cornerRadius: 26))
                    }.buttonStyle(.plain).accessibilityLabel(store.t("View income insights"))
                    HStack(spacing: 12) {
                        Panel { Metric(title: store.t("Sessions today"), value: "\(today.filter { $0.status == .scheduled || $0.status == .completed }.count)") }
                        Panel { Metric(title: store.t("Active clients"), value: "\(store.ledger.activeClients.filter { c in store.ledger.remainingForClient(c.id) > 0 || store.ledger.sessions.contains { store.ledger.client(for: $0)?.id == c.id && $0.status == .scheduled } }.count)") }
                    }
                    HStack(spacing: 12) {
                        Button { booking = true } label: {
                            Label(store.t("Book session"), systemImage: "calendar.badge.plus")
                                .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                .foregroundStyle(Palette.ink).frame(maxWidth: .infinity, minHeight: 54)
                                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).disabled(store.ledger.activeClients.isEmpty).opacity(store.ledger.activeClients.isEmpty ? 0.45 : 1)
                        Button { if store.canAddClient { addClient = true } else { store.showSubscription = true } } label: {
                            Label(store.t("Add client"), systemImage: "person.badge.plus")
                                .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                .foregroundStyle(Palette.ink).frame(maxWidth: .infinity, minHeight: 54)
                                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.ink.opacity(0.15), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                    paymentFollowUps
                    HStack { Text(store.t("Today's schedule")).font(.title3.bold()); Spacer(); Text("\(today.count)").font(.caption.bold()).padding(7).background(.white, in: Circle()) }
                    if today.isEmpty {
                        Panel {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: "sun.max").font(.title2)
                                Text(store.t(store.ledger.activeClients.isEmpty ? "A fresh start for your business." : "A little breathing room.")).font(.headline)
                                Text(store.t(store.ledger.activeClients.isEmpty ? "Add your first client, then book a paid session, package session or free trial." : "No sessions today. Book your next training session.")).font(.subheadline).foregroundStyle(Palette.muted)
                                if store.ledger.activeClients.isEmpty { Button(store.t("Add your first client")) { if store.canAddClient { addClient = true } else { store.showSubscription = true } }.buttonStyle(PrimaryActionStyle()) }
                            }
                        }
                    }
                    ForEach(today) { session in SessionCard(session: session) }
                    reminders
                }.padding(20).frame(maxWidth: 760)
            }.frame(maxWidth: .infinity).background(Palette.canvas).toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $settings) { SettingsView() }
                .sheet(isPresented: $booking) { BookingForm() }
                .sheet(isPresented: $addClient) { ClientForm() }
                .sheet(item: $paymentSession) { session in
                    if let client = store.ledger.client(for: session) {
                        PaymentForm(clientID: client.id, initialSessionID: session.id, prefillBalance: true)
                    }
                }
        }
    }
    @ViewBuilder private var paymentFollowUps: some View {
        let sessions = store.ledger.paymentFollowUps(at: store.clockDate)
        if !sessions.isEmpty {
            HStack {
                Text(store.t("Payments to record")).font(.title3.bold())
                Spacer()
                Text("\(sessions.count)").font(.caption.bold())
            }
            Text(store.t("Already collected? Record it here to keep your balance up to date.")).font(.subheadline).foregroundStyle(Palette.muted)
            ForEach(sessions) { session in
                Button {
                    if let client = store.ledger.client(for: session), store.canManageClient(client.id) { paymentSession = session }
                    else { store.showSubscription = true }
                } label: {
                    Panel {
                        HStack(spacing: 12) {
                            Image(systemName: "dollarsign.circle").font(.title2).foregroundStyle(Color.orange)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.ledger.client(for: session)?.name ?? store.t("Client")).font(.headline)
                                Text("\(store.date(session.start)) · \(store.time(session.start))").font(.caption).foregroundStyle(Palette.muted)
                                Text(store.t("Record payment")).font(.caption.bold())
                            }
                            Spacer()
                            Text(store.money(store.ledger.sessionBalance(session))).font(.headline)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private var reminders: some View {
        let low = store.ledger.clients.filter { c in store.ledger.packages.contains { $0.clientID == c.id } && store.ledger.remainingForClient(c.id) <= 2 }
        let due = store.ledger.packages.filter { store.ledger.balance($0.id) > 0 }
        let singleDue = store.ledger.sessions.filter { $0.packageID == nil && $0.end > store.clockDate && store.ledger.sessionBalance($0) > 0 }
        let expired = store.ledger.packages.filter { store.ledger.expired($0) && store.ledger.remaining($0.id) > 0 }
        let expiring = store.ledger.packages.filter { p in
            guard let expiry = p.expires else { return false }
            return !store.ledger.expired(p) && expiry < Date().addingTimeInterval(7 * 86400) && store.ledger.available(p.id) > 0
        }
        let pending = store.ledger.sessions.filter { $0.end < Date() && $0.status == .scheduled && !Calendar.current.isDateInToday($0.start) }
        if !low.isEmpty || !due.isEmpty || !singleDue.isEmpty || !pending.isEmpty || !expired.isEmpty || !expiring.isEmpty {
            Text(store.t("Needs a little attention")).font(.title3.bold())
            Panel {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(low) { c in NavigationLink { ClientDetail(clientID: c.id) } label: {
                        Label("\(c.name) · \(store.ledger.remainingForClient(c.id)) \(store.t("sessions left"))", systemImage: "arrow.triangle.2.circlepath").font(.subheadline)
                    } }
                    ForEach(due) { p in NavigationLink { ClientDetail(clientID: p.clientID) } label: {
                        Label("\(store.ledger.client(p.clientID)?.name ?? "") · \(store.money(store.ledger.balance(p.id))) \(store.t("due"))", systemImage: "creditcard").font(.subheadline)
                    } }
                    ForEach(singleDue) { s in NavigationLink { SessionDetail(sessionID: s.id) } label: {
                        Label("\(store.ledger.client(for: s)?.name ?? "") · \(store.money(store.ledger.sessionBalance(s))) \(store.t("due"))", systemImage: "creditcard").font(.subheadline)
                    } }
                    ForEach(expiring + expired) { p in NavigationLink { ClientDetail(clientID: p.clientID) } label: {
                        Label("\(store.ledger.client(p.clientID)?.name ?? "") · \(store.t(store.ledger.expired(p) ? "Expired" : "Expires soon"))", systemImage: "clock.badge.exclamationmark").font(.subheadline)
                    } }
                    ForEach(pending.prefix(5)) { s in NavigationLink { SessionDetail(sessionID: s.id) } label: {
                        Label("\(store.ledger.client(for: s)?.name ?? "") · \(store.date(s.start)) · \(store.t(s.automaticCompletionSuppressed == true ? "Manually kept scheduled" : "Awaiting automatic completion"))", systemImage: "checkmark.circle").font(.subheadline)
                    } }
                }
            }
        }
    }
}
struct SessionCard: View {
    @EnvironmentObject var store: TrainerStore
    let session: Session
    @State private var payment = false
    private var muted: Bool { session.status != .scheduled || session.end <= store.clockDate }
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
            NavigationLink { SessionDetail(sessionID: session.id) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.time(session.start)).font(.subheadline.bold())
                    Text("\(session.minutes) \(store.t("min"))").font(.caption).foregroundStyle(Palette.muted)
                }.frame(width: 82, alignment: .leading)
                Rectangle().fill(muted ? Color.gray.opacity(0.4) : Palette.accent).frame(width: 3, height: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.ledger.client(for: session)?.name ?? store.t("Client")).font(.headline).foregroundStyle(muted ? Palette.muted : Palette.ink)
                    if !session.location.isEmpty { Text(session.location).font(.caption).foregroundStyle(Palette.muted) }
                    if session.isTrial {
                        Text(store.t("Free trial")).font(.caption2.bold()).foregroundStyle(Palette.muted)
                    } else {
                        let remaining = store.ledger.available(session.packageID)
                        Text("\(remaining) \(store.t(remaining == 1 ? "session left" : "sessions left"))").font(.caption2.bold()).foregroundStyle(Palette.muted)
                    }
                    if session.status != .scheduled { Text(store.t(session.status.key)).font(.caption2.bold()).foregroundStyle(session.charged ? Palette.ink : Palette.muted) }
                    else if session.end <= store.clockDate && session.automaticCompletionSuppressed == true { Text(store.t("Manually kept scheduled")).font(.caption2.bold()).foregroundStyle(Palette.muted) }
                }
                Spacer(minLength: 0)
                Image(systemName: session.status == .completed ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(Palette.muted)
            }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if session.packageID == nil && !session.isTrial && session.end <= store.clockDate && store.ledger.sessionBalance(session) > 0 {
                Button {
                    if let client = store.ledger.client(for: session), store.canManageClient(client.id) { payment = true }
                    else { store.showSubscription = true }
                } label: {
                    Label("\(store.t("Payment due")) · \(store.money(store.ledger.sessionBalance(session)))", systemImage: "dollarsign.circle")
                        .font(.caption.bold()).foregroundStyle(Color.orange)
                        .padding(.horizontal, 10).frame(minHeight: 44)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.leading, 99)
                    .accessibilityLabel("\(store.t("Record payment")) · \(store.money(store.ledger.sessionBalance(session)))")
            }
            }
        }.opacity(muted ? 0.88 : 1)
            .sheet(isPresented: $payment) {
                if let client = store.ledger.client(for: session) { PaymentForm(clientID: client.id, initialSessionID: session.id, prefillBalance: true) }
            }
    }
}
struct ScheduleView: View {
    @EnvironmentObject var store: TrainerStore
    @State private var date = Date()
    @State private var booking = false
    @State private var picker = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SampleBanner()
                    Button { picker.toggle() } label: { HStack { Text(date.formatted(.dateTime.month(.wide).year().locale(store.locale))).font(.title2.bold()); Image(systemName: "chevron.down"); Spacer(); Image(systemName: "calendar") } }
                    if picker { DatePicker(store.t("Date"), selection: $date, displayedComponents: .date).datePickerStyle(.graphical).padding().background(.white, in: RoundedRectangle(cornerRadius: 20)) }
                    HStack {
                        Button { date = Calendar.current.date(byAdding: .day, value: -7, to: date)! } label: { Image(systemName: "chevron.left") }.accessibilityLabel(store.t("Previous week"))
                        ForEach(-3...3, id: \.self) { offset in
                            let day = Calendar.current.date(byAdding: .day, value: offset, to: date)!
                            Button { date = day } label: {
                                VStack(spacing: 9) {
                                    Text(day.formatted(.dateTime.weekday(.narrow).locale(store.locale))).font(.caption)
                                    Text(day.formatted(.dateTime.day())).font(.headline)
                                    Circle().fill(store.ledger.sessions.contains { Calendar.current.isDate($0.start, inSameDayAs: day) } ? Palette.ink : .clear).frame(width: 4, height: 4)
                                }.frame(maxWidth: .infinity).padding(.vertical, 12).background(offset == 0 ? Palette.accent : .clear, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                        Button { date = Calendar.current.date(byAdding: .day, value: 7, to: date)! } label: { Image(systemName: "chevron.right") }.accessibilityLabel(store.t("Next week"))
                    }
                    HStack {
                        Text(store.date(date)).font(.headline); Spacer()
                        Button(store.t("Today")) { date = Date() }.font(.caption.bold())
                    }
                    let sessions = store.ledger.sessions.filter { Calendar.current.isDate($0.start, inSameDayAs: date) }.sorted { $0.start < $1.start }
                    if sessions.isEmpty { ContentUnavailableView(store.t("No sessions booked"), systemImage: "calendar", description: Text(store.t("Make room for progress. Add a session to your calendar."))) }
                    ForEach(sessions) { session in SessionCard(session: session) }
                }.padding(20).frame(maxWidth: 760)
            }.frame(maxWidth: .infinity).background(Palette.canvas).navigationTitle(store.t("Calendar"))
                .toolbar { ToolbarItem(placement: .primaryAction) { Button { booking = true } label: { Image(systemName: "plus") }.accessibilityLabel(store.t("Book session")).disabled(store.ledger.activeClients.isEmpty) } }
                .sheet(isPresented: $booking) { BookingForm(initialDate: date) }
        }
    }
}
struct ClientsView: View {
    @EnvironmentObject var store: TrainerStore
    @State private var query = ""
    @State private var showArchived = false
    @State private var add = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    SampleBanner()
                    Picker(store.t("Clients"), selection: $showArchived) { Text(store.t("Active")).tag(false); Text(store.t("Archived")).tag(true) }.pickerStyle(.segmented)
                    if store.ledger.clients.isEmpty { ContentUnavailableView(store.t("Your people, all in one place."), systemImage: "person.2", description: Text(store.t("Add your first client to get started."))) }
                    let found = store.ledger.clients.filter { $0.isArchived == showArchived }.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.email.localizedCaseInsensitiveContains(query) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    if found.isEmpty && !store.ledger.clients.isEmpty {
                        if query.isEmpty { ContentUnavailableView(store.t(showArchived ? "No archived clients" : "No active clients"), systemImage: "person.crop.circle") }
                        else { ContentUnavailableView.search(text: query) }
                    }
                    ForEach(found) { client in NavigationLink { ClientDetail(clientID: client.id) } label: {
                        Panel {
                            HStack(spacing: 14) {
                                Avatar(name: client.name)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(client.name).font(.headline)
                                    if !client.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(client.goal).font(.caption).foregroundStyle(Palette.muted).lineLimit(1) }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) { Text("\(store.ledger.remainingForClient(client.id))").font(.title3.bold()); Text(store.t("sessions left")).font(.caption2).foregroundStyle(Palette.muted) }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                            }
                        }
                    }.buttonStyle(.plain) }
                }.padding(20).frame(maxWidth: 760)
            }.frame(maxWidth: .infinity).background(Palette.canvas).navigationTitle(store.t("Clients"))
                .searchable(text: $query, prompt: store.t("Search clients"))
                .toolbar { ToolbarItem(placement: .primaryAction) { Button { if store.canAddClient { add = true } else { store.showSubscription = true } } label: { Image(systemName: "plus") }.accessibilityLabel(store.t("Add client")) } }
                .sheet(isPresented: $add) { ClientForm() }
        }
    }
}
struct ClientDetail: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: TrainerStore
    let clientID: UUID
    @State private var edit = false
    @State private var sell = false
    @State private var payment = false
    @State private var booking = false
    private var packages: [Package] { store.ledger.packages.filter { $0.clientID == clientID }.sorted { $0.purchased > $1.purchased } }
    private var singleSales: [Session] { store.ledger.sessions.filter { $0.clientID == clientID && $0.packageID == nil && !$0.isTrial }.sorted { $0.start > $1.start } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let c = store.ledger.client(clientID) {
                    if c.isArchived {
                        Panel { Text(store.t("Archived client")).font(.headline) }
                    }
                    if !c.isArchived && !store.canManageClient(clientID) {
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(store.t("Read-only client"), systemImage: "lock")
                                Text(store.t("Upgrade to Pro to manage more than 3 clients. Your records remain available to view and export.")).font(.caption).foregroundStyle(Palette.muted)
                                Button(store.t("Upgrade to Pro")) { store.showSubscription = true }.buttonStyle(PrimaryActionStyle())
                            }
                        }
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack { Avatar(name: c.name); VStack(alignment: .leading, spacing: 5) { Text(c.name).font(.title2.bold()); if !c.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(c.goal).font(.subheadline).foregroundStyle(Palette.muted) } } }
                            if !c.email.isEmpty { Label(c.email, systemImage: "envelope").font(.subheadline).textSelection(.enabled) }
                            if !c.phone.isEmpty { Label(c.phone, systemImage: "phone").font(.subheadline).textSelection(.enabled) }
                            if !c.notes.isEmpty { Divider(); Text(c.notes).font(.subheadline).textSelection(.enabled) }
                        }
                    }
                    Panel {
                        VStack(spacing: 12) {
                            Button { if store.canManageClient(clientID) { booking = true } else { store.showSubscription = true } } label: {
                                Label(store.t("Book session"), systemImage: "calendar.badge.plus")
                                    .frame(maxWidth: .infinity, minHeight: 28)
                            }.buttonStyle(PrimaryActionStyle())
                            HStack(spacing: 12) {
                                Button { if store.canManageClient(clientID) { sell = true } else { store.showSubscription = true } } label: {
                                    secondaryActionLabel("Sell sessions", icon: "plus.rectangle.on.rectangle")
                                }
                                Button { if store.canManageClient(clientID) { payment = true } else { store.showSubscription = true } } label: {
                                    secondaryActionLabel("Record payment", icon: "dollarsign.circle")
                                }
                            }.buttonStyle(.plain)
                        }.disabled(c.isArchived).opacity(c.isArchived ? 0.5 : 1)
                    }
                    Text(store.t("Sessions overview")).font(.title3.bold())
                    let totals = store.ledger.sessionTotals(for: clientID)
                    Panel {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Metric(title: store.t("Sessions available"), value: "\(totals.available)")
                                Metric(title: store.t("Outstanding balance"), value: store.money(store.ledger.balanceForClient(clientID)))
                            }
                            Divider()
                            Text("\(totals.purchased) \(store.t("purchased")) · \(totals.used) \(store.t("used")) · \(totals.booked) \(store.t("booked"))")
                                .font(.body).foregroundStyle(Palette.muted)
                        }
                    }
                    if packages.isEmpty && singleSales.isEmpty { Panel { Text(store.t("No purchased sessions yet. Sell one or more sessions to book later, or book a single session or free trial anytime.")).font(.subheadline).foregroundStyle(Palette.muted) } }
                    if !packages.isEmpty || !singleSales.isEmpty {
                        DisclosureGroup(store.t("Purchase details")) {
                            VStack(spacing: 12) {
                                ForEach(packages) { p in packageCard(p) }
                                ForEach(singleSales) { session in
                                    NavigationLink { SessionDetail(sessionID: session.id) } label: { singleSaleCard(session) }.buttonStyle(.plain)
                                }
                            }.padding(.top, 12)
                        }.font(.subheadline).tint(Palette.ink)
                    }
                    Text(store.t("Session history")).font(.title3.bold())
                    let sessions = store.ledger.sessions.filter { store.ledger.client(for: $0)?.id == clientID }.sorted { $0.start > $1.start }
                    if sessions.isEmpty { Text(store.t("No sessions yet.")).font(.subheadline).foregroundStyle(Palette.muted) }
                    ForEach(sessions) { s in
                        VStack(alignment: .leading, spacing: 7) { Text(store.date(s.start)).font(.caption).foregroundStyle(Palette.muted); SessionCard(session: s) }
                    }
                    HStack { Text(store.t("Payment history")).font(.title3.bold()); Spacer() }
                    let payments = store.ledger.payments.filter { store.ledger.client(for: $0)?.id == clientID }.sorted { $0.date > $1.date }
                    if payments.isEmpty { Text(store.t("No payments yet.")).font(.subheadline).foregroundStyle(Palette.muted) }
                    ForEach(payments) { pay in Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(store.money(pay.cents)).font(.headline); Spacer(); Text(store.t(pay.method)).font(.caption) }
                            Text("\(store.date(pay.date)) · \(store.ledger.package(pay.packageID)?.name ?? store.t("Single session"))").font(.caption).foregroundStyle(Palette.muted)
                            if !pay.note.isEmpty { Text(pay.note).font(.caption) }
                        }
                    } }
                }
            }.padding(20).frame(maxWidth: 760)
        }.frame(maxWidth: .infinity).background(Palette.canvas).navigationTitle(store.t("Client details")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button(store.t("Edit")) { edit = true } } }
            .onChange(of: store.ledger.client(clientID)) { _, client in if client == nil { dismiss() } }
            .sheet(isPresented: $edit) { ClientForm(existing: store.ledger.client(clientID)) }
            .sheet(isPresented: $sell) { PackageForm(clientID: clientID) }
            .sheet(isPresented: $payment) { PaymentForm(clientID: clientID) }
            .sheet(isPresented: $booking) { BookingForm(clientID: clientID) }
    }
    private func secondaryActionLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 19, weight: .medium))
            Text(store.t(title)).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, minHeight: 68)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.ink.opacity(0.16), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
    private func singleSaleCard(_ session: Session) -> some View {
        let used = session.charged ? 1 : 0
        let booked = session.status == .scheduled ? 1 : 0
        let received = store.ledger.sessionPaid(session.id)
        let refundable = max(0, received - store.ledger.sessionPrice(session))
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(store.t("Single session")).font(.headline)
                    Spacer()
                    Text("\(session.minutes) \(store.t("min / session"))").font(.caption).foregroundStyle(Palette.muted)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                }
                HStack {
                    Text("0 / 1").font(.title2.bold())
                    Text(store.t("remaining")).font(.caption).foregroundStyle(Palette.muted)
                    Spacer()
                    Text(store.money(session.feeCents ?? 0)).font(.headline)
                }
                ProgressView(value: Double(used + booked), total: 1).tint(Palette.ink)
                Text("\(used) \(store.t("used")) · \(booked) \(store.t("booked")) · \(store.money(received)) \(store.t("paid"))").font(.caption).foregroundStyle(Palette.muted)
                Text("\(store.date(session.start)) · \(store.time(session.start)) · \(store.t(session.status.key))").font(.caption).foregroundStyle(Palette.muted)
                if refundable > 0 {
                    Text("\(store.t("Available to refund")): \(store.money(refundable))").font(.caption).foregroundStyle(Palette.muted)
                }
            }
        }.opacity(session.status == .scheduled ? 1 : 0.88)
    }
    private func packageCard(_ p: Package) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text(p.name).font(.headline); Spacer(); Text("\(p.minutes) \(store.t("min / session"))").font(.caption).foregroundStyle(Palette.muted) }
                HStack { Text("\(store.ledger.available(p.id)) / \(p.sessions)").font(.title2.bold()); Text(store.t("remaining")).font(.caption).foregroundStyle(Palette.muted); Spacer(); Text(store.money(p.priceCents)).font(.headline) }
                ProgressView(value: Double(store.ledger.used(p.id) + store.ledger.reserved(p.id)), total: Double(p.sessions)).tint(Palette.ink)
                Text("\(store.ledger.used(p.id)) \(store.t("used")) · \(store.ledger.reserved(p.id)) \(store.t("booked")) · \(store.money(store.ledger.paid(p.id))) \(store.t("paid"))").font(.caption).foregroundStyle(Palette.muted)
                if let expiry = p.expires { Text("\(store.t(store.ledger.expired(p) ? "Expired" : "Expires")) \(store.date(expiry))").font(.caption).foregroundStyle(store.ledger.expired(p) ? .red : Palette.muted) }
            }
        }
    }
}
struct InsightsView: View {
    @State private var exportIncome = false
    @EnvironmentObject var store: TrainerStore
    @State private var period = 1
    private var component: Calendar.Component { period == 0 ? .weekOfYear : (period == 1 ? .month : .year) }
    private var interval: DateInterval { Calendar.current.dateInterval(of: component, for: Date())! }
    private var bucketComponent: Calendar.Component { period == 2 ? .month : .day }
    private var bucketCount: Int { period == 0 ? 7 : (period == 2 ? 12 : Calendar.current.range(of: .day, in: .month, for: interval.start)!.count) }
    private var previous: DateInterval {
        let date = Calendar.current.date(byAdding: component, value: -1, to: Date())!
        return Calendar.current.dateInterval(of: component, for: date)!
    }
    private func received(_ range: DateInterval) -> Int { store.ledger.payments.filter { $0.date >= range.start && $0.date < range.end }.reduce(0) { $0 + $1.cents } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SampleBanner()
                    Picker(store.t("Period"), selection: $period) { Text(store.t("This week")).tag(0); Text(store.t("This month")).tag(1); Text(store.t("This year")).tag(2) }.pickerStyle(.segmented)
                    Panel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.t("Payments received")).font(.subheadline).foregroundStyle(Palette.muted)
                            Text(store.money(received(interval))).font(.system(size: 40, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                            Text("\(store.money(received(interval) - received(previous))) \(store.t(period == 2 ? "vs. previous year" : "vs. previous period"))").font(.caption).foregroundStyle(Palette.muted)
                            Chart {
                                ForEach(0..<bucketCount, id: \.self) { offset in
                                    let day = Calendar.current.date(byAdding: bucketComponent, value: offset, to: interval.start)!
                                    let end = Calendar.current.date(byAdding: bucketComponent, value: 1, to: day)!
                                    BarMark(x: .value(store.t("Date"), day, unit: bucketComponent), y: .value(store.t("USD"), Double(received(DateInterval(start: day, end: end))) / 100)).foregroundStyle(Palette.ink).cornerRadius(4)
                                }
                            }.frame(height: 180).chartYAxis { AxisMarks(position: .leading) }.chartXAxis {
                                if period == 2 {
                                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) }
                                } else {
                                    AxisMarks(values: .stride(by: .day, count: period == 0 ? 1 : 7)) { _ in AxisValueLabel(format: .dateTime.day()) }
                                }
                            }.environment(\.locale, store.locale)
                        }
                    }
                    let sessions = store.ledger.sessions.filter { $0.start >= interval.start && $0.start < interval.end }
                    HStack(spacing: 12) {
                        InsightsMetricCard(title: store.t("Session revenue"), value: store.money(sessions.reduce(0) { $0 + store.ledger.earnedCents(for: $1) }), subtitle: store.t("Includes charged cancellations"))
                        InsightsMetricCard(title: store.t("Sessions completed"), value: "\(sessions.filter { $0.status == .completed }.count)", subtitle: store.t("In this period"))
                    }
                    Panel {
                        VStack(spacing: 16) {
                            HStack { Text(store.t("Outstanding balance")); Spacer(); Text(store.money(store.ledger.totalBalance)).bold() }
                            Divider()
                            HStack { Text(store.t("Remaining sessions")); Spacer(); Text("\(store.ledger.packages.reduce(0) { $0 + store.ledger.available($1.id) })").bold() }
                            Text(store.t("All-time balances, including expired packages.")).font(.caption).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.subheadline)
                    }
                    Text(store.t("Payments follow the payment date. Session revenue follows the session date and package price. Refunds reduce payments received; these figures are not profit.")).font(.caption).foregroundStyle(Palette.muted)
                }.padding(20).frame(maxWidth: 760)
            }.frame(maxWidth: .infinity).background(Palette.canvas).navigationTitle(store.t("Insights"))
                .toolbar { ToolbarItem(placement: .primaryAction) { Button { exportIncome = true } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel(store.t("Export income CSV")) } }
                .sheet(isPresented: $exportIncome) { IncomeExportView().environmentObject(store) }
        }
    }
}

private struct InsightsMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.caption).foregroundStyle(Palette.muted)
                    .lineLimit(2, reservesSpace: true)
                Text(value).font(.system(size: 27, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(Palette.muted)
                    .lineLimit(2, reservesSpace: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SampleBanner: View {
    @EnvironmentObject var store: TrainerStore
    var body: some View {
        if store.isDemo {
            HStack { Label(store.t("Sample mode"), systemImage: "sparkles"); Spacer(); Button(store.t("Exit samples")) { store.endDemo() }.bold() }
                .font(.caption).padding(12).background(Palette.accent.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
