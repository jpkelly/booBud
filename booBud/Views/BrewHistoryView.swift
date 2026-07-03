import SwiftUI

/// Sheet for saving the current brew or recalling a past one.
/// - "Save Current Brew": shown only when there is recorded data.
/// - "Saved Brews": list of past brews with stats, tap to recall, swipe to delete.
struct BrewHistoryView: View {
    @Bindable var viewModel: ScaleViewModel
    @Bindable var store: BrewStore
    var onRecall: (SavedBrew) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var brewName: String = ""
    @State private var brewNote: String = ""
    @State private var hasSaved: Bool = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Save section
                if viewModel.canSaveBrew, !hasSaved {
                    saveSection
                } else if hasSaved {
                    savedConfirmation
                }

                // MARK: - Saved brews
                if store.brews.isEmpty {
                    emptyState
                } else {
                    Section("Saved Brews") {
                        ForEach(store.brews) { brew in
                            brewRow(brew)
                        }
                        .onDelete(perform: deleteBrews)
                    }
                }
            }
            .navigationTitle("Brews")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                let df = DateFormatter()
                df.dateFormat = "MMM d, h:mm a"
                brewName = "Brew \(df.string(from: Date()))"
            }
        }
    }

    // MARK: - Save section

    private var saveSection: some View {
        Section("Save Current Brew") {
            VStack(alignment: .leading, spacing: 8) {
                // Quick stats preview
                statsPreview
            }
            .padding(.vertical, 4)

            TextField("Name", text: $brewName)
                .font(.body)

            HStack {
                TextField("Note (optional)", text: $brewNote, axis: .vertical)
                    .font(.callout)
                    .lineLimit(1...3)

                Spacer(minLength: 12)

                Button {
                    saveBrew()
                } label: {
                    Text("Save")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .disabled(brewName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(brewName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
            }
        }
    }

    private var savedConfirmation: some View {
        Section {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Brew saved!")
                    .fontWeight(.medium)
                Spacer()
                Button("Save Another") {
                    hasSaved = false
                    brewNote = ""
                }
                .font(.callout)
            }
        }
    }

    private var statsPreview: some View {
        let finalW = viewModel.weightHistory.last?.weight ?? 0
        let peakW = viewModel.weightHistory.map(\.weight).max() ?? 0
        let peakF = viewModel.flowRateHistory.map(\.flowRate).max() ?? 0
        let dur = viewModel.brewTimer.elapsed

        return VStack(alignment: .leading, spacing: 4) {
            Text("Brew Summary")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                statItem(icon: "clock", label: durationFormatter.string(from: dur) ?? "0s")
                statItem(icon: "scalemass", label: viewModel.displayUnit.format(finalW))
                Spacer()
            }

            HStack(spacing: 16) {
                statItem(icon: "arrow.up.to.line.compact", label: "Peak \(viewModel.displayUnit.format(peakW))")
                statItem(icon: "water.waves", label: String(format: "%.1f g/s", peakF))
                Spacer()
            }
        }
    }

    private func statItem(icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    private func saveBrew() {
        let name = brewName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        store.add(
            name: name,
            note: brewNote.trimmingCharacters(in: .whitespacesAndNewlines),
            weightPoints: viewModel.weightHistory.asGraphPoints,
            flowPoints: viewModel.flowRateHistory.asGraphPoints,
            displayUnit: viewModel.displayUnit
        )
        hasSaved = true
    }

    // MARK: - Brew list

    private var emptyState: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("No saved brews")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Tap Save Current Brew after your next brew to build a history.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    private func brewRow(_ brew: SavedBrew) -> some View {
        Button {
            dismiss()
            onRecall(brew)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(brew.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(dateFormatter.string(from: brew.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !brew.note.isEmpty {
                    Text(brew.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    Label(durationFormatter.string(from: brew.duration) ?? "0s",
                          systemImage: "clock")
                    Label(brew.displayUnit.format(brew.finalWeight),
                          systemImage: "scalemass")
                    Label(String(format: "%.1f g/s", brew.peakFlow),
                          systemImage: "water.waves")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                // Underlay button
                if viewModel.underlayBrew?.id == brew.id {
                    Button {
                        viewModel.underlayBrew = nil
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.line.flattrend.xyaxis")
                                .font(.caption2)
                            Text("Remove underlay")
                                .font(.caption2)
                        }
                        .foregroundStyle(.orange.opacity(0.8))
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        viewModel.underlayBrew = brew
                        viewModel.hideUnderlayChip = false
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.line.flattrend.xyaxis")
                                .font(.caption2)
                            Text("Show as underlay")
                                .font(.caption2)
                        }
                        .foregroundStyle(.cyan.opacity(0.8))
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func deleteBrews(at offsets: IndexSet) {
        for idx in offsets {
            let brew = store.brews[idx]
            if viewModel.underlayBrew?.id == brew.id {
                viewModel.underlayBrew = nil
            }
            store.delete(brew)
        }
    }
}
