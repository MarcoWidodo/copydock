import AppKit
import CopyDockCore

final class ClipboardWatcher {
    private let pasteboard = NSPasteboard.general
    private let store: SlotStore
    private let maximumBytes: () -> Int
    private var timer: Timer?
    private(set) var lastSeenChangeCount: Int
    var shouldDeferCapture: (() -> Bool)?
    var onCaptureRejected: ((ClipboardCaptureError) -> Void)?

    init(store: SlotStore, maximumBytes: @escaping () -> Int = { 20 * 1_024 * 1_024 }) {
        self.store = store
        self.maximumBytes = maximumBytes
        lastSeenChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func markCurrentChangeAsSeen() {
        lastSeenChangeCount = pasteboard.changeCount
    }

    func captureSnapshot(
        from pasteboard: NSPasteboard,
        privacyFilter: PrivacyFilter = PrivacyFilter()
    ) -> Result<ClipboardSnapshot, ClipboardCaptureError> {
        ClipboardSnapshot.capture(
            from: pasteboard,
            privacyFilter: privacyFilter,
            maximumBytes: maximumBytes()
        )
    }

    func reportCaptureRejection(_ error: ClipboardCaptureError) {
        if case .tooLarge = error { onCaptureRejected?(error) }
    }

    private func checkClipboard() {
        guard pasteboard.changeCount != lastSeenChangeCount else { return }
        guard shouldDeferCapture?() != true else { return }

        lastSeenChangeCount = pasteboard.changeCount
        switch captureSnapshot(from: pasteboard) {
        case .success(let snapshot):
            PromisedFileMaterializer.shared.cleanup(slot: 0)
            _ = store.capture(snapshot, into: 0)
        case .failure(let error):
            reportCaptureRejection(error)
        }
    }
}
