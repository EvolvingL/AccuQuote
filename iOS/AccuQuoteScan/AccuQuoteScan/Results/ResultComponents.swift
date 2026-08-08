import SwiftUI

// MARK: - Result sub-components

struct DimensionCell: View {
    let label: String; let value: String; let unit: String
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AQ.secondary)
                .kerning(0.5)
                .textCase(.uppercase)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(AQ.ink)
                Text(unit)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AQ.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

struct StatCell: View {
    let label: String; let value: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AQ.ink)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(AQ.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

