import Foundation

enum Age: String, CaseIterable {
    case day, week, month, year

    var seconds: TimeInterval {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .year: return 365 * 86_400
        }
    }

    var label: String { "a " + rawValue }
}

enum MinSize: Int, CaseIterable {
    case any = 0, kb100 = 100_000, mb1 = 1_000_000, mb10 = 10_000_000

    var label: String {
        switch self {
        case .any: return "any size"
        case .kb100: return "100 KB"
        case .mb1: return "1 MB"
        case .mb10: return "10 MB"
        }
    }
}

/// the saved limits on history. nil is no limit.
struct Rules: Equatable {
    var keep: Age?
    var maxItems: Int?
    var maxMB: Int?

    var any: Bool { keep != nil || maxItems != nil || maxMB != nil }

    static func load() -> Rules {
        let d = UserDefaults.standard
        return Rules(
            keep: d.string(forKey: "keepFor").flatMap(Age.init(rawValue:)),
            maxItems: d.integer(forKey: "maxItems") > 0 ? d.integer(forKey: "maxItems") : nil,
            maxMB: d.integer(forKey: "maxMB") > 0 ? d.integer(forKey: "maxMB") : nil
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(keep?.rawValue, forKey: "keepFor")
        d.set(maxItems ?? 0, forKey: "maxItems")
        d.set(maxMB ?? 0, forKey: "maxMB")
    }
}

/// deletes old history. pinned clips are never touched: Store.rows() leaves them out.
enum Housekeeping {
    private static let q = DispatchQueue(label: "party.chee.clipcat.housekeeping", qos: .utility)
    private static var timer: Timer?

    /// what the rules would delete, from rows newest first
    static func doomed(_ rules: Rules, rows: [Store.Row]) -> [Store.Row] {
        guard rules.any else { return [] }
        let cutoff = rules.keep.map { Date().addingTimeInterval(-$0.seconds) }
        let maxBytes = rules.maxMB.map { $0 * 1_000_000 }
        var total = 0
        var out: [Store.Row] = []
        for (index, row) in rows.enumerated() {
            total += row.bytes
            let old = cutoff.map { row.used < $0 } ?? false
            let many = rules.maxItems.map { index >= $0 } ?? false
            let big = maxBytes.map { total > $0 } ?? false
            if old || many || big { out.append(row) }
        }
        return out
    }

    /// a one-off: older than this and at least this big
    static func cleanup(age: Age, minSize: MinSize, rows: [Store.Row]) -> [Store.Row] {
        let cutoff = Date().addingTimeInterval(-age.seconds)
        return rows.filter { $0.used < cutoff && (minSize == .any || $0.bytes >= minSize.rawValue) }
    }

    /// at launch: size up old clips, apply the rules, then again every hour
    static func start() {
        q.async { Store.shared.measure() }
        tidy()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in tidy() }
        timer?.tolerance = 600
    }

    static func tidy(then done: (() -> Void)? = nil) {
        q.async {
            let gone = doomed(Rules.load(), rows: Store.shared.rows())
            finish(gone, done)
        }
    }

    static func delete(_ rows: [Store.Row], then done: (() -> Void)? = nil) {
        q.async { finish(rows, done) }
    }

    private static func finish(_ rows: [Store.Row], _ done: (() -> Void)?) {
        if !rows.isEmpty {
            Store.shared.delete(rows)
            if rows.count > 200 { Store.shared.vacuum() }
        }
        DispatchQueue.main.async {
            if !rows.isEmpty { NotificationCenter.default.post(name: .clipsChanged, object: nil) }
            done?()
        }
    }
}

/// what the history part of settings is showing
final class HistorySettings: ObservableObject {
    /// limits being edited. they only count once saved.
    @Published var draft = Rules.load() { didSet { preview() } }
    @Published private(set) var saved = Rules.load()
    @Published private(set) var draftDeletes = 0

    @Published var cleanAge = Age.month { didSet { armed = false; preview() } }
    @Published var cleanSize = MinSize.any { didSet { armed = false; preview() } }
    @Published private(set) var cleanCount = 0
    @Published private(set) var cleanBytes = 0
    /// the delete button wants a second click
    @Published var armed = false

    @Published private(set) var count = 0
    @Published private(set) var bytes = 0
    private var rows: [Store.Row] = []

    func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let rows = Store.shared.rows()
            let totals = Store.shared.totals()
            DispatchQueue.main.async {
                self.rows = rows
                self.count = totals.count
                self.bytes = totals.bytes
                self.preview()
            }
        }
    }

    private func preview() {
        draftDeletes = draft == saved ? 0 : Housekeeping.doomed(draft, rows: rows).count
        let gone = Housekeeping.cleanup(age: cleanAge, minSize: cleanSize, rows: rows)
        cleanCount = gone.count
        cleanBytes = gone.reduce(0) { $0 + $1.bytes }
    }

    func save() {
        draft.save()
        saved = draft
        Housekeeping.tidy { [weak self] in self?.reload() }
    }

    func clean() {
        guard cleanCount > 0 else { return }
        guard armed else {
            armed = true
            return
        }
        armed = false
        let gone = Housekeeping.cleanup(age: cleanAge, minSize: cleanSize, rows: rows)
        Housekeeping.delete(gone) { [weak self] in self?.reload() }
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
