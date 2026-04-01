import SwiftUI
import AppKit

struct PullRequestRowView: View {
    let pr: PullRequest
    @Environment(GitService.self) private var gitService
    @State private var isHovered = false
    @State private var copiedMessage: String? = nil

    // 4 buttons × 22pt + 3 gaps × 2pt = 94pt — fixed so ZStack never shifts layout
    private let trailingWidth: CGFloat = 94

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 0, height: 22) // pin row height to button height
            Text("#\(pr.number)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.1)))
                .onTapGesture { copyWithFeedback("#\(pr.number)") }
                .help("Click to copy PR number")

            Text(pr.title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if isHovered {
                ZStack {
                    if let msg = copiedMessage {
                        Text(msg)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            .transition(.opacity)
                    } else {
                        HStack(spacing: 2) {
                            HoverIconButton(systemImage: "link", tooltip: "Copy title & link") {
                                copyWithFeedback("[\(pr.title)](\(pr.url))")
                            }

                            HoverIconButton(systemImage: "arrow.up.right.square", tooltip: "Open in browser") {
                                openInBrowser()
                            }

                            HoverIconButton(systemImage: "doc.on.doc", tooltip: "Copy URL") {
                                copyWithFeedback(pr.url)
                            }

                            HoverIconButton(systemImage: "arrow.trianglehead.swap", tooltip: "Checkout branch") {
                                Task { await gitService.checkoutPRBranch(pr) }
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .frame(width: trailingWidth)
                .animation(.easeInOut(duration: 0.15), value: copiedMessage == nil)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { h in withAnimation(.easeInOut(duration: 0.1)) { isHovered = h } }
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Open in Browser") { openInBrowser() }
            Button("Checkout Branch") {
                Task { await gitService.checkoutPRBranch(pr) }
            }
            Divider()
            Button("Copy Title & Link") { copyWithFeedback("[\(pr.title)](\(pr.url))") }
            Button("Copy URL") { copyWithFeedback(pr.url) }
            Button("Copy PR Number") { copyWithFeedback("#\(pr.number)") }
        }
    }

    private func openInBrowser() {
        guard let url = URL(string: pr.url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyWithFeedback(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        withAnimation { copiedMessage = "Copied!" }
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation { copiedMessage = nil }
        }
    }
}
