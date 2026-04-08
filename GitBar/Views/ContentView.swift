import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(GitService.self) private var gitService
    @Environment(SettingsService.self) private var settingsService
    @State private var selectedTab: AppTab = .branches
    @State private var showRepoList = false
    @State private var showSettings = false
    @State private var draggingTab: AppTab? = nil
    @State private var dropTargetTab: AppTab? = nil

    var body: some View {
        ZStack {
            mainView
                .offset(x: (showRepoList || showSettings) ? -440 : 0)

            RepoListView(isShowing: $showRepoList, onShowSettings: {
                withAnimation {
                    showRepoList = false
                    showSettings = true
                }
            })
            .offset(x: showRepoList ? 0 : 440)

            SettingsView(isShowing: $showSettings)
                .offset(x: showSettings ? 0 : 440)
        }
        .animation(.spring(duration: 0.28, bounce: 0.05), value: showRepoList)
        .animation(.spring(duration: 0.28, bounce: 0.05), value: showSettings)
        .frame(width: 440, height: 500)
        .onChange(of: settingsService.selectedRepoPath) { _, newPath in
            if let path = newPath {
                gitService.repoPath = path
                gitService.isDirty = true
                if gitService.isPopoverVisible {
                    Task { await gitService.refreshAfterRepoSelection() }
                }
            } else {
                gitService.repoPath = ""
                gitService.branches = []
                gitService.worktrees = []
                gitService.stashes = []
                gitService.pullRequests = []
                gitService.errorMessage = nil
            }
        }
        .onChange(of: settingsService.showBranchesTab) { _, isEnabled in
            if !isEnabled && selectedTab == .branches { selectFirstVisibleTab() }
        }
        .onChange(of: settingsService.showWorktreeTab) { _, isEnabled in
            if !isEnabled && selectedTab == .worktrees { selectFirstVisibleTab() }
        }
        .onChange(of: settingsService.showStashTab) { _, isEnabled in
            if !isEnabled && selectedTab == .stashes { selectFirstVisibleTab() }
        }
        .onChange(of: settingsService.autoFetchEnabled) { _, newValue in
            gitService.autoFetchEnabled = newValue
        }
        .onChange(of: settingsService.showPRTab) { _, isEnabled in
            if !isEnabled && selectedTab == .pullRequests { selectFirstVisibleTab() }
        }
    }

    // MARK: - Main View

    private var mainView: some View {
        VStack(spacing: 0) {
            repoHeader

            Divider().opacity(0.5)

            if gitService.repoPath.isEmpty {
                emptyState
            } else {
                if let error = gitService.errorMessage {
                    errorBanner(error)
                }
                if hasVisibleTabs {
                    tabBar
                    Divider().opacity(0.5)
                    // P2: Only render the active tab instead of all 4 via ZStack+opacity
                    switch selectedTab {
                    case .branches:
                        BranchesView()
                    case .worktrees:
                        WorktreesView()
                    case .stashes:
                        StashesView()
                    case .pullRequests:
                        PullRequestsView()
                    }
                } else {
                    allTabsHiddenState
                }
            }

            Divider().opacity(0.5)
            bottomBar
        }
        .frame(width: 440, height: 500)
    }

    // MARK: - Repo Header

    private var repoHeader: some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(gitService.repoPath.isEmpty ? Color.secondary.opacity(0.15) : Color.green.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(gitService.repoPath.isEmpty ? Color.secondary : Color.green)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(repoName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !gitService.repoPath.isEmpty {
                        Text(shortPath)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Click to select a repository")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { showRepoList = true } }

            IconButton(systemImage: "plus", tooltip: "Add repository") {
                addRepo()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(height: 58)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(settingsService.tabOrder, id: \.self) { tab in
                if isTabVisible(tab) {
                    TabButton(title: tabTitle(tab), count: tabCount(tab), tab: tab, selected: selectedTab) {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                    }
                    .opacity(draggingTab == tab ? 0.4 : 1.0)
                    .background(dropTargetTab == tab && draggingTab != tab ? Color.accentColor.opacity(0.1) : Color.clear)
                    .onDrag {
                        draggingTab = tab
                        return NSItemProvider(object: tab.rawValue as NSString)
                    }
                    .onDrop(
                        of: [.plainText],
                        isTargeted: Binding(
                            get: { dropTargetTab == tab },
                            set: { isTarget in
                                if isTarget { dropTargetTab = tab }
                                else if dropTargetTab == tab { dropTargetTab = nil }
                            }
                        )
                    ) { providers in
                        providers.first?.loadObject(ofClass: NSString.self) { item, _ in
                            guard let src = item as? String else { return }
                            DispatchQueue.main.async {
                                settingsService.moveTab(from: src, onto: tab.rawValue)
                                draggingTab = nil
                                dropTargetTab = nil
                            }
                        }
                        return true
                    }
                }
            }
        }
        .frame(height: 38)
    }

    private func isTabVisible(_ tab: AppTab) -> Bool {
        switch tab {
        case .branches: return settingsService.showBranchesTab
        case .worktrees: return settingsService.showWorktreeTab
        case .stashes: return settingsService.showStashTab
        case .pullRequests: return settingsService.showPRTab
        }
    }

    private var hasVisibleTabs: Bool {
        settingsService.tabOrder.contains(where: { isTabVisible($0) })
    }

    private func selectFirstVisibleTab() {
        if let first = settingsService.tabOrder.first(where: { isTabVisible($0) }) {
            selectedTab = first
        }
    }

    private func tabTitle(_ tab: AppTab) -> String {
        switch tab {
        case .branches: return "Branches"
        case .worktrees: return "Worktrees"
        case .stashes: return "Stash"
        case .pullRequests: return "PRs"
        }
    }

    private func tabCount(_ tab: AppTab) -> Int {
        switch tab {
        case .branches: return gitService.branches.count
        case .worktrees: return gitService.worktrees.count
        case .stashes: return gitService.stashes.count
        case .pullRequests: return gitService.pullRequests.count
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        BottomBar(onSettings: { withAnimation { showSettings = true } })
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No repository selected")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            Text("Click the header to add or select\na git repository")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var allTabsHiddenState: some View {
        AllTabsHiddenView()
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button {
                gitService.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Helpers

    private var repoName: String {
        guard !gitService.repoPath.isEmpty else { return "No Repository" }
        return URL(fileURLWithPath: gitService.repoPath).lastPathComponent
    }

    private var shortPath: String {
        let home = NSHomeDirectory()
        return gitService.repoPath.replacingOccurrences(of: home, with: "~")
    }

    private func addRepo() {
        guard let path = openRepoPicker() else { return }
        Task {
            if await gitService.isGitRepo(path) {
                settingsService.addRepo(path)
            }
        }
    }
}

// MARK: - All Tabs Hidden

private struct AllTabsHiddenView: View {
    @State private var isAnimating = false

    private enum Constants {
        static let spacing: CGFloat = 12
        static let iconSize: CGFloat = 32
        static let steamWispWidth: CGFloat = 3
        static let steamWispHeight: CGFloat = 8
        static let steamWispSpacing: CGFloat = 3
        static let steamWispOpacity: Double = 0.35
        static let steamOffsetX: CGFloat = -4
        static let steamOffsetY: CGFloat = -12
        static let animatedOffset: CGFloat = -6
        static let animationDuration: Double = 1.1
        static let animationStagger: Double = 0.3
        static let titleFontSize: CGFloat = 14
        static let subtitleFontSize: CGFloat = 12
    }

    var body: some View {
        VStack(spacing: Constants.spacing) {
            Spacer()
            ZStack(alignment: .topTrailing) {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: Constants.iconSize, weight: .light))
                    .foregroundStyle(.secondary)
                // Steam wisps
                VStack(spacing: Constants.steamWispSpacing) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(Color.secondary.opacity(Constants.steamWispOpacity))
                            .frame(width: Constants.steamWispWidth, height: Constants.steamWispHeight)
                            .offset(y: isAnimating ? Constants.animatedOffset : 0)
                            .opacity(isAnimating ? 0 : 0.8)
                            .animation(
                                .easeInOut(duration: Constants.animationDuration)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * Constants.animationStagger),
                                value: isAnimating
                            )
                    }
                }
                .offset(x: Constants.steamOffsetX, y: Constants.steamOffsetY)
            }
            .onAppear { isAnimating = true }
            Text("Nothing brewing here.")
                .font(.system(size: Constants.titleFontSize, weight: .medium))
                .foregroundStyle(.primary)
            Text("Enable at least one tab in Settings to see something here.")
                .font(.system(size: Constants.subtitleFontSize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let count: Int
    let tab: AppTab
    let selected: AppTab
    let action: () -> Void

    var isSelected: Bool { tab == selected }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.1))
                        )
                }
            }
            Spacer()
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(height: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Icon Button

struct BackHeader: View {
    let title: String
    let action: () -> Void
    var trailing: AnyView? = nil
    @State private var isHovered = false

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(isHovered ? Color.primary.opacity(0.07) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { isHovered = h } }
            .onTapGesture(perform: action)

            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(height: 58)
    }
}

struct IconButton: View {
    let systemImage: String
    let tooltip: String
    let action: () -> Void
    @State private var isHovered = false

    init(systemImage: String, tooltip: String = "", action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.tooltip = tooltip
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(isHovered ? Color.primary.opacity(0.07) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .customTooltip(tooltip)
    }
}

// MARK: - Bottom Bar

struct BottomBar: View {
    @Environment(GitService.self) private var gitService
    @Environment(UpdateService.self) private var updateService
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if gitService.isLoading {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 16, height: 16)
            }
            Spacer()
            IconButton(systemImage: "arrow.clockwise", tooltip: "Refresh") {
                Task { await gitService.refresh() }
            }
            .disabled(gitService.repoPath.isEmpty || gitService.isLoading)

            if updateService.isUpdateAvailable {
                IconButton(systemImage: "arrow.down.circle", tooltip: updateTooltip) {
                    Task { await updateService.installLatestUpdate() }
                }
                .disabled(updateService.isInstallingUpdate)
            }

            IconButton(systemImage: "gearshape", tooltip: "Settings") {
                onSettings()
            }

            IconButton(systemImage: "power", tooltip: "Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var updateTooltip: String {
        if let latestVersion = updateService.latestVersion {
            return "Update available (\(latestVersion))"
        }
        return "Update available"
    }
}
