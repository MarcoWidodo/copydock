# Contributing to CopyDock

Thank you for helping improve CopyDock. Small, focused changes are easiest to review.

## Before opening a change

1. Search existing issues and explain the user problem, not only the proposed implementation.
2. Preserve the defining constraints: nine stable slots, local-only operation, no clipboard-content persistence, and no network dependency.
3. Avoid adding a package dependency when an Apple framework or a small local implementation is sufficient.
4. Never include real passwords, private clipboard data, or identifying file paths in tests, screenshots, or bug reports.

## Development workflow

```sh
swift build --product CopyDock
swift run CopyDockChecks
swift run CopyDock --self-check-preview
```

For UI changes, also build the bundle with `./scripts/build-app.sh` and manually verify:

- all four screen edges and edge snapping;
- 44 pt and 86 pt slot-size extremes;
- None, Glass, and Solid backgrounds at opacity extremes;
- mouse hover timing and preview bounds;
- keyboard behavior with and without Accessibility permission;
- text, formatted text, screenshots, PNG/JPEG files, folders, and multi-file drag/drop;
- Clear All, hard reset, ordinary quit, and relaunch.

## Pull requests

Describe the user-visible behavior, tests performed, privacy or permission impact, and any known compatibility limitations. Add or update checks for core behavior. Keep generated `.app` bundles, archives, local preferences, and `.build` output out of commits.

By contributing, you agree that your contribution is licensed under the MIT License.
