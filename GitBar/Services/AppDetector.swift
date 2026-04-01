import AppKit

enum AppDetector {
    static func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static func appURL(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    static func installedTerminals() -> [SupportedTerminal] {
        SupportedTerminal.allCases.filter { isInstalled(bundleIdentifier: $0.rawValue) }
    }

    static func installedEditors() -> [SupportedEditor] {
        SupportedEditor.allCases.filter { isInstalled(bundleIdentifier: $0.rawValue) }
    }
}
