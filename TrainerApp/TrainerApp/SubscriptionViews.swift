import SwiftUI
import StoreKit

struct SubscriptionSettings: View {
    @EnvironmentObject var store: TrainerStore
    @ObservedObject var subscription: SubscriptionManager
    var body: some View {
        Section(store.t("Your plan")) {
            LabeledContent("Session Book", value: subscription.isPro ? "Pro" : store.t("Free"))
            if subscription.isChecking { ProgressView(store.t("Checking subscription…")) }
            Text(store.t(subscription.isPro ? "Unlimited clients with your Pro subscription." : "Manage 3 clients for free. Upgrade to Pro for unlimited clients.")).font(.subheadline).foregroundStyle(Palette.muted)
            Button(store.t(subscription.isPro ? "Manage Pro subscription" : "Upgrade to Pro")) { store.showSubscription = true }
            if !subscription.isPro && store.ledger.activeClients.count > ClientAccessPolicy.freeLimit {
                Text(store.t("Your first 3 clients remain editable. Other clients stay available to view and export.")).font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }
}
struct SubscriptionView: View {
    @EnvironmentObject var store: TrainerStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var subscription: SubscriptionManager
    @State private var privacy = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "person.2.badge.plus").font(.system(size: 36)).padding(20).background(Palette.accent, in: RoundedRectangle(cornerRadius: 22))
                    Text("Session Book Pro").font(.largeTitle.bold())
                    Text(store.t("More clients. Choose the plan that fits.")).font(.title3).foregroundStyle(Palette.muted)
                    Panel {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(store.t("Unlimited clients"), systemImage: "person.2")
                            Label(store.t("Keep all your session and payment tools"), systemImage: "calendar.badge.checkmark")
                            Label(store.t("Your existing data stays with you"), systemImage: "checkmark.shield")
                        }.font(.subheadline)
                    }
                    if !subscription.isPro {
                        Picker(store.t("Billing period"), selection: $subscription.selectedID) {
                            Text(store.t("Yearly")).tag(SubscriptionManager.annualID)
                            Text(store.t("Monthly")).tag(SubscriptionManager.monthlyID)
                        }.pickerStyle(.segmented).disabled(subscription.busy)
                    }
                    if subscription.isPro {
                        Label(store.t("Pro is active"), systemImage: "checkmark.seal.fill").font(.headline)
                        Button(store.t("Manage subscription")) { Task { await subscription.manage() } }.buttonStyle(.bordered)
                    } else if let product = subscription.product {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(product.displayPrice) / \(store.t(subscription.selectedID == SubscriptionManager.annualID ? "year" : "month"))").font(.system(size: 34, weight: .bold, design: .rounded))
                            Text(store.t(subscription.selectedID == SubscriptionManager.annualID ? "Annual subscription · automatically renews" : "Monthly subscription · automatically renews")).font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        Button { Task { await subscription.purchase() } } label: {
                            HStack { if subscription.busy { ProgressView() }; Text(store.t(subscription.selectedID == SubscriptionManager.annualID ? "Subscribe annually" : "Subscribe monthly")).frame(maxWidth: .infinity) }
                        }.buttonStyle(PrimaryActionStyle()).disabled(subscription.busy || subscription.isChecking)
                    } else {
                        Text(store.t("Subscription")).font(.title2.bold())
                        Text(store.t("Price unavailable")).foregroundStyle(Palette.muted)
                        Button(store.t("Retry loading price")) { Task { await subscription.loadProduct() } }.buttonStyle(.bordered)
                    }
                    if let message = subscription.message { Text(store.t(message)).font(.subheadline).foregroundStyle(Palette.muted) }
                    Button(store.t("Restore purchases")) { Task { await subscription.restore() } }.disabled(subscription.busy)
                    Text(store.t("Payment is charged to your Apple Account when you confirm. The subscription renews at the selected interval unless cancelled at least 24 hours before the current period ends. Manage or cancel in your App Store account settings.")).font(.caption).foregroundStyle(Palette.muted)
                    Text(store.t("Free includes 3 editable clients. If Pro expires, your first 3 clients remain editable; all other records can still be viewed and exported.")).font(.caption).foregroundStyle(Palette.muted)
                    HStack {
                        Button(store.t("Privacy policy")) { privacy = true }
                        Spacer()
                        Link(store.t("Terms of use"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }.font(.caption)
                }.padding(24).frame(maxWidth: 700)
            }.frame(maxWidth: .infinity).background(Palette.canvas)
                .navigationTitle(store.t("Your subscription")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Done")) { dismiss() } } }
                .task { await subscription.loadProduct() }
                .onChange(of: subscription.isPro) { _, active in if active { dismiss() } }
                .sheet(isPresented: $privacy) { PrivacyPolicyView() }
        }.tint(Palette.ink)
    }
}
struct PrivacyPolicyView: View {
    @EnvironmentObject var store: TrainerStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Session Book").font(.title.bold())
                    Text(store.t("Client details, notes, sessions and payment records are stored locally on this device. Session Book has no developer-operated account server, advertising or analytics service.")).font(.body)
                    Text(store.t("Apple processes subscription payments. The app uses verified StoreKit subscription information to determine Pro access; it does not receive your payment card details.")).font(.body)
                    Text(store.t("If you choose to export a calendar event or backup, that copy is saved to the location or calendar you select. Notifications are scheduled locally. You control calendar and notification permissions in iPhone Settings.")).font(.body)
                    Text(store.t("You can export your records from Settings. Deleting the app may remove locally stored records. Keep a backup before deleting the app.")).font(.body)
                }.padding(24)
            }.navigationTitle(store.t("Privacy policy")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("Done")) { dismiss() } } }
        }
    }
}
