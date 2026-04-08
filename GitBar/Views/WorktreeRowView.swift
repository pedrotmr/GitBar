import SwiftUI

struct WorktreeRowView: View {
    let worktree: Worktree
    @Environment(GitService.self) private var gitService
    @Environment(SettingsService.self) private var settingsService
    @State private var isHovered = false
    @State private var showDeleteConfirm = false
    @State private var showForceDeleteConfirm = false
    @State private var isDeleting = false
    @State private var hasUncommittedChanges = false

    var body: some View {
        HStack(spacing: 10) {
            // Folder icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 30, height: 30)
                Image(systemName: worktree.isBare ? "cylinder" : "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(worktree.displayPath)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if worktree.isMain {
                        Badge("main", color: .accentColor)
                    }
                    if worktree.isBare {
                        Badge("bare", color: .secondary)
                    }
                }
                if let branch = worktree.branch {
                    Text(branch)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isDeleting {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 60)
            } else if isHovered {
                HStack(spacing: 2) {
                    HoverIconButton(systemImage: "folder", tooltip: "Open in Finder", action: openInFinder)
                    HoverIconButton(systemImage: "terminal", tooltip: "Open in Terminal", action: openInTerminal)
                    HoverIconButton(systemImage: "chevron.left.forwardslash.chevron.right", tooltip: "Open in Editor", action: openInEditor)
                    if !worktree.isMain && !worktree.isBare {
                        HoverIconButton(systemImage: "trash", tooltip: "Delete worktree") {
                            triggerDelete()
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(isDeleting ? 0.5 : 1)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered && !isDeleting ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { h in
            guard !isDeleting else { return }
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = h }
        }
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Open in Finder") { openInFinder() }
            Button("Open in Terminal") { openInTerminal() }
            Button("Open in Editor") { openInEditor() }
            if !worktree.isMain && !worktree.isBare {
                Divider()
                Button("Delete Worktree", role: .destructive) {
                    triggerDelete()
                }
                Button("Force Delete Worktree", role: .destructive) {
                    showForceDeleteConfirm = true
                }
            }
        }
        .confirmationDialog(
            "Delete worktree?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .confirmationDialog(
            "Force delete worktree?",
            isPresented: $showForceDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Force Delete", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let branch = worktree.branch {
                Text("The worktree and branch \"\(branch)\" will be permanently deleted, including any uncommitted changes. This cannot be undone.")
            } else {
                Text("The worktree will be permanently deleted, including any uncommitted changes. This cannot be undone.")
            }
        }
    }

    private var confirmationMessage: String {
        var parts: [String] = []
        if hasUncommittedChanges {
            parts.append("This worktree has uncommitted changes.")
        }
        if let branch = worktree.branch {
            parts.append("Branch \"\(branch)\" will also be deleted.")
        }
        return parts.isEmpty ? "This cannot be undone." : parts.joined(separator: " ")
    }

    private func triggerDelete() {
        Task {
            hasUncommittedChanges = await gitService.hasUncommittedChanges(worktree.path)
            showDeleteConfirm = true
        }
    }

    private func performDelete() {
        isDeleting = true
        Task {
            await gitService.deleteWorktreeAndBranch(worktree)
            isDeleting = false
        }
    }

    private func openInFinder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: worktree.path))
    }

    private func openInTerminal() {
        let url = URL(fileURLWithPath: worktree.path)
        let terminal = settingsService.preferredTerminal
        guard let appURL = AppDetector.appURL(bundleIdentifier: terminal.rawValue) else {
            NSWorkspace.shared.open(url)
            return
        }
        if terminal == .cmux {
            let cli = appURL.appendingPathComponent("Contents/Resources/bin/cmux")
            let p = Process()
            p.executableURL = cli
            p.arguments = ["new-workspace", "--command", "cd '\(shellQuoted(worktree.path))' && exec $SHELL"]
            try? p.run()
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .init(), completionHandler: nil)
        }
    }

    private func shellQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private func openInEditor() {
        let url = URL(fileURLWithPath: worktree.path)
        let bundleId = settingsService.preferredEditor.rawValue
        if let appURL = AppDetector.appURL(bundleIdentifier: bundleId) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .init(), completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Badge

struct Badge: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}
