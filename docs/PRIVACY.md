# Privacy

CopyDock is designed around temporary, local clipboard use.

## Data CopyDock reads

- Clipboard representations produced by explicit copy actions and supported drag-and-drop operations.
- Local file URLs and metadata needed to preview or re-drop Finder items.
- Accessibility trust state, solely to enable global numbered shortcuts and synthesized paste.
- Local appearance, placement, preview, and capture-limit preferences.

## Storage and retention

The nine slot contents exist in process memory only and disappear when CopyDock quits. Settings persist through macOS `UserDefaults`; they do not contain clipboard payloads. Lazy file promises are copied to a uniquely named directory under the macOS temporary directory. Those files are removed when the relevant slot is replaced or cleared, on hard reset, on normal quit, and on the next launch after a crash.

## Network activity

CopyDock contains no networking, cloud sync, account, update-checking, analytics, advertising, or telemetry implementation. Building or downloading CopyDock may involve GitHub, but the running application does not.

## Filtering

CopyDock refuses clipboard snapshots marked concealed, transient, or auto-generated and blocks identifiers associated with several password managers. Filtering is defensive rather than a guarantee: applications can expose sensitive content under ordinary public pasteboard types. Pause capture or use **Ignore Next Copy** before handling sensitive material.

## Clearing data

- **Clear All** removes all nine clipboard slots and materialized promise files.
- **Hard Reset CopyDock** also restores all preferences to their defaults.
- Quitting clears all in-memory clipboard content.
- To remove saved preferences manually, quit CopyDock and delete preferences for `com.marcowidodo.copydock`.

## Permission model

The global show/hide shortcut uses a permission-free Carbon hot key. Numbered copy/paste uses a keyboard event tap and therefore requires Accessibility access. Drag-and-drop, previews, settings, and manual controls remain available without it.
