import Foundation

enum PRCategory { case created, assigned, reviewRequested }

struct PullRequest: Identifiable, Hashable {
    var id: Int { number }
    let number: Int
    let title: String
    let headRefName: String
    let url: String
    let category: PRCategory
}
