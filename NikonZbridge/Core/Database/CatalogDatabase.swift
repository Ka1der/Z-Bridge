import Foundation
import SQLite3

/// Статистика фотосессии
public struct SessionStats: Sendable, Codable, Hashable {
    public let framesCount: Int
    public let filesCount: Int
    public let totalBytes: Int64
    public let errorsCount: Int
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    public init(
        framesCount: Int = 0,
        filesCount: Int = 0,
        totalBytes: Int64 = 0,
        errorsCount: Int = 0
    ) {
        self.framesCount = framesCount
        self.filesCount = filesCount
        self.totalBytes = totalBytes
        self.errorsCount = errorsCount
    }
}

/// Актор персистентной базы данных каталога на базе SQLite с поддержкой WAL и версионирования схемы
public actor CatalogDatabase {
    public static let shared = CatalogDatabase()
    
    private var db: OpaquePointer?
    public let databaseURL: URL
    
    public init(customDatabaseURL: URL? = nil) {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let catalogDir = baseDir.appendingPathComponent("Catalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: catalogDir, withIntermediateDirectories: true)
        
        let fileURL = customDatabaseURL ?? catalogDir.appendingPathComponent("nikon_bridge_catalog.sqlite")
        self.databaseURL = fileURL
        
        let connection = Self.openDatabase(at: fileURL)
        Self.runMigrations(db: connection)
        self.db = connection
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    private static func openDatabase(at databaseURL: URL) -> OpaquePointer? {
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databaseURL.path, &connection, flags, nil) == SQLITE_OK {
            // Включаем WAL-режим для безопасного многопоточного параллельного чтения/записи
            sqlite3_exec(connection, "PRAGMA journal_mode = WAL;", nil, nil, nil)
            sqlite3_exec(connection, "PRAGMA foreign_keys = ON;", nil, nil, nil)
            sqlite3_exec(connection, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
            return connection
        }
        return nil
    }
    
    // MARK: - Версионирование схемы и миграции (Этап 3)
    
    private static func getUserVersion(db: OpaquePointer?) -> Int32 {
        var version: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = sqlite3_column_int(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)
        return version
    }
    
    private static func setUserVersion(_ version: Int32, db: OpaquePointer?) {
        let sql = "PRAGMA user_version = \(version);"
        sqlite3_exec(db, sql, nil, nil, nil)
    }
    
    private static func runMigrations(db: OpaquePointer?) {
        let currentVersion = getUserVersion(db: db)
        
        if currentVersion < 1 {
            // Миграция v1: создание основных таблиц и индексов
            let schemaSQL = """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                folder_path TEXT NOT NULL,
                is_closed INTEGER NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 0,
                author TEXT,
                copyright TEXT,
                comment TEXT
            );

            CREATE TABLE IF NOT EXISTS assets (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                filename TEXT NOT NULL,
                file_path TEXT NOT NULL,
                format TEXT NOT NULL,
                file_size INTEGER NOT NULL,
                sha256_checksum TEXT,
                verification_status TEXT NOT NULL,
                received_at REAL NOT NULL,
                transfer_duration REAL NOT NULL,
                camera_model TEXT,
                lens_model TEXT,
                exposure_time REAL,
                f_number REAL,
                iso INTEGER,
                focal_length REAL,
                capture_date REAL,
                is_missing INTEGER NOT NULL DEFAULT 0,
                rating INTEGER NOT NULL DEFAULT 0,
                pick_status INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS transfer_jobs (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                source_id TEXT NOT NULL,
                source_model TEXT,
                transport_type TEXT NOT NULL,
                source_file_id TEXT NOT NULL,
                destination_path TEXT NOT NULL,
                state TEXT NOT NULL,
                progress REAL NOT NULL,
                transferred_bytes INTEGER NOT NULL,
                total_bytes INTEGER,
                attempts INTEGER NOT NULL,
                error_message TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_assets_session ON assets(session_id);
            CREATE INDEX IF NOT EXISTS idx_assets_filename ON assets(filename);
            CREATE INDEX IF NOT EXISTS idx_assets_rating ON assets(rating);
            CREATE INDEX IF NOT EXISTS idx_assets_pick_status ON assets(pick_status);
            CREATE INDEX IF NOT EXISTS idx_jobs_session ON transfer_jobs(session_id);
            """
            
            if sqlite3_exec(db, schemaSQL, nil, nil, nil) == SQLITE_OK {
                setUserVersion(3, db: db)
            }
        } else {
            if currentVersion < 2 {
                // Миграция v2 для существующих БД: добавление rating и pick_status
                let migrationSQL = """
                ALTER TABLE assets ADD COLUMN rating INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE assets ADD COLUMN pick_status INTEGER NOT NULL DEFAULT 0;
                CREATE INDEX IF NOT EXISTS idx_assets_rating ON assets(rating);
                CREATE INDEX IF NOT EXISTS idx_assets_pick_status ON assets(pick_status);
                """
                _ = sqlite3_exec(db, migrationSQL, nil, nil, nil)
                setUserVersion(2, db: db)
            }
            if currentVersion < 3 {
                // Миграция v3: добавление метаданных сессии (автор, копирайт, комментарий)
                let migrationV3SQL = """
                ALTER TABLE sessions ADD COLUMN author TEXT;
                ALTER TABLE sessions ADD COLUMN copyright TEXT;
                ALTER TABLE sessions ADD COLUMN comment TEXT;
                """
                _ = sqlite3_exec(db, migrationV3SQL, nil, nil, nil)
                setUserVersion(3, db: db)
            }
        }
    }
    
    // MARK: - Операции с сессиями (Sessions)
    
    public func upsertSession(_ session: CaptureSession, isActive: Bool? = nil) {
        if isActive == true || (isActive == nil && session.isActive) {
            sqlite3_exec(db, "UPDATE sessions SET is_active = 0;", nil, nil, nil)
        }
        
        let sql = """
        INSERT INTO sessions (id, name, created_at, updated_at, folder_path, is_closed, is_active, author, copyright, comment)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            updated_at = excluded.updated_at,
            folder_path = excluded.folder_path,
            is_closed = excluded.is_closed,
            is_active = COALESCE(?, is_active),
            author = excluded.author,
            copyright = excluded.copyright,
            comment = excluded.comment;
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        let idStr = session.id.uuidString
        let folderPath = session.folderURL.standardizedFileURL.path
        let activeInt: Int32 = (isActive ?? session.isActive) ? 1 : 0
        let closedInt: Int32 = session.isClosed ? 1 : 0
        
        sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (session.name as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 3, session.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 4, session.updatedAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 5, (folderPath as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 6, closedInt)
        sqlite3_bind_int(stmt, 7, activeInt)
        
        if let author = session.author {
            sqlite3_bind_text(stmt, 8, (author as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        
        if let copyright = session.copyright {
            sqlite3_bind_text(stmt, 9, (copyright as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        
        if let comment = session.comment {
            sqlite3_bind_text(stmt, 10, (comment as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 10)
        }
        
        if let activeFlag = isActive {
            sqlite3_bind_int(stmt, 11, activeFlag ? 1 : 0)
        } else {
            sqlite3_bind_null(stmt, 11)
        }
        
        sqlite3_step(stmt)
    }
    
    public func getAllSessions() -> [CaptureSession] {
        let sql = "SELECT id, name, created_at, updated_at, folder_path, is_closed, is_active, author, copyright, comment FROM sessions ORDER BY created_at DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        var list: [CaptureSession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let session = parseSession(from: stmt) {
                list.append(session)
            }
        }
        return list
    }
    
    public func getActiveSession() -> CaptureSession? {
        let sql = "SELECT id, name, created_at, updated_at, folder_path, is_closed, is_active, author, copyright, comment FROM sessions WHERE is_active = 1 ORDER BY updated_at DESC LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return parseSession(from: stmt)
        }
        return nil
    }
    
    public func setActiveSession(id: UUID) {
        let resetSQL = "UPDATE sessions SET is_active = 0;"
        sqlite3_exec(db, resetSQL, nil, nil, nil)
        
        let setSQL = "UPDATE sessions SET is_active = 1, updated_at = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, setSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, (id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    public func setSessionClosed(id: UUID, isClosed: Bool) {
        let sql = "UPDATE sessions SET is_closed = ?, updated_at = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, isClosed ? 1 : 0)
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, (id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    public func getSession(by id: UUID) -> CaptureSession? {
        let sql = "SELECT id, name, created_at, updated_at, folder_path, is_closed, is_active, author, copyright, comment FROM sessions WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return parseSession(from: stmt)
        }
        return nil
    }
    
    public func updateSessionNameAndPaths(
        id: UUID,
        newName: String,
        oldFolderPath: String,
        newFolderPath: String
    ) {
        let sessionIDStr = id.uuidString
        let cleanOldPath = (oldFolderPath as NSString).standardizingPath
        let cleanNewPath = (newFolderPath as NSString).standardizingPath
        
        // 1. Обновляем сессию в таблице sessions
        let sessionSQL = "UPDATE sessions SET name = ?, folder_path = ?, updated_at = ? WHERE id = ?;"
        var stmt1: OpaquePointer?
        if sqlite3_prepare_v2(db, sessionSQL, -1, &stmt1, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt1, 1, (newName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt1, 2, (cleanNewPath as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt1, 3, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt1, 4, (sessionIDStr as NSString).utf8String, -1, nil)
            sqlite3_step(stmt1)
        }
        sqlite3_finalize(stmt1)
        
        // 2. Обновляем пути всех ассетов сессии в таблице assets
        if cleanOldPath != cleanNewPath {
            let assetSQL = """
            UPDATE assets
            SET file_path = ? || substr(file_path, length(?) + 1)
            WHERE session_id = ? AND (file_path = ? OR file_path LIKE ? || '/%');
            """
            var stmt2: OpaquePointer?
            if sqlite3_prepare_v2(db, assetSQL, -1, &stmt2, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt2, 1, (cleanNewPath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt2, 2, (cleanOldPath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt2, 3, (sessionIDStr as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt2, 4, (cleanOldPath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt2, 5, (cleanOldPath as NSString).utf8String, -1, nil)
                sqlite3_step(stmt2)
            }
            sqlite3_finalize(stmt2)
            
            // 3. Обновляем пути назначения всех заданий сессии в таблице transfer_jobs
            let jobSQL = """
            UPDATE transfer_jobs
            SET destination_path = ? || substr(destination_path, length(?) + 1)
            WHERE session_id = ? AND (destination_path = ? OR destination_path LIKE ? || '/%');
            """
            var stmt3: OpaquePointer?
            if sqlite3_prepare_v2(db, jobSQL, -1, &stmt3, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt3, 1, (cleanNewPath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt3, 2, (cleanOldPath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt3, 3, (sessionIDStr as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt3, 4, (cleanOldPath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt3, 5, (cleanOldPath as NSString).utf8String, -1, nil)
                sqlite3_step(stmt3)
            }
            sqlite3_finalize(stmt3)
        }
    }
    
    public func updateSessionName(id: UUID, newName: String, folderPath: String) {
        let oldPath = getSession(by: id)?.folderURL.standardizedFileURL.path ?? folderPath
        updateSessionNameAndPaths(
            id: id,
            newName: newName,
            oldFolderPath: oldPath,
            newFolderPath: folderPath
        )
    }
    
    public func updateSessionMetadata(id: UUID, author: String?, copyright: String?, comment: String?) {
        let sql = "UPDATE sessions SET author = ?, copyright = ?, comment = ?, updated_at = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if let a = author {
                sqlite3_bind_text(stmt, 1, (a as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            if let c = copyright {
                sqlite3_bind_text(stmt, 2, (c as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            if let com = comment {
                sqlite3_bind_text(stmt, 3, (com as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 5, (id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    public func deleteSession(id: UUID) {
        let idStr = (id.uuidString as NSString).utf8String
        
        let delJobs = "DELETE FROM transfer_jobs WHERE session_id = ?;"
        var stmtJobs: OpaquePointer?
        if sqlite3_prepare_v2(db, delJobs, -1, &stmtJobs, nil) == SQLITE_OK {
            sqlite3_bind_text(stmtJobs, 1, idStr, -1, nil)
            sqlite3_step(stmtJobs)
        }
        sqlite3_finalize(stmtJobs)
        
        let delAssets = "DELETE FROM assets WHERE session_id = ?;"
        var stmtAssets: OpaquePointer?
        if sqlite3_prepare_v2(db, delAssets, -1, &stmtAssets, nil) == SQLITE_OK {
            sqlite3_bind_text(stmtAssets, 1, idStr, -1, nil)
            sqlite3_step(stmtAssets)
        }
        sqlite3_finalize(stmtAssets)
        
        let sql = "DELETE FROM sessions WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, idStr, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    public func getSessionStats(id: UUID) -> SessionStats {
        let idStr = id.uuidString
        var filesCount = 0
        var totalBytes: Int64 = 0
        
        let assetsSQL = "SELECT COUNT(*), COALESCE(SUM(file_size), 0) FROM assets WHERE session_id = ? AND is_missing = 0;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, assetsSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                filesCount = Int(sqlite3_column_int(stmt, 0))
                totalBytes = sqlite3_column_int64(stmt, 1)
            }
        }
        sqlite3_finalize(stmt)
        
        var errorsCount = 0
        let errorsSQL = "SELECT COUNT(*) FROM transfer_jobs WHERE session_id = ? AND (state LIKE 'failed%' OR state LIKE 'interrupted%');"
        if sqlite3_prepare_v2(db, errorsSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                errorsCount = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        // Подсчет уникальных кадров (по базовому имени)
        var framesCount = 0
        let framesSQL = "SELECT COUNT(DISTINCT substr(filename, 1, instr(filename, '.') - 1)) FROM assets WHERE session_id = ? AND is_missing = 0;"
        if sqlite3_prepare_v2(db, framesSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                framesCount = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        if framesCount == 0 && filesCount > 0 {
            framesCount = filesCount
        }
        
        return SessionStats(
            framesCount: framesCount,
            filesCount: filesCount,
            totalBytes: totalBytes,
            errorsCount: errorsCount
        )
    }
    
    private func parseSession(from stmt: OpaquePointer?) -> CaptureSession? {
        guard let stmt = stmt else { return nil }
        guard let idText = sqlite3_column_text(stmt, 0),
              let id = UUID(uuidString: String(cString: idText)),
              let nameText = sqlite3_column_text(stmt, 1),
              let pathText = sqlite3_column_text(stmt, 4) else {
            return nil
        }
        
        let name = String(cString: nameText)
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let folderPath = String(cString: pathText)
        let folderURL = URL(fileURLWithPath: folderPath)
        let isClosed = sqlite3_column_int(stmt, 5) != 0
        let isActive = sqlite3_column_int(stmt, 6) != 0
        
        let author = sqlite3_column_text(stmt, 7).map { String(cString: $0) }
        let copyright = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
        let comment = sqlite3_column_text(stmt, 9).map { String(cString: $0) }
        
        return CaptureSession(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            folderURL: folderURL,
            isClosed: isClosed,
            isActive: isActive,
            author: author,
            copyright: copyright,
            comment: comment
        )
    }
    
    // MARK: - Операции с ассетами (Assets)
    
    public func upsertAsset(_ asset: MediaAsset) {
        let sql = """
        INSERT INTO assets (
            id, session_id, filename, file_path, format, file_size, sha256_checksum,
            verification_status, received_at, transfer_duration, camera_model,
            lens_model, exposure_time, f_number, iso, focal_length, capture_date, is_missing,
            rating, pick_status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            filename = excluded.filename,
            file_path = excluded.file_path,
            file_size = excluded.file_size,
            sha256_checksum = excluded.sha256_checksum,
            verification_status = excluded.verification_status,
            is_missing = excluded.is_missing,
            rating = excluded.rating,
            pick_status = excluded.pick_status;
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        let idStr = asset.id.uuidString
        let sessionIDStr = asset.sessionID.uuidString
        let pathStr = asset.fileURL.standardizedFileURL.path
        let formatStr = asset.format.displayName
        let statusStr = asset.verificationResult.isValid ? "valid" : "corrupted"
        let missingInt: Int32 = asset.isMissing ? 1 : 0
        
        sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (sessionIDStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (asset.filename as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (pathStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (formatStr as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 6, asset.fileSize)
        
        if let checksum = asset.sha256Checksum {
            sqlite3_bind_text(stmt, 7, (checksum as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        
        sqlite3_bind_text(stmt, 8, (statusStr as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 9, asset.receivedAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 10, asset.transferDuration)
        
        if let cam = asset.metadata.cameraModel {
            sqlite3_bind_text(stmt, 11, (cam as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 11) }
        
        if let lens = asset.metadata.lensModel {
            sqlite3_bind_text(stmt, 12, (lens as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 12) }
        
        if let exp = asset.metadata.exposureTime {
            sqlite3_bind_double(stmt, 13, exp)
        } else { sqlite3_bind_null(stmt, 13) }
        
        if let fNum = asset.metadata.fNumber {
            sqlite3_bind_double(stmt, 14, fNum)
        } else { sqlite3_bind_null(stmt, 14) }
        
        if let iso = asset.metadata.iso {
            sqlite3_bind_int(stmt, 15, Int32(iso))
        } else { sqlite3_bind_null(stmt, 15) }
        
        if let focal = asset.metadata.focalLength {
            sqlite3_bind_double(stmt, 16, focal)
        } else { sqlite3_bind_null(stmt, 16) }
        
        if let cap = asset.metadata.captureDate {
            sqlite3_bind_double(stmt, 17, cap.timeIntervalSince1970)
        } else { sqlite3_bind_null(stmt, 17) }
        
        sqlite3_bind_int(stmt, 18, missingInt)
        sqlite3_bind_int(stmt, 19, Int32(asset.rating))
        sqlite3_bind_int(stmt, 20, Int32(asset.pickStatus.rawValue))
        
        sqlite3_step(stmt)
    }
    
    public func getAssets(for sessionID: UUID) -> [MediaAsset] {
        let sql = "SELECT * FROM assets WHERE session_id = ? ORDER BY received_at DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (sessionID.uuidString as NSString).utf8String, -1, nil)
        
        var list: [MediaAsset] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let asset = parseAsset(from: stmt) {
                list.append(asset)
            }
        }
        return list
    }
    
    public func getAllAssets() -> [MediaAsset] {
        let sql = "SELECT * FROM assets ORDER BY received_at DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        var list: [MediaAsset] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let asset = parseAsset(from: stmt) {
                list.append(asset)
            }
        }
        return list
    }
    
    public func markAssetMissing(id: UUID, isMissing: Bool) {
        let sql = "UPDATE assets SET is_missing = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, isMissing ? 1 : 0)
            sqlite3_bind_text(stmt, 2, (id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    public func deleteAsset(id: UUID) {
        let sql = "DELETE FROM assets WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    /// Получение множества source_file_id всех успешно завершенных переносов для сессии
    public func getImportedSourceFileIDs(for sessionID: UUID) -> Set<String> {
        let sql = "SELECT source_file_id FROM transfer_jobs WHERE session_id = ? AND state LIKE 'Завершено%';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (sessionID.uuidString as NSString).utf8String, -1, nil)
        var set = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) {
                set.insert(String(cString: text))
            }
        }
        return set
    }
    
    /// Проверка наличия сохраненного ассета с таким именем и размером в сессии
    public func hasAsset(sessionID: UUID, filename: String, fileSize: Int64) -> Bool {
        let sql = "SELECT 1 FROM assets WHERE session_id = ? AND filename = ? AND file_size = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (sessionID.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (filename as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 3, fileSize)
        return sqlite3_step(stmt) == SQLITE_ROW
    }
    
    private func parseAsset(from stmt: OpaquePointer?) -> MediaAsset? {
        guard let stmt = stmt else { return nil }
        guard let idText = sqlite3_column_text(stmt, 0),
              let id = UUID(uuidString: String(cString: idText)),
              let sessionText = sqlite3_column_text(stmt, 1),
              let sessionID = UUID(uuidString: String(cString: sessionText)),
              let filenameText = sqlite3_column_text(stmt, 2),
              let pathText = sqlite3_column_text(stmt, 3) else {
            return nil
        }
        
        let filename = String(cString: filenameText)
        let filePath = String(cString: pathText)
        let fileURL = URL(fileURLWithPath: filePath)
        let format = MediaFormat(fileExtension: fileURL.pathExtension)
        let fileSize = sqlite3_column_int64(stmt, 5)
        
        var checksum: String?
        if let checkText = sqlite3_column_text(stmt, 6) {
            checksum = String(cString: checkText)
        }
        
        let receivedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
        let duration = sqlite3_column_double(stmt, 9)
        
        var metadata = AssetMetadata()
        if let cam = sqlite3_column_text(stmt, 10) { metadata.cameraModel = String(cString: cam) }
        if let lens = sqlite3_column_text(stmt, 11) { metadata.lensModel = String(cString: lens) }
        if sqlite3_column_type(stmt, 12) != SQLITE_NULL { metadata.exposureTime = sqlite3_column_double(stmt, 12) }
        if sqlite3_column_type(stmt, 13) != SQLITE_NULL { metadata.fNumber = sqlite3_column_double(stmt, 13) }
        if sqlite3_column_type(stmt, 14) != SQLITE_NULL { metadata.iso = Int(sqlite3_column_int(stmt, 14)) }
        if sqlite3_column_type(stmt, 15) != SQLITE_NULL { metadata.focalLength = sqlite3_column_double(stmt, 15) }
        if sqlite3_column_type(stmt, 16) != SQLITE_NULL { metadata.captureDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 16)) }
        
        let isMissing = sqlite3_column_int(stmt, 17) != 0
        
        var rating = 0
        if sqlite3_column_count(stmt) > 18 && sqlite3_column_type(stmt, 18) != SQLITE_NULL {
            rating = Int(sqlite3_column_int(stmt, 18))
        }
        
        var pickStatus: PickStatus = .unflagged
        if sqlite3_column_count(stmt) > 19 && sqlite3_column_type(stmt, 19) != SQLITE_NULL {
            let val = Int(sqlite3_column_int(stmt, 19))
            pickStatus = PickStatus(rawValue: val) ?? .unflagged
        }
        
        return MediaAsset(
            id: id,
            sessionID: sessionID,
            filename: filename,
            fileURL: fileURL,
            format: format,
            fileSize: fileSize,
            metadata: metadata,
            verificationResult: .valid(checksum: checksum),
            sha256Checksum: checksum,
            isMissing: isMissing,
            receivedAt: receivedAt,
            transferDuration: duration,
            rating: rating,
            pickStatus: pickStatus
        )
    }
    
    // MARK: - Рейтинг и отбор (Этап 9)
    
    public func updateAssetRating(id: UUID, rating: Int) {
        let sql = "UPDATE assets SET rating = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(max(0, min(5, rating))))
            sqlite3_bind_text(stmt, 2, (id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    public func updateAssetPickStatus(id: UUID, status: PickStatus) {
        let sql = "UPDATE assets SET pick_status = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(status.rawValue))
            sqlite3_bind_text(stmt, 2, (id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    public func batchUpdateRating(ids: [UUID], rating: Int) {
        for id in ids {
            updateAssetRating(id: id, rating: rating)
        }
    }
    
    public func batchUpdatePickStatus(ids: [UUID], status: PickStatus) {
        for id in ids {
            updateAssetPickStatus(id: id, status: status)
        }
    }
    
    // MARK: - Операции с заданиями переноса (Transfer Jobs)
    
    public func upsertJob(_ job: TransferJob) {
        let sql = """
        INSERT INTO transfer_jobs (
            id, session_id, source_id, source_model, transport_type, source_file_id,
            destination_path, state, progress, transferred_bytes, total_bytes,
            attempts, error_message, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            state = excluded.state,
            progress = excluded.progress,
            transferred_bytes = excluded.transferred_bytes,
            total_bytes = excluded.total_bytes,
            attempts = excluded.attempts,
            error_message = excluded.error_message,
            updated_at = excluded.updated_at;
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (job.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (job.sessionID.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (job.source.id as NSString).utf8String, -1, nil)
        
        if let model = job.source.model {
            sqlite3_bind_text(stmt, 4, (model as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 4) }
        
        sqlite3_bind_text(stmt, 5, (job.source.transportType.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (job.sourceFileID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, (job.destinationURL.standardizedFileURL.path as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, (job.state.label as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 9, job.progress)
        sqlite3_bind_int64(stmt, 10, job.transferredBytes)
        
        if let total = job.totalBytes {
            sqlite3_bind_int64(stmt, 11, total)
        } else { sqlite3_bind_null(stmt, 11) }
        
        sqlite3_bind_int(stmt, 12, Int32(job.attempts))
        
        if let err = job.error {
            sqlite3_bind_text(stmt, 13, (err.localizedDescription as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 13) }
        
        sqlite3_bind_double(stmt, 14, job.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 15, job.updatedAt.timeIntervalSince1970)
        
        sqlite3_step(stmt)
    }
    
    /// Восстановление прерванных заданий: при запуске приложения любые незавершенные задания
    /// переводятся в статус interrupted
    public func markIncompleteJobsInterrupted(reason: String) -> Int {
        let sql = """
        UPDATE transfer_jobs
        SET state = 'Прервано',
            error_message = ?,
            updated_at = ?
        WHERE state IN ('Ожидание', 'Выполнение', 'Проверка');
        """
        
        var stmt: OpaquePointer?
        var changed = 0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (reason as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            if sqlite3_step(stmt) == SQLITE_DONE {
                changed = Int(sqlite3_changes(db))
            }
        }
        sqlite3_finalize(stmt)
        return changed
    }
    
    public func getJob(id: UUID) -> TransferJob? {
        let sql = "SELECT * FROM transfer_jobs WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return parseJob(from: stmt)
        }
        return nil
    }
    
    public func getJobs(for sessionID: UUID) -> [TransferJob] {
        let sql = "SELECT * FROM transfer_jobs WHERE session_id = ? ORDER BY created_at DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (sessionID.uuidString as NSString).utf8String, -1, nil)
        
        var list: [TransferJob] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let job = parseJob(from: stmt) {
                list.append(job)
            }
        }
        return list
    }
    
    private func parseJob(from stmt: OpaquePointer?) -> TransferJob? {
        guard let stmt = stmt else { return nil }
        guard let idText = sqlite3_column_text(stmt, 0),
              let id = UUID(uuidString: String(cString: idText)),
              let sessionText = sqlite3_column_text(stmt, 1),
              let sessionID = UUID(uuidString: String(cString: sessionText)),
              let sourceIDText = sqlite3_column_text(stmt, 2),
              let typeText = sqlite3_column_text(stmt, 4),
              let fileIDText = sqlite3_column_text(stmt, 5),
              let destText = sqlite3_column_text(stmt, 6),
              let stateText = sqlite3_column_text(stmt, 7) else {
            return nil
        }
        
        let sourceID = String(cString: sourceIDText)
        var sourceModel: String?
        if let mod = sqlite3_column_text(stmt, 3) { sourceModel = String(cString: mod) }
        let typeStr = String(cString: typeText)
        let transportType = CameraTransportType(rawValue: typeStr) ?? .usb
        let source = CameraSource(id: sourceID, model: sourceModel, transportType: transportType)
        
        let fileID = String(cString: fileIDText)
        let destURL = URL(fileURLWithPath: String(cString: destText))
        let stateStr = String(cString: stateText)
        
        let progress = sqlite3_column_double(stmt, 8)
        let transferred = sqlite3_column_int64(stmt, 9)
        var total: Int64?
        if sqlite3_column_type(stmt, 10) != SQLITE_NULL { total = sqlite3_column_int64(stmt, 10) }
        let attempts = Int(sqlite3_column_int(stmt, 11))
        
        var error: TransferError?
        if let errText = sqlite3_column_text(stmt, 12) {
            error = .generic(String(cString: errText))
        }
        
        let state: TransferState
        switch stateStr {
        case "Завершено": state = .completed(assetID: id)
        case "Выполнение": state = .inProgress(progress: progress, bytesTransferred: transferred, totalBytes: total)
        case "Проверка": state = .verifying
        case "Прервано": state = .interrupted(reason: error?.localizedDescription ?? "Прервано")
        case "Отменено": state = .cancelled
        case "Ошибка": state = .failed(error: error ?? .generic("Ошибка"))
        default: state = .pending
        }
        
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14))
        
        return TransferJob(
            id: id,
            source: source,
            sourceFileID: fileID,
            destinationURL: destURL,
            sessionID: sessionID,
            state: state,
            progress: progress,
            transferredBytes: transferred,
            totalBytes: total,
            attempts: attempts,
            error: error,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    // MARK: - Диагностическая статистика базы данных
    
    public struct DatabaseStats: Sendable {
        public let schemaVersion: Int32
        public let totalSessions: Int
        public let totalAssets: Int
        public let journalMode: String
        public let fileSizeBytes: Int64
        public let databasePath: String
        
        public init(
            schemaVersion: Int32,
            totalSessions: Int,
            totalAssets: Int,
            journalMode: String,
            fileSizeBytes: Int64,
            databasePath: String
        ) {
            self.schemaVersion = schemaVersion
            self.totalSessions = totalSessions
            self.totalAssets = totalAssets
            self.journalMode = journalMode
            self.fileSizeBytes = fileSizeBytes
            self.databasePath = databasePath
        }
    }
    
    public func getDatabaseStats() -> DatabaseStats {
        let version = Self.getUserVersion(db: db)
        let sessionsCount = getAllSessions().count
        let assetsCount = getAllAssets().count
        var size: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: databaseURL.path),
           let fileSize = attrs[.size] as? Int64 {
            size = fileSize
        }
        return DatabaseStats(
            schemaVersion: version,
            totalSessions: sessionsCount,
            totalAssets: assetsCount,
            journalMode: "WAL",
            fileSizeBytes: size,
            databasePath: databaseURL.path
        )
    }
}

