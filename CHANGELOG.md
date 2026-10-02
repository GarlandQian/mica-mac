# Changelog

## 0.33.0 - 2026-10-02

### Workbench

- Adopted the macOS 27 Liquid Glass design: the unified toolbar, floating sidebar, and inspector are now drawn by the system instead of a painted page fill.
- Moved content to system semantic colors and grouped fills, so the workbench follows Increase Contrast, Reduce Transparency, and the glass tint preference.
- Refreshed panels, topology, telemetry, proxy nodes, and badges with borderless concentric cards, continuous corners, capsule tags, and inset data tables.
- Grouped toolbar commands with visibility priorities, pinned the controller switcher above sidebar navigation, and presented proxy node previews on Liquid Glass.
- Redesigned proxy node details as one framed card with summary and capability tags, titled section cards, aligned key-value rows, localized test times, and a delay-history strip.
- Added a menu bar item with live upload and download rates and per-group node switching; while shown it keeps the controller session running after the last window closes, and Settings can hide it.
- Policy groups can sort the displayed nodes by lowest latency from a Sort Nodes menu; controller order stays the default and the catalog is never reordered.
- Controllers rows now offer one-click Use and native drag reordering; Actions presents each command as a card with a single Run command and in-card confirmation.
- Overview shows operational summaries and network information by default, and saved Overview preferences are upgraded once to include them; the redundant instrument rail is opt-in.
- Network information groups align to the top of their columns, and ports show as plain numbers without digit grouping.
- Scan tables draw unreported values as quiet dashes, drop repeated row icons and placeholder separators, and use consistent title-case headers.
- Logs shows error and warning totals beside the entry count; each jumps to the newest visible entry of that level.
- Rules can be narrowed by reported type and target policy from facet menus with per-value counts.
- Made the Logs level a segmented choice with accurate help, made Follow Newest a toggle button, and combined the editor's scheme, host, and port into one address row with a live URL preview.
- Action, Configuration, and Diagnostics bars name the target controller instead of repeating the page title.
- Inspectors collapse unreported fields into one summary line per section; the policy-group directory gained rounded selection, hover, and group types, and duplicate Locate and status-badge commands were removed.
- Configuration shows a small set of outbound modes as a segmented control, and management forms place controls at the trailing edge like System Settings.
- Settings previews Appearance and interface text size as tiles; its first section is now General.
- Diagnostics leads with a status-tinted verdict card with fact tags and shows working areas as navigation cards.
- Bulk and destructive commands (Close All, Close Connection/Group, Clear Logs, Update All Sources) are titled buttons; the editor bar names the controller being edited.

### Verification

- Scroll interaction timing (explicit gestures versus wheel bursts) is a pure state machine tested with explicit instants, removing the wall-clock wait that made a table scroll test flaky under load.
- New rules are verified by named behavior tests that the source contract requires, replacing several implementation-text checks.
- `Localizable.xcstrings` is kept canonical by `scripts/normalize-localizations.mjs`, and the source contract rejects unsorted or reformatted catalogs.

## 0.32.0 - 2026-09-23

### Reliability and controller data

- Improved persisted profile and credential recovery, live-session task ownership, and runtime log publication.
- Added bounded backpressure for sing-box event streams and more reliable Mihomo endpoint encoding and policy projections.
- Reduced redundant Surge and Mihomo projection work while preserving controller order and reported values.

### Workbench

- Improved live catalog observation, table scroll continuity, connection navigation, and timeline selection behavior.
- Refined source timestamp handling and deferred presentation updates while users interact with tables.

### Verification

- Added regression and performance coverage for credential storage, controller streaming, profile lifecycle, scrolling, navigation, and projection behavior.
- GitHub Actions validates the macOS 27 toolchain, source contracts, tests, and release build.

## 0.31.0 - 2026-09-23

### Workbench

- Refined Overview topology presentation with focused and complete display modes, route summaries, viewport-aware sizing, and improved dense-path navigation.
- Hardened live-session task supervision, command scopes, generation ownership, cross-surface navigation, and workspace lifecycle handling.
- Expanded controller projections and Surge connection-route data while preserving reported order, optionality, and credential boundaries.

### Verification

- Added regression coverage for topology summaries, route projections, live-session ownership, navigation, rendering, and performance behavior.
- Release build and the complete offline test suite pass.

## 0.30.0 - 2026-09-13

### Workbench

- Reworked the native Workbench around live controller data, with dedicated workspace, monitor, and controller destinations.
- Improved topology readability, proxy navigation, policy-group interaction, and cross-surface state ownership.
- Hardened live-session publication, controller selection, refresh boundaries, and asynchronous command ownership.

### Verification

- Expanded offline source-contract, controller-boundary, navigation, rendering, and performance coverage.
- Kept Mica remote-controller-only with no bundled or launched local core.

## 0.29.0 - 2026-07-10

### Rebuilt

- Replaced the old four-workspace Dashboard, Control Bay, Command Bar, and Command Palette with a single native SparkXie-aligned Workbench.
- Added dedicated Overview, Policy Groups, Connections, Rules, Sources, Logs, Core Config, Core Actions, Diagnostics, and Settings destinations.
- Moved controller profile editing into the main-window detail region.
- Rebuilt settings so language, appearance, and font scale apply immediately to the main window and Settings scene.

### Data

- Preserved raw Mihomo `/proxies` JSON object-key order instead of sorting policy groups by name or `GLOBAL` membership.
- Added regression coverage for controller order, escaped quotes, and surrogate-pair Unicode policy names.
- Exposed full reported connection IDs, hosts, process/path, source/destination, rules, payloads, chains, and metadata in the active UI.
- Rebuilt rules as payload-first rows and sources as proxy-source/rule-set rows using real provider fields.
- Kept unavailable fields explicit and removed fabricated presentation labels and mock data paths.

### Interface

- Applied the Rose Pine Dawn/Main palette to light and dark appearances.
- Reserved Liquid Glass/material for navigation and action chrome; data content uses restrained fills and separators.
- Added inline expandable policy-group blocks with node selection, delay testing, loading, and fixed-selection boundaries.
- Made controller names and endpoints fully visible and font-scale-aware in the sidebar.
- Removed the persistent startup profile-load banner.
- Removed obsolete command-palette, Control Bay, Routing/Traffic workspace, and command-home localization keys.

### Controller Operations

- Kept Mica as a remote controller only: no bundled or launched local core and no system proxy/firewall/OpenWrt changes.
- Added capability-gated Mihomo remote config, provider, connection, cache, restart, and upgrade paths.
- Added Surge HTTP API support through `X-Key` with backend-specific policy, request, DNS, and near-live boundaries.
- Kept Tailscale hidden until a backend reports real support.

### Verification

- Added a source contract covering the replacement architecture, data visibility, ordering, localization, visual tokens, and forbidden legacy surfaces.
- Added a network-free runtime smoke probe covering English/Chinese, system/light/dark, four font scales, menus, help, accessibility, and every visible destination.
- Swift build passes and 18 unit tests pass.
- Visual smoke passed for Chinese/dark/extra-large and English/light/standard configurations.
