import Foundation

struct Stash: Identifiable, Hashable {
    var id: String { ref }
    let ref: String
    let message: String
}
