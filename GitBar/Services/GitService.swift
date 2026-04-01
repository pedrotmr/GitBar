import Foundation
import Observation

@MainActor
@Observable
class GitService {
    var repoPath: String = "" {
        didSet { setupWatcher() }
    }
    var branches: [Branch] = []
    var worktrees: [Worktree] = []
    var stashes: [Stash] = []
    var pullRequests: [PullRequest] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var isDirty = false
    var isPopoverVisible = false {
        didSet { if isPopoverVisible { Task { await refreshIfNeeded() } } }
    }
    var autoFetchEnabled = false {
        didSet { autoFetchEnabled ? startFetchTimer() : stopFetchTimer() }
    }

    private var watcher: GitRepositoryWatcher?
    private var fetchTimer: Timer?

    func refresh() async {
        guard !repoPath.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        await fetchBranches()
        await fetchWorktrees()
        await fetchStashes()
        await fetchPullRequests()
        isLoading = false
    }

    private func runGit(_ args: [String], at path: String? = nil) async -> ShellResult {
        let executionPath = path ?? self.repoPath
        return await Task.detached {
            ShellExecutor.run(args, at: executionPath)
        }.value
    }

    private func runGH(_ args: [String]) async -> ShellResult {
        let path = self.repoPath
        return await Task.detached {
            ShellExecutor.run("gh", args, at: path)
        }.value
    }

    func fetchBranches() async {
        let result = await runGit(["branch", "--format=%(refname:short) %(HEAD)"])
        guard result.exitCode == 0 else {
            errorMessage = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        branches = result.stdout
            .split(separator: "\n")
            .compactMap { line -> Branch? in
                let parts = line.split(separator: " ", maxSplits: 1)
                guard let namePart = parts.first else { return nil }
                let isCurrent = parts.count == 2 && parts[1] == "*"
                return Branch(name: String(namePart), isCurrent: isCurrent)
            }
    }

    func fetchWorktrees() async {
        let result = await runGit(["worktree", "list", "--porcelain"])
        guard result.exitCode == 0 else {
            errorMessage = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }

        var parsed: [Worktree] = []
        var isFirst = true
        let stanzas = result.stdout.components(separatedBy: "\n\n")
        for stanza in stanzas {
            let lines = stanza.split(separator: "\n").map(String.init)
            guard !lines.isEmpty else { continue }
            var worktreePath: String?
            var branch: String?
            var commit: String?
            var isBare = false

            for line in lines {
                if line.hasPrefix("worktree ") {
                    worktreePath = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    commit = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch refs/heads/") {
                    branch = String(line.dropFirst("branch refs/heads/".count))
                } else if line == "bare" {
                    isBare = true
                }
            }

            if let p = worktreePath {
                parsed.append(Worktree(
                    path: p,
                    branch: branch,
                    commitHash: commit,
                    isBare: isBare,
                    isMain: isFirst
                ))
                isFirst = false
            }
        }
        worktrees = parsed
    }

    func fetchStashes() async {
        let result = await runGit(["stash", "list", "--format=%gd%x1f%gs"])
        guard result.exitCode == 0 else {
            errorMessage = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }

        stashes = result.stdout
            .split(separator: "\n")
            .compactMap { line -> Stash? in
                let parts = line.split(separator: "\u{1f}", maxSplits: 1).map(String.init)
                guard let ref = parts.first, !ref.isEmpty else { return nil }
                let message = parts.count == 2 ? parts[1] : ""
                return Stash(ref: ref, message: message)
            }
    }

    func fetchPullRequests() async {
        // Resolve GitHub owner/repo from git remote
        let remoteResult = await runGit(["remote", "get-url", "origin"])
        guard remoteResult.exitCode == 0,
              let ownerRepo = parseGitHubOwnerRepo(from: remoteResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            pullRequests = []
            return
        }

        // Get authenticated GitHub username
        let userResult = await runGH(["api", "user", "--jq", ".login"])
        guard userResult.exitCode == 0 else {
            pullRequests = []
            return
        }
        let username = userResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            pullRequests = []
            return
        }

        // Fetch open PRs
        let prResult = await runGH([
            "pr", "list",
            "--repo", ownerRepo,
            "--state", "open",
            "--json", "number,title,headRefName,url,author,assignees,reviewRequests",
            "--limit", "100"
        ])
        guard prResult.exitCode == 0,
              let data = prResult.stdout.data(using: .utf8)
        else {
            pullRequests = []
            return
        }

        struct GHUser: Codable { let login: String }
        struct GHReviewRequest: Codable {
            let requestedReviewer: GHUser?
            enum CodingKeys: String, CodingKey { case requestedReviewer }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                requestedReviewer = try? container.decodeIfPresent(GHUser.self, forKey: .requestedReviewer)
            }
        }
        struct GHPRResponse: Codable {
            let number: Int
            let title: String
            let headRefName: String
            let url: String
            let author: GHUser
            let assignees: [GHUser]
            let reviewRequests: [GHReviewRequest]
        }

        let raw: [GHPRResponse]
        do {
            raw = try JSONDecoder().decode([GHPRResponse].self, from: data)
        } catch {
            errorMessage = "Failed to parse PRs: \(error.localizedDescription)"
            pullRequests = []
            return
        }

        // Fetch review-requested PRs using GitHub's server-side search, which handles
        // team review requests (not just individual ones)
        struct GHPRSimple: Codable { let number: Int }
        let reviewReqResult = await runGH([
            "pr", "list",
            "--repo", ownerRepo,
            "--state", "open",
            "--search", "review-requested:@me",
            "--json", "number",
            "--limit", "500"
        ])
        var reviewRequestedNumbers = Set<Int>()
        if reviewReqResult.exitCode == 0,
           let reviewData = reviewReqResult.stdout.data(using: .utf8) {
            do {
                let reviewRaw = try JSONDecoder().decode([GHPRSimple].self, from: reviewData)
                reviewRequestedNumbers = Set(reviewRaw.map(\.number))
            } catch {
                print("[GitBar] Failed to parse team review requests: \(error.localizedDescription)")
            }
        } else if reviewReqResult.exitCode != 0 {
            print("[GitBar] Failed to fetch team review requests (exit \(reviewReqResult.exitCode)): \(reviewReqResult.stderr)")
        }

        var created = [PullRequest]()
        var assigned = [PullRequest]()
        var reviewRequested = [PullRequest]()

        for pr in raw {
            if pr.author.login == username {
                created.append(PullRequest(number: pr.number, title: pr.title, headRefName: pr.headRefName, url: pr.url, category: .created))
            } else if pr.assignees.contains(where: { $0.login == username }) {
                assigned.append(PullRequest(number: pr.number, title: pr.title, headRefName: pr.headRefName, url: pr.url, category: .assigned))
            } else if pr.reviewRequests.contains(where: { $0.requestedReviewer?.login == username })
                        || reviewRequestedNumbers.contains(pr.number) {
                reviewRequested.append(PullRequest(number: pr.number, title: pr.title, headRefName: pr.headRefName, url: pr.url, category: .reviewRequested))
            }
        }

        pullRequests = created + assigned + reviewRequested
    }

    private func parseGitHubOwnerRepo(from remoteURL: String) -> String? {
        let raw: String?
        if remoteURL.hasPrefix("git@github.com:") {
            raw = String(remoteURL.dropFirst("git@github.com:".count))
        } else if let range = remoteURL.range(of: "github.com/") {
            raw = String(remoteURL[range.upperBound...])
        } else {
            return nil
        }
        guard var path = raw else { return nil }
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        return path.isEmpty ? nil : path
    }

    func checkoutPRBranch(_ pr: PullRequest) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let fetchResult = await runGit(["fetch", "origin", pr.headRefName])
        guard fetchResult.exitCode == 0 else {
            errorMessage = fetchResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        let checkoutResult = await runGit(["checkout", pr.headRefName])
        if checkoutResult.exitCode == 0 {
            await fetchBranches()
        } else {
            errorMessage = checkoutResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func switchBranch(_ name: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let result = await runGit(["checkout", name])
        if result.exitCode == 0 {
            await fetchBranches()
        } else {
            errorMessage = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func deleteBranch(_ name: String, force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let flag = force ? "-D" : "-d"
        let result = await runGit(["branch", flag, name])
        if result.exitCode == 0 {
            await fetchBranches()
        } else {
            errorMessage = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func deleteLocalAndRemoteBranch(_ name: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        _ = await runGit(["push", "origin", "--delete", name])
        let localResult = await runGit(["branch", "-D", name])
        if localResult.exitCode == 0 {
            await fetchBranches()
        } else {
            errorMessage = localResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func deleteWorktreeAndBranch(_ worktree: Worktree) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let removeResult = await runGit(["worktree", "remove", "--force", worktree.path])
        guard removeResult.exitCode == 0 else {
            errorMessage = removeResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        if let branch = worktree.branch {
            let deleteResult = await runGit(["branch", "-D", branch])
            guard deleteResult.exitCode == 0 else {
                errorMessage = deleteResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
        }
        await refresh()
    }

    func applyStash(_ ref: String) async {
        await runStashCommand("apply", ref: ref)
    }

    func popStash(_ ref: String) async {
        await runStashCommand("pop", ref: ref)
    }

    func dropStash(_ ref: String) async {
        await runStashCommand("drop", ref: ref)
    }

    private func runStashCommand(_ command: String, ref: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        let result = await runGit(["stash", command, ref])
        if result.exitCode == 0 {
            await refresh()
        } else {
            errorMessage = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func hasUncommittedChanges(_ path: String) async -> Bool {
        let result = await runGit(["status", "--porcelain"], at: path)
        return result.exitCode == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isGitRepo(_ path: String) async -> Bool {
        let result = await runGit(["rev-parse", "--is-inside-work-tree"], at: path)
        return result.exitCode == 0
    }

    func refreshIfNeeded() async {
        guard isDirty else { return }
        isDirty = false
        await refresh()
    }

    private func setupWatcher() {
        watcher?.stop()
        guard !repoPath.isEmpty else { watcher = nil; return }
        watcher = GitRepositoryWatcher { [weak self] in
            guard let self else { return }
            self.isDirty = true
        }
        watcher?.start(repoPath: repoPath)
    }

    private func startFetchTimer() {
        stopFetchTimer()
        fetchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.performFetch() }
        }
    }

    private func stopFetchTimer() {
        fetchTimer?.invalidate()
        fetchTimer = nil
    }

    private func performFetch() async {
        guard !repoPath.isEmpty else { return }
        let result = await runGit(["fetch", "--all", "--quiet"])
        guard result.exitCode == 0 else {
            let errorOutput = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = "Auto-fetch failed: \(errorOutput.isEmpty ? "Unknown error (exit code \(result.exitCode))" : errorOutput)"
            return
        }
        if isPopoverVisible { await refresh() } else { isDirty = true }
    }
}
