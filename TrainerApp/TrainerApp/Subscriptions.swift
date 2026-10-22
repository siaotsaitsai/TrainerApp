import Foundation
import Combine
import StoreKit
import UIKit

@MainActor final class SubscriptionManager: ObservableObject {
    static let annualID = "com.siaotsaitsai.sessionbook.pro.annual"
    @Published private(set) var isPro = false
    @Published private(set) var isChecking = true
    static let monthlyID = "com.siaotsaitsai.sessionbook.pro.monthly"
    static let productIDs = [annualID, monthlyID]
    @Published var selectedID = annualID
    @Published private(set) var products: [Product] = []
    var product: Product? { products.first { $0.id == selectedID } }
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private var refreshGeneration = 0
    private var updates: Task<Void, Never>?
    func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    if case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID) {
                        await transaction.finish()
                        await self.refreshEntitlements()
                    }
                }
            }
        }
        await refreshEntitlements()
        await loadProduct()
        await refreshEntitlements()
    }
    func loadProduct() async {
        do {
            products = try await Product.products(for: Self.productIDs).filter { p in
                guard p.type == .autoRenewable, let period = p.subscription?.subscriptionPeriod, period.value == 1 else { return false }
                return (p.id == Self.annualID && period.unit == .year) || (p.id == Self.monthlyID && period.unit == .month)
            }
            if products.isEmpty { message = "Subscriptions are not available right now. Please try again later." }
            else { message = nil }
        } catch { message = "Could not load subscriptions. Check your connection and retry." }
    }
    func refreshEntitlements() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        var entitled = false
        // Apple includes subscribed and grace-period subscriptions, excluding revoked/refunded ones.
        // Do not infer access from a cached Boolean or the expiration date alone.
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil, !transaction.isUpgraded {
                entitled = true
            }
        }
        // Reconcile with the subscription-group status when the entitlement sequence
        // has not yet caught up with a successful purchase or plan change.
        if !entitled {
            for product in products {
                guard let info = product.subscription, let statuses = try? await info.status else { continue }
                for status in statuses where status.state == .subscribed || status.state == .inGracePeriod {
                    if case .verified(let transaction) = status.transaction,
                       case .verified = status.renewalInfo,
                       Self.productIDs.contains(transaction.productID),
                       transaction.revocationDate == nil, !transaction.isUpgraded {
                        entitled = true
                    }
                }
            }
        }
        guard generation == refreshGeneration else { return }
        isPro = entitled
        isChecking = false
    }
    func purchase() async {
        guard !busy, let product else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification, Self.productIDs.contains(transaction.productID) else {
                    message = "Apple could not verify this purchase. Please restore purchases or try again."; return
                }
                // Deliver verified access before dismissing the purchase flow, then
                // finish and reconcile with Apple's current subscription status.
                refreshGeneration += 1
                if transaction.revocationDate == nil, !transaction.isUpgraded,
                   let expiry = transaction.expirationDate, expiry > Date() {
                    isPro = true
                    isChecking = false
                }
                await transaction.finish()
                await refreshEntitlements()
                if !isPro { message = "Purchase received. Subscription status is still updating. Please restore purchases in a moment." }
            case .pending: message = "Purchase pending approval. Pro will unlock when Apple confirms payment."
            case .userCancelled: break
            @unknown default: message = "The purchase could not be completed. Please try again."
            }
        } catch { message = "The purchase could not be completed. Please try again." }
    }
    func restore() async {
        guard !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isPro ? "Your Pro subscription is restored." : "No active subscription was found for this Apple Account."
        } catch { message = "Could not restore purchases. Please try again." }
    }
    func manage() async {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        do { try await AppStore.showManageSubscriptions(in: scene); await refreshEntitlements() }
        catch { message = "Could not open subscription settings. Please try again." }
    }
}
