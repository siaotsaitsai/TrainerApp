import Foundation

struct LedgerPersistence {
    let file: URL
    func load() throws -> Ledger {
        guard FileManager.default.fileExists(atPath: file.path) else { return Ledger() }
        let ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file))
        guard ledger.version == 1 else { throw LedgerError(key: "This backup version is not supported.") }
        return ledger
    }
    func save(_ ledger: Ledger) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ledger)
        if FileManager.default.fileExists(atPath: file.path) {
            let prior = try Data(contentsOf: file)
            try prior.write(to: file.deletingLastPathComponent().appendingPathComponent("ledger.previous.json"), options: .atomic)
        }
        try data.write(to: file, options: .atomic)
    }
}
