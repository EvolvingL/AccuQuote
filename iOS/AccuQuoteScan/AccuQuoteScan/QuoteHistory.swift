import SwiftUI
import Foundation

// MARK: - Saved Quote models

struct SavedQuoteItem: Identifiable, Codable {
    let id: String
    let description: String
    let qty: Double
    let unit: String
    let unitPrice: Double
    let sku: String
    let supplier: String
    var sectionKey: String   // "" for old records — default handled by CodingKeys
    var total: Double { qty * unitPrice }

    // Backwards-compatible decode: sectionKey defaults to ""
    enum CodingKeys: String, CodingKey {
        case id, description, qty, unit, unitPrice, sku, supplier, sectionKey
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self,   forKey: .id)
        description = try c.decode(String.self,   forKey: .description)
        qty         = try c.decode(Double.self,   forKey: .qty)
        unit        = try c.decode(String.self,   forKey: .unit)
        unitPrice   = try c.decode(Double.self,   forKey: .unitPrice)
        sku         = try c.decode(String.self,   forKey: .sku)
        supplier    = try c.decode(String.self,   forKey: .supplier)
        sectionKey  = (try? c.decode(String.self, forKey: .sectionKey)) ?? ""
    }
    init(id: String, description: String, qty: Double, unit: String,
         unitPrice: Double, sku: String, supplier: String, sectionKey: String = "") {
        self.id = id; self.description = description; self.qty = qty
        self.unit = unit; self.unitPrice = unitPrice; self.sku = sku
        self.supplier = supplier; self.sectionKey = sectionKey
    }
}

struct SavedQuoteSection: Identifiable, Codable {
    let id: String          // sectionKey
    let label: String
    let labourDays: Double
    let labourRate: Double
    let notes: String
    let items: [SavedQuoteItem]
    var labourTotal: Double { labourDays * labourRate }
    var materialsTotal: Double { items.reduce(0) { $0 + $1.total } }
    var sectionSubtotal: Double { labourTotal + materialsTotal }
}

struct SavedQuote: Identifiable, Codable {
    let id: String
    let savedAt: Date
    let customerName: String
    let jobDescription: String
    let roomType: String
    let floorArea: Double
    // Flat totals kept for backwards compat + quick display in history list
    let labourDays: Double
    let labourRate: Double
    let labourTotal: Double
    let items: [SavedQuoteItem]
    let subtotal: Double
    let vatRate: Double
    let vatAmount: Double
    let grandTotal: Double
    let notes: String
    // Sectioned breakdown — empty for old records
    var sections: [SavedQuoteSection]

    enum CodingKeys: String, CodingKey {
        case id, savedAt, customerName, jobDescription, roomType, floorArea
        case labourDays, labourRate, labourTotal, items
        case subtotal, vatRate, vatAmount, grandTotal, notes, sections
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(String.self,         forKey: .id)
        savedAt        = try c.decode(Date.self,           forKey: .savedAt)
        customerName   = try c.decode(String.self,         forKey: .customerName)
        jobDescription = try c.decode(String.self,         forKey: .jobDescription)
        roomType       = try c.decode(String.self,         forKey: .roomType)
        floorArea      = try c.decode(Double.self,         forKey: .floorArea)
        labourDays     = try c.decode(Double.self,         forKey: .labourDays)
        labourRate     = try c.decode(Double.self,         forKey: .labourRate)
        labourTotal    = try c.decode(Double.self,         forKey: .labourTotal)
        items          = try c.decode([SavedQuoteItem].self, forKey: .items)
        subtotal       = try c.decode(Double.self,         forKey: .subtotal)
        vatRate        = try c.decode(Double.self,         forKey: .vatRate)
        vatAmount      = try c.decode(Double.self,         forKey: .vatAmount)
        grandTotal     = try c.decode(Double.self,         forKey: .grandTotal)
        notes          = try c.decode(String.self,         forKey: .notes)
        sections       = (try? c.decode([SavedQuoteSection].self, forKey: .sections)) ?? []
    }
    init(id: String, savedAt: Date, customerName: String, jobDescription: String,
         roomType: String, floorArea: Double, labourDays: Double, labourRate: Double,
         labourTotal: Double, items: [SavedQuoteItem], subtotal: Double, vatRate: Double,
         vatAmount: Double, grandTotal: Double, notes: String, sections: [SavedQuoteSection] = []) {
        self.id = id; self.savedAt = savedAt; self.customerName = customerName
        self.jobDescription = jobDescription; self.roomType = roomType
        self.floorArea = floorArea; self.labourDays = labourDays
        self.labourRate = labourRate; self.labourTotal = labourTotal
        self.items = items; self.subtotal = subtotal; self.vatRate = vatRate
        self.vatAmount = vatAmount; self.grandTotal = grandTotal
        self.notes = notes; self.sections = sections
    }
}

// MARK: - Quote History Store (file-backed)

@MainActor
final class QuoteHistoryStore: ObservableObject {
    static let shared = QuoteHistoryStore()

    @Published private(set) var quotes: [SavedQuote] = []

    private static let legacyDefaultsKey = "aq_quote_history"
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("aq_quote_history.json")
    }

    private init() { load() }

    func save(_ quote: SavedQuote) {
        quotes.insert(quote, at: 0)
        persistAsync()
    }

    func delete(id: String) {
        quotes.removeAll { $0.id == id }
        persistAsync()
    }

    // MARK: - I/O

    private func load() {
        let url = Self.fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            // Primary: read from file
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([SavedQuote].self, from: data) {
                quotes = decoded
                return
            }
        }
        // Fallback: migrate from UserDefaults
        if let data = UserDefaults.standard.data(forKey: Self.legacyDefaultsKey),
           let decoded = try? JSONDecoder().decode([SavedQuote].self, from: data) {
            quotes = decoded
            persistAsync()   // write to file immediately
            UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
        }
    }

    private func persistAsync() {
        let snapshot = quotes
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: Self.fileURL, options: .atomic)
        }
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
                if !quote.sections.isEmpty {
                    Text("·").foregroundColor(AQ.rule)
                    Text("\(quote.sections.count) sections")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AQ.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
