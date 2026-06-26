import SwiftUI

/// Main container view — weight display + controls + device picker.
struct ContentView: View {
    @State private var viewModel = ScaleViewModel()
    @State private var showDevicePicker = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "130E0C"),
                    Color(hex: "241711"),
                    Color(hex: "331E13"),
                    Color(hex: "221610"),
                    Color(hex: "0C0A09")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                Spacer()
                    .frame(height: 40)

                WeightDisplayView(viewModel: viewModel)

                BrewTimerView(viewModel: viewModel)

                WeightGraphView(data: viewModel.weightHistory, displayUnit: viewModel.displayUnit)
                    .frame(height: 200)
                    .padding(.leading, 4)
                    .padding(.trailing, 16)
                    .padding(.top, 80)

                Spacer()
            }
        }
        .sheet(isPresented: $showDevicePicker) {
            DeviceDiscoveryView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.startScanning()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            connectionStatusPill

            Spacer()

            // Scale battery (only shown when scale reports battery data)
            if viewModel.batteryPercent > 0 {
                HStack(spacing: 2) {
                    Image(systemName: viewModel.batteryIcon)
                        .font(.caption)
                    Text("\(viewModel.batteryPercent)%")
                        .font(.caption)
                }
                .foregroundStyle(viewModel.batteryPercent <= 10 ? .red : viewModel.batteryPercent <= 20 ? .yellow : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .offset(x: 4)
        }
    }

    private var connectionStatusPill: some View {
        Button {
            showDevicePicker = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)

                Text(connectionLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .connected:    return .green
        case .connecting:   return .orange
        case .scanning:     return .blue
        case .failed:       return .red
        case .disconnected: return .gray
        }
    }

    private var connectionLabel: String {
        switch viewModel.connectionState {
        case .disconnected:      return "Not Connected"
        case .scanning:          return "Scanning…"
        case .connecting(let n): return "Connecting to \(n)"
        case .connected(let n):  return n
        case .failed(let e):     return e
        }
    }
}
