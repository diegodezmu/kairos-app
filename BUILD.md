# Kairos Build

Run all commands from the repository root.

Before the first build, initialize submodules:

```sh
git submodule update --init --recursive
```

## Commands

```sh
swift test --package-path KairosCore
swift build --package-path KairosCore
xcodebuild -scheme Kairos -destination 'platform=macOS' build
```
