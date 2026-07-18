# Mica Architecture

## Contents

- [Sources of truth](#sources-of-truth)
- [Repository and targets](#repository-and-targets)
- [Application composition](#application-composition)
- [State and data flow](#state-and-data-flow)
- [Dependency injection and persistence](#dependency-injection-and-persistence)
- [Concurrency ownership](#concurrency-ownership)
- [SwiftUI and AppKit boundary](#swiftui-and-appkit-boundary)

## Sources Of Truth

Use this precedence when facts disagree:

1. `Package.swift`, current source, and current tests.
2. Active contracts under `.trellis/spec/`, especially:
   - `.trellis/spec/backend/controller-data-contract.md`
   - `.trellis/spec/frontend/live-session-controller-contract.md`
   - `.trellis/spec/frontend/workbench-ui-contract.md`
3. `AGENTS.md` project decisions.
4. `docs/` and `README.md` as maintained summaries.
5. Archived Trellis tasks and external reference projects only as historical evidence.

Do not turn an archived plan, enum case, or documentation sentence into a runtime capability without checking the implementation.

## Repository And Targets

Mica is a Swift Package, not a hand-maintained `.xcodeproj`:

| Path | Responsibility |
|---|---|
| `Package.swift` | Swift 6.2 package manifest, products, targets, macOS deployment target. |
| `Sources/MicaCore/` | HTTP/WebSocket/gRPC controller transport, endpoint/RPC construction, response/DTO models, unified capability models, profile persistence, and secret stores. |
| `Sources/Mica/` | App entry, AppModel/session coordination, presentation models, localization/preferences, and native UI. |
| `Sources/Mica/Features/Workbench/` | Active main-window navigation and all workbench pages. |
| `Tests/MicaCoreTests/` | Protocol/model/storage tests, primarily XCTest. |
| `Tests/MicaTests/` | Session, transaction, layout, and presentation tests using Swift Testing. |
| `scripts/verify-real-controller-source.mjs` | Static durable-contract verifier for source architecture and visible product rules. |
| `Sources/Mica/Resources/Localizable.xcstrings` | English source catalog plus Simplified Chinese translations. |
| `.trellis/spec/` | Executable project contracts loaded before implementation. |
| `tmp/codex/` | Required repository-local scratch/build/DerivedData location for agent work. |

Package products and targets:

- `Mica`: executable target depending on `MicaCore`; processes `Sources/Mica/Resources`; embeds `Sources/Mica/App/Info.plist` with linker `-sectcreate` flags.
- `MicaCore`: library target with no UI dependency.
- `MicaCoreTests`: test target for `MicaCore`.
- `MicaTests`: test target importing both `Mica` and `MicaCore`.

The current local Xcode workspace is generated under `.swiftpm/xcode/package.xcworkspace`; `.swiftpm/` is ignored and is not the project source of truth. Shared schemes currently include `Mica`, `MicaCore`, and `Mica-Package`.

`MicaCore` directly depends on the exact versions declared in `Package.swift`: `grpc-swift-2` 2.4.2, `grpc-swift-nio-transport` 2.9.0, `grpc-swift-protobuf` 2.4.1, and `swift-protobuf` 1.38.0. They implement the native sing-box StartedService boundary and must not leak transport types into SwiftUI presentation code.

## Application Composition

`Sources/Mica/App/MicaApp.swift` is the `@main`, `@MainActor` entry point.

- It creates one main `WindowGroup` and one native `Settings` scene.
- It owns the shared `@State AppModel` and `AppPreferencesStore`.
- It injects language, appearance, font scale, locale, dynamic type, control size, color scheme, and accent through `micaAppPreferences`.
- It defines standard File/View/Controller menu commands and focused command routing.
- `MicaAppDelegate` only activates the normal macOS application and brings the first window forward.

`ContentView` owns the root `NavigationSplitView` and same-window controller editor replacement. It also:

- persists `WorkbenchDestination`;
- migrates legacy navigation keys once;
- starts loading persisted profiles;
- forwards sleep/wake and final-main-window lifecycle to AppModel;
- coordinates dirty-editor navigation and `MainWindowCloseGuard`.

`WorkbenchRootView` owns destination routing, toolbar controller selection, search placement, Test/Refresh/Pause controls, and the fixed bottom session status bar.

`WorkbenchDestination` is the only top-level navigation enum. Its eleven fixed cases are:

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
11. Settings

## State And Data Flow

The implemented flow is:

```text
RouterProfile + credential
  -> side-effect-free HTTP + StartedService probe when needed
  -> MihomoClient / SurgeHttpAPIClient / SingBoxGRPCClient
  -> HTTP DTOs or generated protobuf messages -> MicaCore response models
  -> ControllerSession endpoint cache, SurgeControlSnapshot, or sing-box stream state
  -> DashboardSnapshot / view-state projections
  -> Workbench SwiftUI views
```

Important boundaries:

- `MicaCore` response models describe controller payloads and preserve backend detail.
- `UnifiedControllerSnapshot` is a controller-neutral summary used for capabilities, health, and diagnostics. It is not the full visible-data model.
- `DashboardSnapshot`, `ProxyGroupViewState`, `RuleViewState`, `ProxyProviderViewState`, and connection projections are app/presentation state.
- Pure presentation helpers under `Features/Workbench` filter, group, sort a copy for native table sort order, or bound local reveal windows. They do not perform network I/O.
- SwiftUI views consume AppModel and presentation values. They must not instantiate protocol decoders or create endpoint tasks.

`AppModel` is `@MainActor @Observable`. It owns:

- stored profiles, selected profile ID, cached credentials, and profile transactions;
- the active `ControllerSession` and effective auto-detected backend;
- endpoint refresh and stream task handles marked `@ObservationIgnored`;
- dashboard/unified/Surge/sing-box presentation snapshots;
- capability-gated operations and operation/command status;
- language-aware cached presentation state.

`ControllerSession` owns one selected-controller generation and its generation-scoped state:

- fast/medium/slow refresh lane states;
- last successful endpoint values;
- pending paused presentation;
- bounded traffic, logs, and closed-connection state;
- sing-box version/status/groups/mode/connections/Tailscale state and its independent Tailscale error;
- transfer-rate derivation and runtime counters;
- live-observation diagnostics.

Switching, replacing, deleting the active controller, sleeping, or closing the final main window invalidates the generation and cancels the task tree. Every asynchronous publish must validate selected controller ID, session controller ID, and generation.

## Dependency Injection And Persistence

Project protocols:

- `ControllerAdapterProtocol`: controller-neutral test/snapshot interface.
- `RouterProfileStore`: asynchronous profile load/save.
- `SecretStore`: asynchronous credential read/save/delete.

Concrete stores:

- `JSONRouterProfileStore` writes `~/Library/Application Support/Mica/routers.json` atomically.
- `FileSecretStore` is the current `AppModel` default and writes a separate plaintext `secrets.json` keyed by profile UUID.
- `KeychainSecretStore` exists but is not the current default.
- `InMemoryRouterProfileStore` and `InMemorySecretStore` support deterministic tests.

`RouterProfile` stores only `secretReference`, never the credential value. Profile save/delete operations persist before mutating observable state and roll back credential changes if profile persistence fails.

Client injection differs today:

- `MihomoClient` accepts an optional `URLSession`.
- `SurgeHttpAPIClient` accepts an optional `URLSession` and has an internal injectable `SurgeHTTPDataLoader` initializer used by protocol request tests.
- `SingBoxGRPCClient` conforms to `SingBoxGRPCClientProtocol`; generated StartedService clients are wrapped by `SingBoxStartedServiceAdapter`, and tests use the gRPC in-process transport fixture.

Do not claim a general transport abstraction exists beyond those implemented seams.

## Concurrency Ownership

- Keep UI-observable mutation on `@MainActor AppModel`.
- Keep HTTP clients and persistence stores as actors.
- Keep cross-actor payloads `Sendable`; MicaCore response models generally conform to `Sendable` and `Equatable`.
- Store long-lived operation and stream tasks on AppModel, cancel the previous task for the same operation slot, and clear both task and busy marker on termination.
- Reuse `SessionRefreshLaneState` single-flight/coalescing and `SessionRetryPolicy`; do not add a competing polling loop.
- Keep all sing-box StartedService producers as children of one structured throwing task group. Cancellation must propagate to every stream and the gRPC client channel; do not add a second lossy cross-domain event queue.
- Classify failures through `RouterTrialFailureCategory` before deciding retry behavior or user-facing copy.
- Preserve last successful endpoint data after later failures; only never-loaded data becomes an error empty state.

## SwiftUI And AppKit Boundary

SwiftUI owns all content UI: scenes, navigation, forms, tables, inspectors, toolbars, settings, controller editor, empty states, and Liquid Glass controls.

Current AppKit usage is narrow and infrastructure-oriented:

- `MicaAppDelegate`: activation policy and initial window activation.
- `AppAppearance`: applies `NSAppearance` to the application and existing windows.
- `MainWindowCloseGuard`: `NSWindowDelegate` forwarding and native destructive dirty-close confirmation.
- `ContentView`: `NSWorkspace` sleep/wake notifications.
- `AppModelDiagnostics`: `NSPasteboard` export.
- `MicaStyle`: adaptive `NSColor` construction.
- `AppRuntimeSmokeProbe`: optional non-controller runtime inspection.

Do not add AppKit-hosted workbench content or an AppKit parallel navigation/state layer. Introduce AppKit only for a macOS service that SwiftUI does not expose adequately, and keep observable content state in AppModel/SwiftUI.
