import AppKit

final class ClipModel: ObservableObject {
    @Published var query = "" { didSet { refresh() } }
    @Published private(set) var clips: [Clip] = []
    @Published var selected = 0
    var onPick: ((Clip, Bool) -> Void)?
    private var generation = 0

    var current: Clip? { clips.indices.contains(selected) ? clips[selected] : nil }

    func refresh(keep: Bool = false) {
        generation += 1
        let generation = generation
        let query = query
        let keepID = keep ? current?.id : nil
        DispatchQueue.global(qos: .userInteractive).async {
            let found = Store.shared.search(query)
            DispatchQueue.main.async {
                guard generation == self.generation else { return }
                self.clips = found
                self.selected = keepID.flatMap { id in found.firstIndex { $0.id == id } } ?? 0
            }
        }
    }

    func move(_ by: Int) {
        guard !clips.isEmpty else { return }
        selected = max(0, min(clips.count - 1, selected + by))
    }

    func forget() {
        guard let clip = current else { return }
        Store.shared.delete(clip)
        clips.remove(at: selected)
        selected = min(selected, max(0, clips.count - 1))
    }

    func handle(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 125: move(1)
        case 126: move(-1)
        case 121: move(8) // page down
        case 116: move(-8) // page up
        case 36, 76: if let clip = current { onPick?(clip, !cmd) }
        case 51 where cmd: forget()
        default:
            if cmd, let ch = event.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n),
               clips.indices.contains(n - 1) {
                onPick?(clips[n - 1], true)
                return true
            }
            return false
        }
        return true
    }
}

final class EmojiModel: ObservableObject {
    static let columns = 10

    @Published var query = "" { didSet { refresh() } }
    @Published private(set) var results: [Emoji] = []
    @Published var selected = 0
    var onPick: ((Emoji, Bool) -> Void)?
    private lazy var all = Emoji.load()

    var current: Emoji? { results.indices.contains(selected) ? results[selected] : nil }

    private var recents: [String] {
        UserDefaults.standard.stringArray(forKey: "recentEmoji") ?? []
    }

    func warm() {
        _ = all
    }

    func refresh() {
        let words = query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        if words.isEmpty {
            let recent = recents
            let lookup = Dictionary(all.map { ($0.char, $0) }, uniquingKeysWith: { a, _ in a })
            let recentSet = Set(recent)
            results = recent.compactMap { lookup[$0] } + all.filter { !recentSet.contains($0.char) }
        } else {
            let recentRank = Dictionary(recents.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
            results = all.enumerated()
                .compactMap { (index, emoji) -> (Emoji, Int, Int)? in
                    var exact = 0
                    for word in words {
                        guard emoji.words.contains(where: { $0.hasPrefix(word) }) else { return nil }
                        if emoji.words.contains(word) { exact += 1 }
                    }
                    // whole-word hits first, then recently used, then unicode order
                    let rank = recentRank[emoji.char].map { $0 - 1000 } ?? index
                    return (emoji, exact, rank)
                }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
                .map(\.0)
        }
        selected = 0
    }

    func remember(_ emoji: Emoji) {
        var recent = recents.filter { $0 != emoji.char }
        recent.insert(emoji.char, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(40)), forKey: "recentEmoji")
    }

    func move(_ by: Int) {
        guard !results.isEmpty else { return }
        selected = max(0, min(results.count - 1, selected + by))
    }

    func handle(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 123: move(-1)
        case 124: move(1)
        case 125: move(Self.columns)
        case 126: move(-Self.columns)
        case 36, 76: if let emoji = current { onPick?(emoji, !cmd) }
        default: return false
        }
        return true
    }
}
