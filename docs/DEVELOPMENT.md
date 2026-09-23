# Development

## Local Verification

All disposable output belongs under `tmp/codex/`.

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
git diff --check
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
```

The source verifier checks localization and active implementation boundaries;
it does not depend on agent configuration or task-management files. Swift tests
exercise protocol behavior, session ownership, ordering, presentation caches,
and navigation. Production application launch and real-controller checks are
separate from these offline tests.

When explicitly authorized, run the optional smoke syntax and probe separately:

```bash
node --check scripts/verify-runtime-smoke.mjs
node scripts/verify-runtime-smoke.mjs tmp/codex/swift-build/debug/Mica
```

For measured hot-path changes, run the opt-in offline Release benchmark after the focused tests:

```bash
scripts/run-performance-benchmarks.sh before
scripts/run-performance-benchmarks.sh after
```

The command uses deterministic local fixtures, writes JSON under `tmp/codex/performance/<label>/`, and never reads profiles or contacts a controller. Compare matching case names and fixture counts; wall-clock build time is not comparable unless both runs start from an explicitly clean, identical scratch directory.

## Native sing-box Dependencies

`Package.swift` pins the StartedService transport dependencies exactly:

- `grpc-swift-2` 2.4.2
- `grpc-swift-nio-transport` 2.9.0
- `grpc-swift-protobuf` 2.4.1
- `swift-protobuf` 1.38.0

The license files in the resolved SwiftPM checkouts are Apache License 2.0. Generated protobuf Swift files are checked in; regenerate them only through `scripts/generate-sing-box-grpc.sh`. A future DMG/Sparkle packaging task must include the required third-party license notices.

## Dependency Decisions

Third-party Swift packages are allowed across UI and controller code when a mature package materially improves correctness, performance, security, protocol integration, or long-term maintenance. Before changing `Package.swift`, verify macOS 27 and Swift 6.2 support, maintenance activity, redistributable licensing, transitive/build/binary cost, concurrency and cancellation behavior, and whether Apple frameworks or a small local implementation already solve the problem cleanly. Record the rationale and boundary tests with the change.

The current dependency audit found only the four direct gRPC/protobuf packages listed above, all required by sing-box StartedService. The Workbench uses Observation, native Swift concurrency, Swift Charts, `Canvas`, and local bounded/indexed data structures. The July 2026 performance bake-off found no chart, collection, scheduler, persistence, or localization package that justified extra runtime/build/license cost, so no dependency was added.

## UI Smoke

Offline rendering uses the production Workbench views in an isolated test-owned
window, in-memory profile and secret stores, a disposable preference suite, and
deterministic local samples. It excludes the production session lifecycle and
asserts that no session tasks or controller clients were created. AppKit caches
only that test window's own view hierarchy at its native backing scale, including
native Lists, Tables, Charts, and Canvas, then the harness closes it. No desktop
capture or screen-recording permission is required. Pixel checks reject blank
surfaces and unreadable native sidebar text. These native view snapshots verify
layout and content; they do not reproduce WindowServer occlusion, shadows, or
final material compositing.

On the current macOS host, cached native sidebar vibrancy produces black selected
rows even in an isolated system-control probe. The sidebar contrast assertion
therefore remains a failure for full-window snapshots; do not treat readable
business content as complete window validation or weaken that assertion.

```bash
MICA_RENDER_DESTINATIONS=all \
MICA_RENDER_OUTPUT_DIR="$PWD/tmp/codex/workbench-rendering" \
swift test --scratch-path tmp/codex/swift-build --filter WorkbenchRenderingTests
```

This renders all ten destinations with 820x580 and 1440x900 content viewports in
English/Chinese and light/dark appearance, including the policy-group directory
and active member list. Captures also include the native title bar at its actual height, without
rescaling. Omit `MICA_RENDER_DESTINATIONS` for Overview only, or pass comma-separated
destination IDs for a focused check. The test skips unless its output directory
is explicitly set beneath `tmp/codex/`.

Set `MICA_RENDER_SURFACE=topology` for the production topology alone. Add
`MICA_RENDER_TOPOLOGY_DENSE=1` for shared multi-stage routes, or `stress` for
1,000 connections across 66 nodes and 600 edges. `MICA_RENDER_TOPOLOGY_FOCUS=pinned`
captures a selected real path. These variants retain the same offline guards
and filename-separated appearance/viewport matrix.

Set `MICA_RENDER_SELECTION=first` with Connections, Rules, or Sources to exercise
the selected context strip and assert that the table retains usable height.
Rules and Sources also assert that actual native table columns stop before the
inspector boundary; a table's own visible rectangle can extend beneath it when
a localized control inflates its parent.
Combine Connections with the dense topology fixture for longer chains. `MICA_RENDER_INSPECTOR=1`
includes the production inspector for the selected item, without mounting the
live-session lifecycle. Controllers uses additional offline profiles with long
names, DNS endpoints, and IPv6 addresses to check wrapping.

For individual node details, use `MICA_RENDER_DESTINATIONS=proxies`,
`MICA_RENDER_NODE_DETAILS=runtime` and `MICA_RENDER_SELECTION=first`.
The selected node opens inline; Proxies has no separate inspector.
This standard-Mihomo-shaped fixture contains runtime
identity, capabilities, and test state but no original protocol configuration.
Its inspected node differs from the selected node. `WorkbenchProxyNodeInteractionTests`
also clicks the inspection body through the test window and presses the native
action buttons to verify that inspecting, switching, and testing dispatch
independently, including disabled/read-only states.

`MICA_RENDER_NODE_DETAILS=ss` and `vless` are synthetic optional-configuration
fixtures for rendering server/cipher/password or UUID/Reality fields. They do
not establish that real controllers expose those values. Runtime-only, missing
type, and sensitive-extension regressions are tested separately.

When explicitly requested, UI smoke may launch the already-built Mica executable with command-line preference overrides. Do not click Test, Refresh, source update, connection close, or core-action controls during a visual-only pass. Store screenshots, window metadata, temporary homes, and helper scripts under `tmp/codex/`, then remove them when the task no longer needs them.

## Focused Architecture Checks

- `ControllerHTTPRequestExecutorTests` checks family authentication, response
  validation, and cancellation with injected transports.
- `LiveSessionTaskSupervisorTests` checks task replacement, cancellation
  groups, generation rebinding, and late-completion rejection.
- `OverviewViewportLayoutTests` checks readable dimensions across short,
  narrow, and wide windows, including topology priority and one-row trends.
- Topology tests check complete path retention, exact aggregation memberships,
  deterministic ordering, unavailable routes, and access to the complete graph.
- `SurgeConnectionRouteProjectionTests` checks active/recent policy roles,
  missing final policies, equal reported names, and request-order preservation.
- Policy presentation tests check source order, one active member index,
  filtering, current-session acceptance, and reuse of unchanged projections.
- Page-model tests check session isolation, same-ID observation, exact filtered
  navigation, delayed sorting, log follow, and accessibility-page continuity.
- Navigation-model tests check dirty/saving guards, abandoned intents, and
  callbacks from replaced editors.
- Native Table tests verify actual visible rows after initial positioning and
  appending, adjacent-table isolation, user-scroll events, and anchor restoration.

None of these checks requires a running controller or access to saved profiles.

## Product Boundary

Mica is a remote controller application. Development and verification must not download, bundle, start, or run a local core, and must not modify system proxy settings, environment variables, firewall rules, OpenWrt, SSH, or `ubus` state.
