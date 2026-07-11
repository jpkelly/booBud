import SwiftUI

/// Settings screen — unit selection and any future preferences.
struct SettingsView: View {
    @Bindable var viewModel: ScaleViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ViewThatFits(in: .vertical) {
                    compactSettingsContent

                    ScrollView {
                        compactSettingsContent
                            .padding(.bottom, 12)
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
            AboutView(versionString: versionString, expiryString: expiryString, expiryColor: expiryColor)
        }
    }

    // MARK: - Compact layout

    private var compactSettingsContent: some View {
        VStack(spacing: 10) {
            brewAndGraphCard
            flowDetectionCard
            autoStopCard
            pourDetectionCard
            aboutButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var pourDetectionCard: some View {
        settingsCard {
            settingToggle("Auto-detect pour", isOn: $viewModel.autoDetectPour)

            if viewModel.autoDetectPour {
                cardDivider
                sliderSetting(
                    title: "Pour trigger",
                    value: String(format: "%.1f g", viewModel.pourTriggerGrams)
                ) {
                    Slider(value: $viewModel.pourTriggerGrams, in: 0.1...1, step: 0.1) {
                        Text("Grams")
                    }
                }
            }
        }
    }

    private var flowDetectionCard: some View {
        settingsCard {
            settingToggle("Detect flow stop", isOn: $viewModel.flowStopDetectionEnabled)

            if viewModel.flowStopDetectionEnabled {
                cardDivider
                sliderSetting(
                    title: "Stop threshold",
                    value: String(format: "%.1f g/s", viewModel.flowStopThreshold)
                ) {
                    Slider(value: $viewModel.flowStopThreshold, in: 0.1...1.0, step: 0.1) {
                        Text("Threshold")
                    }
                }
            }
        }
    }

    private var brewAndGraphCard: some View {
        settingsCard {
            HStack(spacing: 12) {
                Text("Grind step")
                    .font(.callout)
                Spacer(minLength: 8)
                Picker("Grind step", selection: $viewModel.grindStep) {
                    Text("0.05").tag(0.05)
                    Text("0.1").tag(0.1)
                    Text("0.25").tag(0.25)
                    Text("0.5").tag(0.5)
                    Text("1.0").tag(1.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 220)
            }

            cardDivider
            settingToggle("Flow Auto Range", isOn: $viewModel.flowAutoRange)

            if !viewModel.flowAutoRange {
                cardDivider
                sliderSetting(
                    title: "Flow axis max",
                    value: String(format: "%.1f g/s", viewModel.flowMax)
                ) {
                    Slider(value: $viewModel.flowMax, in: 1...20, step: 0.5) {
                        Text("Flow max")
                    }
                }
            }
        }
    }

    private var autoStopCard: some View {
        settingsCard {
            settingToggle("Auto-stop timer", isOn: $viewModel.autoStopEnabled)

            if viewModel.autoStopEnabled {
                cardDivider
                sliderSetting(
                    title: "Stop after",
                    value: String(format: "%.0f s", viewModel.autoStopSeconds)
                ) {
                    Slider(value: $viewModel.autoStopSeconds, in: 5...120, step: 1) {
                        Text("Seconds")
                    }
                }
            }
        }
    }

    private var aboutButton: some View {
        Button {
            showAbout = true
        } label: {
            settingsCard {
                HStack(alignment: .center, spacing: 12) {
                    Text("About")
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(versionString)
                            .foregroundStyle(Color.warmSecondary)
                        Text(expiryString)
                            .foregroundStyle(expiryColor)
                    }
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.callout)
        }
    }

    private func sliderSetting<SliderView: View>(
        title: String,
        value: String,
        @ViewBuilder slider: () -> SliderView
    ) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer()
                Text(value)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Color.warmSecondary)
            }
            slider()
                .controlSize(.small)
        }
    }

    private var cardDivider: some View {
        Divider()
            .overlay(.secondary.opacity(0.12))
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
    let versionString: String
    let expiryString: String
    let expiryColor: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            Image("SplashImage")
                .resizable()
                .scaledToFit()

            Text("Version \(versionString)  ·  Expires \(expiryString)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.warmSecondary.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(16)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
    }
}
