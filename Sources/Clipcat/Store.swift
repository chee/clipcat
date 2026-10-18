import CryptoKit
import Foundation
import SQLite3

struct Clip: Identifiable, Equatable {
    enum Kind: Int, CaseIterable { case text = 0, image = 1, file = 2, link = 3, color = 4 }

    let id: Int64
    let kind: Kind
    let body: String
    /// text found in the picture. nil until vision has looked at it.
    let vision: String?
    let labels: String
    let image: String?
    let created: Date
    let used: Date
    /// the app it was copied in
    let app: String
    let count: Int
    let pinned: Bool
}

/// what to look for. words match text and what vision saw; the rest narrow it down.
struct ClipSearch {
    var words: [String] = []
    var kinds: [Clip.Kind]?
    var app: String?
    var pinnedOnly = false
}

extension Notification.Name {
    static let clipsChanged = Notification.Name("party.chee.clipcat.clipsChanged")
}

private let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// every clip ever, in sqlite, with an fts5 index over the text and whatever vision saw.
final class Store {
    static let shared = Store()

    let imageDir: URL
    private var db: OpaquePointer?
    private let q = DispatchQueue(label: "party.chee.clipcat.store")
    private let columns = "c.id, c.kind, c.body, c.vision, c.labels, c.image, c.created, c.used, c.app, c.count, c.pinned"

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipcat", isDirectory: true)
        imageDir = base.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        let path = base.appendingPathComponent("clips.sqlite").path
        sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        sqlite3_exec(db, Self.schema, nil, nil, nil)
        // older databases. these fail harmlessly when the column is already there.
        for column in ["app TEXT NOT NULL DEFAULT ''", "count INTEGER NOT NULL DEFAULT 1", "pinned INTEGER NOT NULL DEFAULT 0",
                       "bytes INTEGER NOT NULL DEFAULT 0"] {
            sqlite3_exec(db, "ALTER TABLE clips ADD COLUMN \(column)", nil, nil, nil)
        }
    }

    private static let schema = """
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;
    CREATE TABLE IF NOT EXISTS clips (
        id INTEGER PRIMARY KEY,
        kind INTEGER NOT NULL,
        hash TEXT NOT NULL UNIQUE,
        body TEXT NOT NULL DEFAULT '',
        vision TEXT,
        labels TEXT NOT NULL DEFAULT '',
        image TEXT,
        created REAL NOT NULL,
        used REAL NOT NULL,
        app TEXT NOT NULL DEFAULT '',
        count INTEGER NOT NULL DEFAULT 1,
        pinned INTEGER NOT NULL DEFAULT 0,
        bytes INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS clips_used ON clips(used DESC);
    CREATE VIRTUAL TABLE IF NOT EXISTS clips_fts USING fts5(
        body, vision, labels,
        content = 'clips', content_rowid = 'id',
        tokenize = 'unicode61 remove_diacritics 2'
    );
    CREATE TRIGGER IF NOT EXISTS clips_ai AFTER INSERT ON clips BEGIN
        INSERT INTO clips_fts(rowid, body, vision, labels) VALUES (new.id, new.body, new.vision, new.labels);
    END;
    CREATE TRIGGER IF NOT EXISTS clips_ad AFTER DELETE ON clips BEGIN
        INSERT INTO clips_fts(clips_fts, rowid, body, vision, labels) VALUES ('delete', old.id, old.body, old.vision, old.labels);
    END;
    CREATE TRIGGER IF NOT EXISTS clips_au AFTER UPDATE OF body, vision, labels ON clips BEGIN
        INSERT INTO clips_fts(clips_fts, rowid, body, vision, labels) VALUES ('delete', old.id, old.body, old.vision, old.labels);
        INSERT INTO clips_fts(rowid, body, vision, labels) VALUES (new.id, new.body, new.vision, new.labels);
    END;
    """

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// inserts a clip, or bumps it to the top if we've seen it before.
    /// `seen` is false when vision still needs to look at it.
    @discardableResult
    func add(_ kind: Clip.Kind, body: String, image: String? = nil, bytes: Int? = nil, hash: String, app: String) -> (id: Int64, seen: Bool)? {
        q.sync { () -> (id: Int64, seen: Bool)? in
            let now = Date().timeIntervalSince1970
            var result: (id: Int64, seen: Bool)?
            self.run("""
                INSERT INTO clips (kind, hash, body, image, created, used, app, bytes) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(hash) DO UPDATE SET used = excluded.used, app = excluded.app, count = count + 1
                RETURNING id, vision IS NOT NULL
                """, [kind.rawValue, hash, body, image, now, now, app, bytes ?? body.utf8.count]) { st in
                result = (id: sqlite3_column_int64(st, 0), seen: sqlite3_column_int(st, 1) != 0)
            }
            return result
        }
    }

    func setVision(_ id: Int64, text: String, labels: String) {
        q.sync { _ = self.run("UPDATE clips SET vision = ?, labels = ? WHERE id = ?", [text, labels, id]) }
    }

    func touch(_ id: Int64) {
        q.sync { _ = self.run("UPDATE clips SET used = ? WHERE id = ?", [Date().timeIntervalSince1970, id]) }
    }

    func setPinned(_ id: Int64, _ pinned: Bool) {
        q.sync { _ = self.run("UPDATE clips SET pinned = ? WHERE id = ?", [pinned ? 1 : 0, id]) }
    }

    func delete(_ clip: Clip) {
        q.sync { _ = self.run("DELETE FROM clips WHERE id = ?", [clip.id]) }
        if let path = clip.image { try? FileManager.default.removeItem(atPath: path) }
    }

    /// one row per unpinned clip, newest first: what housekeeping needs to decide what goes
    struct Row {
        let id: Int64
        let image: String?
        let bytes: Int
        let used: Date
    }

    func rows() -> [Row] {
        q.sync { () -> [Row] in
            var out: [Row] = []
            self.run("SELECT id, image, bytes, used FROM clips WHERE pinned = 0 ORDER BY used DESC", []) { st in
                out.append(Row(
                    id: sqlite3_column_int64(st, 0),
                    image: self.optional(st, 1),
                    bytes: Int(sqlite3_column_int64(st, 2)),
                    used: Date(timeIntervalSince1970: sqlite3_column_double(st, 3))
                ))
            }
            return out
        }
    }

    /// how many clips there are, and how much room they take
    func totals() -> (count: Int, bytes: Int) {
        q.sync { () -> (count: Int, bytes: Int) in
            var result = (count: 0, bytes: 0)
            self.run("SELECT count(*), coalesce(sum(bytes), 0) FROM clips", []) { st in
                result = (count: Int(sqlite3_column_int64(st, 0)), bytes: Int(sqlite3_column_int64(st, 1)))
            }
            return result
        }
    }

    func delete(_ rows: [Row]) {
        guard !rows.isEmpty else { return }
        q.sync {
            self.run("BEGIN", [])
            for chunk in stride(from: 0, to: rows.count, by: 500).map({ rows[$0..<min($0 + 500, rows.count)] }) {
                self.run("DELETE FROM clips WHERE id IN (" + chunk.map { String($0.id) }.joined(separator: ",") + ")", [])
            }
            self.run("COMMIT", [])
        }
        for path in rows.compactMap(\.image) { try? FileManager.default.removeItem(atPath: path) }
    }

    /// gives the disk space back after a big delete
    func vacuum() {
        q.sync { _ = self.run("VACUUM", []) }
    }

    /// clips from before sizes were kept. text is measured in sql, pictures by their file.
    func measure() {
        let pictures = q.sync { () -> [(id: Int64, path: String)] in
            self.run("UPDATE clips SET bytes = length(CAST(body AS BLOB)) WHERE bytes = 0 AND kind != 1", [])
            var out: [(id: Int64, path: String)] = []
            self.run("SELECT id, image FROM clips WHERE bytes = 0 AND kind = 1 AND image IS NOT NULL", []) { st in
                out.append((id: sqlite3_column_int64(st, 0), path: self.string(st, 1)))
            }
            return out
        }
        for picture in pictures {
            let size = (try? FileManager.default.attributesOfItem(atPath: picture.path))?[.size] as? Int
            q.sync { _ = self.run("UPDATE clips SET bytes = ? WHERE id = ?", [size ?? 1, picture.id]) }
        }
    }

    /// pictures vision hasn't looked at yet (eg. the app quit mid-look)
    func unseen() -> [(id: Int64, path: String)] {
        q.sync { () -> [(id: Int64, path: String)] in
            var out: [(id: Int64, path: String)] = []
            self.run("SELECT id, image FROM clips WHERE kind = 1 AND vision IS NULL AND image IS NOT NULL", []) { st in
                out.append((id: sqlite3_column_int64(st, 0), path: self.string(st, 1)))
            }
            return out
        }
    }

    func search(_ search: ClipSearch, limit: Int = 400) -> [Clip] {
        var conditions: [String] = []
        var args: [Any?] = []
        if let kinds = search.kinds {
            conditions.append("c.kind IN (" + kinds.map { String($0.rawValue) }.joined(separator: ", ") + ")")
        }
        if search.pinnedOnly { conditions.append("c.pinned = 1") }
        if let app = search.app {
            conditions.append("c.app LIKE ? ESCAPE '\\'")
            args.append("%" + Self.likeEscape(app) + "%")
        }

        return q.sync { () -> [Clip] in
            func select(_ from: String, _ extra: [String], _ extraArgs: [Any?]) -> (ok: Bool, clips: [Clip]) {
                var out: [Clip] = []
                let all = extra + conditions
                let filter = all.isEmpty ? "" : "WHERE " + all.joined(separator: " AND ")
                let ok = self.run(
                    "SELECT \(self.columns) \(from) \(filter) ORDER BY c.pinned DESC, c.used DESC LIMIT ?",
                    extraArgs + args + [limit]
                ) { out.append(self.clip($0)) }
                return (ok, out)
            }

            if search.words.isEmpty { return select("FROM clips c", [], []).clips }

            // every word, as a prefix, anywhere in the text or in what vision saw
            let match = search.words.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
                .joined(separator: " ")
            let found = select("FROM clips_fts JOIN clips c ON c.id = clips_fts.rowid", ["clips_fts MATCH ?"], [match])
            if found.ok && !found.clips.isEmpty { return found.clips }

            // nothing by word prefix, try plain substring
            var extra: [String] = []
            var extraArgs: [Any?] = []
            for word in search.words {
                extra.append("(c.body LIKE ? ESCAPE '\\' OR c.vision LIKE ? ESCAPE '\\' OR c.labels LIKE ? ESCAPE '\\')")
                let like = "%" + Self.likeEscape(word) + "%"
                extraArgs += [like, like, like]
            }
            return select("FROM clips c", extra, extraArgs).clips
        }
    }

    private static func likeEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: sqlite bits

    @discardableResult
    private func run(_ sql: String, _ args: [Any?], _ row: (OpaquePointer) -> Void = { _ in }) -> Bool {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { return false }
        defer { sqlite3_finalize(st) }
        for (i, arg) in args.enumerated() {
            let n = Int32(i + 1)
            guard let arg else {
                sqlite3_bind_null(st, n)
                continue
            }
            switch arg {
            case let v as Int64: sqlite3_bind_int64(st, n, v)
            case let v as Int: sqlite3_bind_int64(st, n, Int64(v))
            case let v as Double: sqlite3_bind_double(st, n, v)
            case let v as String: sqlite3_bind_text(st, n, v, -1, TRANSIENT)
            default: sqlite3_bind_null(st, n)
            }
        }
        while true {
            let rc = sqlite3_step(st)
            if rc == SQLITE_ROW { row(st) } else { return rc == SQLITE_DONE }
        }
    }

    private func string(_ st: OpaquePointer, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(st, i) else { return "" }
        return String(cString: c)
    }

    private func optional(_ st: OpaquePointer, _ i: Int32) -> String? {
        sqlite3_column_type(st, i) == SQLITE_NULL ? nil : string(st, i)
    }

    private func clip(_ st: OpaquePointer) -> Clip {
        Clip(
            id: sqlite3_column_int64(st, 0),
            kind: Clip.Kind(rawValue: Int(sqlite3_column_int(st, 1))) ?? .text,
            body: string(st, 2),
            vision: optional(st, 3),
            labels: string(st, 4),
            image: optional(st, 5),
            created: Date(timeIntervalSince1970: sqlite3_column_double(st, 6)),
            used: Date(timeIntervalSince1970: sqlite3_column_double(st, 7)),
            app: string(st, 8),
            count: Int(sqlite3_column_int(st, 9)),
            pinned: sqlite3_column_int(st, 10) != 0
        )
    }
}

/// a "#rrggbb"-ish string, as 0...1 components
enum Hex {
    static func parse(_ string: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("#") else { return nil }
        var digits = String(t.dropFirst())
        guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count <= 4 { digits = digits.map { "\($0)\($0)" }.joined() }
        if digits.count == 6 { digits += "ff" }
        guard let v = UInt64(digits, radix: 16) else { return nil }
        func c(_ shift: UInt64) -> Double { Double((v >> shift) & 0xFF) / 255 }
        return (c(24), c(16), c(8), c(0))
    }
}
