# Mica

Mica is a native macOS workbench for user-managed remote controllers. It connects to controller APIs that the user has already enabled; it does not download, bundle, start, or supervise a local core.

## Current Workbench

The main window is a single native `NavigationSplitView` with these ten
destinations:

1. Overview
2. Proxies
3. Connections
4. Logs
5. Rules
6. Sources
7. Controllers
8. Configuration
9. Actions
10. Diagnostics

The sidebar groups these destinations into Workspace, Monitor, and Controller. Native
application Settings is separate and opens from the app menu; it is not a
Workbench destination. Policy groups expand inline and preserve controller
order. Node selection, latency tests, connection inspection, and source
inspection stay in the same window rather than opening ordinary sheets or
popovers.

## Data Contract

- Active workspaces show controller-reported business data in full: endpoint, host, request URL, IDs, provider/source names, policy and node names, rule payloads, route chains, and log messages.
- Missing fields render as localized unavailable or not-reported values. Mica does not invent counts, delays, rows, hit rates, or chart samples.
- Charts are allowed only when a real time series exists.
- Copied diagnostics exclude credentials, authorization headers, subscription URLs, Keychain contents, raw response bodies, and raw stream bodies.

## Controller Support

- Mihomo-compatible external-controller APIs, including Nikki, OpenClash, CMFA,
  and Stash profiles, with runtime-specific capability boundaries.
- Surge HTTP API through user-provided `X-Key` access.
- sing-box StartedService over gRPC, including capability-gated status, policy,
  connection, log, and Tailscale operations.
- Auto Detect resolves a supported runtime before exposing its commands; unknown
  or unsupported capabilities remain visibly unavailable.

Tailscale is a readiness- and capability-gated section in Configuration, not a
top-level destination. Mica never treats shared transport code as proof that a
controller family supports every operation.

Mica does not modify macOS proxy settings, environment variables, firewall rules, OpenWrt/LuCI, SSH, or `ubus` state.

## Interface

- English, Simplified Chinese, and Follow System language modes.
- Follow System, Light, and Dark appearance modes.
- Standard, Comfortable, Large, and Extra Large interface text sizes.
- Shared native typography, neutral surfaces, and the macOS accent preference.
- Native toolbar commands, keyboard navigation, SF Symbols, VoiceOver labels, and font-aware sidebar/table layouts.

## Requirements

- macOS 27 or newer.
- Swift 6.2 toolchain or a compatible Xcode release.
- Node.js for source and runtime contract scripts.
- A controller that you operate and authorize yourself.

## Development

Disposable output belongs under `tmp/codex/`.

Default offline checks:

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
git diff --check
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
```

Runtime smoke is an explicitly authorized opt-in check, separate from the
default gate:

```bash
node --check scripts/verify-runtime-smoke.mjs
node scripts/verify-runtime-smoke.mjs tmp/codex/swift-build/debug/Mica
```

The smoke probe exits before `AppModel` is created and does not access a
controller, launch a core, or modify system networking. Run it only when the
user or task explicitly permits runtime smoke.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Controller Data Model](docs/DATA_MODEL.md)
- [Controller Compatibility](docs/CONTROLLER_COMPATIBILITY.md)
- [UI Guidelines](docs/UI_GUIDELINES.md)
- [Development Workflow](docs/DEVELOPMENT.md)
