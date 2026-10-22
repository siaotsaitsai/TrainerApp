import SwiftUI
import UIKit
import UserNotifications

struct ReminderSettings: View {
    @EnvironmentObject var store: TrainerStore
    @Environment(\.openURL) private var openURL
    @ObservedObject var service: ReminderService
    @State private var updating = false
    var body: some View {
        Section {
            Toggle(store.t("Session reminders"), isOn: Binding(get: { store.remindersEnabled }, set: { enabled in
                updating = true
                Task { await store.setRemindersEnabled(enabled); updating = false }
            })).disabled(updating)
            if updating { ProgressView() }
            if store.remindersEnabled {
                Picker(store.t("Remind me"), selection: $store.reminderMinutes) {
                    ForEach([0, 5, 15, 30, 60, 1440], id: \.self) { Text(store.reminderLabel($0)).tag($0) }
                }
                LabeledContent(store.t("Reminders queued"), value: "\(service.queuedCount)")
            }
            if service.authorization == .denied {
                Text(store.t("Notifications are blocked. Allow notifications in iPhone Settings to receive session reminders.")).font(.caption).foregroundStyle(.secondary)
                Button(store.t("Open iPhone Settings")) { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            }
            if store.remindersEnabled && service.allowed {
                Button { Task { await service.sendTest(chinese: store.chinese) } } label: { Label(store.t("Send test notification"), systemImage: "bell.badge") }
                if service.testSent { Text(store.t("Test notification scheduled. Arrives in 5 seconds.")).font(.caption).foregroundStyle(Palette.muted) }
            }
            if let failure = service.failure {
                Text(store.t(failure)).font(.caption).foregroundStyle(.red)
                Button(store.t("Retry reminders")) { store.syncReminders() }
            }
        } header: { Text(store.t("Before your sessions")) }
        footer: { Text(store.t("Local alerts work when the app is closed. The next 60 reminders refresh when you open the app. If the lead time has passed, the alert arrives at session start. Focus and notification settings may silence alerts.")) }
    }
}
struct BookingReminderPicker: View {
    @EnvironmentObject var store: TrainerStore
    @Binding var value: Int
    var body: some View {
        Section {
            Picker(store.t("Reminder"), selection: $value) {
                Text("\(store.t("Use default")) · \(store.reminderLabel(store.reminderMinutes))").tag(-2)
                Text(store.t("No reminder")).tag(-1)
                ForEach([0, 5, 15, 30, 60, 1440], id: \.self) { Text(store.reminderLabel($0)).tag($0) }
            }
            if !store.remindersEnabled {
                Button(store.t("Enable session reminders")) { Task { await store.setRemindersEnabled(true) } }
            }
        } header: { Text(store.t("Before this session")) }
        footer: { Text(store.t(store.remindersEnabled ? "Changing or cancelling a booking updates its reminder automatically." : "Enable notifications to receive reminders. This preference is saved with your session.")) }
    }
}
extension TrainerStore {
    func reminderLabel(_ minutes: Int) -> String {
        switch minutes {
        case -1: t("No reminder")
        case 0: t("At session start")
        case 60: t("1 hour before")
        case 1440: t("1 day before")
        default: "\(minutes) \(t("minutes before"))"
        }
    }
}
