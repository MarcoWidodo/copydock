# Troubleshooting

## Command-Shift-Space does nothing

Another app may own the shortcut. Use the CopyDock menu-bar icon to show the inventory, then quit or reconfigure the conflicting app. This toggle does not require Accessibility permission.

## Command-C/V plus a number changes tabs instead

Open the inventory and click **Enable Shortcuts**. In **System Settings → Privacy & Security → Accessibility**, enable CopyDock. If CopyDock was replaced by a newly built copy, remove the stale entry, add the current app, then quit and reopen CopyDock.

## A numbered paste does not arrive in one app

The destination may read the pasteboard after CopyDock restores it. Try drag-and-drop for that app. An app-specific paste-delay setting is planned; the current restore delay is 350 ms.

## A preview is blank or generic

Confirm the original file still exists and is readable. CopyDock supports common ImageIO formats, while proprietary formats use the native file icon and metadata. A source app may provide a private representation with no public preview even though paste still works in that app.

## The dock layout looks wrong

Hide and show the dock, choose **Reset Dock Layout**, or drag it toward a screen edge. Hard reset is available in Settings and clears all slots as well as preferences.

## CopyDock will not open

For an ad-hoc build, Control-click the app and select **Open** on first launch. Do not disable system-wide Gatekeeper. If macOS reports that the app is damaged, download it again from the repository's release page or build it from source.

## Collecting useful diagnostics

When filing an issue, include the CopyDock and macOS versions, Mac architecture, source and destination applications, clipboard type (text/image/file), and exact steps using non-sensitive sample content. State whether drag-and-drop works and whether Accessibility is enabled. Never attach private clipboard contents.
