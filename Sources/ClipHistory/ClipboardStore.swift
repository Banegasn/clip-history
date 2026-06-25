import Foundation
import SQLite3
import CryptoKit

/// SQLite-backed persistent clipboard history with an LRU-style cap.
///
/// Layout: `~/Library/Application Support/ClipHistory/store.sqlite`
/// One table `items(id, kind, text, blob, thumb, hash, created_at)`.
/// - `blob`  : full payload for images (PNG); nil for text/file.
/// - `thumb` : small PNG thumbnail for images; nil otherwise.
/// - `hash`  : SHA-256 of the content, used to dedupe / move-to-top.
final class ClipboardStore {
    private var db: OpaquePointer?
    private let cap: Int

    // SQLite wants SQLITE_TRANSIENT so it copies bound text/blob buffers.
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(cap: Int = 200) {
        self.cap = cap
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("store.sqlite").path

        if sqlite3_open(path, &db) != SQLITE_OK {
            NSLog("ClipHistory: failed to open DB at \(path)")
        }
        exec("""
            CREATE TABLE IF NOT EXISTS items (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                kind       TEXT    NOT NULL,
                text       TEXT,
                blob       BLOB,
                thumb      BLOB,
                hash       TEXT    NOT NULL,
                created_at REAL    NOT NULL,
                pinned     INTEGER NOT NULL DEFAULT 0
            );
            """)
        exec("CREATE INDEX IF NOT EXISTS idx_hash ON items(hash);")
        migrate()
    }

    /// Schema upgrades for databases created by earlier versions.
    private func migrate() {
        var hasPinned = false
        if let stmt = prepare("PRAGMA table_info(items);") {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if columnText(stmt, 1) == "pinned" { hasPinned = true }
            }
            sqlite3_finalize(stmt)
        }
        if !hasPinned {
            exec("ALTER TABLE items ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;")
        }
    }

    deinit { sqlite3_close(db) }

    // MARK: - Writes

    /// Insert a new entry. If identical content already exists it is moved to the
    /// top (deleted then re-inserted) so duplicates collapse. Enforces the cap.
    @discardableResult
    func insert(kind: ClipKind, text: String?, blob: Data?, thumb: Data?) -> Bool {
        let hash = Self.contentHash(kind: kind, text: text, blob: blob)
        let now = Date().timeIntervalSince1970

        // If identical content already exists, just move it to the top — this
        // preserves its pinned state instead of dropping and re-inserting it.
        if let sel = prepare("SELECT id FROM items WHERE hash = ? LIMIT 1;") {
            bindText(sel, 1, hash)
            let exists = sqlite3_step(sel) == SQLITE_ROW
            sqlite3_finalize(sel)
            if exists {
                if let upd = prepare("UPDATE items SET created_at = ? WHERE hash = ?;") {
                    sqlite3_bind_double(upd, 1, now)
                    bindText(upd, 2, hash)
                    sqlite3_step(upd)
                    sqlite3_finalize(upd)
                }
                return true
            }
        }

        guard let stmt = prepare(
            "INSERT INTO items (kind, text, blob, thumb, hash, created_at) VALUES (?, ?, ?, ?, ?, ?);"
        ) else { return false }
        bindText(stmt, 1, kind.rawValue)
        if let text { bindText(stmt, 2, text) } else { sqlite3_bind_null(stmt, 2) }
        if let blob { bindBlob(stmt, 3, blob) } else { sqlite3_bind_null(stmt, 3) }
        if let thumb { bindBlob(stmt, 4, thumb) } else { sqlite3_bind_null(stmt, 4) }
        bindText(stmt, 5, hash)
        sqlite3_bind_double(stmt, 6, now)
        let ok = sqlite3_step(stmt) == SQLITE_DONE
        sqlite3_finalize(stmt)

        enforceCap()
        return ok
    }

    func setPinned(id: Int64, pinned: Bool) {
        guard let stmt = prepare("UPDATE items SET pinned = ? WHERE id = ?;") else { return }
        sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    func delete(id: Int64) {
        guard let stmt = prepare("DELETE FROM items WHERE id = ?;") else { return }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    func clear() {
        exec("DELETE FROM items;")
    }

    private func enforceCap() {
        // Pinned items are never evicted; the cap applies to unpinned items only.
        exec("""
            DELETE FROM items WHERE pinned = 0 AND id NOT IN (
                SELECT id FROM items WHERE pinned = 0 ORDER BY created_at DESC LIMIT \(cap)
            );
            """)
    }

    // MARK: - Reads

    /// All items newest-first, without the heavy full `blob` (thumbnails only).
    func all() -> [ClipItem] {
        guard let stmt = prepare(
            "SELECT id, kind, text, thumb, created_at, pinned FROM items ORDER BY pinned DESC, created_at DESC;"
        ) else { return [] }
        defer { sqlite3_finalize(stmt) }

        var result: [ClipItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let kind = ClipKind(rawValue: columnText(stmt, 1) ?? "text") ?? .text
            let text = columnText(stmt, 2)
            let thumb = columnBlob(stmt, 3)
            let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            let pinned = sqlite3_column_int(stmt, 5) != 0
            result.append(ClipItem(id: id, kind: kind, text: text, thumb: thumb,
                                   createdAt: created, pinned: pinned))
        }
        return result
    }

    /// The full payload (PNG) for an image item, loaded lazily at paste time.
    func fullData(for id: Int64) -> Data? {
        guard let stmt = prepare("SELECT blob FROM items WHERE id = ?;") else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return columnBlob(stmt, 0)
    }

    // MARK: - Hashing

    static func contentHash(kind: ClipKind, text: String?, blob: Data?) -> String {
        let data: Data
        switch kind {
        case .image: data = blob ?? Data()
        case .text, .file: data = Data((text ?? "").utf8)
        }
        let digest = SHA256.hash(data: data)
        return kind.rawValue + ":" + digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - SQLite helpers

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let err {
            NSLog("ClipHistory SQL error: \(String(cString: err))")
            sqlite3_free(err)
        }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("ClipHistory: prepare failed for \(sql)")
            return nil
        }
        return stmt
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
    }

    private func bindBlob(_ stmt: OpaquePointer?, _ idx: Int32, _ value: Data) {
        value.withUnsafeBytes { raw in
            _ = sqlite3_bind_blob(stmt, idx, raw.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }

    private func columnBlob(_ stmt: OpaquePointer?, _ idx: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, idx) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, idx))
        guard count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }
}
