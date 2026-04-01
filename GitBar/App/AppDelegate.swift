import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var gitService = GitService()
    private var settingsService = SettingsService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "GitBar")
            button.action = #selector(togglePopover)
            button.target = self
        }
        self.statusItem = statusItem

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environment(gitService)
                .environment(settingsService)
        )
        self.popover = popover

        if let path = settingsService.selectedRepoPath {
            gitService.repoPath = path
            Task { await gitService.refresh() }
        }
        gitService.autoFetchEnabled = settingsService.autoFetchEnabled
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
                gitService.isPopoverVisible = false
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
                gitService.isPopoverVisible = true
            }
        }
    }
}
