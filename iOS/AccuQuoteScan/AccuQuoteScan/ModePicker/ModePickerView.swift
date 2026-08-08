import SwiftUI

// MARK: - ModePickerView (Tri-Mode Scanning build spec §1)
//
// Three-card mode picker replacing the old single "Start Scan" CTA — the
// real entry point that makes Space mode and Full Works reachable without
// going through Dev Tools. AccuQuoteScan has no lock badge on Full Works
// (§4.3: included in all AccuQuoteScan tiers) — that variant is AccuScan-
// only and belongs in AccuScan's own port of this screen.

struct ModePickerView: View {
    var onSelectRoom: () -> Void
    var onSelectSpace: () -> Void
    var onSelectFullWorks: () -> Void

    @State private var selected: ScanMode?

    var body: some View {
        VStack(spacing: 12) {
            ModeCard(
                mode: .room,
                glyph: "cube.transparent",
                title: "Room",
                subtitle: "Scan a full room in under a minute",
                estimatedTime: "30–60 s",
                accuracyLabel: "±2cm",
                accuracyHex: "#22C55E",
                isSelected: selected == .room,
                action: { select(.room, action: onSelectRoom) }
            )
            ModeCard(
                mode: .space,
                glyph: "viewfinder.rectangular",
                title: "Space",
                subtitle: "Measure a detail — under a sink, a window, an alcove",
                estimatedTime: "15–30 s",
                accuracyLabel: "±1cm",
                accuracyHex: "#3B82F6",
                isSelected: selected == .space,
                action: { select(.space, action: onSelectSpace) }
            )
            ModeCard(
                mode: .fullWorks,
                glyph: "building.2",
                title: "Full Works",
                subtitle: "Map an entire property, floor by floor",
                estimatedTime: "10–25 min",
                accuracyLabel: "±2–5cm",
                accuracyHex: "#F59E0B",
                isSelected: selected == .fullWorks,
                action: { select(.fullWorks, action: onSelectFullWorks) }
            )
        }
        .padding(.horizontal, 24)
    }

    private func select(_ mode: ScanMode, action: @escaping () -> Void) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            selected = mode
        }
        // Fix #9 — shortened from 0.15s: still enough to see the selection
        // highlight animate in before the flow transitions away, without
        // adding a noticeable lag to what should be an instant tap-to-go
        // action, especially now that returning users often skip this
        // screen entirely (see ModeLandingView's last-used-mode routing).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            action()
            selected = nil
        }
    }
}

private struct ModeCard: View {
    let mode: ScanMode
    let glyph: String
    let title: String
    let subtitle: String
    let estimatedTime: String
    let accuracyLabel: String
    let accuracyHex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AQ.blue.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: glyph)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(AQ.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AQ.display(20))
                        .foregroundColor(AQ.ink)
                    Text(subtitle)
                        .font(AQ.body(14))
                        .foregroundColor(AQ.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(estimatedTime)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(AQ.secondary)
                    .padding(.top, 2)

                    Text(accuracyLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: accuracyHex))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(hex: accuracyHex).opacity(0.12))
                        .cornerRadius(8)
                        .padding(.top, 2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AQ.secondary.opacity(0.5))
            }
            .padding(20)
            .background(AQ.fill)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? AQ.blue : AQ.rule, lineWidth: isSelected ? 2 : 1)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
