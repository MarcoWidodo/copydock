import AppKit
import Combine
import CopyDockCore

final class InventoryPanel: NSPanel, NSWindowDelegate {
    private let store: SlotStore
    private let settings: AppSettings
    private let inventoryView: InventoryView
    private var settingsObserver: AnyCancellable?
    private var snapWorkItem: DispatchWorkItem?
    private var isProgrammaticMove = false

    var onRequestAccessibility: (() -> Void)? {
        didSet { inventoryView.onRequestAccessibility = onRequestAccessibility }
    }
    var onOpenSettings: (() -> Void)? {
        didSet { inventoryView.onOpenSettings = onOpenSettings }
    }

    init(store: SlotStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        inventoryView = InventoryView(store: store, settings: settings)

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        delegate = self
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isMovable = true
        isMovableByWindowBackground = true
        contentView = inventoryView

        settingsObserver = settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applySettings() }
        }
        applySettings()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func showDock() {
        // Rebuilding fixed constraints gives the UI a clean recovery point after
        // any interrupted or cancelled drag session without touching slot data.
        resetLayout()
        orderFrontRegardless()
    }

    func toggleDock() {
        if isVisible {
            orderOut(nil)
        } else {
            showDock()
        }
    }

    func reloadSlots() { inventoryView.reload() }

    func flash(slot: Int, isError: Bool = false) {
        guard inventoryView.slotViews.indices.contains(slot) else { return }
        inventoryView.slotViews[slot].flash(isError: isError)
    }

    func showCaptureRejection(_ error: ClipboardCaptureError) {
        guard case .tooLarge(let limitBytes) = error else { return }
        let limit = ByteCountFormatter.string(fromByteCount: Int64(limitBytes), countStyle: .file)
        showDock()
        inventoryView.showNotice("Item exceeds the \(limit) slot limit")
    }

    func showNotice(_ message: String) {
        showDock()
        inventoryView.showNotice(message)
    }

    func setShortcutStatus(enabled: Bool) {
        if inventoryView.setShortcutStatus(enabled: enabled) {
            resetLayout()
        }
    }

    func resetLayout() {
        applySettings()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove, settings.edgeSnapping else { return }
        snapWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.snapToNearestEdge() }
        snapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func applySettings() {
        alphaValue = CGFloat(settings.opacity)
        hasShadow = settings.backgroundStyle != .none
        inventoryView.applySettings()
        resizeAndPosition()
    }

    private func resizeAndPosition(on preferredScreen: NSScreen? = nil) {
        isProgrammaticMove = true
        defer { isProgrammaticMove = false }
        let desiredSize = inventoryView.requiredContentSize
        setContentSize(desiredSize)

        let targetScreen = preferredScreen ?? screen ?? screenUnderPointer() ?? NSScreen.main
        guard let visibleFrame = targetScreen?.visibleFrame else { return }
        let margin: CGFloat = 14
        let origin: NSPoint
        switch settings.position {
        case .bottom:
            origin = NSPoint(x: visibleFrame.midX - desiredSize.width / 2, y: visibleFrame.minY + margin)
        case .top:
            origin = NSPoint(x: visibleFrame.midX - desiredSize.width / 2, y: visibleFrame.maxY - desiredSize.height - margin)
        case .left:
            origin = NSPoint(x: visibleFrame.minX + margin, y: visibleFrame.midY - desiredSize.height / 2)
        case .right:
            origin = NSPoint(x: visibleFrame.maxX - desiredSize.width - margin, y: visibleFrame.midY - desiredSize.height / 2)
        }

        setFrameOrigin(origin)
    }

    private func snapToNearestEdge() {
        guard let targetScreen = bestScreenForCurrentFrame() else { return }
        let visible = targetScreen.visibleFrame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let distances: [(DockPosition, CGFloat)] = [
            (.left, abs(center.x - visible.minX)),
            (.right, abs(visible.maxX - center.x)),
            (.bottom, abs(center.y - visible.minY)),
            (.top, abs(visible.maxY - center.y))
        ]
        guard let nearest = distances.min(by: { $0.1 < $1.1 })?.0 else { return }
        if settings.position != nearest { settings.position = nearest }
        resizeAndPosition(on: targetScreen)
    }

    private func bestScreenForCurrentFrame() -> NSScreen? {
        NSScreen.screens.max {
            $0.frame.intersection(frame).width * $0.frame.intersection(frame).height
                < $1.frame.intersection(frame).width * $1.frame.intersection(frame).height
        }
    }

    private func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }
}

final class InventoryView: NSView {
    let store: SlotStore
    let settings: AppSettings
    private var stackView: NSStackView?
    private var permissionButton: NSButton?
    private var noticeLabel: NSTextField?
    private var noticeWorkItem: DispatchWorkItem?
    private(set) var slotViews: [SlotView] = []
    private(set) var shortcutsEnabled = false
    var onRequestAccessibility: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(store: SlotStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        super.init(frame: .zero)
        wantsLayer = true
        rebuildStack()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { true }

    var requiredContentSize: NSSize {
        let slot = settings.slotLength
        let gap: CGFloat = 7
        let slotSpan = slot * 9 + gap * 8
        let padding: CGFloat = settings.backgroundStyle == .none ? 10 : 20
        if settings.position.isVertical {
            let controlsHeight: CGFloat = shortcutsEnabled ? 59 : 88
            let controlsWidth: CGFloat = shortcutsEnabled ? 26 : 76
            return NSSize(
                width: max(slot, controlsWidth) + padding,
                height: slotSpan + padding + 10 + controlsHeight
            )
        }
        let controlsWidth: CGFloat = shortcutsEnabled ? 59 : 124
        let controlsHeight: CGFloat = shortcutsEnabled ? 26 : 58
        return NSSize(
            width: slotSpan + padding + 10 + controlsWidth,
            height: max(slot, controlsHeight) + padding
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard settings.backgroundStyle != .none else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 18, yRadius: 18)
        if settings.backgroundStyle == .glass {
            settings.dockBackgroundColor.withAlphaComponent(0.58).setFill()
            NSColor.white.withAlphaComponent(0.18).setStroke()
        } else {
            settings.dockBackgroundColor.withAlphaComponent(0.96).setFill()
            NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
        }
        path.fill()
        path.lineWidth = 1
        path.stroke()
    }

    func applySettings() {
        rebuildStack()
        needsDisplay = true
    }

    func reload() {
        for (index, slotView) in slotViews.enumerated() { slotView.snapshot = store[index] }
    }

    func showNotice(_ message: String) {
        noticeWorkItem?.cancel()
        noticeLabel?.removeFromSuperview()

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.textColor = .white
        label.backgroundColor = .systemRed.withAlphaComponent(0.92)
        label.drawsBackground = true
        label.isBezeled = false
        label.wantsLayer = true
        label.layer?.cornerRadius = 9
        label.layer?.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        noticeLabel = label
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -20),
            label.heightAnchor.constraint(equalToConstant: 28)
        ])

        let workItem = DispatchWorkItem { [weak self, weak label] in
            guard let self, let label else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                label.animator().alphaValue = 0
            } completionHandler: {
                label.removeFromSuperview()
                if self.noticeLabel === label { self.noticeLabel = nil }
            }
        }
        noticeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: workItem)
    }

    @discardableResult
    func setShortcutStatus(enabled: Bool) -> Bool {
        guard shortcutsEnabled != enabled else { return false }
        shortcutsEnabled = enabled
        rebuildStack()
        return true
    }

    func rebuildStack() {
        stackView?.removeFromSuperview()
        let slotLength = settings.slotLength
        slotViews = (0..<SlotStore.slotCount).map { index in
            let view = SlotView(index: index, store: store, settings: settings)
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.widthAnchor.constraint(equalToConstant: slotLength),
                view.heightAnchor.constraint(equalToConstant: slotLength)
            ])
            return view
        }

        let slotStack = NSStackView(views: slotViews)
        slotStack.orientation = settings.position.isVertical ? .vertical : .horizontal
        slotStack.distribution = .fill
        slotStack.spacing = 7
        slotStack.setHuggingPriority(.required, for: settings.position.isVertical ? .vertical : .horizontal)
        slotStack.setContentCompressionResistancePriority(.required, for: settings.position.isVertical ? .vertical : .horizontal)

        let settingsButton = iconButton(symbol: "gearshape", description: "Open CopyDock settings", action: #selector(openSettings))
        let clearButton = iconButton(symbol: "trash", description: "Clear all nine slots", action: #selector(clearAllSlots))

        let iconStack = NSStackView(views: [settingsButton, clearButton])
        iconStack.orientation = settings.position.isVertical ? .vertical : .horizontal
        iconStack.alignment = settings.position.isVertical ? .centerX : .centerY
        iconStack.spacing = 7
        iconStack.setHuggingPriority(.required, for: settings.position.isVertical ? .vertical : .horizontal)

        var controlRows: [NSView] = [iconStack]
        if !shortcutsEnabled {
            let permission = FloatingPillButton(
                title: settings.position.isVertical ? "Enable" : "Enable Shortcuts",
                accent: settings.accentColor,
                target: self,
                action: #selector(requestAccessibility)
            )
            permission.controlSize = .small
            permission.toolTip = "Grant Accessibility access for Command-C/V plus a number"
            permission.setAccessibilityLabel("Enable keyboard shortcuts")
            permissionButton = permission
            controlRows.insert(permission, at: 0)
        } else {
            permissionButton = nil
        }

        let controls = NSStackView(views: controlRows)
        controls.orientation = .vertical
        controls.alignment = .centerX
        controls.spacing = 6
        controls.setHuggingPriority(.required, for: .horizontal)

        let mainStack = NSStackView(views: [slotStack, controls])
        mainStack.orientation = settings.position.isVertical ? .vertical : .horizontal
        mainStack.alignment = settings.position.isVertical ? .centerX : .centerY
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)
        stackView = mainStack

        let inset: CGFloat = settings.backgroundStyle == .none ? 5 : 10
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        ])
        needsDisplay = true
    }

    private func iconButton(symbol: String, description: String, action: Selector) -> NSButton {
        let button = FloatingIconButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage(),
            accent: settings.accentColor,
            target: self,
            action: action
        )
        button.toolTip = description
        button.setAccessibilityLabel(description)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
        return button
    }

    @objc private func clearAllSlots() {
        PromisedFileMaterializer.shared.cleanupAll()
        store.clearAll()
    }
    @objc private func requestAccessibility() { onRequestAccessibility?() }
    @objc private func openSettings() { onOpenSettings?() }
}

final class FloatingIconButton: NSButton {
    private let accent: NSColor
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false

    init(image: NSImage, accent: NSColor, target: AnyObject?, action: Selector?) {
        self.accent = accent
        super.init(frame: .zero)
        self.image = image
        self.target = target
        self.action = action
        isBordered = false
        imagePosition = .imageOnly
        contentTintColor = .white
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
        (isHighlighted || isHovered ? accent.withAlphaComponent(0.92) : NSColor(calibratedWhite: 0.12, alpha: 0.82)).setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        circle.lineWidth = 1
        circle.stroke()
        super.draw(dirtyRect)
    }
}

final class FloatingPillButton: NSButton {
    private let accent: NSColor

    init(title: String, accent: NSColor, target: AnyObject?, action: Selector?) {
        self.accent = accent
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        contentTintColor = .white
        font = .systemFont(ofSize: 11, weight: .semibold)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        (isHighlighted ? accent.highlight(withLevel: 0.12) ?? accent : accent).setFill()
        pill.fill()
        super.draw(dirtyRect)
    }
}

final class SlotView: NSView, NSDraggingSource {
    let index: Int
    private let store: SlotStore
    private let settings: AppSettings
    private let numberLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(wrappingLabelWithString: "")
    private let imageView = NSImageView()
    private var trackingAreaRef: NSTrackingArea?
    private var previewWorkItem: DispatchWorkItem?
    private var previewPopover: NSPopover?
    private var flashColor: NSColor?
    private var dragStarted = false
    private var isHovered = false

    var snapshot: ClipboardSnapshot? {
        didSet {
            closePreview()
            updateLabels()
            needsDisplay = true
        }
    }

    init(index: Int, store: SlotStore, settings: AppSettings) {
        self.index = index
        self.store = store
        self.settings = settings
        snapshot = store[index]
        super.init(frame: .zero)
        wantsLayer = true
        let promisedTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes([.string, .html, .rtf, .png, .tiff, .fileURL] + promisedTypes)
        configureSubviews()
        updateLabels()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        guard settings.hoverPreviews, snapshot != nil else { return }
        previewWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.showPreview() }
        previewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        previewWorkItem?.cancel()
        previewWorkItem = nil
        closePreview()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset: CGFloat = settings.slotShape == .bubbles ? 3 : 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let radius = settings.slotShape == .bubbles ? rect.height * 0.31 : min(12, rect.height * 0.2)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let accent = settings.accentColor

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = isHovered ? 10 : 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor.black.withAlphaComponent(isHovered ? 0.34 : 0.22)
        shadow.set()

        if let flashColor {
            flashColor.withAlphaComponent(0.74).setFill()
        } else if isHovered {
            accent.withAlphaComponent(0.50).setFill()
        } else if snapshot == nil {
            settings.slotBaseColor.withAlphaComponent(0.78).setFill()
        } else {
            settings.slotBaseColor.withAlphaComponent(0.96).setFill()
        }
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        (isHovered ? accent.withAlphaComponent(0.95) : NSColor.white.withAlphaComponent(snapshot == nil ? 0.20 : 0.36)).setStroke()
        path.lineWidth = isHovered ? 1.6 : 1
        path.stroke()
    }

    private func configureSubviews() {
        numberLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        numberLabel.alignment = .center
        numberLabel.textColor = .white.withAlphaComponent(0.70)
        numberLabel.translatesAutoresizingMaskIntoConstraints = false

        previewLabel.font = .systemFont(ofSize: 9, weight: .medium)
        previewLabel.alignment = .center
        previewLabel.maximumNumberOfLines = 3
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.textColor = .white
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(numberLabel)
        addSubview(previewLabel)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            numberLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            numberLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            numberLabel.widthAnchor.constraint(equalToConstant: 14),
            numberLabel.heightAnchor.constraint(equalToConstant: 13),
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            previewLabel.topAnchor.constraint(equalTo: topAnchor, constant: 19),
            previewLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        ])
    }

    private func updateLabels() {
        numberLabel.stringValue = "\(index + 1)"
        if let image = snapshot?.previewImage {
            imageView.image = image
            imageView.isHidden = false
            previewLabel.isHidden = true
        } else {
            imageView.image = nil
            imageView.isHidden = true
            previewLabel.isHidden = false
            previewLabel.stringValue = snapshot?.previewText ?? ""
            previewLabel.textColor = snapshot == nil ? .white.withAlphaComponent(0.22) : .white
        }
        setAccessibilityLabel("Slot \(index + 1), \(snapshot?.previewText ?? "empty")")
    }

    func flash(isError: Bool = false) {
        flashColor = isError ? .systemRed : settings.accentColor
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            self?.flashColor = nil
            self?.needsDisplay = true
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !(sender.draggingSource is SlotView) else { return [] }
        return .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !(sender.draggingSource is SlotView)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !(sender.draggingSource is SlotView) else { return false }
        let isReceivingPromise = PromisedFileMaterializer.shared.receive(
            from: sender.draggingPasteboard,
            into: index
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let snapshot):
                _ = self.store.capture(snapshot, into: self.index, explicit: true)
                self.flash()
            case .failure:
                self.flash(isError: true)
                (self.window as? InventoryPanel)?.showNotice("The promised file could not be received")
            }
        }
        if isReceivingPromise { return true }
        switch ClipboardSnapshot.capture(
            from: sender.draggingPasteboard,
            maximumBytes: settings.maximumCaptureBytes
        ) {
        case .success(let captured):
            PromisedFileMaterializer.shared.cleanup(slot: index)
            _ = store.capture(captured, into: index, explicit: true)
            flash()
            return true
        case .failure(let error):
            (window as? InventoryPanel)?.showCaptureRejection(error)
            flash(isError: true)
            return false
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStarted = false
        if snapshot == nil { window?.performDrag(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        closePreview()
        guard !dragStarted, let snapshot else { return }
        let pasteboardItems = snapshot.pasteboardItems()
        guard !pasteboardItems.isEmpty else { return }
        dragStarted = true
        let draggingItems = pasteboardItems.enumerated().map { offset, item -> NSDraggingItem in
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            let delta = CGFloat(min(offset, 4)) * 3
            let frame = bounds.insetBy(dx: 4, dy: 4).offsetBy(dx: delta, dy: -delta)
            draggingItem.setDraggingFrame(frame, contents: snapshot.previewImage ?? snapshot.primaryFileIcon)
            return draggingItem
        }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let clear = NSMenuItem(title: "Clear Slot \(index + 1)", action: #selector(clearSlot), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func clearSlot() {
        PromisedFileMaterializer.shared.cleanup(slot: index)
        store.clear(index)
    }

    private func showPreview() {
        guard isHovered, let snapshot else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = SlotPreviewViewController(
            slotNumber: index + 1,
            snapshot: snapshot,
            characterLimit: settings.previewTextLimit,
            previewSize: settings.previewSize
        )
        popover.contentSize = settings.previewSize
        let edge: NSRectEdge
        switch settings.position {
        case .bottom: edge = .maxY
        case .top: edge = .minY
        case .left: edge = .maxX
        case .right: edge = .minX
        }
        popover.show(relativeTo: bounds, of: self, preferredEdge: edge)
        previewPopover = popover
    }

    private func closePreview() {
        previewWorkItem?.cancel()
        previewWorkItem = nil
        previewPopover?.close()
        previewPopover = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

final class SlotPreviewViewController: NSViewController {
    private let slotNumber: Int
    private let snapshot: ClipboardSnapshot
    private let characterLimit: Int
    private let previewSize: NSSize

    init(slotNumber: Int, snapshot: ClipboardSnapshot, characterLimit: Int, previewSize: NSSize) {
        self.slotNumber = slotNumber
        self.snapshot = snapshot
        self.characterLimit = characterLimit
        self.previewSize = previewSize
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = previewSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let effect = NSVisualEffectView()
        effect.frame = NSRect(origin: .zero, size: previewSize)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active

        let title = NSTextField(labelWithString: "Slot \(slotNumber)")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let content: NSView
        if let image = snapshot.previewImage {
            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            content = imageView
        } else if snapshot.kind == .files, !snapshot.fileURLs.isEmpty {
            content = filePreview()
        } else {
            content = textPreview(previewBody)
        }
        content.translatesAutoresizingMaskIntoConstraints = false

        let byteCount = snapshot.primaryReferencedFileSize ?? Int64(snapshot.totalBytes)
        let bytes = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        let name = snapshot.primaryImageFileURL?.lastPathComponent
        let nameFragment = name.map { " · \($0)" } ?? ""
        let metadata = NSTextField(labelWithString: "\(kindTitle)\(nameFragment) · \(bytes) · copied \(snapshot.createdAt.formatted(date: .omitted, time: .shortened))")
        metadata.font = .systemFont(ofSize: 10)
        metadata.textColor = .secondaryLabelColor
        metadata.translatesAutoresizingMaskIntoConstraints = false
        let contentHeight = max(previewSize.height - 78, 80)

        effect.addSubview(title)
        effect.addSubview(content)
        effect.addSubview(metadata)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            title.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: metadata.topAnchor, constant: -10),
            content.heightAnchor.constraint(equalToConstant: contentHeight),
            metadata.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            metadata.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            metadata.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -14)
        ])
        view = effect
    }

    private func textPreview(_ text: String) -> NSView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        let availableWidth = max(previewSize.width - 40, 200)
        let minimumHeight = max(previewSize.height - 84, 100)
        textView.frame = NSRect(x: 0, y: 0, width: availableWidth, height: minimumHeight)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: minimumHeight)
        textView.maxSize = NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
        if let container = textView.textContainer, let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: container)
            let usedHeight = layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2
            textView.frame.size.height = max(minimumHeight, usedHeight)
        }
        return scrollView
    }

    private func filePreview() -> NSView {
        let iconView = NSImageView(image: snapshot.primaryFileIcon ?? NSImage())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72)
        ])

        let details = textPreview(previewBody)
        let stack = NSStackView(views: [iconView, details])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 14
        details.translatesAutoresizingMaskIntoConstraints = false
        details.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        return stack
    }

    private var kindTitle: String {
        if snapshot.primaryImageFileURL != nil { return "Image file" }
        switch snapshot.kind {
        case .text: return "Text"
        case .richText: return "Formatted text"
        case .image: return "Image"
        case .files: return "File"
        case .other: return "Clipboard item"
        }
    }

    private var previewBody: String {
        let text = snapshot.detailedPreviewText
        return text.count > characterLimit ? String(text.prefix(characterLimit)) + "…" : text
    }
}
