import SwiftUI

// MARK: - PDF Share Sheet

// Also relied on by ScanViewer3D.swift's AR Quick Look .fullScreenCover(item:) —
// one conformance per module, so it lives here rather than being redeclared there.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Quote row components

struct QuoteLineItemRow: View {
    let item: QuoteLineItem
    let formatQty: (Double) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuoteRow(
                label: item.description,
                value: "£\(String(format: "%.2f", item.total))",
                bold: false, multiline: false
            )
            HStack(spacing: 8) {
                Text("\(formatQty(item.qty)) \(item.unit) × £\(String(format: "%.2f", item.unitPrice))")
                    .font(.system(size: 12)).foregroundColor(AQ.secondary)
                if !item.sku.isEmpty {
                    Text("·").foregroundColor(AQ.rule)
                    HStack(spacing: 3) {
                        if !item.supplier.isEmpty {
                            Text(item.supplier)
                                .font(.system(size: 11, weight: .medium)).foregroundColor(AQ.blue)
                        }
                        Text("SKU \(item.sku)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(AQ.blue)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(AQ.blue.opacity(0.07)).cornerRadius(5)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        Divider().background(AQ.rule).padding(.leading, 24)
    }
}

struct QuoteSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .foregroundColor(AQ.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 4)
    }
}

struct QuoteRow: View {
    let label: String
    let value: String
    let bold: Bool
    var multiline: Bool = false

    var body: some View {
        HStack(alignment: multiline ? .top : .center) {
            Text(label)
                .font(bold ? .system(size: 15, weight: .semibold) : AQ.body(15))
                .foregroundColor(bold ? AQ.ink : AQ.label)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(bold ? .system(size: 17, weight: .bold) : .system(size: 15, weight: .medium))
                .foregroundColor(bold ? AQ.ink : AQ.label)
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    @ObservedObject var coordinator: ScanCoordinator

    // Fix #11 — same retry-vs-not classification QuoteErrorView already had
    // (Fix #34); this screen previously always showed "Try Again" even for
    // errors a retry could never fix, with no way out for the user.
    private var isRetryable: Bool { ScanErrorClassifier.isRetryable(message) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color(red: 0.98, green: 0.96, blue: 0.94))
                    .frame(width: 80, height: 80)
                Image(systemName: isRetryable ? "exclamationmark" : "lock")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(Color(red: 0.85, green: 0.40, blue: 0.20))
            }
            .padding(.bottom, 28)

            Text(isRetryable ? "Scan Failed" : "Subscription Required")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(AQ.ink)
                .padding(.bottom, 10)
            Text(message)
                .font(AQ.body(15))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 0) {
                Divider().background(AQ.rule).padding(.bottom, 20)
                if isRetryable {
                    Button { coordinator.reset() } label: {
                        Text("Try Again")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(AQ.blue)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
                } else {
                    // Always provide a way out, matching QuoteErrorView's Fix #34.
                    Button { coordinator.reset() } label: {
                        Text("Close")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AQ.secondary)
                    }
                    .padding(.bottom, 44)
                }
            }
        }
        .background(Color.white)
    }
}

// MARK: - Labour Edit Sheet

struct LabourEditSheet: View {
    let current: Double
    let onSave: (Double) -> Void
    let onCancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    // Reject NaN/Inf (which Double(_:) happily parses from "nan"/"inf"), negatives,
    // and absurd values. An unvalidated override here would poison every downstream
    // total (VAT, grand total, Stripe deposit, PDF) with a non-finite or junk number.
    var parsed: Double? {
        guard let v = Double(text.replacingOccurrences(of: "£", with: "")
                                  .replacingOccurrences(of: ",", with: "")),
              v.isFinite, v >= 0, v <= 10_000_000 else { return nil }
        return v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit Labour Total")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AQ.ink)
            Text("Override the calculated labour cost for this quote.")
                .font(.system(size: 14))
                .foregroundColor(AQ.secondary)
            HStack {
                Text("£").font(.system(size: 22, weight: .semibold)).foregroundColor(AQ.secondary)
                TextField("0", text: $text)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AQ.ink)
                    .keyboardType(.decimalPad)
                    .focused($focused)
            }
            .padding(16)
            .background(AQ.fill)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.blue, lineWidth: 1.5))
            HStack(spacing: 10) {
                Button("Cancel") { onCancel() }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AQ.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(AQ.fill).cornerRadius(12)
                Button("Save") {
                    if let v = parsed { onSave(v) }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(parsed != nil ? AQ.blue : AQ.rule).cornerRadius(12)
                .disabled(parsed == nil)
            }
        }
        .padding(28)
        .onAppear {
            text = String(Int(current))
            focused = true
        }
    }
}
