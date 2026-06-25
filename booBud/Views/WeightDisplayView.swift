import SwiftUI

/// Large weight display with unit label.
struct WeightDisplayView: View {
    @Bindable var viewModel: ScaleViewModel

    var body: some View {
        VStack(spacing: 4) {
            (Text(viewModel.displayWeight)
                .font(.system(size: 80, weight: .thin, design: .default))
                .monospacedDigit()
            + Text(" \(viewModel.weightUnitSymbol)")
                .font(.system(size: 36, weight: .medium, design: .default))
                .foregroundStyle(.secondary)
                .baselineOffset(20)
            )
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity, alignment: .center)

            // Stability indicator
            if let reading = viewModel.currentReading {
                HStack(spacing: 6) {
                    Circle()
                        .fill(reading.isStable ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(reading.isStable ? "Stable" : "Measuring")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top)
        .frame(maxWidth: .infinity)
    }
}
