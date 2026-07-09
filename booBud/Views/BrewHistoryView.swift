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
    @State private var beanWeight: Double = 18.0
    @State private var grindSetting: Double = 2.0

    // Edit sheet
    @State private var editingBrew: SavedBrew? = nil

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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingBrew) { brew in
                BrewEditSheet(brew: brew, store: store, viewModel: viewModel)
            }
            .onAppear {
                let df = DateFormatter()
                df.dateFormat = "MMM d, h:mm a"
                brewName = "Brew \(df.string(from: Date()))"
                beanWeight = viewModel.lastBeanWeight
                grindSetting = viewModel.lastGrindSetting
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

            beanGrindRow(beanWeight: $beanWeight, grindSetting: $grindSetting, grindStep: viewModel.grindStep)

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
        let dur = viewModel.flowStoppedAt ?? viewModel.brewTimer.elapsed

        return VStack(alignment: .leading, spacing: 4) {
            Text("Brew Summary")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                statItem(icon: "drop", label: formatBrewSeconds(dur))
                if let stopTime = viewModel.flowStoppedAt {
                    statItem(icon: "timer", label: formatBrewSeconds(viewModel.brewTimer.elapsed))
                    let _ = stopTime // suppress unused warning
                }
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

    private func formatBrewSeconds(_ t: Double) -> String {
        String(format: "%.1fs", t)
    }

    private func saveBrew() {
        let name = brewName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        store.add(
            name: name,
            note: brewNote.trimmingCharacters(in: .whitespacesAndNewlines),
            weightPoints: viewModel.weightHistory.asGraphPoints,
            flowPoints: viewModel.flowRateHistory.asGraphPoints,
            displayUnit: viewModel.displayUnit,
            beanWeight: beanWeight,
            grindSetting: grindSetting,
            flowStoppedAt: viewModel.flowStoppedAt
        )
        viewModel.lastBeanWeight = beanWeight
        viewModel.lastGrindSetting = grindSetting
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
        return Button {
            dismiss()
            onRecall(brew)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(brew.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.warmSecondary)
                    Button {
                        editingBrew = brew
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(Color.warmSecondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(dateFormatter.string(from: brew.date))
                        .font(.caption)
                        .foregroundStyle(Color.warmSecondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "scalemass.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.warmSecondary.opacity(0.6))
                    Text(String(format: "%.1fg", brew.beanWeight))
                        .font(.caption)
                        .foregroundStyle(Color.warmSecondary)
                    Image(systemName: "dial.medium.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.warmSecondary.opacity(0.6))
                        .scaleEffect(1.3)
                    Text(grindString(brew.grindSetting))
                        .font(.caption)
                        .foregroundStyle(Color.warmSecondary)
                    if !brew.note.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Color.warmSecondary.opacity(0.5))
                        Text(brew.note)
                            .font(.caption)
                            .foregroundStyle(Color.warmSecondary)
                            .lineLimit(1)
                    }
                }

                // Thumbnail card + metadata row
                HStack(alignment: .top, spacing: 10) {
                    BrewThumbnailView(
                        weightPoints: brew.weightPoints,
                        flowPoints: brew.flowPoints
                    )
                    .frame(width: 130)

                    VStack(alignment: .leading, spacing: 4) {
                        let effectiveStop = brew.flowStoppedAt
                            ?? (brew.weightPoints.contains { $0.value > 5.0 }
                                ? brew.flowPoints.computeFlowStoppedAt(threshold: viewModel.flowStopThreshold)
                                : nil)

                        // Times row
                        HStack(spacing: 6) {
                            if let stop = effectiveStop {
                                Image(systemName: "drop")
                                    .font(.caption2)
                                    .foregroundStyle(.cyan.opacity(0.8))
                                    .frame(width: 14, alignment: .center)
                                Text(formatBrewSeconds(stop))
                                Text("·").foregroundStyle(.secondary)
                                Image(systemName: "timer")
                                Text(formatBrewSeconds(brew.duration))
                            } else {
                                Image(systemName: "timer")
                                Text(formatBrewSeconds(brew.duration))
                            }
                        }

                        // Weight + flow row
                        HStack(spacing: 6) {
                            Image(systemName: "scalemass")
                                .foregroundStyle(.orange.opacity(0.8))
                            Text(brew.displayUnit.format(brew.finalWeight))
                            Text("·").foregroundStyle(.secondary)
                            Image(systemName: "water.waves")
                            Text(String(format: "%.1f g/s", brew.peakFlow))
                        }

                        // Underlay button
                        if viewModel.underlayBrew?.id == brew.id {
                            Button {
                                viewModel.underlayBrew = nil
                                dismiss()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.line.flattrend.xyaxis")
                                    Text("Remove underlay")
                                }
                                .font(.caption2)
                                .foregroundStyle(.orange.opacity(0.8))
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.orange.opacity(0.5), lineWidth: 1))
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
                                    Text("Show as underlay")
                                }
                                .font(.caption2)
                                .foregroundStyle(.cyan.opacity(0.8))
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.cyan.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.warmSecondary)
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

// MARK: - Edit Sheet

struct BrewEditSheet: View {
    let brew: SavedBrew
    @Bindable var store: BrewStore
    let viewModel: ScaleViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var editName: String = ""
    @State private var editNote: String = ""
    @State private var editBeanWeight: Double = 18.0
    @State private var editGrindSetting: Double = 2.0

    var body: some View {
        NavigationStack {
            List {
                Section("Brew Summary") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 16) {
                            if let stop = brew.flowStoppedAt {
                                statItem(icon: "drop", label: formatSecs(stop))
                                statItem(icon: "timer", label: formatSecs(brew.duration))
                            } else {
                                statItem(icon: "drop", label: formatSecs(brew.duration))
                            }
                            statItem(icon: "scalemass", label: brew.displayUnit.format(brew.finalWeight))
                            Spacer()
                        }
                        HStack(spacing: 16) {
                            statItem(icon: "arrow.up.to.line.compact", label: "Peak \(brew.displayUnit.format(brew.peakWeight))")
                            statItem(icon: "water.waves", label: String(format: "%.1f g/s", brew.peakFlow))
                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("Name", text: $editName)
                        .font(.body)

                    beanGrindRow(beanWeight: $editBeanWeight, grindSetting: $editGrindSetting, grindStep: viewModel.grindStep)

                    HStack {
                        TextField("Note (optional)", text: $editNote, axis: .vertical)
                            .font(.callout)
                            .lineLimit(1...3)
                        Spacer(minLength: 12)
                        Button {
                            let name = editName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            store.update(brew, name: name, note: editNote.trimmingCharacters(in: .whitespacesAndNewlines), beanWeight: editBeanWeight, grindSetting: editGrindSetting)
                            // Refresh underlay if the edited brew is the currently active underlay
                            if viewModel.underlayBrew?.id == brew.id {
                                viewModel.underlayBrew = store.brews.first { $0.id == brew.id }
                            }
                            dismiss()
                        } label: {
                            Text("Save")
                                .font(.callout.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                        .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(editName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
                    }
                }
            }
            .navigationTitle("Edit Brew")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                editName = brew.name
                editNote = brew.note
                editBeanWeight = brew.beanWeight
                editGrindSetting = brew.grindSetting
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

    private func formatSecs(_ t: Double) -> String {
        String(format: "%.1fs", t)
    }
}

// MARK: - Shared bean weight + grind rows (editable text + native Stepper)

/// Bean weight and grind setting rows with direct text entry + native Stepper +/- buttons.
/// Shared by the save section and edit sheet.
@MainActor
@ViewBuilder
fileprivate func beanGrindRow(beanWeight: Binding<Double>, grindSetting: Binding<Double>, grindStep: Double) -> some View {
    Stepper(value: beanWeight, in: 0...100, step: 0.1) {
        HStack(spacing: 6) {
            Image(systemName: "scalemass.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Bean weight")
                .font(.callout)
            Spacer(minLength: 8)
            TextField("", value: beanWeight, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
            Text("g")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
    Stepper(value: grindSetting, in: 0...100, step: grindStep) {
        HStack(spacing: 6) {
            Image(systemName: "dial.medium.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .scaleEffect(1.3)
            Text("Grind")
                .font(.callout)
            Spacer(minLength: 8)
            TextField("", value: grindSetting, format: .number.precision(.fractionLength(1...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
        }
    }
}
