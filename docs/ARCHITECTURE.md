# Architecture

CopyDock is a small AppKit application with SwiftUI used for Settings. It has no server component and no third-party runtime dependency.

## Components

- `CopyDockCore.ClipboardSnapshot` captures pasteboard items and representations, derives text/file/image previews, and reconstructs pasteboard items.
- `CopyDockCore.PrivacyFilter` rejects concealed, transient, auto-generated, and known password-manager types.
- `CopyDockCore.SlotStore` owns exactly nine optional snapshots and the most-recently-copied pointer.
- `ClipboardWatcher` observes ordinary clipboard changes and places accepted data in slot 1.
- `KeyboardEventTap` implements Command-C/V followed by digits and coordinates pasteboard swapping.
- `GlobalHotKey` registers the permission-free Command-Shift-Space toggle.
- `InventoryPanel` renders the floating dock, drag/drop surfaces, controls, and delayed previews.
- `PromisedFileMaterializer` turns lazy file promises into scoped temporary files and manages cleanup.
- `AppSettings` stores non-content preferences; `SettingsWindow` presents them.

## Copy flow

1. The keyboard event tap sees Command-C and waits briefly for an optional digit.
2. macOS performs the normal copy.
3. CopyDock reads all available pasteboard item representations.
4. The privacy filter and configured byte ceiling validate the snapshot.
5. The snapshot enters slot 1 or the selected slot and the dock refreshes.

## Paste flow

1. The event tap sees Command-V and waits for an optional digit.
2. With no digit, CopyDock sends the ordinary paste unchanged.
3. With a digit, CopyDock saves the current pasteboard, writes the selected snapshot, sends Command-V, and restores the saved pasteboard after 350 ms.

## Trust boundaries

Clipboard payloads and promised files are untrusted input. Preview generation is bounded by a configurable item-size limit and 1,440-pixel image thumbnail cap. CopyDock never executes clipboard data or uploaded files. Accessibility permission is used only for keyboard interception and synthesized paste, but macOS grants it process-wide; users should run trusted builds only.
