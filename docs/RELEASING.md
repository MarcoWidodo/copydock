# Releasing CopyDock

## Preflight

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Support/Info.plist`.
2. Update `CHANGELOG.md` and the version statement in `README.md`.
3. Run `swift build --product CopyDock`.
4. Run `swift run CopyDockChecks` and `swift run CopyDock --self-check-preview`.
5. Run `./scripts/build-app.sh release` and complete the manual matrix in `CONTRIBUTING.md`.
6. Inspect the bundle metadata with `plutil -p dist/CopyDock.app/Contents/Info.plist` and verify its signature with `codesign --verify --deep --strict --verbose=2 dist/CopyDock.app`.

## Friend-share build

The build script applies an ad-hoc signature. Package it without extended attributes:

```sh
ditto -c -k --sequesterRsrc --keepParent dist/CopyDock.app dist/CopyDock-0.6.0.zip
shasum -a 256 dist/CopyDock-0.6.0.zip
```

Create an annotated Git tag matching the version and attach the ZIP plus checksum to a GitHub release. Explain that it is not notarized and document the Control-click **Open** procedure.

## Wider distribution

Before distributing beyond trusted friends:

1. Join the Apple Developer Program and install a Developer ID Application certificate.
2. Replace ad-hoc signing with hardened-runtime Developer ID signing.
3. Submit the ZIP to Apple's notary service with `notarytool`.
4. Staple the notarization ticket to the app and re-verify Gatekeeper assessment.
5. Test a clean download on a separate Mac and both supported architectures.

Never commit signing certificates, App Store Connect credentials, notary profiles, or generated release archives.
