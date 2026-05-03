import Foundation
import PencilKit
import UIKit

@MainActor
final class TemplateBrushRecentColorCoordinator {
    struct State {
        let activeBrushPreset: BrushPreset
        let userBrushPresets: [BrushPreset]
        let recentColors: [RecentColorToken]
        let activeColorToken: RecentColorToken?
        let appliedRecentColor: UIColor?
        let appliedRecentColorRevision: Int
    }

    private let brushPresetStore: any BrushPresetStoreProviding
    private let recentColorsStore: any RecentColorsStoreProviding
    private(set) var activeBrushPreset: BrushPreset
    private var userBrushPresets: [BrushPreset] = []
    private var recentColorsByTemplateID: [String: [RecentColorToken]] = [:]
    private var recentColors: [RecentColorToken] = []
    private var activeColorToken: RecentColorToken?
    private var appliedRecentColor: UIColor?
    private var appliedRecentColorRevision = 0

    init(
        brushPresetStore: any BrushPresetStoreProviding,
        recentColorsStore: any RecentColorsStoreProviding
    ) {
        self.brushPresetStore = brushPresetStore
        self.recentColorsStore = recentColorsStore
        self.activeBrushPreset = BrushPreset.builtInPresets.first(where: { $0.id == BrushPreset.defaultPresetID }) ?? BrushPreset.builtInPresets[0]
    }

    var allBrushPresets: [BrushPreset] {
        BrushPreset.builtInPresets + userBrushPresets
    }

    var state: State {
        State(
            activeBrushPreset: activeBrushPreset,
            userBrushPresets: userBrushPresets,
            recentColors: recentColors,
            activeColorToken: activeColorToken,
            appliedRecentColor: appliedRecentColor,
            appliedRecentColorRevision: appliedRecentColorRevision
        )
    }

    func selectBrushPreset(_ preset: BrushPreset) -> State {
        activeBrushPreset = preset
        return state
    }

    func saveCurrentAsPreset(name: String, width: CGFloat, opacity: CGFloat) -> State {
        let preset = BrushPreset(
            id: "custom-\(UUID().uuidString)",
            name: name,
            inkType: activeBrushPreset.inkType,
            width: width,
            opacity: opacity,
            isBuiltIn: false
        )
        userBrushPresets.append(preset)
        persistUserPresets()
        return state
    }

    func deleteCustomPreset(_ id: String) -> State {
        userBrushPresets.removeAll { $0.id == id }
        if activeBrushPreset.id == id {
            activeBrushPreset = BrushPreset.builtInPresets[0]
        }
        persistUserPresets()
        return state
    }

    func loadBrushPresets(onStateChange: @escaping @MainActor (State) -> Void) {
        Task { [brushPresetStore] in
            do {
                userBrushPresets = try await brushPresetStore.loadUserPresets()
                onStateChange(state)
            } catch {
                // Preserve the existing behavior: failed loads fall back to built-in presets only.
            }
        }
    }

    func loadRecentColors(
        validTemplateIDs: Set<String>,
        selectedTemplateID: String,
        onStateChange: @escaping @MainActor (State) -> Void
    ) {
        Task { [recentColorsStore] in
            do {
                let colorsByTemplateID = try await recentColorsStore.loadRecentColorsByTemplateID()
                if validTemplateIDs.isEmpty {
                    recentColorsByTemplateID = colorsByTemplateID
                } else {
                    let filteredColorsByTemplateID = colorsByTemplateID.filter { validTemplateIDs.contains($0.key) }
                    recentColorsByTemplateID = filteredColorsByTemplateID
                    if filteredColorsByTemplateID.count != colorsByTemplateID.count {
                        persistRecentColors()
                    }
                }
                _ = refreshRecentColors(for: selectedTemplateID)
                onStateChange(state)
            } catch {
                recentColorsByTemplateID = [:]
                recentColors = []
                activeColorToken = nil
                onStateChange(state)
            }
        }
    }

    func recordUsedColor(_ color: UIColor, selectedTemplateID: String) -> State? {
        guard !selectedTemplateID.isEmpty,
              let token = RecentColorToken(uiColor: color)
        else {
            return nil
        }

        activeColorToken = token
        updateRecentColors(with: token, selectedTemplateID: selectedTemplateID)
        return state
    }

    func applyRecentColor(_ token: RecentColorToken, selectedTemplateID: String) -> State? {
        guard !selectedTemplateID.isEmpty else {
            return nil
        }

        activeColorToken = token
        appliedRecentColor = token.uiColor
        appliedRecentColorRevision += 1
        return state
    }

    func refreshRecentColors(for selectedTemplateID: String) -> State {
        recentColors = recentColorsByTemplateID[selectedTemplateID] ?? []
        activeColorToken = nil
        return state
    }

    func retainRecentColors(for validTemplateIDs: Set<String>, selectedTemplateID: String) -> State? {
        let filteredColorsByTemplateID = recentColorsByTemplateID.filter { validTemplateIDs.contains($0.key) }
        guard filteredColorsByTemplateID != recentColorsByTemplateID else {
            return nil
        }

        recentColorsByTemplateID = filteredColorsByTemplateID
        persistRecentColors()
        return refreshRecentColors(for: selectedTemplateID)
    }

    func removeRecentColors(for templateID: String, selectedTemplateID: String) -> State? {
        guard recentColorsByTemplateID.removeValue(forKey: templateID) != nil else {
            return nil
        }

        if selectedTemplateID == templateID {
            recentColors = []
            activeColorToken = nil
        }
        persistRecentColors()
        return state
    }

    func renameRecentColors(from oldTemplateID: String, to newTemplateID: String) {
        guard let recentColors = recentColorsByTemplateID.removeValue(forKey: oldTemplateID) else {
            return
        }

        recentColorsByTemplateID[newTemplateID] = recentColors
        persistRecentColors()
    }

    private func updateRecentColors(with token: RecentColorToken, selectedTemplateID: String) {
        let updatedColors = RecentColorsStoreService.inserting(
            token,
            into: recentColorsByTemplateID[selectedTemplateID] ?? []
        )
        guard updatedColors != recentColorsByTemplateID[selectedTemplateID] else {
            return
        }

        recentColorsByTemplateID[selectedTemplateID] = updatedColors
        recentColors = updatedColors
        persistRecentColors()
    }

    private func persistUserPresets() {
        let presets = userBrushPresets
        Task { [brushPresetStore, presets] in
            try? await brushPresetStore.saveUserPresets(presets)
        }
    }

    private func persistRecentColors() {
        let colorsByTemplateID = recentColorsByTemplateID
        Task { [recentColorsStore, colorsByTemplateID] in
            try? await recentColorsStore.saveRecentColorsByTemplateID(colorsByTemplateID)
        }
    }
}
