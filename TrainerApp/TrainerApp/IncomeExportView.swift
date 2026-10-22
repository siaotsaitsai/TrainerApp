import SwiftUI
import UniformTypeIdentifiers

import UIKit

private struct CSVShareFile: Identifiable {
    let id = UUID()
    let url: URL
}
private struct CSVShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
struct IncomeExportView: View {
    @EnvironmentObject var store: TrainerStore
    @Environment(\.dismiss) private var dismiss
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var shareFile: CSVShareFile?
    @State private var temporaryFolder: URL?
    @State private var exportError = false
    private var years: [Int] {
        Array(Set(store.ledger.payments.map { Calendar.current.component(.year, from: $0.date) } + [Calendar.current.component(.year, from: Date())])).sorted(by: >)
    }
    private var payments: [Payment] { IncomeCSV.payments(in: store.ledger, year: year) }
    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Reporting period")) {
                    Picker(store.t("Year"), selection: $year) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }
                    Text(store.t("Includes all payments and refunds in the selected calendar year, based on payment date and your device time zone.")).font(.caption)
                }
                Section(store.t("Export summary")) {
                    LabeledContent(store.t("Transactions"), value: String(payments.count))
                    LabeledContent(store.t("Payments received"), value: store.money(payments.filter { $0.cents > 0 }.reduce(0) { $0 + $1.cents }))
                    LabeledContent(store.t("Refunds"), value: store.money(payments.filter { $0.cents < 0 }.reduce(0) { $0 + $1.cents }))
                    LabeledContent(store.t("Net received"), value: store.money(payments.reduce(0) { $0 + $1.cents }))
                }
                Section {
                    Button {
                        do {
                            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            temporaryFolder = folder
                            let url = folder.appendingPathComponent("SessionBook-Income-\(year).csv")
                            try IncomeCSV.data(ledger: store.ledger, year: year).write(to: url, options: .atomic)
                            shareFile = CSVShareFile(url: url)
                        } catch { exportError = true }
                    } label: { Label(store.t("Export income CSV"), systemImage: "square.and.arrow.up") }.disabled(payments.isEmpty)
                } footer: {
                    Text(store.t("Exports recorded cash receipts in USD, with refunds as negative amounts. Includes client names, payment methods and payment notes. This is not a profit or tax calculation; expenses and other income are not included."))
                }
            }.navigationTitle(store.t("Export income CSV")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Done")) { dismiss() } } }
                .sheet(item: $shareFile, onDismiss: {
                    if let folder = temporaryFolder { try? FileManager.default.removeItem(at: folder) }
                    temporaryFolder = nil
                }) { file in CSVShareSheet(url: file.url) }
                .alert(store.t("Could not export CSV. Please try again."), isPresented: $exportError) { Button(store.t("OK"), role: .cancel) {} }
        }.tint(Palette.ink)
    }
}
