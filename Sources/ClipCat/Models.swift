import AppKit

/// the chips under the search bar. tab and shift-tab move between them.
enum ClipFilter: String, CaseIterable {
    case all, pinned, text, links, pictures, files, colors

    var kinds: [Clip.Kind]? {
        switch self {
        case .all, .pinned: return nil
        case .text: return [.text]
        case .links: return [.link]
        case .pictures: return [.image]
        case .files: return [.file]
        case .colors: return [.color]
        }
    }
}

enum EmojiFilter: String, CaseIterable {
    case all, recent, faces, people, nature, food, things, flags
}

final class ClipModel: ObservableObject {
    @Published var query = "" { didSet { refresh() } }
    @Published var filter = ClipFilter.all { didSet { refresh() } }
    @Published private(set) var clips: [Clip] = []
    @Published var selected = 0
    var onPick: ((Clip, Bool) -> Void)?
    private var generation = 0

    var current: Clip? { clips.indices.contains(selected) ? clips[selected] : nil }

    /// the query, with "@app" words pulled out as a filter on where it was copied
    var search: ClipSearch {
        var search = ClipSearch(kinds: filter.kinds, pinnedOnly: filter == .pinned)
        for word in query.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            if word.hasPrefix("@"), word.count > 1 {
                search.app = String(word.dropFirst())
            } else {
                search.words.append(word)
            }
        }
        return search
    }

    func refresh(keep: Bool = false) {
        generation += 1
        let generation = generation
        let search = search
        let keepID = keep ? current?.id : nil
        DispatchQueue.global(qos: .userInteractive).async {
            let found = Store.shared.search(search)
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

    func cycle(_ by: Int) {
        let all = ClipFilter.allCases
        let index = all.firstIndex(of: filter) ?? 0
        filter = all[(index + by + all.count) % all.count]
    }

    func forget() {
        guard let clip = current else { return }
        Store.shared.delete(clip)
        clips.remove(at: selected)
        selected = min(selected, max(0, clips.count - 1))
    }

    func togglePin() {
        guard let clip = current else { return }
        Store.shared.setPinned(clip.id, !clip.pinned)
        refresh(keep: true)
    }

    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        switch event.keyCode {
        case 125: move(1)
        case 126: move(-1)
        case 121: move(8) // page down
        case 116: move(-8) // page up
        case 48: cycle(flags.contains(.shift) ? -1 : 1) // tab
        case 36, 76: if let clip = current { onPick?(clip, !cmd) }
        case 51 where cmd: forget()
        case 35 where cmd: togglePin() // p
        case 31 where cmd: if let clip = current { Paster.open(clip) } // o
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
    static let columns = 9

    @Published var query = "" { didSet { refresh() } }
    @Published var filter = EmojiFilter.all { didSet { refresh() } }
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
        let recent = recents
        let recentRank = Dictionary(recent.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })

        var pool: [Emoji]
        switch filter {
        case .all: pool = all
        case .recent:
            let lookup = Dictionary(all.map { ($0.char, $0) }, uniquingKeysWith: { a, _ in a })
            pool = recent.compactMap { lookup[$0] }
        default: pool = all.filter { $0.group.rawValue == filter.rawValue }
        }

        if words.isEmpty {
            if filter == .all {
                pool = pool.filter { recentRank[$0.char] != nil }.sorted { recentRank[$0.char]! < recentRank[$1.char]! }
                    + pool.filter { recentRank[$0.char] == nil }
            }
            results = pool
        } else {
            results = pool.enumerated()
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
        UserDefaults.standard.set(Array(recent.prefix(45)), forKey: "recentEmoji")
    }

    func move(_ by: Int) {
        guard !results.isEmpty else { return }
        selected = max(0, min(results.count - 1, selected + by))
    }

    func cycle(_ by: Int) {
        let all = EmojiFilter.allCases
        let index = all.firstIndex(of: filter) ?? 0
        filter = all[(index + by + all.count) % all.count]
    }

    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        switch event.keyCode {
        case 123: move(-1)
        case 124: move(1)
        case 125: move(Self.columns)
        case 126: move(-Self.columns)
        case 48: cycle(flags.contains(.shift) ? -1 : 1)
        case 36, 76: if let emoji = current { onPick?(emoji, !cmd) }
        default: return false
        }
        return true
    }
}
