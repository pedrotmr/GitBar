import SwiftUI

struct SettingsView: View {
    @Binding var isShowing: Bool
    @Environment(SettingsService.self) private var settingsService
    @State private var installedTerminals: [SupportedTerminal] = []
    @State private var installedEditors: [SupportedEditor] = []
    @State private var showAutoFetchInfo = false

    var body: some View {
        @Bindable var settingsService = settingsService
        VStack(spacing: 0) {
            BackHeader(title: "Settings", action: { withAnimation { isShowing = false } })

            Divider().opacity(0.5)

            Form {
                Section("Tabs") {
                    Toggle("Show Branches", isOn: $settingsService.showBranchesTab)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                    Toggle("Show Stash", isOn: $settingsService.showStashTab)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                    Toggle("Show Worktrees", isOn: $settingsService.showWorktreeTab)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                    Toggle("Show Pull Requests", isOn: $settingsService.showPRTab)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }

                Section("Git") {
                    Toggle(isOn: $settingsService.autoFetchEnabled) {
                        HStack(spacing: 6) {
                            Text("Auto-fetch from remote")
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(showAutoFetchInfo ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.5))
                                .onHover { showAutoFetchInfo = $0 }
                                .popover(isPresented: $showAutoFetchInfo, arrowEdge: .bottom) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Auto-fetch from Remote")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Runs git fetch --all every 60 seconds in the background to keep remote tracking branches up to date.")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(12)
                                    .frame(width: 230)
                                }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }

                Section("Open With") {
                    Picker("Terminal", selection: $settingsService.preferredTerminal) {
                        ForEach(installedTerminals) { terminal in
                            Text(terminal.displayName).tag(terminal)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                    Picker("Editor", selection: $settingsService.preferredEditor) {
                        ForEach(installedEditors) { editor in
                            Text(editor.displayName).tag(editor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
        .frame(width: 440, height: 500)
        .onAppear {
            installedTerminals = AppDetector.installedTerminals()
            installedEditors = AppDetector.installedEditors()
        }
    }
}
