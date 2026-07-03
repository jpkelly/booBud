import Foundation
import os

/// Persists saved brews to a JSON file in the app's Documents directory.
/// Newest-first ordering. Thread-safe via @MainActor + @Observable.
@MainActor
@Observable
final class BrewStore {
    private(set) var brews: [SavedBrew] = []

    private let logger = Logger(subsystem: "com.boobud.brewstore", category: "BrewStore")
    private let storeURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storeURL = docs.appendingPathComponent("brews.json")
        load()
    }

    // MARK: - Public API

    /// Save the current brew session to disk.
    func add(
        name: String,
        note: String = "",
        weightPoints: [GraphPoint],
        flowPoints: [GraphPoint],
        displayUnit: WeightUnit
    ) {
        let brew = SavedBrew(
            name: name,
            note: note,
            weightPoints: weightPoints,
            flowPoints: flowPoints,
            displayUnit: displayUnit
        )
        brews.insert(brew, at: 0)
        persist()
        logger.info("Saved brew '\(name)' — \(brew.weightPoints.count) weight, \(brew.flowPoints.count) flow points")
    }

    /// Delete a brew by id.
    func delete(_ brew: SavedBrew) {
        brews.removeAll { $0.id == brew.id }
        persist()
        logger.info("Deleted brew '\(brew.name)'")
    }

    /// Rename or update the note for an existing brew.
    func update(_ brew: SavedBrew, name: String? = nil, note: String? = nil) {
        guard let idx = brews.firstIndex(where: { $0.id == brew.id }) else { return }
        if let name { brews[idx].name = name }
        if let note { brews[idx].note = note }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            logger.info("No saved brews file yet — starting fresh")
            return
        }
        do {
            let data = try Data(contentsOf: storeURL)
            brews = try JSONDecoder().decode([SavedBrew].self, from: data)
            brews.sort { $0.date > $1.date }
            logger.info("Loaded \(self.brews.count) saved brew(s)")
        } catch {
            logger.error("Failed to load brews: \(error.localizedDescription)")
            brews = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(brews)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            logger.error("Failed to save brews: \(error.localizedDescription)")
        }
    }
}
