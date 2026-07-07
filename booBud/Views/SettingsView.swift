import SwiftUI

/// Settings screen — unit selection and any future preferences.
struct SettingsView: View {
    @Bindable var viewModel: ScaleViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Auto-Stop Timer") {
                    Toggle("Auto-stop", isOn: $viewModel.autoStopEnabled)
                    if viewModel.autoStopEnabled {
                        HStack {
                            Text("Stop after")
                            Spacer()
                            TextField("", value: $viewModel.autoStopSeconds, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .foregroundStyle(Color.warmSecondary)
                            Text("s")
                                .foregroundStyle(Color.warmSecondary)
                        }
                        Slider(value: $viewModel.autoStopSeconds, in: 5...120, step: 1) {
                            Text("Seconds")
                        }
                    }
                }

                Section("Pour Detection") {
                    Toggle("Auto-detect pour", isOn: $viewModel.autoDetectPour)
                    if viewModel.autoDetectPour {
                        HStack {
                            Text("Trigger at")
                            Spacer()
                            TextField("", value: $viewModel.pourTriggerGrams, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .foregroundStyle(Color.warmSecondary)
                            Text("g")
                                .foregroundStyle(Color.warmSecondary)
                        }
                        Slider(value: $viewModel.pourTriggerGrams, in: 0.1...1, step: 0.1) {
                            Text("Grams")
                        }
                    }
                }

                Section("Flow Detection") {
                    Toggle("Detect flow stop", isOn: $viewModel.flowStopDetectionEnabled)
                    if viewModel.flowStopDetectionEnabled {
                        HStack {
                            Text("Stop threshold")
                            Spacer()
                            Text(String(format: "%.1f g/s", viewModel.flowStopThreshold))
                                .foregroundStyle(Color.warmSecondary)
                        }
                        Slider(value: $viewModel.flowStopThreshold, in: 0.1...1.0, step: 0.1) {
                            Text("Threshold")
                        }
                    }
                }

                Section("Graph") {
                    Toggle("Flow Auto Range", isOn: $viewModel.flowAutoRange)
                    if !viewModel.flowAutoRange {
                        HStack {
                            Text("Flow axis max")
                            Spacer()
                            Text(String(format: "%.1f g/s", viewModel.flowMax))
                                .foregroundStyle(Color.warmSecondary)
                        }
                        Slider(value: $viewModel.flowMax, in: 1...20, step: 0.5) {
                            Text("Flow max")
                        }
                    }
                    Toggle("Overlay status on graph", isOn: $viewModel.graphOverlayIndicators)
                }

                Section {
                    Button {
                        showAbout = true
                    } label: {
                        HStack {
                            Text("Version")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(versionString)
                                .foregroundStyle(Color.warmSecondary)
                        }
                    }

                    HStack {
                        Text("App expires")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(expiryString)
                            .foregroundStyle(expiryColor)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .fullScreenCover(isPresented: $showAbout) {
            AboutView()
        }
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// Reads ExpirationDate from the embedded provisioning profile.
    private var provisioningExpiry: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        // The profile is a CMS-signed blob. The plist payload is embedded as raw bytes
        // between the XML header and </plist> — extract it by scanning for the markers.
        let marker = Data("<?xml".utf8)
        let closer = Data("</plist>".utf8)
        guard let startRange = data.range(of: marker),
              let endRange = data.range(of: closer, in: startRange.lowerBound..<data.endIndex) else { return nil }
        let plistData = data[startRange.lowerBound ..< endRange.upperBound]
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let date = plist["ExpirationDate"] as? Date else { return nil }
        return date
    }

    private var expiryString: String {
        guard let expiry = provisioningExpiry else { return "Unknown" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        if days <= 0 { return "Expired" }
        if days == 1 { return "Tomorrow" }
        return "\(days) days"
    }

    private var expiryColor: Color {
        guard let expiry = provisioningExpiry else { return Color.warmSecondary }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        if days <= 0 { return .red }
        if days <= 7 { return .orange }
        return Color.warmSecondary
    }
}

// MARK: - About View

/// Full-screen splash-style about screen. Tap anywhere to dismiss.
private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
            Image("SplashImage")
                .resizable()
                .scaledToFit()
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
    }
}
