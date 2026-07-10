import SwiftUI
import OSLog

/// Main container view — weight display + controls + device picker.
struct ContentView: View {
    private static let lifecycleLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.boobud.app",
        category: "lifecycle"
    )

    @Environment(\.scenePhase) private var scenePhase
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
                    WeightGraphView(
                        data: graphWeightData,
                        flowData: graphFlowData,
                        displayUnit: recalledBrew?.displayUnit ?? viewModel.displayUnit,
                        flowAutoRange: viewModel.flowAutoRange,
                        flowMax: viewModel.flowMax,
                        underlayWeight: viewModel.underlayBrew?.weightPoints.asWeightTuples ?? [],
                        underlayFlow: viewModel.underlayBrew?.flowPoints.asFlowTuples ?? [],
                        flowStoppedAt: effectiveFlowStoppedAt,
                        peakWeight: effectivePeakWeight,
                        underlayBeanWeight: viewModel.underlayBrew?.beanWeight,
                        underlayGrindSetting: viewModel.underlayBrew?.grindSetting
                    )
                        .frame(height: 200)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showBrewHistory = true
                        }
                        .overlay(alignment: .top) {
                            if hasStatusIndicators {
                                statusOverlayContent
                                    .offset(y: -28)
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
            updateIdleTimer()
        }
        .onChange(of: viewModel.connectionState) { _, newState in
            if case .connected = newState {
                dismissSplash()
            }
            updateIdleTimer()
        }
        .onChange(of: scenePhase) { _, newPhase in
            updateIdleTimer()

            switch newPhase {
            case .active:
                Self.lifecycleLogger.info("App foregrounded (active)")
            case .background:
                Self.lifecycleLogger.info("App backgrounded")
            case .inactive:
                Self.lifecycleLogger.info("App inactive")
            @unknown default:
                Self.lifecycleLogger.info("App phase changed: unknown")
            }
        }
    }

    // MARK: - Idle Timer

    private func updateIdleTimer() {
        let isConnected: Bool = {
            if case .connected = viewModel.connectionState { return true }
            return false
        }()
        let shouldStayAwake = (scenePhase == .active) && isConnected
        UIApplication.shared.isIdleTimerDisabled = shouldStayAwake
        Self.lifecycleLogger.info("Idle timer disabled: \(shouldStayAwake) (phase=\(String(describing: scenePhase)), connected=\(isConnected))")
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

    /// Flow-stop time to annotate on the graph.
    /// Only applies when weight has exceeded 5g (prevents false triggers at pour start).
    /// - Live pour: from the running detection in the view model
    /// - Recalled brew: stored value if available, otherwise computed post-hoc from flowPoints
    private var effectiveFlowStoppedAt: Double? {
        if let brew = recalledBrew {
            let hasSubstantialWeight = brew.weightPoints.contains { $0.value > 5.0 }
            guard hasSubstantialWeight else { return nil }
            return brew.flowStoppedAt ?? brew.flowPoints.computeFlowStoppedAt(threshold: viewModel.flowStopThreshold)
        }
        let maxWeight = viewModel.weightHistory.map(\.weight).max() ?? 0
        guard maxWeight > 5.0 else { return nil }
        return viewModel.flowStoppedAt
    }

    /// Peak weight to annotate with a horizontal dashed line on the graph.
    /// - Recalled brew: max from the brew's weight points
    /// - Live pour: max from live weight history
    /// Returns nil when there is no data.
    private var effectivePeakWeight: Double? {
        let maxW = graphWeightData.map(\.weight).max() ?? 0
        return maxW > 0 ? maxW : nil
    }

    // MARK: - Status indicators (recall + underlay, sized to match graph legend)

    /// Whether any status indicator is currently visible.
    private var hasStatusIndicators: Bool {
        recalledBrew != nil
            || (viewModel.underlayBrew != nil && !viewModel.hideUnderlayChip)
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
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                if let brew = recalledBrew {
                    Text(brew.date.formatted(.dateTime.month(.abbreviated).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                        .font(.system(size: 9))
                    Text("·")
                        .font(.system(size: 9))
                        .opacity(0.6)
                    HStack(spacing: 3) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 8))
                        Text(String(format: "%.1fg", brew.beanWeight))
                            .font(.system(size: 9))
                    }
                    Text("·")
                        .font(.system(size: 9))
                        .opacity(0.6)
                    HStack(spacing: 3) {
                        Image(systemName: "dial.medium.fill")
                            .font(.system(size: 8))
                            .scaleEffect(1.3)
                        Text(grindString(brew.grindSetting))
                            .font(.system(size: 9))
                    }
                    if !brew.note.isEmpty {
                        Text("·")
                            .font(.system(size: 9))
                            .opacity(0.6)
                        Text(brew.note)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                }
                Image(systemName: "xmark")
                    .font(.system(size: 8))
            }
            .foregroundStyle(Color.warmSecondary)
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
