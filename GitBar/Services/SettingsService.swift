import Foundation
import Observation
import SwiftUI

@Observable
class SettingsService {
    private let repoPathsKey = "repoPaths_v2"
    private let selectedPathKey = "selectedRepoPath_v2"
    private let preferredTerminalKey = "preferredTerminal"
    private let preferredEditorKey = "preferredEditor"
    private let showBranchesTabKey = "showBranchesTab"
    private let showStashTabKey = "showStashTab"
    private let showWorktreeTabKey = "showWorktreeTab"
    private let autoFetchEnabledKey = "autoFetchEnabled"
    private let showPRTabKey = "showPRTab"
    private let tabOrderKey = "tabOrder"

    var repoPaths: [String]
    var selectedRepoPath: String?
    var preferredTerminal: SupportedTerminal {
        didSet { UserDefaults.standard.set(preferredTerminal.rawValue, forKey: preferredTerminalKey) }
    }
    var preferredEditor: SupportedEditor {
        didSet { UserDefaults.standard.set(preferredEditor.rawValue, forKey: preferredEditorKey) }
    }
    var showBranchesTab: Bool {
        didSet { UserDefaults.standard.set(showBranchesTab, forKey: showBranchesTabKey) }
    }
    var showStashTab: Bool {
        didSet { UserDefaults.standard.set(showStashTab, forKey: showStashTabKey) }
    }
    var showWorktreeTab: Bool {
        didSet { UserDefaults.standard.set(showWorktreeTab, forKey: showWorktreeTabKey) }
    }
    var autoFetchEnabled: Bool {
        didSet { UserDefaults.standard.set(autoFetchEnabled, forKey: autoFetchEnabledKey) }
    }
    var showPRTab: Bool {
        didSet { UserDefaults.standard.set(showPRTab, forKey: showPRTabKey) }
    }
    var tabOrder: [AppTab] {
        didSet { UserDefaults.standard.set(tabOrder.map(\.rawValue), forKey: tabOrderKey) }
    }

    init() {
        repoPaths = UserDefaults.standard.stringArray(forKey: repoPathsKey) ?? []
        selectedRepoPath = UserDefaults.standard.string(forKey: selectedPathKey)
        let terminalRaw = UserDefaults.standard.string(forKey: preferredTerminalKey) ?? ""
        preferredTerminal = SupportedTerminal(rawValue: terminalRaw) ?? .terminal
        let editorRaw = UserDefaults.standard.string(forKey: preferredEditorKey) ?? ""
        preferredEditor = SupportedEditor(rawValue: editorRaw) ?? .vscode
        showBranchesTab = UserDefaults.standard.object(forKey: showBranchesTabKey) as? Bool ?? true
        showStashTab = UserDefaults.standard.object(forKey: showStashTabKey) as? Bool ?? true
        showWorktreeTab = UserDefaults.standard.object(forKey: showWorktreeTabKey) as? Bool ?? true
        autoFetchEnabled = UserDefaults.standard.bool(forKey: autoFetchEnabledKey)
        showPRTab = UserDefaults.standard.object(forKey: showPRTabKey) as? Bool ?? true
        let defaultOrder: [AppTab] = [.branches, .stashes, .worktrees, .pullRequests]
        let saved = (UserDefaults.standard.stringArray(forKey: tabOrderKey) ?? []).compactMap(AppTab.init(rawValue:))
        let missing = defaultOrder.filter { !saved.contains($0) }
        tabOrder = saved.isEmpty ? defaultOrder : saved + missing
    }

    func addRepo(_ path: String) {
        if !repoPaths.contains(path) {
            repoPaths.append(path)
            UserDefaults.standard.set(repoPaths, forKey: repoPathsKey)
        }
        selectedRepoPath = path
        UserDefaults.standard.set(path, forKey: selectedPathKey)
    }

    func removeRepo(_ path: String) {
        repoPaths.removeAll { $0 == path }
        UserDefaults.standard.set(repoPaths, forKey: repoPathsKey)
        if selectedRepoPath == path {
            selectedRepoPath = repoPaths.first
            UserDefaults.standard.set(selectedRepoPath, forKey: selectedPathKey)
        }
    }

    func moveRepo(fromOffsets source: IndexSet, toOffset destination: Int) {
        repoPaths.move(fromOffsets: source, toOffset: destination)
        UserDefaults.standard.set(repoPaths, forKey: repoPathsKey)
    }

    func moveTab(from sourceRaw: String, onto targetRaw: String) {
        guard let from = AppTab(rawValue: sourceRaw),
              let to = AppTab(rawValue: targetRaw),
              from != to,
              let fromIndex = tabOrder.firstIndex(of: from),
              let toIndex = tabOrder.firstIndex(of: to)
        else { return }
        tabOrder.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
    }

    func selectRepo(_ path: String) {
        selectedRepoPath = path
        UserDefaults.standard.set(path, forKey: selectedPathKey)
    }
}
