import Foundation

struct MemoryPlaybackQueue {
    private(set) var ids: [String]
    private(set) var index: Int
    private let original: [String]
    private(set) var shuffle: Bool
    var repeatMode = 0
    var current: String { ids[index] }
    init(ids: [String], start: Int, shuffle: Bool) {
        original = ids; self.shuffle = shuffle
        if shuffle { self.ids = [ids[start]] + ids.enumerated().filter { $0.offset != start }.map(\.element).shuffled(); index = 0 }
        else { self.ids = ids; index = start }
    }
    mutating func next(automatic: Bool = false) -> String? {
        if automatic && repeatMode == 2 { return current }
        if index + 1 < ids.count { index += 1; return current }
        if repeatMode == 1 { index = 0; return current }
        return nil
    }
    mutating func previous() -> String {
        if index > 0 { index -= 1 }
        else if repeatMode == 1 { index = ids.count - 1 }
        return current
    }
    mutating func setShuffle(_ enabled: Bool) {
        guard shuffle != enabled else { return }
        let selected = current; shuffle = enabled
        if enabled { ids = [selected] + original.filter { $0 != selected }.shuffled(); index = 0 }
        else { ids = original; index = ids.firstIndex(of: selected) ?? 0 }
    }
}
