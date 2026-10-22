import SwiftUI

@main struct TrainerApp: App {
    @StateObject private var store = TrainerStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .environment(\.locale, store.locale)
                .tint(Palette.ink)
                .preferredColorScheme(.light)
                .task {
                    store.syncReminders()
                    await store.subscriptions.start()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(60)) } catch { break }
                        await store.subscriptions.refreshEntitlements()
                    }
                }
                .task {
                    while !Task.isCancelled {
                        store.refreshElapsedSessions()
                        do { try await Task.sleep(for: .seconds(15)) } catch { break }
                    }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.refreshElapsedSessions(); store.syncReminders(); Task { await store.subscriptions.refreshEntitlements() } } }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in store.syncReminders() }
                .sheet(isPresented: Binding(get: { store.showSubscription && store.sheetDepth == 0 }, set: { store.showSubscription = $0 })) {
                    SubscriptionView(subscription: store.subscriptions).environmentObject(store)
                }
                .alert(store.t("Something needs attention"), isPresented: Binding(get: { store.error != nil && store.sheetDepth == 0 }, set: { if !$0 { Task { @MainActor in store.error = nil } } })) {
                    Button(store.t("OK")) { store.error = nil }
                } message: { Text(store.t(store.error ?? "")) }
        }
    }
}
