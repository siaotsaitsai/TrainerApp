import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor final class TrainerStore: ObservableObject {
    @Published private(set) var ledger = Ledger()
    @Published private(set) var clockDate = Date()
    @Published var error: String?
    @Published private(set) var isDemo = false
    @Published var sheetDepth = 0
    @Published var language: String { didSet { UserDefaults.standard.set(language, forKey: "language"); syncReminders() } }
    @Published var use24Hours: Bool { didSet { UserDefaults.standard.set(use24Hours, forKey: "use24Hours"); syncReminders() } }
    let reminders = ReminderService()
    let subscriptions = SubscriptionManager()
    @Published var showSubscription = false
    private var subscriptionChanges: AnyCancellable?
    @Published private(set) var remindersEnabled: Bool
    @Published var reminderMinutes: Int { didSet { UserDefaults.standard.set(reminderMinutes, forKey: "reminderMinutes"); syncReminders() } }
    private let file: URL
    private var writable = true
    private var beforeDemo: Ledger?
    var chinese: Bool { language == "zh-Hans" || (language == "system" && Locale.preferredLanguages.first?.hasPrefix("zh") == true) }
    var locale: Locale { Locale(identifier: chinese ? "zh_Hans_US" : "en_US") }
    init() {
        remindersEnabled = UserDefaults.standard.bool(forKey: "remindersEnabled")
        reminderMinutes = UserDefaults.standard.object(forKey: "reminderMinutes") as? Int ?? 30
        language = UserDefaults.standard.string(forKey: "language") ?? "system"
        use24Hours = UserDefaults.standard.bool(forKey: "use24Hours")
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TrainerApp", isDirectory: true)
        file = directory.appendingPathComponent("ledger.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            ledger = try LedgerPersistence(file: file).load()
        } catch {
            writable = false
            self.error = "Unable to open saved data. Your original file is preserved."
        }
        subscriptionChanges = subscriptions.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    func t(_ key: String) -> String {
        guard chinese else { return key }
        guard let path = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    @discardableResult func change(_ operation: (inout Ledger) throws -> Void) -> Bool {
        guard writable else { error = "Unable to open saved data. Your original file is preserved."; return false }
        do {
            var updated = ledger
            try operation(&updated)
            if isDemo { ledger = updated; return true }
            guard ClientAccessPolicy.canApply(before: ledger, after: updated, isPro: subscriptions.isPro) else {
                showSubscription = true
                return false
            }
            try LedgerPersistence(file: file).save(updated)
            ledger = updated
            syncReminders()
            return true
        } catch { self.error = (error as? LedgerError)?.key ?? "Could not save changes. Please try again."; return false }
    }
    @discardableResult func manageClient(_ id: UUID, action: String) -> Bool {
        guard writable else { return false }
        do {
            var updated = ledger
            if action == "archive" { try updated.archiveClient(id) }
            else if action == "delete" { try updated.deleteClient(id) }
            else if action == "restore" {
                guard canAddClient else { showSubscription = true; return false }
                if let index = updated.clients.firstIndex(where: { $0.id == id }) { updated.clients[index].archivedAt = nil }
            } else { return false }
            if !isDemo { try LedgerPersistence(file: file).save(updated) }
            ledger = updated
            syncReminders()
            return true
        } catch { self.error = (error as? LedgerError)?.key ?? "Could not save changes. Please try again."; return false }
    }
    var openedSessionPublisher: AnyPublisher<UUID?, Never> { reminders.$openedSessionID.eraseToAnyPublisher() }
    func clearOpenedNotification() { reminders.openedSessionID = nil }
    var canAddClient: Bool { isDemo || subscriptions.isPro || ledger.activeClients.count < ClientAccessPolicy.freeLimit }
    func canManageClient(_ id: UUID) -> Bool { isDemo || subscriptions.isPro || ClientAccessPolicy.freeClientIDs(in: ledger).contains(id) }
    func startDemo() {
        guard !isDemo else { return }
        beforeDemo = ledger
        isDemo = true; ledger = Ledger.demo()
    }
    func endDemo() {
        guard isDemo, let original = beforeDemo else { return }
        ledger = original; beforeDemo = nil; isDemo = false
    }
    func refreshElapsedSessions(at now: Date = Date()) {
        clockDate = now
        guard writable else { return }
        var updated = ledger
        guard updated.completeElapsedSessions(at: now) > 0 else { return }
        if isDemo { ledger = updated; return }
        do {
            // Time-based completion applies to existing bookings even after Pro expires.
            try LedgerPersistence(file: file).save(updated)
            ledger = updated
            syncReminders()
        } catch { self.error = "Could not save changes. Please try again." }
    }
    func syncReminders() {
        // Sample mode never creates, removes or changes real session reminders.
        guard writable else { return }
        reminders.synchronize(ledger: beforeDemo ?? ledger, enabled: remindersEnabled, minutes: reminderMinutes, chinese: chinese, use24Hours: use24Hours)
    }
    func setRemindersEnabled(_ enabled: Bool) async {
        if enabled {
            guard await reminders.requestPermission() else { return }
        }
        remindersEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "remindersEnabled")
        syncReminders()
    }
    func money(_ cents: Int) -> String { (Double(cents) / 100).formatted(.currency(code: "USD").locale(locale)) }
    func time(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.dateFormat = use24Hours ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
    func date(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day().year().locale(locale)) }
    func exportData() -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(ledger)) ?? Data()
    }
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

enum Palette {
    static let ink = Color(red: 0.08, green: 0.16, blue: 0.18)
    static let accent = Color(red: 0.77, green: 0.93, blue: 0.37)
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.95)
    static let muted = Color(red: 0.39, green: 0.46, blue: 0.44)
}
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 22)) }
}
struct Metric: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 27, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
            if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(Palette.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct Avatar: View {
    let name: String
    var body: some View {
        Text(name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()).font(.subheadline.bold())
            .frame(width: 44, height: 44).background(Palette.accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(enabled ? Palette.ink : Palette.muted)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(enabled ? Palette.accent : Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
