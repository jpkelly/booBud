import SwiftUI

/// Bottom control bar — Tare button only.
struct ControlBarView: View {
    @Bindable var viewModel: ScaleViewModel

    var body: some View {
        HStack(spacing: 32) {
            ControlButton(
                icon: "scalemass",
                label: "Tare",
                action: { viewModel.tare() }
            )
        }
    }
}

// MARK: - Control Button

private struct ControlButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .frame(width: 72, height: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(.secondary)
    }
}
