import SwiftUI

/// Sheet that shows nearby Bookoo scales for connection.
struct DeviceDiscoveryView: View {
    @Bindable var viewModel: ScaleViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                switch viewModel.connectionState {
                case .scanning:
                    Section("Nearby Scales") {
                        if viewModel.discoveredScales.isEmpty {
                            scanningEmptyView
                        } else {
                            ForEach(viewModel.discoveredScales) { scale in
                                scaleRow(scale)
                            }
                        }
                    }

                case .connected(let name):
                    Section("Connected") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(name)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Disconnect", role: .destructive) {
                                viewModel.disconnect()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                default:
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Scanning…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Select Scale")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.connectionState != .scanning {
                        Button("Scan Again") {
                            viewModel.startScanning()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Subviews

    private var scanningEmptyView: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                    .padding(.bottom, 4)
                Text("Looking for Bookoo scales…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Make sure your scale is on and nearby.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 32)
            Spacer()
        }
    }

    private func scaleRow(_ scale: ScaleViewModel.DiscoveredScale) -> some View {
        Button {
            viewModel.connect(to: scale)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scale.name)
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Signal: \(scale.signalBars)  \(scale.rssi) dBm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
