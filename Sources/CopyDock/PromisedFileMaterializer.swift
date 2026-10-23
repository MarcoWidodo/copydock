import AppKit
import CopyDockCore

/// Turns lazy Finder-style file promises into concrete, local file URLs while
/// CopyDock is running. The private temporary directory is removed on cleanup.
final class PromisedFileMaterializer {
    static let shared = PromisedFileMaterializer()

    enum ReceiptError: Error {
        case couldNotCreateDestination
        case noFilesReceived
    }

    private final class ReceiptState {
        var urls: [URL] = []
        var remaining: Int
        var finished = false
        let completion: (Result<ClipboardSnapshot, Error>) -> Void

        init(remaining: Int, completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void) {
            self.remaining = remaining
            self.completion = completion
        }
    }

    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let receiptQueue: OperationQueue
    private var slotDirectories: [Int: URL] = [:]

    private init() {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        Self.removeStalePromiseDirectories(in: temporaryDirectory)
        rootDirectory = temporaryDirectory
            .appendingPathComponent("CopyDock-FilePromises-" + UUID().uuidString, isDirectory: true)
        receiptQueue = OperationQueue()
        receiptQueue.name = "CopyDock file promise receipts"
        receiptQueue.qualityOfService = .userInitiated
    }

    private static func removeStalePromiseDirectories(in temporaryDirectory: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries where
            entry.lastPathComponent.hasPrefix("CopyDock-FilePromises-") ||
            entry.lastPathComponent.hasPrefix("SlotDock-FilePromises-") {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    @discardableResult
    func receive(
        from pasteboard: NSPasteboard,
        into slot: Int,
        completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void
    ) -> Bool {
        guard let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver], !receivers.isEmpty else {
            return false
        }

        cleanup(slot: slot)
        let directoryName = "slot-" + String(slot + 1) + "-" + UUID().uuidString
        let destination = rootDirectory.appendingPathComponent(directoryName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            completion(.failure(ReceiptError.couldNotCreateDestination))
            return true
        }
        slotDirectories[slot] = destination

        let expectedFiles = receivers.reduce(0) { total, receiver in
            total + max(receiver.fileTypes.count, 1)
        }
        let state = ReceiptState(remaining: expectedFiles, completion: completion)

        for receiver in receivers {
            receiver.receivePromisedFiles(
                atDestination: destination,
                options: [:],
                operationQueue: receiptQueue
            ) { [weak self] fileURL, error in
                DispatchQueue.main.async {
                    guard let self, !state.finished else { return }
                    if error == nil { state.urls.append(fileURL) }
                    state.remaining -= 1
                    if state.remaining <= 0 { self.finish(state, slot: slot) }
                }
            }
        }

        // Some providers under-report or over-report promised filenames. This
        // bounded fallback completes with everything delivered so far.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, !state.finished else { return }
            self.finish(state, slot: slot)
        }
        return true
    }

    func cleanup(slot: Int) {
        guard let directory = slotDirectories.removeValue(forKey: slot) else { return }
        try? fileManager.removeItem(at: directory)
    }

    func cleanupAll() {
        slotDirectories.removeAll()
        try? fileManager.removeItem(at: rootDirectory)
    }

    private func finish(_ state: ReceiptState, slot: Int) {
        guard !state.finished else { return }
        state.finished = true
        guard !state.urls.isEmpty else {
            cleanup(slot: slot)
            state.completion(.failure(ReceiptError.noFilesReceived))
            return
        }

        let items = state.urls.map { url in
            ClipboardItem(representations: [
                NSPasteboard.PasteboardType.fileURL.rawValue: Data(url.absoluteString.utf8),
                NSPasteboard.PasteboardType.string.rawValue: Data(url.path.utf8)
            ])
        }
        state.completion(.success(ClipboardSnapshot(items: items)))
    }
}
