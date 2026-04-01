import Foundation

struct Branch: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let isCurrent: Bool
}
