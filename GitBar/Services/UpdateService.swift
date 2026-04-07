import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UpdateService {
    private let owner = "pedrotmr"
    private let repository = "GitBar"
    private let cooldown: TimeInterval = 60 * 30

    var isChecking = false
    var isInstallingUpdate = false
    var isUpdateAvailable = false
    var latestVersion: String?
    var latestReleaseURL: URL?
    var latestDownloadURL: URL?
    var lastErrorMessage: String?

    private var lastCheckedAt: Date?

    func checkForUpdatesIfNeeded() async {
        guard shouldCheckNow else { return }
        await checkForUpdates(force: false)
    }

    func checkForUpdates(force: Bool) async {
        if !force && !shouldCheckNow { return }
        if isChecking { return }

        isChecking = true
        defer {
            isChecking = false
            lastCheckedAt = Date()
        }

        do {
            let release = try await fetchLatestRelease()
            latestVersion = release.tagName
            latestReleaseURL = release.htmlURL
            latestDownloadURL = preferredDownloadURL(from: release)
            isUpdateAvailable = isRemoteVersionNewer(release.tagName)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Failed to check for updates."
        }
    }

    func openLatestRelease() {
        guard let url = latestReleaseURL else { return }
        NSWorkspace.shared.open(url)
    }

    func installLatestUpdate() async {
        guard !isInstallingUpdate else { return }
        guard isUpdateAvailable else { return }
        guard let downloadURL = latestDownloadURL else {
            lastErrorMessage = "No downloadable update artifact found."
            openLatestRelease()
            return
        }

        isInstallingUpdate = true
        defer { isInstallingUpdate = false }

        do {
            let zipFile = try await downloadUpdateArchive(from: downloadURL)
            let extractedAppURL = try await unzipAndLocateApp(from: zipFile)
            try launchInstallerScript(newAppURL: extractedAppURL, targetAppURL: Bundle.main.bundleURL)
            NSApp.terminate(nil)
        } catch {
            lastErrorMessage = "Failed to install update automatically."
            openLatestRelease()
        }
    }

    private var shouldCheckNow: Bool {
        guard let lastCheckedAt else { return true }
        return Date().timeIntervalSince(lastCheckedAt) >= cooldown
    }

    private func fetchLatestRelease() async throws -> LatestRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest") else {
            throw UpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw UpdateError.invalidResponse
        }

        return try JSONDecoder().decode(LatestRelease.self, from: data)
    }

    private func preferredDownloadURL(from release: LatestRelease) -> URL? {
        if let named = release.assets.first(where: { asset in
            let lowerName = asset.name.lowercased()
            return lowerName.contains("gitbar") && lowerName.hasSuffix(".zip")
        }) {
            return named.browserDownloadURL
        }

        if let anyZip = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) {
            return anyZip.browserDownloadURL
        }

        return nil
    }

    private func isRemoteVersionNewer(_ remoteTag: String) -> Bool {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return false
        }
        let current = normalizedVersionParts(currentVersion)
        let remote = normalizedVersionParts(remoteTag)
        return compareVersions(lhs: remote, rhs: current) == .orderedDescending
    }

    private func normalizedVersionParts(_ rawVersion: String) -> [Int] {
        let trimmed = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        return sanitized
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    private func compareVersions(lhs: [Int], rhs: [Int]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left > right { return .orderedDescending }
            if left < right { return .orderedAscending }
        }
        return .orderedSame
    }

    private func downloadUpdateArchive(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("GitBar", forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw UpdateError.invalidResponse
        }

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitbar-update-\(UUID().uuidString).zip")
        try? FileManager.default.removeItem(at: archiveURL)
        try FileManager.default.moveItem(at: tempURL, to: archiveURL)
        return archiveURL
    }

    private func unzipAndLocateApp(from zipFileURL: URL) async throws -> URL {
        let extractionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitbar-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)

        try await runProcess(
            executablePath: "/usr/bin/ditto",
            arguments: ["-x", "-k", zipFileURL.path, extractionDirectory.path]
        )

        guard let appURL = firstAppBundle(in: extractionDirectory) else {
            throw UpdateError.missingAppBundle
        }
        return appURL
    }

    private func firstAppBundle(in directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let item = enumerator?.nextObject() as? URL {
            if item.pathExtension == "app" {
                return item
            }
        }
        return nil
    }

    private func launchInstallerScript(newAppURL: URL, targetAppURL: URL) throws {
        let targetParent = targetAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: targetParent.path) else {
            throw UpdateError.targetNotWritable
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitbar-install-\(UUID().uuidString).sh")
        let scriptContents = """
        #!/bin/zsh
        set -euo pipefail
        SOURCE='\(shellQuoted(newAppURL.path))'
        TARGET='\(shellQuoted(targetAppURL.path))'
        STAGING="$TARGET.new"
        sleep 1
        /bin/rm -rf "$STAGING"
        /usr/bin/ditto "$SOURCE" "$STAGING"
        /bin/rm -rf "$TARGET"
        /bin/mv "$STAGING" "$TARGET"
        /usr/bin/open "$TARGET"
        """
        try scriptContents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        try process.run()
    }

    private func shellQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private func runProcess(executablePath: String, arguments: [String]) async throws {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw UpdateError.processFailed
            }
        }.value
    }
}

private extension UpdateService {
    struct LatestRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum UpdateError: Error {
        case invalidURL
        case invalidResponse
        case processFailed
        case missingAppBundle
        case targetNotWritable
    }
}
