# Mica

Mica is a native macOS workbench for user-managed remote controllers. It connects to controller APIs that the user has already enabled; it does not download, bundle, start, or supervise a local core.

## Current Workbench

The main window is a single native `NavigationSplitView` with these destinations:

1. Overview
2. Policy Groups
3. Connections
4. Rules
5. Sources
6. Logs
7. Core Config
8. Core Actions
9. Diagnostics
10. Settings

The information architecture follows SparkXie controller objects while using native macOS interaction patterns. Policy groups expand inline and preserve the controller's original order. Node selection, latency tests, connection inspection, and source inspection stay in the same window rather than opening ordinary sheets or popovers.

## Data Contract

- Active workspaces show controller-reported business data in full: endpoint, host, request URL, IDs, provider/source names, policy and node names, rule payloads, route chains, and log messages.
- Missing fields render as localized unavailable or not-reported values. Mica does not invent counts, delays, rows, hit rates, or chart samples.
- Charts are allowed only when a real time series exists.
- Copied diagnostics exclude credentials, authorization headers, subscription URLs, Keychain contents, raw response bodies, and raw stream bodies.

## Controller Support

- Mihomo-compatible external-controller APIs, including Nikki and OpenClash profiles.
- Surge HTTP API through user-provided `X-Key` access.
- Future backend families remain capability-only until a real adapter exists.
- Tailscale navigation stays hidden until an adapter reports supported state and operations.

Mica does not modify macOS proxy settings, environment variables, firewall rules, OpenWrt/LuCI, SSH, or `ubus` state.

## Interface

- English, Simplified Chinese, and Follow System language modes.
- Follow System, Light, and Dark appearance modes.
- Standard, Comfortable, Large, and Extra Large interface text sizes.
- Rose Pine Dawn/Main color tokens.
- Native toolbar commands, keyboard navigation, SF Symbols, VoiceOver labels, and font-aware sidebar/table layouts.

## Requirements

- macOS 27 or newer.
- Swift 6.2 toolchain or a compatible Xcode release.
- Node.js for source and runtime contract scripts.
- A controller that you operate and authorize yourself.

## Development

Disposable output belongs under `tmp/codex/`.

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
node --check scripts/verify-runtime-smoke.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
git diff --check
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
node scripts/verify-runtime-smoke.mjs tmp/codex/swift-build/debug/Mica
```

The runtime smoke probe exits before `AppModel` is created and does not access a controller, launch a core, or modify system networking.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Controller Data Model](docs/DATA_MODEL.md)
- [Controller Compatibility](docs/CONTROLLER_COMPATIBILITY.md)
- [UI Guidelines](docs/UI_GUIDELINES.md)
- [Development Workflow](docs/DEVELOPMENT.md)
