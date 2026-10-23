import AppKit
import ImageIO
import CopyDockCore
import UniformTypeIdentifiers

private var failures: [String] = []

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

private func snapshot(_ text: String) -> ClipboardSnapshot {
    let data = text.data(using: .utf8)!
    return ClipboardSnapshot(items: [
        ClipboardItem(representations: [NSPasteboard.PasteboardType.string.rawValue: data])
    ])
}

do {
    let store = SlotStore()
    check(store.slots.count == 9, "The store must contain exactly nine slots")
}

do {
    let store = SlotStore()
    check(store.capture(snapshot("three"), into: 2, explicit: true), "Explicit capture should succeed")
    check(store[2]?.previewText == "three", "Slot 3 should hold the captured text")
    check(store.lastCopiedSlot == 2, "The last-copied pointer should track Slot 3")
    check(store[0] == nil, "A directed copy should not overwrite Slot 1")
}

do {
    let store = SlotStore()
    store.isCapturePaused = true
    check(!store.capture(snapshot("automatic"), into: 0), "Paused capture should reject automatic copies")
    check(store.capture(snapshot("dragged"), into: 0, explicit: true), "An explicit drag should still be accepted")
    check(store[0]?.previewText == "dragged", "The dragged item should be stored")
}

do {
    let store = SlotStore()
    store.ignoreNextCapture = true
    check(!store.capture(snapshot("secret"), into: 0), "Ignore-next should reject one capture")
    check(store.capture(snapshot("safe"), into: 0), "Capture should resume after ignore-next")
    check(store[0]?.previewText == "safe", "The safe follow-up copy should be stored")
}

do {
    let filter = PrivacyFilter()
    check(!filter.allows(typeNames: ["org.nspasteboard.ConcealedType"]), "Concealed content must be rejected")
    check(
        !filter.allows(typeNames: ["com.agilebits.onepassword", "public.utf8-plain-text"]),
        "1Password content must be rejected even when text is also present"
    )
    check(filter.allows(typeNames: ["public.utf8-plain-text"]), "Ordinary text should be allowed")
}

do {
    let multiItem = ClipboardSnapshot(items: [
        ClipboardItem(representations: [NSPasteboard.PasteboardType.string.rawValue: Data("first".utf8)]),
        ClipboardItem(representations: [NSPasteboard.PasteboardType.string.rawValue: Data("second".utf8)])
    ])
    check(multiItem.pasteboardItems().count == 2, "Multiple clipboard items must remain distinct when dragged or pasted")
}

do {
    let multiline = snapshot("Line one\nLine two\nLine three")
    check(multiline.detailedPreviewText.contains("\n"), "Detailed hover previews should preserve paragraph breaks")
}

do {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: 4,
        height: 4,
        bitsPerComponent: 8,
        bytesPerRow: 16,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    context?.setFillColor(NSColor.systemPink.cgColor)
    context?.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    let image = context?.makeImage()

    for (type, extensionName) in [(UTType.png, "png"), (UTType.jpeg, "jpg")] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyDockChecks-" + UUID().uuidString)
            .appendingPathExtension(extensionName)
        defer { try? FileManager.default.removeItem(at: url) }

        if let image,
           let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            check(CGImageDestinationFinalize(destination), "The test image should be writable")
        } else {
            check(false, "The test image should be writable")
        }

        let imageFile = ClipboardSnapshot(items: [
            ClipboardItem(representations: [
                NSPasteboard.PasteboardType.fileURL.rawValue: Data(url.absoluteString.utf8)
            ])
        ])
        check(imageFile.kind == .files, "Image-file references should retain file semantics")
        check(!imageFile.fileURLs.isEmpty, "\(extensionName.uppercased()) file URLs should decode")
        check(imageFile.fileURLs.first?.pathExtension == extensionName, "\(extensionName.uppercased()) extensions should survive decoding")
        check(imageFile.primaryImageFileURL != nil, "\(extensionName.uppercased()) files should be recognized as images")
        check(imageFile.previewImage != nil, "\(extensionName.uppercased()) files should generate thumbnails")
    }
}

if failures.isEmpty {
    print("CopyDock checks passed (8 groups).")
} else {
    for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
    exit(1)
}
