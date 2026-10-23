import AppKit
import ApplicationServices
import CopyDockCore

private let syntheticEventMarker: Int64 = 0x534C4F54444F434B

final class KeyboardEventTap {
    private let store: SlotStore
    private weak var panel: InventoryPanel?
    private weak var watcher: ClipboardWatcher?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var copyChord: (initialChangeCount: Int, destination: Int?)?
    private var pasteChordIsPending = false
    private var suppressedKeyUps = Set<Int64>()
    private let stateLock = NSLock()
    private var keyboardCopyInFlight = false

    init(store: SlotStore, panel: InventoryPanel, watcher: ClipboardWatcher) {
        self.store = store
        self.panel = panel
        self.watcher = watcher
        watcher.shouldDeferCapture = { [weak self] in
            self?.isKeyboardCopyInFlight ?? false
        }
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    var isRunning: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    private var isKeyboardCopyInFlight: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return keyboardCopyInFlight
    }

    @discardableResult
    func start(requestPermission: Bool) -> Bool {
        if requestPermission {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return true
        }
        guard hasAccessibilityPermission else { return false }

        let mask = eventMask(for: [.keyDown, .keyUp, .flagsChanged])
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<KeyboardEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return controller.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else { return false }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private func eventMask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isBareCommand = flags.contains(.maskCommand)
            && !flags.contains(.maskShift)
            && !flags.contains(.maskControl)
            && !flags.contains(.maskAlternate)

        if type == .keyUp, suppressedKeyUps.remove(keyCode) != nil {
            return nil
        }

        if type == .keyDown,
           keyCode == 49,
           flags.contains(.maskCommand),
           flags.contains(.maskShift) {
            suppressedKeyUps.insert(keyCode)
            DispatchQueue.main.async { [weak self] in self?.panel?.toggleDock() }
            return nil
        }

        if type == .keyDown, isBareCommand, keyCode == 8 { // C
            stateLock.lock()
            keyboardCopyInFlight = true
            stateLock.unlock()
            copyChord = (NSPasteboard.general.changeCount, nil)
            DispatchQueue.main.async { [weak self] in self?.panel?.showDock() }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, isBareCommand, keyCode == 9 { // V
            pasteChordIsPending = true
            suppressedKeyUps.insert(keyCode)
            DispatchQueue.main.async { [weak self] in self?.panel?.showDock() }
            return nil
        }

        if type == .keyDown,
           flags.contains(.maskCommand),
           let slot = slotIndex(for: keyCode) {
            if let pendingCopy = copyChord {
                copyChord = nil
                suppressedKeyUps.insert(keyCode)
                finishCopy(initialChangeCount: pendingCopy.initialChangeCount, destination: slot)
                return nil
            }
            if pasteChordIsPending {
                pasteChordIsPending = false
                suppressedKeyUps.insert(keyCode)
                DispatchQueue.main.async { [weak self] in self?.paste(slot: slot) }
                return nil
            }
        }

        if type == .keyDown, pasteChordIsPending {
            pasteChordIsPending = false
            DispatchQueue.main.async { [weak self] in self?.postCommandKey(keyCode: 9) }
        }

        if type == .flagsChanged, !flags.contains(.maskCommand) {
            if let pendingCopy = copyChord {
                copyChord = nil
                finishCopy(initialChangeCount: pendingCopy.initialChangeCount, destination: 0)
            }
            if pasteChordIsPending {
                pasteChordIsPending = false
                DispatchQueue.main.async { [weak self] in self?.postCommandKey(keyCode: 9) }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func finishCopy(initialChangeCount: Int, destination: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.captureWhenReady(
                initialChangeCount: initialChangeCount,
                destination: destination,
                attemptsRemaining: 30
            )
        }
    }

    private func captureWhenReady(initialChangeCount: Int, destination: Int, attemptsRemaining: Int) {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != initialChangeCount {
            let result = watcher?.captureSnapshot(from: pasteboard)
                ?? ClipboardSnapshot.capture(from: pasteboard)
            switch result {
            case .success(let snapshot):
                PromisedFileMaterializer.shared.cleanup(slot: destination)
                _ = store.capture(snapshot, into: destination)
                watcher?.markCurrentChangeAsSeen()
                markKeyboardCopyFinished()
                panel?.flash(slot: destination)
                return
            case .failure(let error):
                watcher?.reportCaptureRejection(error)
                watcher?.markCurrentChangeAsSeen()
                markKeyboardCopyFinished()
                panel?.flash(slot: destination, isError: true)
                return
            }
        }

        guard attemptsRemaining > 0 else {
            markKeyboardCopyFinished()
            watcher?.markCurrentChangeAsSeen()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.captureWhenReady(
                initialChangeCount: initialChangeCount,
                destination: destination,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func markKeyboardCopyFinished() {
        stateLock.lock()
        keyboardCopyInFlight = false
        stateLock.unlock()
    }

    private func paste(slot: Int) {
        guard let snapshot = store[slot] else {
            panel?.flash(slot: slot, isError: true)
            return
        }

        let pasteboard = NSPasteboard.general
        let previous = ClipboardSnapshot(pasteboard: pasteboard, privacyFilter: PrivacyFilter(blockedTypeNames: []))
        _ = snapshot.write(to: pasteboard)
        watcher?.markCurrentChangeAsSeen()
        postCommandKey(keyCode: 9)
        panel?.flash(slot: slot)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            if let previous {
                _ = previous.write(to: pasteboard)
            }
            self.watcher?.markCurrentChangeAsSeen()
        }
    }

    private func postCommandKey(keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func slotIndex(for keyCode: Int64) -> Int? {
        let keyCodes: [Int64: Int] = [
            18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
            22: 5, 26: 6, 28: 7, 25: 8
        ]
        return keyCodes[keyCode]
    }
}
