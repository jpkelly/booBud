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

                Section {
                    HStack {
                        Text("Battery")
                        Spacer()
                        Text("\(viewModel.batteryPercent)%")
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
        .presentationDetents([.medium])
    }
}
