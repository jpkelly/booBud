import SwiftUI

/// Brew timer display — elapsed time + play/stop/reset + Tare all in one row.
struct BrewTimerView: View {
    @Bindable var viewModel: ScaleViewModel

    var body: some View {
        VStack(spacing: 32) {
            // Timer digits
            Text(viewModel.brewTimer.elapsedFormatted)
                .font(.system(size: 80, weight: .thin, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(viewModel.brewTimer.isRunning ? Color.orange : Color.secondary)

            // Controls: Play + Tare centered, Reset off to the side
            HStack(spacing: 24) {
                // Start / Stop
                Button {
                    viewModel.toggleTimer()
                } label: {
                    Image(systemName: viewModel.brewTimer.isRunning ? "stop.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 60, height: 60)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.brewTimer.isRunning ? .red : .orange)

                // Tare
                Button {
                    viewModel.tare()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "scalemass")
                            .font(.title2)
                        Text("Tare")
                            .font(.caption)
                    }
                    .frame(width: 60, height: 60)
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Button {
                    viewModel.resetTimer()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .tint(.secondary)
                .disabled(viewModel.brewTimer.elapsed == 0)
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
}
