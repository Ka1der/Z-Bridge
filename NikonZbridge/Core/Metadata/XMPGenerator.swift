import Foundation

/// Генератор стандартных XMP sidecar файлов (.xmp) для переноса оценок, меток и метаданных
public struct XMPGenerator: Sendable {
    
    /// Генерация содержимого XMP XML документа
    public static func generateXMP(
        for asset: MediaAsset,
        targetFilename: String? = nil,
        sessionMetadata: SessionMetadata? = nil
    ) -> String {
        let effectiveFilename = targetFilename ?? asset.filename
        let ext = (effectiveFilename as NSString).pathExtension.uppercased()
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createDateStr = dateFormatter.string(from: asset.metadata.captureDate ?? asset.receivedAt)
        let modifyDateStr = dateFormatter.string(from: now)
        
        // 1. Определение значений рейтинга и меток
        let ratingValue: Int
        var labelValue: String? = nil
        var urgencyValue: String? = nil
        
        if asset.pickStatus == .rejected {
            // Стандарт Adobe Camera Raw / Bridge / darktable: -1 означает отклонённый снимок
            ratingValue = -1
            labelValue = "Reject"
        } else {
            ratingValue = asset.rating
            if asset.pickStatus == .picked {
                labelValue = "Pick"
                urgencyValue = "1"
            }
        }
        
        // 2. Формирование полей описания сессии и авторства
        let author = sessionMetadata?.author
        let copyright = sessionMetadata?.copyright
        let comment = sessionMetadata?.comment
        
        var xml = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="NikonZbridge XMP Core 1.0">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
           xmlns:xmp="http://ns.adobe.com/xap/1.0/"
           xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
           xmlns:dc="http://purl.org/dc/elements/1.1/"
           xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
           xmlns:exif="http://ns.adobe.com/exif/1.0/"
           xmlns:xmpRights="http://ns.adobe.com/xap/1.0/rights/"
           photoshop:SidecarForExtension="\(escapeXML(ext))"
           xmp:Rating="\(ratingValue)"
        """
        
        if let label = labelValue {
            xml += "\n   xmp:Label=\"\(escapeXML(label))\""
        }
        if let urgency = urgencyValue {
            xml += "\n   photoshop:Urgency=\"\(escapeXML(urgency))\""
        }
        
        xml += """
        
           xmp:CreateDate="\(createDateStr)"
           xmp:ModifyDate="\(modifyDateStr)"
           xmp:MetadataDate="\(modifyDateStr)"
           tiff:Make="NIKON CORPORATION"
        """
        
        if let cam = asset.metadata.cameraModel {
            xml += "\n   tiff:Model=\"\(escapeXML(cam))\""
        }
        
        if let exp = asset.metadata.exposureTime {
            xml += "\n   exif:ExposureTime=\"\(String(format: "%.6f", exp))\""
        }
        if let fNum = asset.metadata.fNumber {
            xml += "\n   exif:FNumber=\"\(String(format: "%.2f", fNum))\""
        }
        if let focal = asset.metadata.focalLength {
            xml += "\n   exif:FocalLength=\"\(String(format: "%.1f", focal))\""
        }
        
        xml += ">"
        
        // ISOSpeedRatings
        if let iso = asset.metadata.iso {
            xml += """
            
             <exif:ISOSpeedRatings>
              <rdf:Seq>
               <rdf:li>\(iso)</rdf:li>
              </rdf:Seq>
             </exif:ISOSpeedRatings>
            """
        }
        
        // dc:title & photoshop:Headline
        let title = sessionMetadata?.sessionName ?? effectiveFilename
        xml += """
        
         <dc:title>
          <rdf:Alt>
           <rdf:li xml:lang="x-default">\(escapeXML(title))</rdf:li>
          </rdf:Alt>
         </dc:title>
        """
        
        if let sName = sessionMetadata?.sessionName, !sName.isEmpty {
            xml += """
            
             <photoshop:Headline>\(escapeXML(sName))</photoshop:Headline>
            """
        }
        
        // dc:creator (Автор / Фотограф)
        if let author = author, !author.isEmpty {
            xml += """
            
             <dc:creator>
              <rdf:Seq>
               <rdf:li>\(escapeXML(author))</rdf:li>
              </rdf:Seq>
             </dc:creator>
            """
        }
        
        // dc:rights & xmpRights
        if let copyright = copyright, !copyright.isEmpty {
            xml += """
            
             <dc:rights>
              <rdf:Alt>
               <rdf:li xml:lang="x-default">\(escapeXML(copyright))</rdf:li>
              </rdf:Alt>
             </dc:rights>
              <xmpRights:Marked>True</xmpRights:Marked>
            """
        }
        
        // dc:description (Заметки / Комментарий к съёмке)
        if let comment = comment, !comment.isEmpty {
            xml += """
            
             <dc:description>
              <rdf:Alt>
               <rdf:li xml:lang="x-default">\(escapeXML(comment))</rdf:li>
              </rdf:Alt>
             </dc:description>
            """
        }
        
        xml += """
        
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        
        return xml
    }
    
    /// Запись файла XMP sidecar в целевую директорию рядом с оригиналом
    /// Оригинальный файл гарантированно НЕ затрагивается и не открывается на запись.
    @discardableResult
    public static func writeSidecar(
        for asset: MediaAsset,
        targetFilename: String? = nil,
        to destinationDirectory: URL,
        convention: XMPSidecarNamingConvention = .standardBasename,
        sessionMetadata: SessionMetadata? = nil
    ) throws -> URL {
        let effectiveFilename = targetFilename ?? asset.filename
        let sidecarName = convention.sidecarFilename(for: effectiveFilename)
        let destinationURL = destinationDirectory.appendingPathComponent(sidecarName)
        
        let xmpContent = generateXMP(for: asset, targetFilename: effectiveFilename, sessionMetadata: sessionMetadata)
        guard let data = xmpContent.data(using: .utf8) else {
            throw NSError(domain: "XMPGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось кодировать XMP в UTF-8"])
        }
        
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }
    
    /// Определение имени sidecar-файла для заданного имени оригинала и соглашения
    public static func sidecarFilename(
        for assetFilename: String,
        convention: XMPSidecarNamingConvention = .standardBasename
    ) -> String {
        convention.sidecarFilename(for: assetFilename)
    }
    
    /// Экранирование спецсимволов для XML
    public static func escapeXML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
