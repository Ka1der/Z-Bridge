import Foundation

/// Результат сверки каталога с диском
public struct ReconciliationResult: Sendable {
    public let missingAssetIDs: [UUID]
    public let orphanedFilesFound: [URL]
    public let stagingFilesCleanedCount: Int
    
    public init(
        missingAssetIDs: [UUID] = [],
        orphanedFilesFound: [URL] = [],
        stagingFilesCleanedCount: Int = 0
    ) {
        self.missingAssetIDs = missingAssetIDs
        self.orphanedFilesFound = orphanedFilesFound
        self.stagingFilesCleanedCount = stagingFilesCleanedCount
    }
}

/// Модуль сверки состояния диска с каталогом и устранения последствий аварий
public final class DiskCatalogReconciler: Sendable {
    public init() {}
    
    /// Очистка всех остаточных staging файлов (.staging/*.tmp) во всех папках сессий
    public func cleanAllStagingFiles(in sessionsRootURL: URL) -> Int {
        var cleanedCount = 0
        guard let sessions = try? FileManager.default.contentsOfDirectory(at: sessionsRootURL, includingPropertiesForKeys: nil) else {
            return 0
        }
        
        for sessionFolder in sessions {
            let stagingDir = sessionFolder.appendingPathComponent(".staging", isDirectory: true)
            guard let files = try? FileManager.default.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil) else {
                continue
            }
            for file in files where file.pathExtension == "tmp" || file.lastPathComponent.hasPrefix("transfer_") {
                if (try? FileManager.default.removeItem(at: file)) != nil {
                    cleanedCount += 1
                }
            }
        }
        return cleanedCount
    }
    
    /// Сверка зарегистрированных в каталоге ассетов с реальными файлами на диске
    public func reconcileAssetsWithDisk(knownAssets: [MediaAsset]) -> [UUID] {
        var missingIDs: [UUID] = []
        for asset in knownAssets {
            if !FileManager.default.fileExists(atPath: asset.fileURL.path) {
                missingIDs.append(asset.id)
            }
        }
        return missingIDs
    }
    
    /// Импорт существующих папок съемок из Documents/Sessions без перемещения и перезаписи
    public func discoverExistingSessionFolders(
        in sessionsRootURL: URL,
        knownSessionFolderPaths: Set<String>
    ) -> [CaptureSession] {
        var discovered: [CaptureSession] = []
        guard let folderURLs = try? FileManager.default.contentsOfDirectory(at: sessionsRootURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        
        for folderURL in folderURLs {
            // Проверяем, что это директория и не скрытая папка
            let name = folderURL.lastPathComponent
            if name.hasPrefix(".") { continue }
            
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            
            let standardizedPath = folderURL.resolvingSymlinksInPath().standardizedFileURL.path
            if !knownSessionFolderPaths.contains(standardizedPath) {
                let session = CaptureSession(
                    name: name,
                    folderURL: folderURL.resolvingSymlinksInPath().standardizedFileURL
                )
                discovered.append(session)
            }
        }
        
        return discovered
    }
    
    /// Сканирование файлов внутри папки сессии и создание MediaAsset без их перемещения
    public func discoverAssetsInSessionFolder(
        session: CaptureSession,
        knownFilePaths: Set<String>
    ) -> [MediaAsset] {
        var newAssets: [MediaAsset] = []
        guard let files = try? FileManager.default.contentsOfDirectory(at: session.folderURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return []
        }
        
        for fileURL in files {
            let filename = fileURL.lastPathComponent
            if filename.hasPrefix(".") { continue }
            
            let path = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
            if knownFilePaths.contains(path) { continue }
            
            let ext = fileURL.pathExtension.lowercased()
            let format = MediaFormat(fileExtension: ext)
            guard format.isRAW || format.isJPEG else { continue }
            
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? Int64, size > 0 else {
                continue
            }
            
            let modDate = (attrs[.modificationDate] as? Date) ?? Date()
            
            // Извлекаем EXIF
            let exif = RAWPreviewExtractor.extractEXIFMetadata(from: fileURL)
            var metadata = AssetMetadata()
            if let exifSub = exif?["{Exif}"] as? [String: Any] {
                if let shutter = exifSub["ExposureTime"] as? Double {
                    metadata.exposureTime = shutter
                }
                if let fNum = exifSub["FNumber"] as? Double {
                    metadata.fNumber = fNum
                }
                if let isos = exifSub["ISOSpeedRatings"] as? [Int], let first = isos.first {
                    metadata.iso = first
                }
            }
            if let tiff = exif?["{TIFF}"] as? [String: Any] {
                metadata.cameraModel = tiff["Model"] as? String
            }
            
            let asset = MediaAsset(
                sessionID: session.id,
                filename: filename,
                fileURL: fileURL.resolvingSymlinksInPath().standardizedFileURL,
                format: format,
                fileSize: size,
                metadata: metadata,
                verificationResult: .valid(checksum: nil),
                receivedAt: modDate,
                transferDuration: 0
            )
            newAssets.append(asset)
        }
        
        return newAssets
    }
}
