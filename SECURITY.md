# Security policy

## Supported version

Security fixes currently target the latest release on the `main` branch.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature when it is enabled for this repository. If it is unavailable, open a minimal issue asking for a private reporting channel without including exploit details or clipboard contents.

Include the CopyDock version, macOS version, reproduction steps using non-sensitive test data, expected impact, and whether the issue requires Accessibility permission. Please allow reasonable time for investigation before public disclosure.

## Security boundaries

CopyDock processes clipboard content locally and requires macOS Accessibility permission for global numbered shortcuts and synthesized paste. That permission is powerful: only run builds from source you trust. CopyDock does not claim to protect clipboard contents from other local applications that can access the macOS pasteboard, from screen capture, from compromised accounts, or from malware.

Shared ad-hoc builds are not notarized. The repository owner should sign and notarize wider public releases as described in `docs/RELEASING.md`.
