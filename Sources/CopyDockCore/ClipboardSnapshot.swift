import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ClipboardKind: String {
    case text
    case richText
    case image
    case files
    case other
}

public enum ClipboardCaptureError: Error, Equatable {
    case empty
    case privacyBlocked
    case tooLarge(limitBytes: Int)
}

public struct ClipboardItem {
    public let representations: [String: Data]

    public init(representations: [String: Data]) {
        self.representations = representations
    }
}

public struct ClipboardSnapshot {
    private static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff",
        "bmp", "webp", "jp2", "j2k", "ico", "icns", "avif"
    ]

    public let items: [ClipboardItem]
    public let createdAt: Date

    public init(items: [ClipboardItem], createdAt: Date = Date()) {
        self.items = items
        self.createdAt = createdAt
    }

    public init?(
        pasteboard: NSPasteboard,
        privacyFilter: PrivacyFilter = PrivacyFilter(),
        maximumBytes: Int = 20 * 1_024 * 1_024
    ) {
        switch Self.capture(
            from: pasteboard,
            privacyFilter: privacyFilter,
            maximumBytes: maximumBytes
        ) {
        case .success(let snapshot): self = snapshot
        case .failure: return nil
        }
    }

    public static func capture(
        from pasteboard: NSPasteboard,
        privacyFilter: PrivacyFilter = PrivacyFilter(),
        maximumBytes: Int = 20 * 1_024 * 1_024
    ) -> Result<ClipboardSnapshot, ClipboardCaptureError> {
        guard let pasteboardItems = pasteboard.pasteboardItems,
              !pasteboardItems.isEmpty else {
            return .failure(.empty)
        }

        let allTypes = Set(pasteboardItems.flatMap { $0.types.map(\.rawValue) })
        guard privacyFilter.allows(typeNames: allTypes) else {
            return .failure(.privacyBlocked)
        }

        var byteCount = 0
        var capturedItems: [ClipboardItem] = []

        for item in pasteboardItems {
            var representations: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                byteCount += data.count
                guard byteCount <= maximumBytes else {
                    return .failure(.tooLarge(limitBytes: maximumBytes))
                }
                representations[type.rawValue] = data
            }
            if !representations.isEmpty {
                capturedItems.append(ClipboardItem(representations: representations))
            }
        }

        guard !capturedItems.isEmpty else { return .failure(.empty) }
        return .success(ClipboardSnapshot(items: capturedItems))
    }

    @discardableResult
    public func write(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects(pasteboardItems())
    }

    public var kind: ClipboardKind {
        let types = Set(items.flatMap { $0.representations.keys })
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) { return .files }
        if types.contains(where: { rawType in
            UTType(rawType)?.conforms(to: .image) == true || rawType == UTType.pdf.identifier
        }) { return .image }
        if types.contains(NSPasteboard.PasteboardType.rtf.rawValue)
            || types.contains(NSPasteboard.PasteboardType.html.rawValue) { return .richText }
        if types.contains(NSPasteboard.PasteboardType.string.rawValue) { return .text }
        return .other
    }

    public var previewText: String {
        guard let first = items.first else { return "Empty" }

        if let data = first.representations[NSPasteboard.PasteboardType.string.rawValue],
           let string = String(data: data, encoding: .utf8) {
            let condensed = string
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return condensed.isEmpty ? "Text" : condensed
        }

        if let data = first.representations[NSPasteboard.PasteboardType.rtf.rawValue],
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            let condensed = attributed.string
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return condensed.isEmpty ? "Rich text" : condensed
        }

        if let data = first.representations[NSPasteboard.PasteboardType.html.rawValue],
           let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
           ) {
            let condensed = attributed.string
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return condensed.isEmpty ? "Formatted text" : condensed
        }

        if kind == .files, !fileNames.isEmpty {
            return fileNames.joined(separator: ", ")
        }

        switch kind {
        case .image: return "Image"
        case .files: return items.count == 1 ? "File" : "\(items.count) files"
        case .richText: return "Rich text"
        case .text: return "Text"
        case .other: return "Clipboard item"
        }
    }

    public var detailedPreviewText: String {
        guard let first = items.first else { return "Empty" }

        if let data = first.representations[NSPasteboard.PasteboardType.string.rawValue],
           let string = String(data: data, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let data = first.representations[NSPasteboard.PasteboardType.rtf.rawValue],
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            let trimmed = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let data = first.representations[NSPasteboard.PasteboardType.html.rawValue],
           let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
           ) {
            let trimmed = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if !fileURLs.isEmpty {
            return fileURLs.map { url in
                let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                return "\(name)\n\(url.deletingLastPathComponent().path)"
            }.joined(separator: "\n\n")
        }

        return previewText == "Clipboard item"
            ? formatNames.joined(separator: "\n")
            : previewText
    }

    public var previewImage: NSImage? {
        guard let first = items.first else { return nil }
        let preferredTypes = [
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue,
            UTType.jpeg.identifier,
            UTType.heic.identifier,
            UTType.gif.identifier,
            UTType.pdf.identifier
        ]
        for rawType in preferredTypes {
            if let data = first.representations[rawType], let image = NSImage(data: data) {
                return image
            }
        }
        for (rawType, data) in first.representations where UTType(rawType)?.conforms(to: .image) == true {
            if let image = NSImage(data: data) { return image }
        }

        if let url = primaryImageFileURL,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_440
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return NSImage(cgImage: thumbnail, size: .zero)
            }
        }
        return nil
    }

    public var fileURLs: [URL] {
        items.compactMap { item in
            guard let data = item.representations[NSPasteboard.PasteboardType.fileURL.rawValue],
                  let rawValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            else { return nil }
            return URL(string: rawValue)
        }
    }

    public var fileNames: [String] {
        fileURLs.map { $0.lastPathComponent.removingPercentEncoding ?? $0.lastPathComponent }
    }

    public var primaryFileIcon: NSImage? {
        guard let url = fileURLs.first else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    public var primaryImageFileURL: URL? {
        fileURLs.first { url in
            let fileExtension = url.pathExtension.lowercased()
            if Self.imageFileExtensions.contains(fileExtension) { return true }
            if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
               contentType.conforms(to: .image) {
                return true
            }
            guard let type = UTType(filenameExtension: fileExtension) else { return false }
            return type.conforms(to: .image)
        }
    }

    public var primaryReferencedFileSize: Int64? {
        guard let url = fileURLs.first,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return Int64(size)
    }

    public var formatNames: [String] {
        Array(Set(items.flatMap { $0.representations.keys })).sorted()
    }

    public var totalBytes: Int {
        items.reduce(0) { itemTotal, item in
            itemTotal + item.representations.values.reduce(0) { $0 + $1.count }
        }
    }

    public func firstPasteboardItem() -> NSPasteboardItem? {
        pasteboardItems().first
    }

    public func pasteboardItems() -> [NSPasteboardItem] {
        items.map { captured in
            let item = NSPasteboardItem()
            for (rawType, data) in captured.representations {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return item
        }
    }
}
