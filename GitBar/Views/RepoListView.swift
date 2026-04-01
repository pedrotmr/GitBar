import SwiftUI
import UniformTypeIdentifiers

struct RepoListView: View {
    @Binding var isShowing: Bool
    let onShowSettings: () -> Void
    @Environment(GitService.self) private var gitService
    @Environment(SettingsService.self) private var settingsService
    @State private var showInvalidAlert = false
    @State private var draggingPath: String? = nil
    @State private var dropTargetPath: String? = nil
    @State private var isEndZoneTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            BackHeader(title: "Repositories", action: { withAnimation { isShowing = false } }, trailing: AnyView(
                IconButton(systemImage: "plus", tooltip: "Add repository") { addRepo() }
            ))

            Divider().opacity(0.5)

            if settingsService.repoPaths.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(settingsService.repoPaths, id: \.self) { path in
                            RepoRow(
                                path: path,
                                isSelected: settingsService.selectedRepoPath == path,
                                isDragging: draggingPath == path,
                                isDropTarget: dropTargetPath == path,
                                onSelect: {
                                    settingsService.selectRepo(path)
                                    withAnimation { isShowing = false }
                                },
                                onRemove: {
                                    settingsService.removeRepo(path)
                                },
                                onDragStarted: {
                                    withAnimation(.easeInOut(duration: 0.15)) { draggingPath = path }
                                },
                                onDrop: { src in
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        handleDrop(src, onto: path)
                                        dropTargetPath = nil
                                        draggingPath = nil
                                    }
                                },
                                onDropEntered: {
                                    withAnimation(.easeInOut(duration: 0.12)) { dropTargetPath = path }
                                },
                                onDropExited: {
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        if dropTargetPath == path { dropTargetPath = nil }
                                    }
                                }
                            )
                        }

                        // Drop zone after last row — allows moving an item to the end
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .contentShape(Rectangle())
                            .overlay(alignment: .top) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                                    .opacity(isEndZoneTargeted ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.1), value: isEndZoneTargeted)
                            }
                            .onDrop(
                                of: [.plainText],
                                isTargeted: Binding(
                                    get: { isEndZoneTargeted },
                                    set: { newValue in withAnimation(.easeInOut(duration: 0.12)) { isEndZoneTargeted = newValue } }
                                )
                            ) { providers in
                                providers.first?.loadObject(ofClass: NSString.self) { item, _ in
                                    guard let src = item as? String else { return }
                                    DispatchQueue.main.async {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            if let fromIndex = settingsService.repoPaths.firstIndex(of: src) {
                                                settingsService.moveRepo(
                                                    fromOffsets: IndexSet(integer: fromIndex),
                                                    toOffset: settingsService.repoPaths.count
                                                )
                                            }
                                            draggingPath = nil
                                            isEndZoneTargeted = false
                                        }
                                    }
                                }
                                return true
                            }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    // Safety net: clear drag state if drop lands outside all drop targets
                    .onDrop(of: [.plainText], isTargeted: nil) { _ in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            draggingPath = nil
                            dropTargetPath = nil
                        }
                        return false
                    }
                    // Safety net: reset dim if drag is cancelled (Escape / drop outside window)
                    .task(id: draggingPath) {
                        guard draggingPath != nil else { return }
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation(.easeInOut(duration: 0.15)) { draggingPath = nil }
                    }
                }
            }

            Spacer()

            Divider().opacity(0.5)
            bottomBar
        }
        .frame(width: 440, height: 500)
        .alert("Not a Git Repository", isPresented: $showInvalidAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The selected folder is not a git repository.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No repositories added")
                .font(.system(size: 14, weight: .medium))
            Text("Click + to add a git repository")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomBar: some View {
        BottomBar(onSettings: onShowSettings)
    }

    private func addRepo() {
        guard let path = openRepoPicker() else { return }
        Task {
            if await gitService.isGitRepo(path) {
                settingsService.addRepo(path)
            } else {
                showInvalidAlert = true
            }
        }
    }

    private func handleDrop(_ sourcePath: String, onto targetPath: String) {
        guard sourcePath != targetPath,
              let fromIndex = settingsService.repoPaths.firstIndex(of: sourcePath),
              let toIndex = settingsService.repoPaths.firstIndex(of: targetPath)
        else { return }
        settingsService.moveRepo(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
    }
}

// MARK: - Repo Row

private struct RepoRow: View {
    let path: String
    let isSelected: Bool
    let isDragging: Bool
    let isDropTarget: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onDragStarted: () -> Void
    let onDrop: (String) -> Void
    let onDropEntered: () -> Void
    let onDropExited: () -> Void
    @State private var isHovered = false

    var repoName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var shortPath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                    .frame(width: 30, height: 30)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(repoName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(shortPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
            }

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Remove repository")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else if isSelected {
                Spacer().frame(width: 20)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.04) : (isSelected ? Color.accentColor.opacity(0.05) : Color.clear))
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(height: 2)
                .opacity(isDropTarget ? 1 : 0)
                .animation(.easeInOut(duration: 0.1), value: isDropTarget)
        }
        .opacity(isDragging ? 0.35 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
        .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { isHovered = h } }
        .onDrag {
            onDragStarted()
            return NSItemProvider(object: path as NSString)
        }
        .onDrop(
            of: [.plainText],
            isTargeted: Binding(
                get: { isDropTarget },
                set: { isTarget in if isTarget { onDropEntered() } else { onDropExited() } }
            )
        ) { providers in
            providers.first?.loadObject(ofClass: NSString.self) { item, _ in
                guard let src = item as? String else { return }
                DispatchQueue.main.async { onDrop(src) }
            }
            return true
        }
    }
}
