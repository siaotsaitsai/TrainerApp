import SwiftUI
import EventKit
import EventKitUI

/// iOS presents the system editor; the user chooses a calendar and confirms Add.
/// No access to the user's existing calendars or events is requested.
struct CalendarEditor: UIViewControllerRepresentable {
    let appointment: CalendarAppointment
    let onFinish: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let editor = EKEventEditViewController()
        editor.eventStore = context.coordinator.eventStore
        editor.editViewDelegate = context.coordinator
        let event = EKEvent(eventStore: context.coordinator.eventStore)
        event.title = appointment.title
        event.startDate = appointment.start
        event.endDate = appointment.end
        event.location = appointment.location
        event.notes = appointment.notes
        editor.event = event
        return editor
    }
    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let eventStore = EKEventStore()
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish(action == .saved)
        }
    }
}
