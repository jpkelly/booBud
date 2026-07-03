import SwiftUI

/// Main container view — weight display + controls + device picker.
struct ContentView: View {
    @State private var viewModel = ScaleViewModel()
    @State private var showDevicePicker = false
    @State private var showSettings = false
    @State private var showBrewHistory = false
    @State private var splashOpacity: Double = 1
    @State private var brewStore = BrewStore()
    @State private var recalledBrew: SavedBrew?

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

                VStack(spacing: 4) {
                    if viewModel.graphOverlayIndicators {
                        // Overlay mode: indicators float over the graph — no layout shift
                        ZStack(alignment: .top) {
                            WeightGraphView(
                                data: graphWeightData,
                                flowData: graphFlowData,
                                displayUnit: recalledBrew?.displayUnit ?? viewModel.displayUnit,
                                flowAutoRange: viewModel.flowAutoRange,
                                flowMax: viewModel.flowMax,
                                underlayWeight: viewModel.underlayBrew?.weightPoints.asWeightTuples ?? [],
                                underlayFlow: viewModel.underlayBrew?.flowPoints.asFlowTuples ?? []
                            )
                                .frame(height: 200)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    showBrewHistory = true
                                }

                            if hasStatusIndicators {
                                statusOverlayContent
                                    .padding(.top, 4)
                            }
                        }
                    } else {
                        // Legacy mode: indicators stack above — graph shifts down
                        if hasStatusIndicators {
                            statusOverlayContent
                        }

                        WeightGraphView(
                            data: graphWeightData,
                            flowData: graphFlowData,
                            displayUnit: recalledBrew?.displayUnit ?? viewModel.displayUnit,
                            flowAutoRange: viewModel.flowAutoRange,
                            flowMax: viewModel.flowMax,
                            underlayWeight: viewModel.underlayBrew?.weightPoints.asWeightTuples ?? [],
                            underlayFlow: viewModel.underlayBrew?.flowPoints.asFlowTuples ?? []
                        )
                            .frame(height: 200)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showBrewHistory = true
                            }
                    }
                }
                .padding(.leading, 4)
                .padding(.trailing, 4)
                .padding(.top, 80)

                Spacer()
            }

            // Splash overlay — matches launch screen, dismisses on connect or after 1s
            if splashOpacity > 0 {
                ZStack {
                    Color.black
                    Image("SplashImage")
                        .resizable()
                        .scaledToFit()
                }
                .ignoresSafeArea()
                .opacity(splashOpacity)
                .allowsHitTesting(splashOpacity > 0.01)
            }
        }
        .sheet(isPresented: $showDevicePicker) {
            DeviceDiscoveryView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showBrewHistory) {
            BrewHistoryView(viewModel: viewModel, store: brewStore) { brew in
                recalledBrew = brew
            }
        }
        .onAppear {
            viewModel.startScanning()
            viewModel.restoreUnderlay(from: brewStore)
            scheduleSplashDismissal()
        }
        .onChange(of: viewModel.connectionState) { _, newState in
            if case .connected = newState {
                dismissSplash()
            }
        }
    }

    // MARK: - Splash

    private func dismissSplash() {
        withAnimation(.easeOut(duration: 0.3)) {
            splashOpacity = 0
        }
    }

    private func scheduleSplashDismissal() {
        // Ensure splash shows for at least 1 second if no connection
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if case .connected = viewModel.connectionState { return }
            dismissSplash()
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
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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

    // MARK: - Graph data (live vs. recall)

    /// Returns recalled brew weight data if viewing a saved brew, otherwise live history.
    private var graphWeightData: [(elapsed: Double, weight: Double)] {
        if let brew = recalledBrew {
            return brew.weightPoints.asWeightTuples
        }
        return viewModel.weightHistory
    }

    /// Returns recalled brew flow data if viewing a saved brew, otherwise live history.
    private var graphFlowData: [(elapsed: Double, flowRate: Double)] {
        if let brew = recalledBrew {
            return brew.flowPoints.asFlowTuples
        }
        return viewModel.flowRateHistory
    }

    // MARK: - Status indicators (recall + underlay, sized to match graph legend)

    /// Whether any status indicator is currently visible.
    private var hasStatusIndicators: Bool {
        recalledBrew != nil || (viewModel.underlayBrew != nil && !viewModel.hideUnderlayChip)
    }

    /// Unified chip row — floats over the graph in overlay mode, stacks above in legacy mode.
    /// Font size 9 matches the graph legend and axis labels.
    @ViewBuilder
    private var statusOverlayContent: some View {
        HStack(spacing: 6) {
            if recalledBrew != nil {
                recallChip
            }
            if let underlay = viewModel.underlayBrew, !viewModel.hideUnderlayChip {
                underlayChip(underlay)
            }
        }
        .padding(.horizontal, 6)
    }

    /// Recall indicator chip — tap to return to live data.
    private var recallChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                recalledBrew = nil
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                Text("Viewing: \(recalledBrew?.name ?? "Saved Brew")")
                    .font(.system(size: 9))
                Text("· Back")
                    .font(.system(size: 9))
                    .underline()
                Image(systemName: "xmark")
                    .font(.system(size: 8))
            }
            .foregroundStyle(.cyan.opacity(0.9))
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    /// Underlay reference chip — tap × to hide chip (ghost lines stay).
    private func underlayChip(_ brew: SavedBrew) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.hideUnderlayChip = true
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "chart.line.flattrend.xyaxis")
                    .font(.system(size: 9))
                Text("Ref: \(brew.name)")
                    .font(.system(size: 9))
                Image(systemName: "xmark")
                    .font(.system(size: 8))
            }
            .foregroundStyle(.gray.opacity(0.85))
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}
