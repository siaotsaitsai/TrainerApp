import Foundation

/// Free access is deterministic and never deletes customer data after expiry.
enum ClientAccessPolicy {
    static let freeLimit = 3
    static func freeClientIDs(in ledger: Ledger) -> Set<UUID> {
        Set(ledger.activeClients.sorted { $0.created == $1.created ? $0.id.uuidString < $1.id.uuidString : $0.created < $1.created }.prefix(freeLimit).map(\.id))
    }
    static func canApply(before: Ledger, after: Ledger, isPro: Bool) -> Bool {
        if isPro { return true }
        if after.activeClients.count > before.activeClients.count && after.activeClients.count > freeLimit { return false }
        var editable = freeClientIDs(in: before)
        if before.activeClients.count < freeLimit && after.activeClients.count <= freeLimit { editable.formUnion(after.activeClients.map(\.id)) }
        var affected = Set<UUID>()
        for c in changed(before.clients, after.clients) { affected.insert(c.id) }
        for p in changed(before.packages, after.packages) { affected.insert(p.clientID) }
        for s in changed(before.sessions, after.sessions) {
            if let c = before.client(for: s) ?? after.client(for: s) { affected.insert(c.id) }
        }
        for payment in changed(before.payments, after.payments) {
            if let c = before.client(for: payment) ?? after.client(for: payment) { affected.insert(c.id) }
        }
        return affected.isSubset(of: editable)
    }
    private static func changed<T: Identifiable & Equatable>(_ old: [T], _ new: [T]) -> [T] where T.ID: Hashable {
        let oldMap = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newMap = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        return old.filter { newMap[$0.id] != $0 } + new.filter { oldMap[$0.id] != $0 }
    }
}
