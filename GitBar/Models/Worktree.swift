import Foundation

struct Worktree: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let branch: String?
    let commitHash: String?
    let isBare: Bool
    let isMain: Bool

    var displayPath: String {
        let components = path.split(separator: "/").map(String.init)
        if components.count >= 2 {
            return components.suffix(2).joined(separator: "/")
        }
        return path
    }
}
