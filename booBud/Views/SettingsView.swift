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
                            Text("s")
                                .foregroundStyle(.secondary)
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
                            Text("g")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $viewModel.pourTriggerGrams, in: 0.1...1, step: 0.1) {
                            Text("Grams")
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
                                .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
                        }
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
