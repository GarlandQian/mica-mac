# Mica Architecture

## Repository And Targets

Mica is a Swift Package, not a hand-maintained `.xcodeproj`:

| Path | Responsibility |
|---|---|
| `Package.swift` | Swift 6.2 package manifest, products, targets, macOS deployment target. |
| `Sources/MicaCore/` | HTTP/WebSocket/gRPC controller transport, endpoint/RPC construction, response/DTO models, unified capability models, profile persistence, and secret stores. |
| `Sources/Mica/` | App entry, AppModel/session coordination, presentation models, localization/preferences, and native UI. |
| `Sources/Mica/Features/Workbench/` | Active main-window navigation and all workbench pages. |
| `Tests/MicaCoreTests/` | Protocol, model, and storage tests. |
| `Tests/MicaTests/` | Session, transaction, presentation, and layout tests. |
| `Sources/Mica/Resources/Localizable.xcstrings` | English and Simplified Chinese catalog. |
| `scripts/` | Source verification, gRPC generation, and offline benchmarks. |

`Mica` is the executable and depends on the UI-free `MicaCore` library.
Inspect `Package.swift` for current dependency versions and target settings.
The generated workspace under `.swiftpm/` is disposable, not project source.

## Application Composition

`MicaApp` owns scenes and shared stores; `ContentView` owns the split view,
lifecycle, and same-window controller editing; `WorkbenchRootView` owns routing,
shared session commands, visible-domain mapping, and status chrome.
`WorkbenchDestination` is the sole top-level navigation model; see the
Workbench UI contract for its current cases.

## State And Data Flow

Runtime flow: profile and credential -> side-effect-free probe -> backend
client -> MicaCore response model -> generation-owned session/runtime ->
presentation catalog -> Workbench view.

- `MicaCore` owns backend-specific response models, transport, capabilities,
  and controller-neutral summaries.
- `Mica` owns persistence, the selected session, catalogs, projections,
  preferences, and UI.
- `UnifiedControllerSnapshot` is a neutral summary, not the full visible-data
  model. Views consume narrow catalogs and never decode or create network tasks.

`AppModel` is `@MainActor @Observable` and owns profiles, credentials, the
selected session, effective runtime controller type, operation tasks, and
observable presentation state. `ControllerSession` owns one selected-controller
generation and its committed lifecycle/last-value state.

`LiveSessionRuntime` owns high-frequency raw ingestion off the main actor and
publishes immutable domain envelopes. `SessionRefreshCoordinator` owns the
generation's REST lanes and coalescing. `WorkbenchWorkspaceStore` owns narrow
per-controller/per-destination interaction state, not live data.

Every asynchronous apply validates selected controller ID and session
generation. Publications from `LiveSessionRuntime` also validate monotonic
domain revision. Switching, replacing, or deleting the selected controller,
sleep, and final-window close invalidate the generation and cancel its task
tree. See
`.trellis/spec/frontend/live-session-controller-contract.md` for cadence,
buffer, retry, pause, reconnect, and transaction details.

## Dependency Injection And Persistence

Core seams are `ControllerAdapterProtocol`, `RouterProfileStore`, and
`SecretStore`. HTTP clients accept injectable URL loading where implemented;
`SingBoxGRPCClientProtocol` and the in-process gRPC fixture cover StartedService.

`RouterProfile` stores only `secretReference`. Profile transactions persist
before observable mutation and roll back credential changes on failure.

`JSONRouterProfileStore` is the profile store. `FileSecretStore` is currently
the production default; `KeychainSecretStore` exists but is not wired as the
default. In-memory stores support tests. Do not claim a broader transport or
security abstraction than these implemented seams.

## Concurrency Ownership

- UI-observable mutation stays on `@MainActor AppModel`; raw live mutation
  stays in `LiveSessionRuntime`.
- HTTP clients and persistence stores are actors; cross-actor payloads are
  `Sendable`.
- Long-lived work uses existing operation slots and the selected generation.
  Reuse `SessionRefreshCoordinator`, `SessionRetryPolicy`, and the structured
  sing-box task tree instead of adding polling/retry subsystems.
- Preserve last successful data after later endpoint failures.
- Performance signposts contain typed counts/categories only, never controller
  business data, identifiers, credentials, logs, or raw payloads.

## SwiftUI And AppKit Boundary

SwiftUI owns content UI. AppKit is limited to application/window lifecycle,
appearance application, sleep/wake notifications, pasteboard export, adaptive
color bridging, and optional runtime inspection. Do not add AppKit-hosted
Workbench content or a parallel AppKit navigation/state layer.
