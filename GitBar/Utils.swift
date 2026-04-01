import AppKit

func openRepoPicker() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Add Repository"
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url.path
}
