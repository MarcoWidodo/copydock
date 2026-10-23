import AppKit
import ApplicationServices
import Carbon
import CopyDockCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SlotStore()
    private let settings = AppSettings()
    private var inventoryPanel: InventoryPanel!
    private var settingsWindow: SettingsWindowController!
    private var clipboardWatcher: ClipboardWatcher!
    private var eventTap: KeyboardEventTap!
    private var toggleHotKey: GlobalHotKey!
    private var statusItem: NSStatusItem!
    private var pauseMenuItem: NSMenuItem!
    private var permissionMenuItem: NSMenuItem!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "CopyDockIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        configureApplicationMenu()

        inventoryPanel = InventoryPanel(store: store, settings: settings)
        settingsWindow = SettingsWindowController(
            settings: settings,
            onResetLayout: { [weak self] in self?.inventoryPanel.resetLayout() },
            onHardReset: { [weak self] in self?.hardReset() }
        )
        clipboardWatcher = ClipboardWatcher(
            store: store,
            maximumBytes: { [settings] in settings.maximumCaptureBytes }
        )
        eventTap = KeyboardEventTap(store: store, panel: inventoryPanel, watcher: clipboardWatcher)
        toggleHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.inventoryPanel.toggleDock()
        }

        inventoryPanel.onRequestAccessibility = { [weak self] in self?.requestAccessibilityFromInventory() }
        inventoryPanel.onOpenSettings = { [weak self] in self?.showSettings() }
        clipboardWatcher.onCaptureRejected = { [weak self] error in
            self?.inventoryPanel.showCaptureRejection(error)
        }
        store.onChange = { [weak self] in self?.inventoryPanel.reloadSlots() }

        configureStatusItem()
        inventoryPanel.showDock()
        clipboardWatcher.start()
        _ = eventTap.start(requestPermission: true)
        refreshPermissionState()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPermissionState()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        PromisedFileMaterializer.shared.cleanupAll()
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "CopyDock")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide CopyDock", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit CopyDock", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        NSApplication.shared.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "CopyDock")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "CopyDock"

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Show / Hide Inventory", action: #selector(toggleInventory), keyEquivalent: " ")
        toggle.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(toggle)
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")

        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        for position in DockPosition.allCases {
            let item = NSMenuItem(title: position.displayName, action: #selector(changePosition(_:)), keyEquivalent: "")
            item.representedObject = position.rawValue
            item.target = self
            positionMenu.addItem(item)
        }
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)

        menu.addItem(withTitle: "Reset Dock Layout", action: #selector(resetLayout), keyEquivalent: "")
        menu.addItem(.separator())
        pauseMenuItem = NSMenuItem(title: "Pause Capture", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(pauseMenuItem)
        menu.addItem(withTitle: "Ignore Next Copy", action: #selector(ignoreNextCopy), keyEquivalent: "")
        menu.addItem(withTitle: "Clear All Slots", action: #selector(clearAll), keyEquivalent: "")
        menu.addItem(.separator())

        permissionMenuItem = NSMenuItem(title: "Enable Keyboard Shortcuts…", action: #selector(requestAccessibility), keyEquivalent: "")
        permissionMenuItem.target = self
        menu.addItem(permissionMenuItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CopyDock", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items where item.target == nil && item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    @objc private func toggleInventory() { inventoryPanel.toggleDock() }

    @objc private func showSettings() { settingsWindow.show() }

    @objc private func changePosition(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let position = DockPosition(rawValue: rawValue) else { return }
        settings.position = position
    }

    @objc private func resetLayout() { inventoryPanel.resetLayout() }

    @objc private func togglePause() {
        store.isCapturePaused.toggle()
        pauseMenuItem.state = store.isCapturePaused ? .on : .off
        pauseMenuItem.title = store.isCapturePaused ? "Resume Capture" : "Pause Capture"
    }

    @objc private func ignoreNextCopy() { store.ignoreNextCapture = true }
    @objc private func clearAll() {
        PromisedFileMaterializer.shared.cleanupAll()
        store.clearAll()
    }
    @objc private func requestAccessibility() { requestAccessibilityFromInventory() }

    private func requestAccessibilityFromInventory() {
        _ = eventTap.start(requestPermission: true)
        if !eventTap.hasAccessibilityPermission,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissionState()
    }

    private func refreshPermissionState() {
        if eventTap.hasAccessibilityPermission && !eventTap.isRunning {
            _ = eventTap.start(requestPermission: false)
        }
        let enabled = eventTap.hasAccessibilityPermission && eventTap.isRunning
        inventoryPanel.setShortcutStatus(enabled: enabled)
        permissionMenuItem?.title = enabled ? "Keyboard Shortcuts Enabled" : "Enable Keyboard Shortcuts…"
        permissionMenuItem?.isEnabled = !enabled
    }

    private func hardReset() {
        PromisedFileMaterializer.shared.cleanupAll()
        store.clearAll()
        store.isCapturePaused = false
        store.ignoreNextCapture = false
        settings.resetToDefaults()
        pauseMenuItem.state = .off
        pauseMenuItem.title = "Pause Capture"
        inventoryPanel.resetLayout()
        inventoryPanel.showDock()
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
