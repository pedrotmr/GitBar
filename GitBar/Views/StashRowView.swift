import SwiftUI

struct StashRowView: View {
    let stash: Stash
    @Environment(GitService.self) private var gitService
    @State private var isHovered = false
    @State private var showDropConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 30, height: 30)
                Image(systemName: "archivebox")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(stash.ref)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !stash.message.isEmpty {
                    Text(stash.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 2) {
                HoverIconButton(systemImage: "square.and.arrow.down", tooltip: "Apply stash", action: apply)
                .opacity(isHovered ? 1 : 0)

                HoverIconButton(systemImage: "square.and.arrow.down.on.square", tooltip: "Pop stash", action: pop)
                .opacity(isHovered ? 1 : 0)

                HoverIconButton(systemImage: "trash", tooltip: "Drop stash", action: requestDrop)
                .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { h in withAnimation(.easeInOut(duration: 0.1)) { isHovered = h } }
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Apply", action: apply)
            Button("Pop", action: pop)
            Divider()
            Button("Drop…", role: .destructive, action: requestDrop)
        }
        .confirmationDialog(
            "Drop stash \"\(stash.ref)\"?",
            isPresented: $showDropConfirm,
            titleVisibility: .visible
        ) {
            Button("Drop", role: .destructive) {
                Task { await gitService.dropStash(stash.ref) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func apply() {
        Task { await gitService.applyStash(stash.ref) }
    }

    private func pop() {
        Task { await gitService.popStash(stash.ref) }
    }

    private func requestDrop() {
        showDropConfirm = true
    }
}
