import Foundation
#if canImport(Photos)
import Photos
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif


/// Актор управления пакетным экспортом, внешними накопителями (SSD/SD) и системной медиатекой
public actor ExportManager {
    public static let shared = ExportManager()
    
    private let diskGuard: DiskSpaceGuard
    private let fileManager = FileManager.default
    private var isCancelled = false
    
    public init(diskGuard: DiskSpaceGuard = DiskSpaceGuard()) {
        self.diskGuard = diskGuard
    }
    
    // MARK: - Отмена текущей операции
    
    public func cancel() {
        self.isCancelled = true
    }
    
    // MARK: - Запуск выполнения задания экспорта
    
    public func executeJob(
        _ initialJob: ExportJob,
        onProgress: (@Sendable (ExportJob) -> Void)? = nil
    ) async -> ExportJob {
        self.isCancelled = false
        var job = initialJob
        job.state = .inProgress(progress: 0.0)
        onProgress?(job)
        
        // 1. Проверка авторизации для Photos
        if case .photoLibrary = job.destination {
            let authorized = await checkAndRequestPhotosPermission()
            if !authorized {
                let reason = "Отказано в доступе к медиатеке «Фото». Предоставьте разрешение в Настройках."
                for i in 0..<job.items.count {
                    job.items[i].status = .failed(reason: reason)
                    job.items[i].errorMessage = reason
                }
                job.state = .failed(reason: reason)
                job.result = ExportResult(totalCount: job.items.count, successCount: 0, failedCount: job.items.count, errorMessage: reason)
                job.completedAt = Date()
                onProgress?(job)
                return job
            }
        }
        
        // 2. Security-Scoped доступ для внешних каталогов и SSD
        var isSecurityScoped = false
        var targetFolderURL: URL?
        
        if let target = job.destination.targetURL {
            targetFolderURL = target
            if let bookmark = job.destination.bookmarkData {
                var isStale = false
                #if os(macOS)
                let resolveOptions: URL.BookmarkResolutionOptions = .withSecurityScope
                #else
                let resolveOptions: URL.BookmarkResolutionOptions = []
                #endif
                if let resolved = try? URL(resolvingBookmarkData: bookmark, options: resolveOptions, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    targetFolderURL = resolved
                }
            }
            
            if let folder = targetFolderURL {
                isSecurityScoped = folder.startAccessingSecurityScopedResource()
            }
        }
        
        defer {
            if isSecurityScoped, let folder = targetFolderURL {
                folder.stopAccessingSecurityScopedResource()
            }
        }
        
        // 3. Проверка доступности целевой папки и наличия свободного места
        if let folder = targetFolderURL {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
                let reason = "Целевая папка или внешний накопитель недоступен. Проверьте подключение SSD."
                for i in 0..<job.items.count {
                    job.items[i].status = .failed(reason: reason)
                    job.items[i].errorMessage = reason
                }
                job.state = .failed(reason: reason)
                job.result = ExportResult(totalCount: job.items.count, successCount: 0, failedCount: job.items.count, errorMessage: reason)
                job.completedAt = Date()
                onProgress?(job)
                return job
            }
            
            // Проверка свободного места
            let requiredBytes = job.totalBytes
            let freeBytes = diskGuard.availableFreeBytes(at: folder)
            if freeBytes < requiredBytes + diskGuard.reserveBytes {
                let freeMB = freeBytes / (1024 * 1024)
                let reqMB = (requiredBytes + diskGuard.reserveBytes) / (1024 * 1024)
                let reason = "Недостаточно свободного места на носителе (доступно \(freeMB) МБ, требуется \(reqMB) МБ)."
                for i in 0..<job.items.count {
                    job.items[i].status = .failed(reason: reason)
                    job.items[i].errorMessage = reason
                }
                job.state = .failed(reason: reason)
                job.result = ExportResult(totalCount: job.items.count, successCount: 0, failedCount: job.items.count, errorMessage: reason)
                job.completedAt = Date()
                onProgress?(job)
                return job
            }
        }
        
        // 4. Поэлементный экспорт с детализированным статусом
        var exportedURLs: [URL] = []
        var successCount = 0
        var failedCount = 0
        var skippedCount = 0
        var exportedXMPURLs: [URL] = []
        
        for i in 0..<job.items.count {
            await Task.yield()
            if isCancelled || Task.isCancelled {
                for pendingIndex in i..<job.items.count {
                    if !job.items[pendingIndex].status.isTerminal {
                        job.items[pendingIndex].status = .failed(reason: "Отменено пользователем")
                        job.items[pendingIndex].errorMessage = "Отменено пользователем"
                        failedCount += 1
                    }
                }
                isCancelled = true
                break
            }
            
            // Пропускаем уже успешные элементы (при повторах)
            if job.items[i].status.isSuccess {
                if let url = job.items[i].destinationURL {
                    exportedURLs.append(url)
                }
                successCount += 1
                continue
            }
            
            let item = job.items[i]
            
            // Проверка фильтрации по выбранным типам оригиналов (RAW only, JPEG only, оба)
            guard job.formatSelection.shouldExport(asset: item.asset) else {
                job.items[i].status = .skipped
                skippedCount += 1
                continue
            }
            
            job.items[i].status = .exporting(progress: 0.0)
            onProgress?(job)
            
            do {
                let exportedURL = try await exportSingleItem(
                    item: item,
                    destination: job.destination,
                    targetFolder: targetFolderURL,
                    conflictStrategy: job.conflictStrategy
                )
                
                if let url = exportedURL {
                    job.items[i].status = .success(destinationURL: url)
                    job.items[i].destinationURL = url
                    job.items[i].exportedBytes = item.fileSize
                    job.exportedBytes += item.fileSize
                    exportedURLs.append(url)
                    successCount += 1
                    
                    // Экспорт XMP sidecar (если включен и поддерживается целевым хранилищем)
                    if job.includeXMPSidecars {
                        if case .photoLibrary = job.destination {
                            // Медиатека «Фото» не поддерживает сторонние XMP sidecar файлы
                        } else {
                            let parentFolder = url.deletingLastPathComponent()
                            let exportedFilename = url.lastPathComponent
                            if let xmpURL = try? XMPGenerator.writeSidecar(
                                for: item.asset,
                                targetFilename: exportedFilename,
                                to: parentFolder,
                                convention: job.sidecarNamingConvention,
                                sessionMetadata: job.sessionMetadata
                            ) {
                                exportedXMPURLs.append(xmpURL)
                            }
                        }
                    }
                } else {
                    // Файл был пропущен по стратегии .skip
                    job.items[i].status = .skipped
                    skippedCount += 1
                }
            } catch {
                let isDiskDisconnected = isDriveDisconnectedError(error, targetFolder: targetFolderURL)
                let errorMessage: String
                if isDiskDisconnected {
                    errorMessage = "Внешний накопитель был отключен или извлечен"
                } else {
                    errorMessage = error.localizedDescription
                }
                
                job.items[i].status = .failed(reason: errorMessage)
                job.items[i].errorMessage = errorMessage
                failedCount += 1
                
                // Если диск отключен — отменяем все оставшиеся файлы
                if isDiskDisconnected {
                    for restIndex in (i + 1)..<job.items.count {
                        job.items[restIndex].status = .failed(reason: errorMessage)
                        job.items[restIndex].errorMessage = errorMessage
                        failedCount += 1
                    }
                    break
                }
            }
            
            job.state = .inProgress(progress: job.progressPercentage)
            onProgress?(job)
        }
        
        job.completedAt = Date()
        
        var manifestURL: URL? = nil
        var reportURL: URL? = nil
        
        // Генерация манифеста сессии и markdown-отчета
        if job.includeSessionManifest, let targetFolder = targetFolderURL {
            var fileEntries: [SessionManifestFileEntry] = []
            for item in job.items {
                let isSuccess = item.status.isSuccess
                let finalFilename = item.destinationURL?.lastPathComponent ?? item.asset.filename
                let sidecarPath: String?
                if job.includeXMPSidecars, let destURL = item.destinationURL {
                    let sidecarName = job.sidecarNamingConvention.sidecarFilename(for: destURL.lastPathComponent)
                    let sidecarCandidate = destURL.deletingLastPathComponent().appendingPathComponent(sidecarName)
                    sidecarPath = fileManager.fileExists(atPath: sidecarCandidate.path) ? sidecarCandidate.path : nil
                } else {
                    sidecarPath = nil
                }
                
                let entry = SessionManifestFileEntry(
                    filename: finalFilename,
                    format: item.asset.format.displayName,
                    fileSize: item.fileSize,
                    rating: item.asset.rating,
                    pickStatus: item.asset.pickStatus.label,
                    sha256: item.asset.sha256Checksum,
                    cameraModel: item.asset.metadata.cameraModel,
                    lensModel: item.asset.metadata.lensModel,
                    exposureSummary: item.asset.metadata.quickExposureSummary,
                    exportStatus: isSuccess ? "Успешно" : (item.errorMessage ?? "Ошибка"),
                    destinationPath: item.destinationURL?.path,
                    xmpSidecarPath: sidecarPath
                )
                fileEntries.append(entry)
            }
            
            let manifest = SessionManifest(
                session: job.sessionMetadata ?? SessionMetadata(sessionName: job.id.uuidString, sessionDate: job.createdAt),
                files: fileEntries,
                generatedAt: job.completedAt ?? Date()
            )
            
            if let jsonData = try? manifest.generateJSON() {
                let jsonTarget = targetFolder.appendingPathComponent("session_manifest.json")
                if (try? jsonData.write(to: jsonTarget, options: .atomic)) != nil {
                    manifestURL = jsonTarget
                }
            }
            
            let reportMarkdown = manifest.generateMarkdownReport()
            if let reportData = reportMarkdown.data(using: .utf8) {
                let mdTarget = targetFolder.appendingPathComponent("session_report.md")
                if (try? reportData.write(to: mdTarget, options: .atomic)) != nil {
                    reportURL = mdTarget
                }
            }
        }
        
        let result = ExportResult(
            totalCount: job.items.count,
            successCount: successCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            exportedURLs: exportedURLs,
            exportedXMPURLs: exportedXMPURLs,
            manifestURL: manifestURL,
            reportURL: reportURL,
            errorMessage: failedCount > 0 ? "Ошибок при экспорте: \(failedCount)" : nil
        )
        job.result = result
        
        if isCancelled {
            job.state = .cancelled
        } else if failedCount == 0 {
            job.state = .completed(exportedURLs: exportedURLs)
        } else if successCount > 0 {
            job.state = .failed(reason: "Экспортировано с ошибками (\(failedCount) сбоев)")
        } else {
            job.state = .failed(reason: result.errorMessage ?? "Экспорт завершился ошибкой")
        }
        
        onProgress?(job)
        return job
    }
    
    // MARK: - Повтор только неудачных операций
    
    public func retryFailed(
        in job: ExportJob,
        onProgress: (@Sendable (ExportJob) -> Void)? = nil
    ) async -> ExportJob {
        var retryJob = job
        for i in 0..<retryJob.items.count {
            if retryJob.items[i].status.isFailed {
                retryJob.items[i].status = .pending
                retryJob.items[i].errorMessage = nil
            }
        }
        return await executeJob(retryJob, onProgress: onProgress)
    }
    
    // MARK: - Экспорт одиночного элемента
    
    private func exportSingleItem(
        item: ExportItem,
        destination: ExportDestination,
        targetFolder: URL?,
        conflictStrategy: NameConflictStrategy
    ) async throws -> URL? {
        let sourceURL = item.asset.fileURL
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ExportError.sourceFileNotFound(sourceURL.lastPathComponent)
        }
        
        switch destination {
        case .directory, .externalDrive:
            guard let folder = targetFolder else {
                throw ExportError.targetFolderUnavailable
            }
            return try copyToDirectory(
                sourceURL: sourceURL,
                destinationFolder: folder,
                desiredFilename: item.filename,
                strategy: conflictStrategy
            )
            
        case .photoLibrary(let albumName):
            return try await saveToPhotoLibrary(sourceURL: sourceURL, isRAW: item.asset.isRAW, albumName: albumName)
            
        case .shareSheet:
            // Создаем временную копию для Share Sheet, гарантируя неизменность оригинала
            let tempShareDir = fileManager.temporaryDirectory.appendingPathComponent("ShareExport_\(UUID().uuidString)")
            try fileManager.createDirectory(at: tempShareDir, withIntermediateDirectories: true)
            let tempTarget = tempShareDir.appendingPathComponent(item.filename)
            try fileManager.copyItem(at: sourceURL, to: tempTarget)
            return tempTarget
        }
    }
    
    // MARK: - Копирование в целевой каталог с защитой конфликтов
    
    private func copyToDirectory(
        sourceURL: URL,
        destinationFolder: URL,
        desiredFilename: String,
        strategy: NameConflictStrategy
    ) throws -> URL? {
        let destinationURL = destinationFolder.appendingPathComponent(desiredFilename)
        
        // 1. Защита оригинала: если назначение совпадает с исходным файлом
        if isSameFile(sourceURL, destinationURL) {
            switch strategy {
            case .skip:
                return nil
            case .overwrite:
                // Файл уже находится по целевому пути. Перезапись файла самим собой
                // ни при каких обстоятельствах не должна удалять оригинал!
                return destinationURL
            case .rename:
                // При стратегии переименования создаем копию с уникальным суффиксом "имя (1).ext"
                let uniqueURL = resolveUniqueDestinationURL(destinationFolder: destinationFolder, desiredFilename: desiredFilename)
                try fileManager.copyItem(at: sourceURL, to: uniqueURL)
                return uniqueURL
            }
        }
        
        // 2. Если целевой файл уже существует (но это другой файл)
        if fileManager.fileExists(atPath: destinationURL.path) {
            switch strategy {
            case .skip:
                return nil
            case .overwrite:
                // Безопасная перезапись через временный файл, чтобы исключить потерю данных при сбое
                let tempURL = destinationFolder.appendingPathComponent(".\(desiredFilename).export_tmp_\(UUID().uuidString)")
                try fileManager.copyItem(at: sourceURL, to: tempURL)
                do {
                    _ = try? fileManager.removeItem(at: destinationURL)
                    try fileManager.moveItem(at: tempURL, to: destinationURL)
                } catch {
                    try? fileManager.removeItem(at: tempURL)
                    throw error
                }
                return destinationURL
            case .rename:
                let uniqueURL = resolveUniqueDestinationURL(destinationFolder: destinationFolder, desiredFilename: desiredFilename)
                try fileManager.copyItem(at: sourceURL, to: uniqueURL)
                return uniqueURL
            }
        } else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        }
    }
    
    private func isSameFile(_ url1: URL, _ url2: URL) -> Bool {
        let p1 = url1.standardizedFileURL.resolvingSymlinksInPath().path
        let p2 = url2.standardizedFileURL.resolvingSymlinksInPath().path
        if p1.caseInsensitiveCompare(p2) == .orderedSame {
            return true
        }
        if let res1 = try? url1.resolvingSymlinksInPath().resourceValues(forKeys: [.fileResourceIdentifierKey]),
           let res2 = try? url2.resolvingSymlinksInPath().resourceValues(forKeys: [.fileResourceIdentifierKey]),
           let id1 = res1.fileResourceIdentifier,
           let id2 = res2.fileResourceIdentifier {
            return id1.isEqual(id2)
        }
        return false
    }
    
    private func resolveUniqueDestinationURL(destinationFolder: URL, desiredFilename: String) -> URL {
        let ext = (desiredFilename as NSString).pathExtension
        let base = (desiredFilename as NSString).deletingPathExtension
        
        var counter = 1
        var candidateURL: URL
        repeat {
            let newName: String
            if ext.isEmpty {
                newName = "\(base) (\(counter))"
            } else {
                newName = "\(base) (\(counter)).\(ext)"
            }
            candidateURL = destinationFolder.appendingPathComponent(newName)
            counter += 1
        } while fileManager.fileExists(atPath: candidateURL.path)
        
        return candidateURL
    }
    
    // MARK: - Сохранение в Apple Photos
    
    /// Извлечение высококачественного JPEG-превью для прикрепления к RAW-ассету в Photos
    private func extractPreviewJPEGData(from url: URL) -> Data? {
        // 1. Попытка через RAWPreviewExtractor (максимальный размер 4096)
        if let previewImage = RAWPreviewExtractor.extractThumbnail(from: url, maxPixelSize: 4096) {
            #if canImport(UIKit)
            if let data = previewImage.jpegData(compressionQuality: 0.95) { return data }
            #elseif canImport(AppKit)
            if let tiff = previewImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .jpeg, properties: [:]) { return data }
            #endif
        }
        
        // 2. Попытка через меньший размер (1920)
        if let previewImage = RAWPreviewExtractor.extractThumbnail(from: url, maxPixelSize: 1920) {
            #if canImport(UIKit)
            if let data = previewImage.jpegData(compressionQuality: 0.90) { return data }
            #elseif canImport(AppKit)
            if let tiff = previewImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .jpeg, properties: [:]) { return data }
            #endif
        }
        
        // 3. Прямое чтение первого кадра через CGImageSource
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: false
        ]
        if let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            #if canImport(UIKit)
            let img = UIImage(cgImage: cgImage)
            if let data = img.jpegData(compressionQuality: 0.90) { return data }
            #elseif canImport(AppKit)
            let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .jpeg, properties: [:]) { return data }
            #endif
        }
        
        // 4. Гарантированный синтетический preview для предотвращения ошибки PhotoKit 3300
        return generateFallbackPreviewJPEG(for: url)
    }
    
    private func generateFallbackPreviewJPEG(for url: URL) -> Data? {
        #if canImport(UIKit)
        let size = CGSize(width: 1920, height: 1280)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(red: 18/255.0, green: 20/255.0, blue: 26/255.0, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            
            let title = "NIKON RAW (NEF)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 52, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let filename = url.lastPathComponent
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .medium),
                .foregroundColor: UIColor(white: 0.8, alpha: 1.0)
            ]
            
            title.draw(at: CGPoint(x: 120, y: size.height / 2 - 70), withAttributes: attrs)
            filename.draw(at: CGPoint(x: 120, y: size.height / 2 + 10), withAttributes: subAttrs)
        }
        return image.jpegData(compressionQuality: 0.85)
        #elseif canImport(AppKit)
        let size = NSSize(width: 1920, height: 1280)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: 18/255.0, green: 20/255.0, blue: 26/255.0, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [:])
        #else
        return nil
        #endif
    }
    
    public func saveToPhotoLibrary(
        sourceURL: URL,
        isRAW: Bool,
        albumName: String? = nil
    ) async throws -> URL {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ExportError.sourceFileNotFound(sourceURL.lastPathComponent)
        }
        
        #if canImport(Photos)
        // 1. Поиск альбома СТРОГО СНАРУЖИ performChanges (PhotoKit запрещает fetch внутри блока)
        var targetAlbum: PHAssetCollection? = nil
        var needCreateAlbum = false
        if let album = albumName, !album.isEmpty,
           PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", album)
            let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
            targetAlbum = collections.firstObject
            if targetAlbum == nil {
                needCreateAlbum = true
            }
        }
        
        // 2. Для RAW-файлов подготавливаем временный JPEG-файл превью
        var tempJPEGURL: URL? = nil
        if isRAW {
            if let jpegData = self.extractPreviewJPEGData(from: sourceURL) {
                let tempDir = fileManager.temporaryDirectory.appendingPathComponent("PhotoKitExport_\(UUID().uuidString)")
                try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tempFile = tempDir.appendingPathComponent("\(sourceURL.deletingPathExtension().lastPathComponent)_preview.jpg")
                if (try? jpegData.write(to: tempFile, options: .atomic)) != nil {
                    tempJPEGURL = tempFile
                }
            }
        }
        
        defer {
            if let temp = tempJPEGURL {
                try? fileManager.removeItem(at: temp.deletingLastPathComponent())
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var placeholder: PHObjectPlaceholder?
            
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                placeholder = request.placeholderForCreatedAsset
                
                let rawOptions = PHAssetResourceCreationOptions()
                rawOptions.shouldMoveFile = false
                
                if isRAW {
                    if let tempJPEG = tempJPEGURL {
                        // 1. Основной ресурс (.photo) — JPEG превью для быстрого рендеринга в галерее iOS
                        let photoOptions = PHAssetResourceCreationOptions()
                        photoOptions.shouldMoveFile = false
                        request.addResource(with: .photo, fileURL: tempJPEG, options: photoOptions)
                        
                        // 2. Альтернативный оригинальный RAW (.alternatePhoto) с сохранением полного динамического диапазона
                        request.addResource(with: .alternatePhoto, fileURL: sourceURL, options: rawOptions)
                    } else {
                        request.addResource(with: .photo, fileURL: sourceURL, options: rawOptions)
                    }
                } else {
                    request.addResource(with: .photo, fileURL: sourceURL, options: rawOptions)
                }
                
                // Добавление в альбом (без вызова fetch внутри блока!)
                if let target = targetAlbum, let ph = placeholder {
                    let albumChangeRequest = PHAssetCollectionChangeRequest(for: target)
                    albumChangeRequest?.addAssets([ph] as NSArray)
                } else if needCreateAlbum, let album = albumName, let ph = placeholder {
                    let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: album)
                    createAlbumRequest.addAssets([ph] as NSArray)
                }
            }) { success, error in
                if success {
                    continuation.resume(returning: sourceURL)
                } else {
                    let err = error ?? ExportError.photoLibrarySaveFailed
                    continuation.resume(throwing: err)
                }
            }
        }
        #else
        throw ExportError.photoLibraryNotSupportedOnPlatform
        #endif
    }
    
    // MARK: - Прямое сохранение в системную медиатеку «Фото»
    
    public func saveToPhotos(asset: MediaAsset, albumName: String? = nil) async throws {
        let authorized = await checkAndRequestPhotosPermission()
        guard authorized else {
            throw ExportError.photoLibraryPermissionDenied
        }
        _ = try await saveToPhotoLibrary(sourceURL: asset.fileURL, isRAW: asset.isRAW, albumName: albumName)
    }
    
    public func saveToPhotos(group: CaptureGroup, albumName: String? = nil) async throws {
        let authorized = await checkAndRequestPhotosPermission()
        guard authorized else {
            throw ExportError.photoLibraryPermissionDenied
        }
        
        // Если это парный снимок (RAW + JPEG/HEIF) и оба файла существуют на накопителе
        if let raw = group.rawAsset, let companion = group.jpegAsset ?? group.heifAsset,
           fileManager.fileExists(atPath: raw.fileURL.path),
           fileManager.fileExists(atPath: companion.fileURL.path) {
            #if canImport(Photos)
            var targetAlbum: PHAssetCollection? = nil
            var needCreateAlbum = false
            if let album = albumName, !album.isEmpty,
               PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized {
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "title = %@", album)
                let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
                targetAlbum = collections.firstObject
                if targetAlbum == nil { needCreateAlbum = true }
            }
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var placeholder: PHObjectPlaceholder?
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    placeholder = request.placeholderForCreatedAsset
                    let rawOptions = PHAssetResourceCreationOptions()
                    rawOptions.shouldMoveFile = false
                    let photoOptions = PHAssetResourceCreationOptions()
                    photoOptions.shouldMoveFile = false
                    
                    // 1. Companion JPEG/HEIF как основной .photo
                    request.addResource(with: .photo, fileURL: companion.fileURL, options: photoOptions)
                    // 2. Оригинал RAW как .alternatePhoto
                    request.addResource(with: .alternatePhoto, fileURL: raw.fileURL, options: rawOptions)
                    
                    if let target = targetAlbum, let ph = placeholder {
                        let albumChangeRequest = PHAssetCollectionChangeRequest(for: target)
                        albumChangeRequest?.addAssets([ph] as NSArray)
                    } else if needCreateAlbum, let album = albumName, let ph = placeholder {
                        let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: album)
                        createAlbumRequest.addAssets([ph] as NSArray)
                    }
                }) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? ExportError.photoLibrarySaveFailed)
                    }
                }
            }
            #else
            throw ExportError.photoLibraryNotSupportedOnPlatform
            #endif
        } else if let primary = group.primaryAsset {
            _ = try await saveToPhotoLibrary(sourceURL: primary.fileURL, isRAW: primary.isRAW, albumName: albumName)
        } else {
            throw ExportError.sourceFileNotFound(group.baseName)
        }
    }
    
    // MARK: - Проверка прав доступа к Photos
    
    #if canImport(Photos)
    nonisolated public func photosAuthorizationStatus() -> PHAuthorizationStatus {
        let addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if addStatus != .notDetermined {
            return addStatus
        }
        return PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    nonisolated public func requestPhotosAuthorization() async -> PHAuthorizationStatus {
        let addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if addStatus != .notDetermined {
            return addStatus
        }
        
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                continuation.resume(returning: newStatus)
            }
        }
    }
    #endif
    
    public func checkAndRequestPhotosPermission() async -> Bool {
        #if canImport(Photos)
        // 1. Проверяем разрешение на добавление (.addOnly) — этого достаточно для сохранения
        let addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if addStatus == .authorized || addStatus == .limited {
            return true
        }
        
        // 2. Если статус addOnly еще не определен, запрашиваем addOnly
        if addStatus == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                    continuation.resume(returning: newStatus == .authorized || newStatus == .limited)
                }
            }
            if granted { return true }
        }
        
        // 3. Фолбэк на проверку readWrite (если ранее уже было выдано полное разрешение)
        let rwStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if rwStatus == .authorized || rwStatus == .limited {
            return true
        }
        
        if rwStatus == .notDetermined {
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    continuation.resume(returning: newStatus == .authorized || newStatus == .limited)
                }
            }
        }
        
        return false
        #else
        return false
        #endif
    }
    
    // MARK: - Детекция отключения внешнего накопителя
    
    private func isDriveDisconnectedError(_ error: Error, targetFolder: URL?) -> Bool {
        if let folder = targetFolder, !fileManager.fileExists(atPath: folder.path) {
            return true
        }
        
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            // ENODEV (19) - No such device, EIO (5) - I/O error, ENOENT (2) - No such file
            if nsError.code == 19 || nsError.code == 5 || nsError.code == 2 {
                return true
            }
        }
        if nsError.domain == NSCocoaErrorDomain {
            if nsError.code == NSFileNoSuchFileError || nsError.code == NSFileWriteNoPermissionError {
                if let folder = targetFolder, !fileManager.fileExists(atPath: folder.path) {
                    return true
                }
            }
        }
        return false
    }
    
    // MARK: - Автоматическое фоновое копирование (Live Mirror)
    
    @discardableResult
    public func autoCopyAsset(
        _ asset: MediaAsset,
        destination: ExportDestination,
        formatSelection: ExportFormatSelection = .both,
        strategy: NameConflictStrategy = .rename,
        includeXMP: Bool = false,
        namingConvention: XMPSidecarNamingConvention = .standardBasename,
        sessionMetadata: SessionMetadata? = nil
    ) async throws -> URL? {
        guard formatSelection.shouldExport(asset: asset) else {
            return nil
        }
        
        guard let folder = destination.targetURL else {
            return nil
        }
        
        var isSecurityScoped = false
        if let bookmark = destination.bookmarkData {
            var isStale = false
            #if os(macOS)
            let resolveOptions: URL.BookmarkResolutionOptions = .withSecurityScope
            #else
            let resolveOptions: URL.BookmarkResolutionOptions = []
            #endif
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: resolveOptions, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                isSecurityScoped = resolved.startAccessingSecurityScopedResource()
            }
        } else {
            isSecurityScoped = folder.startAccessingSecurityScopedResource()
        }
        
        defer {
            if isSecurityScoped {
                folder.stopAccessingSecurityScopedResource()
            }
        }
        
        guard fileManager.fileExists(atPath: folder.path) else {
            throw ExportError.targetFolderUnavailable
        }
        
        let copiedURL = try copyToDirectory(
            sourceURL: asset.fileURL,
            destinationFolder: folder,
            desiredFilename: asset.filename,
            strategy: strategy
        )
        
        guard let finalURL = copiedURL else {
            return nil
        }
        
        if includeXMP {
            _ = try? XMPGenerator.writeSidecar(
                for: asset,
                targetFilename: finalURL.lastPathComponent,
                to: folder,
                convention: namingConvention,
                sessionMetadata: sessionMetadata
            )
        }
        
        return finalURL
    }
}

/// Ошибки процесса экспорта
public enum ExportError: LocalizedError, Sendable {
    case sourceFileNotFound(String)
    case targetFolderUnavailable
    case destinationUnreachable(String)
    case externalDriveDisconnected
    case photoLibraryPermissionDenied
    case photoLibrarySaveFailed
    case photoLibraryNotSupportedOnPlatform
    case storageSpaceInsufficient
    case insufficientDiskSpace(needed: Int64, available: Int64)
    
    public var errorDescription: String? {
        switch self {
        case .sourceFileNotFound(let name):
            return "Исходный файл не найден: \(name)"
        case .targetFolderUnavailable:
            return "Целевая папка или внешний накопитель недоступен"
        case .destinationUnreachable(let msg):
            return "Целевой носитель недоступен: \(msg)"
        case .externalDriveDisconnected:
            return "Внешний накопитель был неожиданно отключен"
        case .photoLibraryPermissionDenied:
            return "Доступ к медиатеке «Фото» запрещен"
        case .photoLibrarySaveFailed:
            return "Не удалось сохранить фото в системную медиатеку"
        case .photoLibraryNotSupportedOnPlatform:
            return "Медиатека «Фото» не поддерживается на данной платформе"
        case .storageSpaceInsufficient:
            return "Недостаточно свободного места на носителе"
        case .insufficientDiskSpace(let needed, let available):
            return "Недостаточно свободного места: требуется \(needed) байт, доступно \(available) байт"
        }
    }
}
