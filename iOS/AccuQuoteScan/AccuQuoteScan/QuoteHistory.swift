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
    private nonisolated static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("aq_quote_history.json")
    }

    private static let maxQuotes = 200   // H7: cap history growth
    private var writeTask: Task<Void, Never>?   // H6: serialise persistence

    private init() { load() }

    func save(_ quote: SavedQuote) {
        quotes.insert(quote, at: 0)
        if quotes.count > Self.maxQuotes {
            quotes.removeLast(quotes.count - Self.maxQuotes)
        }
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
        // H6: serialise writes — cancel any pending write and schedule a fresh one
        // from the latest in-memory state, so a slow stale write can't resurrect a
        // deleted quote or drop a just-saved one. Each write captures the current
        // snapshot on the MainActor before handing off to a background encode.
        writeTask?.cancel()
        let snapshot = quotes
        writeTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled,
                  let data = try? JSONEncoder().encode(snapshot) else { return }
            guard !Task.isCancelled else { return }
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}

// MARK: - Quote History View

struct QuoteHistoryView: View {
    @ObservedObject var store: QuoteHistoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""                    // #9 search
    @State private var pendingDeleteID: String? = nil     // #5 delete confirmation
    @State private var showDeleteConfirm = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // #9 filtered list by customer name, job description, or room type
    private var filtered: [SavedQuote] {
        guard !searchText.isEmpty else { return store.quotes }
        return store.quotes.filter {
            $0.customerName.localizedCaseInsensitiveContains(searchText)
            || $0.jobDescription.localizedCaseInsensitiveContains(searchText)
            || $0.roomType.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.quotes.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(AQ.secondary.opacity(0.5))
                            .accessibilityHidden(true)   // #8
                        Text("No quotes yet")
                            .font(.title3.weight(.semibold))   // #1
                            .foregroundColor(AQ.ink)
                        Text("Your generated quotes will appear here.")
                            .font(.subheadline)   // #1
                            .foregroundColor(AQ.secondary)
                        Spacer()
                    }
                } else if filtered.isEmpty {
                    // #9 no-results state
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(AQ.secondary.opacity(0.5))
                            .accessibilityHidden(true)
                        Text("No matches")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(AQ.ink)
                        Text("No quotes match “\(searchText)”.")
                            .font(.subheadline)
                            .foregroundColor(AQ.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(filtered) { quote in
                            QuoteHistoryRow(quote: quote, dateFormatter: dateFormatter)
                                // #29 context menu on long-press
                                .contextMenu {
                                    Button(role: .destructive) {
                                        pendingDeleteID = quote.id
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Delete Quote", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete { offsets in
                            // #5 require confirmation — capture the id first
                            if let i = offsets.first {
                                pendingDeleteID = filtered[i].id
                                showDeleteConfirm = true
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "Search quotes")   // #9
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
            // #5 confirmation dialog
            .confirmationDialog("Delete this quote?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDeleteID { store.delete(id: id) }
                    pendingDeleteID = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteID = nil }
            } message: {
                Text("This quote will be permanently deleted.")
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
                Text(Money.gbp(quote.grandTotal))   // #24 keeps pence when present
                    .font(.title2.weight(.bold))     // #1 (rounded design via modifier below)
                    .fontDesign(.rounded)
                    .foregroundColor(AQ.ink)
                Spacer()
                Text(dateFormatter.string(from: quote.savedAt))
                    .font(.caption)   // #1
                    .foregroundColor(AQ.secondary)
            }

            if !quote.customerName.isEmpty {
                Text(quote.customerName)
                    .font(.footnote.weight(.medium))   // #1
                    .foregroundColor(AQ.label)
                    .lineLimit(1)
            }

            Text(quote.jobDescription)
                .font(.footnote)   // #1
                .foregroundColor(AQ.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Label(quote.roomType.capitalized, systemImage: "cube.transparent")
                    .font(.caption.weight(.medium))   // #1
                    .foregroundColor(AQ.blue)
                Text("·").foregroundColor(AQ.rule)
                Text(String(format: "%.1fm²", quote.floorArea))
                    .font(.caption.weight(.medium))   // #1
                    .foregroundColor(AQ.secondary)
                if !quote.sections.isEmpty {
                    Text("·").foregroundColor(AQ.rule)
                    Text("\(quote.sections.count) sections")
                        .font(.caption.weight(.medium))   // #1
                        .foregroundColor(AQ.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
