# Kairos Build

Run all commands from the repository root.

`KairosCore` provisional iOS deployment target: `iOS 17.0`.
This is a scaffolding default for F1-00 and can be revisited in Phase 2.

## Commands

```sh
swift test --package-path KairosCore
swift build --package-path KairosCore
xcodebuild -scheme Kairos -destination 'platform=macOS' build
```

Optional iOS validation for the package:

```sh
cd KairosCore
xcodebuild -scheme KairosCore -destination 'generic/platform=iOS' build
```
