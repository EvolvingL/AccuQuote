import SwiftUI

/// One priced line in a quote. Codable with synthesized keys — these property
/// names are persisted verbatim in saved quote history, so renaming any of
/// them would break decoding of quotes saved before the rename.
struct QuoteLineItem: Identifiable, Codable {
    let id: UUID
    let description: String
    let qty: Double
    let unit: String
    let unitPrice: Double
    let sku: String
    let supplier: String
    let sectionKey: String   // which section this item belongs to
    /// "real" (matched a live Awin-sourced product — see
    /// PricingIntegration-TechnicalPlan.md §1) or "estimated" (AI-priced,
    /// the default). Anything else the server/AI might send back (missing,
    /// unrecognised) is also treated as "estimated" — see isRealPrice.
    let priceSource: String
    var total: Double { qty * unitPrice }
    var isRealPrice: Bool { priceSource == "real" }

    init(description: String, qty: Double, unit: String, unitPrice: Double,
         sku: String, supplier: String, sectionKey: String = "", priceSource: String = "estimated") {
        self.id = UUID()
        self.description = description
        self.qty = qty
        self.unit = unit
        self.unitPrice = unitPrice
        self.sku = sku
        self.supplier = supplier
        self.sectionKey = sectionKey
        self.priceSource = priceSource
    }
}

/// In-memory result of quote generation, grouped into sections. Not itself
/// persisted (QuoteHistory stores its own serialized form) — the flat
/// computed properties below exist only so older call sites written against
/// a single flat item list keep working unchanged.
struct GeneratedQuote {
    let sections: [QuoteSection]
    let vatRate: Double
    let customerName: String
    let jobDescription: String

    // Flat computed props — existing call sites continue to work unchanged
    var items: [QuoteLineItem] { sections.flatMap { $0.items } }
    var labourDays: Double { sections.reduce(0) { $0 + $1.labourDays } }
    var labourRate: Double { sections.first(where: { $0.labourDays > 0 })?.labourRate ?? 280 }
    var labourTotal: Double { sections.reduce(0) { $0 + $1.labourTotal } }
    var materialsTotal: Double { sections.reduce(0) { $0 + $1.materialsTotal } }
    var subtotal: Double { labourTotal + materialsTotal }
    var vatAmount: Double { subtotal * (vatRate / 100) }
    var grandTotal: Double { subtotal + vatAmount }
    var notes: String { sections.compactMap { $0.notes.isEmpty ? nil : $0.notes }.joined(separator: "\n") }
}

