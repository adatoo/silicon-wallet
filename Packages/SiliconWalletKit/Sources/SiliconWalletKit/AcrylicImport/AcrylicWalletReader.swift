import Foundation
import SQLite3

/// Read-only access to a decrypted Acrylic Wallet 3.5 vault.
///
/// Opens the decrypted bytes with `sqlite3_deserialize`, so the plaintext is only ever held
/// in process memory, never written to disk (DESIGN.md §5). Closing the reader frees it.
public final class AcrylicWalletReader {
    private let db: OpaquePointer

    /// Decrypts `ciphertext` with `password`, opens it as SQLite and confirms
    /// `PRAGMA integrity_check` passes before returning.
    public init(ciphertext: Data, password: String) throws {
        let plaintext = try AcrylicWalletFile.decrypt(ciphertext, password: password)
        db = try Self.openInMemory(plaintext)
        try Self.checkIntegrity(db)
    }

    deinit {
        sqlite3_close(db)
    }

    public func groups() throws -> [AcrylicGroup] {
        try rows(of: "SELECT * FROM groups ORDER BY \"order\"") { row in
            AcrylicGroup(
                id: row.int64("pk"),
                title: row.text("title") ?? "",
                icon: row.text("icon"),
                order: row.int64("order"),
                uuid: row.text("uuid") ?? "",
                defaultHeadersArchive: row.blob("defaultheaders"),
                lastUpdated: row.text("datelastupdated")
            )
        }
    }

    public func entries() throws -> [AcrylicEntry] {
        try rows(of: "SELECT * FROM entries ORDER BY pk") { row in
            AcrylicEntry(
                id: row.int64("pk"),
                title: row.text("title") ?? "",
                parentGroupUUID: row.text("parent"),
                notes: row.text("notes") ?? "",
                fieldValues: AcrylicPropertyListText.parseFlatStringDictionary(row.text("infodictionary") ?? ""),
                extraHeadersText: row.isText("extraheaders") ? row.text("extraheaders") : nil,
                extraHeadersArchive: row.isText("extraheaders") ? nil : row.blob("extraheaders"),
                isStarred: row.int64("star") != 0,
                uuid: row.text("uuid") ?? "",
                fileUUIDs: AcrylicPropertyListText.quotedStrings(afterEqualsIn: row.text("files") ?? ""),
                lastUpdated: row.text("datelastupdated")
            )
        }
    }

    public func files() throws -> [AcrylicFile] {
        try rows(of: "SELECT * FROM files ORDER BY pk") { row in
            AcrylicFile(
                id: row.int64("pk"),
                uuid: row.text("uuid") ?? "",
                name: row.text("name") ?? "",
                size: row.int64("size"),
                type: row.text("type"),
                data: row.blob("data") ?? Data()
            )
        }
    }

    // MARK: - SQLite plumbing

    private static func openInMemory(_ data: Data) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
            let db
        else {
            throw AcrylicWalletError.corruptDatabase
        }

        guard let buffer = sqlite3_malloc64(UInt64(data.count)) else {
            sqlite3_close(db)
            throw AcrylicWalletError.corruptDatabase
        }
        data.withUnsafeBytes { raw in
            buffer.copyMemory(from: raw.baseAddress!, byteCount: data.count)
        }

        let size = sqlite3_int64(data.count)
        let flags = UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_READONLY)
        let deserializeStatus = buffer.withMemoryRebound(to: UInt8.self, capacity: data.count) { typed in
            sqlite3_deserialize(db, "main", typed, size, size, flags)
        }
        guard deserializeStatus == SQLITE_OK else {
            sqlite3_close(db)
            throw AcrylicWalletError.corruptDatabase
        }
        return db
    }

    private static func checkIntegrity(_ db: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else {
            throw AcrylicWalletError.corruptDatabase
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
            let cString = sqlite3_column_text(statement, 0),
            String(cString: cString) == "ok"
        else {
            throw AcrylicWalletError.corruptDatabase
        }
    }

    private func rows<T>(of sql: String, map: (Row) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw AcrylicWalletError.corruptDatabase
        }
        defer { sqlite3_finalize(statement) }

        var columnIndexByName: [String: Int32] = [:]
        let columnCount = sqlite3_column_count(statement)
        for index in 0..<columnCount {
            if let name = sqlite3_column_name(statement, index) {
                columnIndexByName[String(cString: name)] = index
            }
        }

        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(map(Row(statement: statement, columnIndexByName: columnIndexByName)))
        }
        return results
    }

    /// One result row, read by column name so column order in the table never matters.
    private struct Row {
        let statement: OpaquePointer?
        let columnIndexByName: [String: Int32]

        func int64(_ column: String) -> Int64 {
            guard let index = columnIndexByName[column] else { return 0 }
            return sqlite3_column_int64(statement, index)
        }

        func isText(_ column: String) -> Bool {
            guard let index = columnIndexByName[column] else { return false }
            return sqlite3_column_type(statement, index) == SQLITE_TEXT
        }

        func text(_ column: String) -> String? {
            guard let index = columnIndexByName[column], sqlite3_column_type(statement, index) != SQLITE_NULL,
                let cString = sqlite3_column_text(statement, index)
            else {
                return nil
            }
            return String(cString: cString)
        }

        func blob(_ column: String) -> Data? {
            guard let index = columnIndexByName[column], sqlite3_column_type(statement, index) != SQLITE_NULL
            else {
                return nil
            }
            let length = Int(sqlite3_column_bytes(statement, index))
            guard length > 0, let bytes = sqlite3_column_blob(statement, index) else {
                return length == 0 ? Data() : nil
            }
            return Data(bytes: bytes, count: length)
        }
    }
}
