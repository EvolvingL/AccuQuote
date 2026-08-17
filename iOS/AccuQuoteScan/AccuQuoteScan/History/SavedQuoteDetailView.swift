import SwiftUI

// MARK: - Saved Quote Detail View
//
// Previously, tapping a row in "My Quotes" did nothing — QuoteHistoryContent
// only wired up long-press-to-delete (#29's context menu), with no way to
// view the full breakdown or the saved 3D model. This is the missing detail
// screen, reached via a NavigationLink from QuoteHistoryRow.

struct SavedQuoteDetailView: View {
    let quote: SavedQuote

    @State private var arQuickLookURL: URL?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    /// Items grouped by their saved section, in section order; falls back to
    /// a single flat list under "Items" for pre-sectioned old records.
    private var groupedItems: [(label: String, items: [SavedQuoteItem])] {
        guard !quote.sections.isEmpty else {
            return quote.items.isEmpty ? [] : [("Items", quote.items)]
        }
        return quote.sections.map { section in
            let items = quote.items.filter { $0.sectionKey == section.id }
            return (section.label, items.isEmpty ? section.items : items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ── Header ───────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Money.gbp(quote.grandTotal))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundColor(AQ.ink)
                        Spacer()
                        Text("inc. VAT")
                            .font(.caption)
                            .foregroundColor(AQ.secondary)
                    }
                    if !quote.customerName.isEmpty {
                        Text(quote.customerName)
                            .font(.headline)
                            .foregroundColor(AQ.label)
                    }
                    Text(quote.jobDescription)
                        .font(.subheadline)
                        .foregroundColor(AQ.secondary)
                    Text(dateFormatter.string(from: quote.savedAt))
                        .font(.caption)
                        .foregroundColor(AQ.secondary.opacity(0.8))
                }

                // ── Room stats ───────────────────────────────────────────
                HStack(spacing: 8) {
                    if !quote.scanModeDisplayLabel.isEmpty {
                        Text(quote.scanModeDisplayLabel)
                            .font(AQ.caption(11))
                            .foregroundColor(AQ.blue)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(AQ.blue.opacity(0.1))
                            .cornerRadius(5)
                        Text("·").foregroundColor(AQ.rule)
                    }
                    Label(quote.roomType.capitalized, systemImage: "cube.transparent")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AQ.blue)
                    Text("·").foregroundColor(AQ.rule)
                    Text(String(format: "%.1fm²", quote.floorArea))
                        .font(.caption.weight(.medium))
                        .foregroundColor(AQ.secondary)
                }

                // ── 3D model ─────────────────────────────────────────────
                if let scanArtifactURL = quote.scanArtifactURL, let url = URL(string: scanArtifactURL),
                   FileManager.default.fileExists(atPath: url.path) {
                    Button {
                        arQuickLookURL = url
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arkit")
                                .font(.system(size: 16, weight: .medium))
                            Text("View 3D model")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AQ.secondary.opacity(0.5))
                        }
                        .foregroundColor(AQ.ink)
                        .padding(14)
                        .background(AQ.fill)
                        .cornerRadius(12)
                    }
                }

                Divider().background(AQ.rule)

                // ── Sections & items ─────────────────────────────────────
                ForEach(groupedItems, id: \.label) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AQ.secondary)
                            .textCase(.uppercase)

                        ForEach(group.items) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.description)
                                        .font(.system(size: 14))
                                        .foregroundColor(AQ.ink)
                                    Text("\(formatQty(item.qty)) \(item.unit) × \(Money.gbp(item.unitPrice))")
                                        .font(.system(size: 12))
                                        .foregroundColor(AQ.secondary)
                                }
                                Spacer()
                                Text(Money.gbp(item.total))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AQ.ink)
                            }
                        }
                    }
                }

                if !quote.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AQ.secondary)
                            .textCase(.uppercase)
                        Text(quote.notes)
                            .font(.system(size: 14))
                            .foregroundColor(AQ.label)
                    }
                }

                Divider().background(AQ.rule)

                // ── Totals ───────────────────────────────────────────────
                VStack(spacing: 8) {
                    totalRow("Labour", Money.gbp(quote.labourTotal))
                    totalRow("Materials", Money.gbp(quote.subtotal - quote.labourTotal))
                    totalRow("VAT (\(formatQty(quote.vatRate))%)", Money.gbp(quote.vatAmount))
                    Divider().background(AQ.rule)
                    HStack {
                        Text("Total")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AQ.ink)
                        Spacer()
                        Text(Money.gbp(quote.grandTotal))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AQ.ink)
                    }
                }
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("Quote details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $arQuickLookURL) { url in
            ScanARQuickLookView(usdzURL: url)
                .ignoresSafeArea()
        }
    }

    private func totalRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(AQ.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AQ.ink)
        }
    }

    private func formatQty(_ qty: Double) -> String {
        qty == qty.rounded() ? "\(Int(qty))" : String(format: "%.1f", qty)
    }
}
