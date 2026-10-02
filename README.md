# Mica

Mica is a native macOS workbench for monitoring and managing remote controller APIs that you configure and operate. It connects to an existing controller; it does not download, bundle, launch, or supervise a local core.

## What you can do

- Review live traffic, connections, logs, rules, sources, and controller health.
- Inspect proxy groups, nodes, and reported route paths.
- Manage controller profiles and use the operations supported by the selected runtime.
- Move between ten workspaces in one native window. Application preferences live in the separate macOS Settings window.

The workspaces are grouped in the sidebar:

| Group | Workspaces |
| --- | --- |
| Workspace | Overview, Proxies, Connections, Rules, Sources |
| Monitor | Logs, Diagnostics |
| Controller | Controllers, Configuration, Actions |

## Supported controllers

| Controller API | Connection |
| --- | --- |
| Mihomo-compatible APIs | Supports Mihomo, Nikki, OpenClash, CMFA, and Stash profiles, with capabilities depending on the runtime |
| Surge | HTTP API with a user-provided `X-Key` |
| sing-box | StartedService over gRPC with optional Bearer authentication |

Auto Detect identifies a supported runtime before enabling its operations. See the [controller compatibility guide](docs/CONTROLLER_COMPATIBILITY.md) for supported operations and runtime-specific limits.

## Data and system boundaries

- Mica presents controller-reported data and preserves its order. Missing values remain visibly unavailable; charts appear only when a real time series is available.
- Diagnostic copies exclude credentials, authorization headers, subscription URLs, Keychain contents, and raw response or stream bodies.
- Mica does not change macOS proxy settings, environment variables, firewall rules, OpenWrt/LuCI, SSH, or `ubus` state.

## Requirements

- macOS 27 or later
- Swift 6.2 or Xcode 27 to build from source
- Node.js to run the source-contract verification script

## Build and run

Build and launch the app with Swift Package Manager:

```bash
swift build --scratch-path tmp/codex/swift-build
swift run --scratch-path tmp/codex/swift-build Mica
```

## Development checks

Run the source and localization checks, then build and test:

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
git diff --check
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
```

See the [development guide](docs/DEVELOPMENT.md) for UI rendering, performance measurements, and optional runtime smoke instructions.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Controller data model](docs/DATA_MODEL.md)
- [Controller compatibility](docs/CONTROLLER_COMPATIBILITY.md)
- [UI guidelines](docs/UI_GUIDELINES.md)
- [Development workflow](docs/DEVELOPMENT.md)
