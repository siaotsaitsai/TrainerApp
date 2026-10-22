import Foundation
import Combine
import UserNotifications

@MainActor final class ReminderService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var queuedCount = 0
    @Published private(set) var failure: String?
    @Published var openedSessionID: UUID?
    @Published var testSent = false
    private let center = UNUserNotificationCenter.current()
    private var syncTask: Task<Void, Never>?
    private var scheduled = Set(UserDefaults.standard.stringArray(forKey: "scheduledReminderIDs") ?? [])
    override init() {
        super.init()
        center.delegate = self
    }
    var allowed: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }
    func requestPermission() async -> Bool {
        do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { failure = "Could not enable notifications. Please try again." }
        await refreshAuthorization()
        return allowed
    }
    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
    }
    /// Serialize changes so an old booking snapshot cannot overwrite a cancellation.
    func synchronize(ledger: Ledger, enabled: Bool, minutes: Int, chinese: Bool, use24Hours: Bool) {
        let previous = syncTask
        syncTask = Task { @MainActor in
            if let previous { await previous.value }
            await reconcile(ledger: ledger, enabled: enabled, minutes: minutes, chinese: chinese, use24Hours: use24Hours)
        }
    }
    private func reconcile(ledger: Ledger, enabled: Bool, minutes: Int, chinese: Bool, use24Hours: Bool) async {
        await refreshAuthorization()
        failure = nil
        let allPending = await center.pendingNotificationRequests()
        let pending = allPending.filter { $0.identifier.hasPrefix("session-reminder.") }
        guard enabled && allowed else {
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
            scheduled.removeAll(); saveScheduled(); queuedCount = 0
            return
        }
        let plans = SessionReminder.plan(ledger: ledger, minutesBefore: minutes)
        let validIDs = Set(plans.map(\.id))
        let obsolete = pending.map(\.identifier).filter { !validIDs.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix("session-reminder.") && !validIDs.contains($0) })
        scheduled.formIntersection(validIDs)
        let existing = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
        for plan in plans {
            // A request that is no longer pending has already fired. Do not alert twice.
            if scheduled.contains(plan.id) && existing[plan.id] == nil { continue }
            guard let session = ledger.sessions.first(where: { $0.id == plan.sessionID }) else { continue }
            let time = DateFormatter(); time.locale = Locale(identifier: chinese ? "zh_Hans_US" : "en_US")
            time.dateFormat = use24Hours ? "HH:mm" : "h:mm a"
            let content = UNMutableNotificationContent()
            content.title = chinese ? "课程提醒" : "Upcoming session"
            let name = ledger.client(for: session)?.name ?? (chinese ? "客户" : "Client")
            content.body = "\(name) · \(time.string(from: session.start)) · \(session.minutes) \(chinese ? "分钟" : "min")"
            if !session.location.isEmpty { content.body += " · \(session.location)" }
            content.sound = .default
            content.userInfo = ["sessionID": session.id.uuidString]
            let trigger: UNNotificationTrigger
            if let oldTrigger = existing[plan.id]?.trigger {
                trigger = oldTrigger
            } else {
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fireDate)
                components.timeZone = .current
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }
            do {
                try await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
                scheduled.insert(plan.id)
            } catch { failure = "Some reminders could not be scheduled. Open Settings to retry." }
        }
        saveScheduled()
        queuedCount = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("session-reminder.") }.count
    }
    private func saveScheduled() { UserDefaults.standard.set(Array(scheduled), forKey: "scheduledReminderIDs") }
    func sendTest(chinese: Bool) async {
        guard allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = chinese ? "Session Book 测试提醒" : "Session Book test reminder"
        content.body = chinese ? "课前提醒已准备就绪。" : "Your session reminders are ready."
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: "trainerapp-reminder-test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
            testSent = true
        } catch { failure = "Could not send the test notification. Please try again." }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let text = response.notification.request.content.userInfo["sessionID"] as? String, let id = UUID(uuidString: text) {
            Task { @MainActor in self.openedSessionID = id }
        }
        completionHandler()
    }
}
