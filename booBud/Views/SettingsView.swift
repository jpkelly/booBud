import SwiftUI

/// Settings screen — unit selection and any future preferences.
struct SettingsView: View {
    @Bindable var viewModel: ScaleViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight Unit") {
                    Picker("Unit", selection: $viewModel.displayUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.symbol)
                                .tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

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

                Section {
                    HStack {
                        Text("Battery")
                        Spacer()
                        Text("\(viewModel.batteryPercent)%")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionString)
                            .foregroundStyle(.secondary)
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
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
