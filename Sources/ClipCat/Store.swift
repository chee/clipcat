import CryptoKit
import Foundation
import SQLite3

struct Clip: Identifiable, Equatable {
    enum Kind: Int { case text = 0, image = 1, file = 2 }

    let id: Int64
    let kind: Kind
    let body: String
    /// text found in the picture. nil until vision has looked at it.
    let vision: String?
    let labels: String
    let image: String?
    let created: Date
    let used: Date
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
    private let columns = "c.id, c.kind, c.body, c.vision, c.labels, c.image, c.created, c.used"

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipCat", isDirectory: true)
        imageDir = base.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        let path = base.appendingPathComponent("clips.sqlite").path
        sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        sqlite3_exec(db, Self.schema, nil, nil, nil)
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
        used REAL NOT NULL
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
    func add(_ kind: Clip.Kind, body: String, image: String? = nil, hash: String) -> (id: Int64, seen: Bool)? {
        q.sync { () -> (id: Int64, seen: Bool)? in
            let now = Date().timeIntervalSince1970
            var result: (id: Int64, seen: Bool)?
            self.run("""
                INSERT INTO clips (kind, hash, body, image, created, used) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(hash) DO UPDATE SET used = excluded.used
                RETURNING id, vision IS NOT NULL
                """, [kind.rawValue, hash, body, image, now, now]) { st in
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

    func delete(_ clip: Clip) {
        q.sync { _ = self.run("DELETE FROM clips WHERE id = ?", [clip.id]) }
        if let path = clip.image { try? FileManager.default.removeItem(atPath: path) }
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

    func search(_ query: String, limit: Int = 400) -> [Clip] {
        q.sync { () -> [Clip] in
            var out: [Clip] = []
            let words = query.split(whereSeparator: { $0.isWhitespace })
            if words.isEmpty {
                self.run("SELECT \(self.columns) FROM clips c ORDER BY c.used DESC LIMIT ?", [limit]) { out.append(self.clip($0)) }
                return out
            }
            // every word, as a prefix, anywhere in the text or in what vision saw
            let match = words.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }.joined(separator: " ")
            let ok = self.run("""
                SELECT \(self.columns) FROM clips_fts JOIN clips c ON c.id = clips_fts.rowid
                WHERE clips_fts MATCH ? ORDER BY c.used DESC LIMIT ?
                """, [match, limit]) { out.append(self.clip($0)) }
            if ok && !out.isEmpty { return out }

            // nothing by word prefix, try plain substring
            out = []
            let escaped = query
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let like = "%" + escaped + "%"
            self.run("""
                SELECT \(self.columns) FROM clips c
                WHERE c.body LIKE ? ESCAPE '\\' OR c.vision LIKE ? ESCAPE '\\' OR c.labels LIKE ? ESCAPE '\\'
                ORDER BY c.used DESC LIMIT ?
                """, [like, like, like, limit]) { out.append(self.clip($0)) }
            return out
        }
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
            used: Date(timeIntervalSince1970: sqlite3_column_double(st, 7))
        )
    }
}
