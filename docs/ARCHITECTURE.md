# Architecture

## Module Ownership

- `MicaCore` owns controller HTTP/WebSocket/gRPC requests, decoding, endpoint/RPC construction, capability models, and controller-neutral snapshots.
- `Mica` owns profile/credential persistence, application state, presentation availability, localization, appearance, font scale, commands, and SwiftUI composition.
- `Sources/Mica/Features/Workbench/` is the only active main-window information architecture.

## Window Composition

`MicaApp` creates a primary `WindowGroup` and a native Settings scene. `ContentView` owns the `NavigationSplitView`, persisted `WorkbenchDestination`, legacy-navigation migration, main-window lifecycle registration, sleep/wake forwarding, and in-window transactional controller editing. It also coordinates `MainWindowCloseGuard`, a lifecycle-only AppKit delegate proxy that blocks close while saving and presents the native destructive confirmation for a dirty draft. `WorkbenchRootView` provides the controller switcher, native toolbar, search placement, persistent session status bar, focused View-menu navigation, and destination routing.

The sidebar has eleven fixed destinations grouped as Workbench (Overview, Proxies, Connections, Logs, Rules, Sources), Controller Management (Controllers, Configuration, Actions, Diagnostics), and App Settings. It never renders controller rows. Controllers owns the management `Table`; its management selection is independent from `selectedRouterID`, and only explicit Use enters a different session. Recent-controller history observes all selected-ID changes and remains independent from the persisted manual profile order.

Native Liquid Glass is owned by the standard window/sidebar/toolbar hierarchy; the only custom glass component is the constrained interactive selection primitive, never a data-row or log surface.

## Data Flow

1. A stored `RouterProfile` selects the controller family and endpoint.
2. `MihomoClient`, `SurgeHttpAPIClient`, or native `SingBoxGRPCClient` obtains real controller responses. Auto Detect uses side-effect-free HTTP and StartedService probes without rewriting the persisted profile kind.
3. `MicaCore` decodes and normalizes those responses without inventing unavailable fields.
4. `AppModel` coordinates one selected-controller live session. A generation token guards Mihomo streams, Surge near-live polling, sing-box structured gRPC streams, and 2s/5s/30s REST lanes; stale results from replaced generations cannot publish.
5. Pure presentation projections filter real objects without mutating source identity or controller order. Only long policy-member collections use a bounded local reveal window; connections, logs, rules, and sources are not locally reordered or paginated.

`TrafficTimeline`, `PolicyGroupPresentation`, `PolicyGroupInteractionStore`, `ControllerManagementPresentation`, and `ActivityResourcesPresentation` contain bounded or pure view-state transformations. They do not own network access or create fallback business data. `ControllerSession` owns generation-scoped pause state and its fixed pause timestamp, pending presentation, the five-minute traffic timeline, bounded logs, bounded closed connections, refresh-lane status, and endpoint last values. Endpoint failures retain last values and surface stale state; only never-loaded data becomes an error empty state.

The sing-box StartedService session owns status, groups, mode, connection, log, and Tailscale producers in one structured task group. Stream cancellation closes the gRPC client channel, and Tailscale error/readiness remains independent so a Tailscale failure does not erase an otherwise healthy controller session.

Selected-session commands expose shared Test/Refresh/Pause capabilities. Menu, toolbar, Actions, Rules, and Sources consume those capabilities rather than reimplementing pause or busy checks. Settings-only state has no selected generation and therefore cannot issue live-session commands.

Profile save/delete and manual reorder persist before mutating the observable array. Secret changes are rolled back when profile persistence fails. Active-controller edits replace the generation after commit; non-active edits and inserts have no session side effect. The selected controller UUID persists separately in `UserDefaults` and is restored after secrets load.

## Preference Flow

Language, appearance, and font scale are stored with `@AppStorage` and injected at the scene/root boundary through `micaAppPreferences`. Appearance is also applied to `NSApplication` and existing windows. Language changes relocalize cached presentation strings. Font scale updates both SwiftUI dynamic type/control size and Mica's explicit font multiplier.

## Removed Architecture

The four-tab `AppWorkspace`, old Dashboard views, `MicaDashboard` compatibility palette, command palette, command bar, deck/chart abstractions, modal controller editor, sidebar controller list, user-visible snapshot/sync mode, legacy Settings hierarchy, unavailable fixed-selection action, and custom icon/card chrome are not compatibility boundaries. New work must extend the Workbench directly rather than restoring wrappers or aliases for those concepts.
