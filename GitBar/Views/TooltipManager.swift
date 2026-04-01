import AppKit
import SwiftUI

// MARK: - Tooltip content

private struct TooltipContent: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(white: 0.1, opacity: 0.92))
            )
            .fixedSize()
    }
}

// MARK: - View modifier

private struct CustomTooltip: ViewModifier {
    let text: String
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering, !text.isEmpty {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        TooltipManager.shared.show(text)
                    }
                } else {
                    TooltipManager.shared.hide()
                }
            }
            .onDisappear {
                hoverTask?.cancel()
                TooltipManager.shared.hide()
            }
    }
}

extension View {
    func customTooltip(_ text: String) -> some View {
        modifier(CustomTooltip(text: text))
    }
}

// MARK: - Manager

@MainActor
final class TooltipManager {
    static let shared = TooltipManager()
    private var window: NSWindow?

    private init() {}

    func show(_ text: String) {
        let mousePos = NSEvent.mouseLocation

        let hosting = NSHostingView(rootView: TooltipContent(text: text))
        let rawSize = hosting.fittingSize
        let size = CGSize(width: max(rawSize.width, 60), height: max(rawSize.height, 24))

        if window == nil { window = makeWindow() }
        window?.contentView = hosting
        window?.setContentSize(size)

        var x = mousePos.x - size.width / 2
        var y = mousePos.y + 18

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mousePos) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            x = max(vf.minX + 4, min(x, vf.maxX - size.width - 4))
            if y + size.height > vf.maxY { y = mousePos.y - size.height - 10 }
        }

        window?.setFrameOrigin(CGPoint(x: x, y: y))
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return w
    }
}
