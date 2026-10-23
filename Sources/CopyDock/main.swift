import AppKit
import CopyDockCore

private func descendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendants(of:))
}

private func runPreviewSelfCheck() -> Int32 {
    _ = NSApplication.shared
    let sample = "First paragraph\n\nSecond paragraph with enough text to verify the visible document canvas."
    let snapshot = ClipboardSnapshot(items: [
        ClipboardItem(representations: [
            NSPasteboard.PasteboardType.string.rawValue: Data(sample.utf8)
        ])
    ])
    let controller = SlotPreviewViewController(
        slotNumber: 2,
        snapshot: snapshot,
        characterLimit: 4_000,
        previewSize: NSSize(width: 480, height: 360)
    )
    controller.loadView()
    controller.view.layoutSubtreeIfNeeded()

    let views = descendants(of: controller.view)
    let textView = views.compactMap { $0 as? NSTextView }.first
    let scrollView = views.compactMap { $0 as? NSScrollView }.first
    guard textView?.string == sample, (scrollView?.frame.height ?? 0) >= 200 else {
        fputs("FAIL: Hover-preview text canvas is missing or collapsed.\n", stderr)
        return 1
    }
    print("CopyDock hover-preview self-check passed.")
    return 0
}

if CommandLine.arguments.contains("--self-check-preview") {
    exit(runPreviewSelfCheck())
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
