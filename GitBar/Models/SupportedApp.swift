import Foundation

enum SupportedTerminal: String, CaseIterable, Identifiable, Codable {
    case terminal = "com.apple.Terminal"
    case iterm2 = "com.googlecode.iterm2"
    case alacritty = "org.alacritty"
    case ghostty = "com.mitchellh.ghostty"
    case warp = "dev.warp.Warp-Stable"
    case wezterm = "com.github.wez.wezterm"
    case cmux = "com.cmuxterm.app"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm2: return "iTerm2"
        case .alacritty: return "Alacritty"
        case .ghostty: return "Ghostty"
        case .warp: return "Warp"
        case .wezterm: return "WezTerm"
        case .cmux: return "cmux"
        }
    }
}

enum SupportedEditor: String, CaseIterable, Identifiable, Codable {
    case vscode = "com.microsoft.VSCode"
    case cursor = "com.todesktop.230313mzl4w4u92"
    case zed = "dev.zed.Zed"
    case webstorm = "com.jetbrains.webstorm"
    case antigravity = "com.google.Antigravity"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vscode: return "VS Code"
        case .cursor: return "Cursor"
        case .zed: return "Zed"
        case .webstorm: return "WebStorm"
        case .antigravity: return "Google Antigravity"
        }
    }
}
