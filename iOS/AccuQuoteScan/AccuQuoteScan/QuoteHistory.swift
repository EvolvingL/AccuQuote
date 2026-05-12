import SwiftUI
import Foundation

// MARK: - Saved Quote model

struct SavedQuoteItem: Identifiable, Codable {
    let id: String
    let description: String
    let qty: Double
    let unit: String
    let unitPrice: Double
    let sku: String
    let supplier: String
    var total: Double { qty * unitPrice }
}

struct SavedQuote: Identifiable, Codable {
    let id: String
    let savedAt: Date
    let customerName: String
    let jobDescription: String
    let roomType: String
    let floorArea: Double
    let labourDays: Double
    let labourRate: Double
    let labourTotal: Double
    let items: [SavedQuoteItem]
    let subtotal: Double
    let vatRate: Double
    let vatAmount: Double
    let grandTotal: Double
    let notes: String
}

// MARK: - Quote History Store

@MainActor
final class QuoteHistoryStore: ObservableObject {
    static let shared = QuoteHistoryStore()

    @Published private(set) var quotes: [SavedQuote] = []

    private static let storeKey = "aq_quote_history"

    private init() { load() }

    func save(_ quote: SavedQuote) {
        quotes.insert(quote, at: 0)
        persist()
    }

    func delete(id: String) {
        quotes.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(quotes) else { return }
        UserDefaults.standard.set(data, forKey: Self.storeKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storeKey),
              let decoded = try? JSONDecoder().decode([SavedQuote].self, from: data)
        else { return }
        quotes = decoded
    }
}

// MARK: - Quote History View

struct QuoteHistoryView: View {
    @ObservedObject var store: QuoteHistoryStore
    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationView {
            Group {
                if store.quotes.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(AQ.secondary.opacity(0.5))
                        Text("No quotes yet")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AQ.ink)
                        Text("Your generated quotes will appear here.")
                            .font(.system(size: 14))
                            .foregroundColor(AQ.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(store.quotes) { quote in
                            QuoteHistoryRow(quote: quote, dateFormatter: dateFormatter)
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                store.delete(id: store.quotes[i].id)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Quote History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AQ.secondary)
                }
            }
        }
    }
}

// MARK: - Quote History Row

private struct QuoteHistoryRow: View {
    let quote: SavedQuote
    let dateFormatter: DateFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("£\(Int(quote.grandTotal).formatted())")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AQ.ink)
                Spacer()
                Text(dateFormatter.string(from: quote.savedAt))
                    .font(.system(size: 12))
                    .foregroundColor(AQ.secondary)
            }

            if !quote.customerName.isEmpty {
                Text(quote.customerName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AQ.label)
                    .lineLimit(1)
            }

            Text(quote.jobDescription)
                .font(.system(size: 13))
                .foregroundColor(AQ.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Label(quote.roomType.capitalized, systemImage: "cube.transparent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AQ.blue)
                Text("·").foregroundColor(AQ.rule)
                Text(String(format: "%.1fm²", quote.floorArea))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AQ.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
