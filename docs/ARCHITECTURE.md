# Architecture

## Module Ownership

- `MicaCore` owns controller HTTP/WebSocket/gRPC requests, decoding, endpoint/RPC construction, capability models, and controller-neutral snapshots.
- HTTP families share `ControllerHTTPRequestExecutor<Endpoint>` for request construction, authentication, response validation, cancellation, and decoding failures. Endpoints associate their own error type; Mihomo and Surge keep separate protocol semantics. `ControllerHTTPTransport` is the injected I/O boundary. WebSocket and gRPC streaming retain their own lifetimes.
- `Mica` owns profile/credential persistence, application state, presentation availability, localization, appearance, font scale, commands, and SwiftUI composition.
- `LiveSessionTaskSupervisor` owns generation-bound producer tasks. Typed slots replace individual AppModel task properties; unique task tokens protect replacement tasks from late completion. The supervisor cancels streams, refreshes, or the complete session as a group.
- `Sources/Mica/Features/Workbench/` is the only active main-window information architecture.
- The Workbench shell is split by responsibility: `WorkbenchChrome.swift` owns destinations and root lifecycle, `WorkbenchWindow.swift` owns window composition, `WorkbenchNavigationModel` owns editor transactions, `WorkbenchSidebar.swift` owns navigation, and `WorkbenchStatusBar.swift` owns session and operation status. Design tokens and typography live in `Sources/Mica/Design/MicaTheme.swift`; reusable SwiftUI primitives live in `Sources/Mica/Design/MicaThemeComponents.swift`.
- Shared data-browser sizing and scroll coordination, pure presentation utilities, and SwiftUI composition live in `WorkbenchDataInteraction.swift`, `WorkbenchDataPresentation.swift`, and `WorkbenchDataShared.swift` respectively.
- Connections is split by update rate: `WorkbenchConnections.swift` owns row, intent, and navigation projections; `WorkbenchConnectionCache.swift` owns pulse projections and caches; `WorkbenchConnectionsView.swift` owns the native Table and workspace coordination; `WorkbenchConnectionPulseView.swift` owns pulse rendering; and `WorkbenchConnectionDetails.swift` owns the selected route path and inspector. Logs, Rules, and Sources similarly separate pure presentation/cache logic from root Table composition, with selection-driven detail UI kept in dedicated files.
- Management families keep pure projections separate from SwiftUI composition. Overview separates fixed composition, global compact preferences, policy inspection projection, topology geometry, and per-window transient runtimes; it has no generic layout or draft/conflict subsystem.

## Window Composition

`MicaApp` creates a primary `WindowGroup`, one app-owned `OverviewPreferencesStore`, and a native Settings scene. `ContentView` in `WorkbenchWindow.swift` owns the `NavigationSplitView`, persisted `WorkbenchDestination`, one `OverviewWindowRuntime`, main-window lifecycle registration, sleep/wake forwarding, and in-window transactional controller editing. It also coordinates `MainWindowCloseGuard`, a lifecycle-only AppKit delegate proxy that blocks close while saving and presents the native destructive confirmation for a dirty router draft. `WorkbenchRootView` in `WorkbenchChrome.swift` provides the native toolbar, search placement, persistent session status bar, focused View-menu navigation, destination routing, and the sole `LiveSessionVisibleDestination` mapping. `WorkbenchSidebarControllerSwitcher` reads profiles and selected ID in its own view boundary; live session controls remain separate so stream frames do not rebuild switcher contents unnecessarily.

The sidebar uses native `List` selection in three groups: Workspace (Overview, Proxies, Connections, Rules, Sources), Monitor (Logs, Diagnostics), and Controller (Controllers, Configuration, Actions). Its binding passes navigation through the window's dirty-editor guard. A fixed-height controller menu shows profiles in persisted order and includes Add, Manage, and Test commands. Its popup does not displace navigation. Application preferences live in the native Settings scene. Management-row selection remains separate from the active live controller.

A single right-side `.inspector` column attached in `WorkbenchChrome.swift` renders the typed `WorkbenchInspectorSelection` owned by `WorkbenchWorkspaceStore`. `supportsInspector` controls both its presentation and toolbar availability. Proxies, Configuration, Actions, and Diagnostics have no inspector command. Proxies renders the inspected member inline in its active-group list. Other pages register live row resolvers on the store; controller detail resolves its profile from the app model.

Individual policy members preview on hover and inspect inline on default activation;
switching uses a separate command and never also opens details. `ProxyProtocolInspectionProjection`
separates reported runtime facts, optional protocol configuration, and per-URL
test state, preserving unknown extensions as stable leaf paths. Missing values and empty
groups are omitted; zero and false remain data. Sensitive values are masked in
both visible and accessibility output. Reveal state belongs to the inspected
member, controller, and session, including the current member of a selected group.
Inspection never reads a separate configuration file or requests parameters from
the network. Standard Mihomo runtime responses do not contain the original SS
server/cipher/password configuration; optional configuration fixtures verify
rendering only, not that a deployed controller exposes those values. Surge node
types come from exact, unique entries in the reported policy catalog, not parent
group types. Missing Mihomo types are not synthesized during decoding.
Literal punctuation in metadata keys is escaped in display paths, and object
keys have identities distinct from array indices. A structural metadata update
cannot accidentally reuse the reveal state of a different field.

Controller management selection always reconciles against the current filtered
profile list, including after profile refresh or page restoration. Selecting a
managed profile still does not change the live controller. Single-source update
and health-check callbacks capture the page model's session scope; AppModel
rejects stale controller IDs or generations before changing operation state.

Native window/sidebar/toolbar controls own the platform material hierarchy. Workbench content does not define a custom Liquid Glass primitive; selectors, data rows, logs, and inspectors use flat `MicaTheme` surfaces with hairline separators.

## Data Flow

1. A stored `RouterProfile` selects the controller family and endpoint.
2. `MihomoClient` and `SurgeHttpAPIClient` submit typed endpoints through the shared HTTP executor. It checks cancellation before transport and after a response, validates status before decoding, and preserves family-specific authentication and errors. Specialized Mihomo directory decoders retain wire order. Native `SingBoxGRPCClient` owns HTTP/2 RPCs independently. Auto Detect resolves a family without rewriting the persisted profile kind.
3. `MicaCore` decodes and normalizes those responses without inventing unavailable fields.
4. `AppModel` coordinates one selected-controller generation while `LiveSessionRuntime` owns high-frequency raw traffic, memory, connection, closed-history, and log ingestion off the main actor. The actor emits immutable per-domain publications carrying controller ID, generation, revision, receipt time, observation counts, and either a bounded snapshot or log append/drop delta. AppModel rejects stale identities and out-of-order revisions before updating observable presentation state.
5. `LiveSessionTaskSupervisor` binds producers to controller ID and generation. It owns the baseline, periodic/manual/immediate refresh tasks, stream tasks, retries, and probes. Rebinding cancels the preceding generation; obsolete starts and completion tokens cannot replace or clear current work. `SessionRefreshCoordinator` separately coalesces the 2s/5s/30s REST lanes. Mihomo streams, Surge polling, and sing-box structured streams share the same selected-session ownership.
6. Pure presentation projections filter real objects without mutating source identity or controller order. Connections split structure, metrics, and aggregate-traffic revisions; its current-scope pulse rebuilds for structure/filter changes and applies keyed metric deltas without rescanning owner buckets. Logs consume explicit append/drop deltas; rules, sources, policy groups, Overview timelines, and topology use bounded caches keyed by their actual inputs. Inactive destinations do not perform expensive projection work, and activation publishes only the latest current-generation state.

`TrafficTimeline`, `MemoryTimeline`, `ConnectionCountTimeline`, the Workbench projection caches, and `ConnectionTopologyBuilder` contain bounded or pure presentation transformations. `WorkbenchWorkspaceStore` owns narrow per-controller/per-destination search, sort, selection, the active proxy group, its member query and inspected member, and same-window connection navigation; persistence is coalesced and excludes live session state. Proxy browsing uses `activeGroupID`, `proxyMemberQuery`, and `inspectedProxyMemberID`, with no multi-open-group layout or per-group filter dictionaries. These types do not own network access or create fallback business data.

Surge connection projection keeps the reported final policy in the first chain
slot and the original policy in its own following slot, including equal names.
If only the original policy is present, an empty first slot preserves an unknown
final outbound. The shared topology then retains the partial path and marks its
route unavailable; it never promotes the original policy or destination address
to an inferred exit. Active and recent Surge requests use the same projection.

`ControllerSession` remains the main-actor lifecycle and atomic baseline authority: generation, capability-aware connecting/reconnecting state, pause controls, endpoint last values, and committed presentation mirrors. `LiveSessionRuntime` is the generation-owned raw ingestion authority after installation. It retains five-minute timelines, the O(1) 2,000-entry/8 MiB log ring, connection-rate tracking, and pending closed rows until publication. The root destination maps visible domains; logs/traffic/connections/memory publish at 5/4/2/1 Hz with one non-restarting task slot per domain. Surge near-live polling advances the same visible traffic/count timelines and connections domain. Hidden domains retain raw state and flush once on entry. Endpoint failures retain last values and surface stale state; only never-loaded data becomes an error empty state.

Performance instrumentation uses privacy-safe `OSSignposter` intervals and operation counters. Payloads contain only typed counts/categories, never controller names, hosts, request URLs, connection IDs, rules, logs, credentials, or raw responses. The opt-in offline Release benchmark uses deterministic fixtures and writes comparable JSON reports under `tmp/codex/performance/`; it never opens a controller connection.

Sources keeps provider test URLs and subscription metadata in the typed dashboard projection. Update All is an AppModel operation over the existing provider task slot: it filters only reported updatable entries, preserves catalog order, runs sequentially with generation checks after every suspension, publishes typed progress and per-source failures, and performs one provider snapshot refresh at the end. Overview remains a focused summary: the route topology leads, followed by one compact row of real traffic/active-connection trends with memory context. Its dense summary preserves exact path membership and provides access to the complete all-active-path Canvas graph. Chart readouts and timestamps use the same projected snapshot as the plots, so pause freezes them together. Cumulative connection aggregates never masquerade as rates. Instrument readouts, short latency/rule/active-connection summaries, and controller/network facts are globally optional and hidden by default. Policy-node inspection reads only the published policy catalog, its scalar AppModel revision, and cached topology geometry; unchanged hover/pin work does not deep-compare the catalog or perform network work. Full connection metadata and retained closed history stay on Connections rather than creating a second Overview browser.

The sing-box StartedService session owns status, groups, mode, connection, log, and Tailscale producers in one structured task group. Stream cancellation closes the gRPC client channel, Tailscale error/readiness remains independent so a Tailscale failure does not erase an otherwise healthy controller session, and every reported log level including `trace` survives into the Logs presentation.

Selected-session commands expose shared Test/Refresh/Pause capabilities. Menu, toolbar, Actions, Rules, and Sources consume those capabilities rather than reimplementing pause or busy checks. Settings-only state has no selected generation and therefore cannot issue live-session commands.
Actions receives evidence-free runtime command rows only for controller families with verified runtime dispatchers; it does not observe full diagnostic evidence or stream payload collections. Diagnostics and Actions both consume pure typed snapshots, while controller-wide failure deduplication and safe evidence fallback remain presentation contracts rather than controller API behavior.

Profile save/delete and manual reorder persist before mutating the observable array. Secret changes are rolled back when profile persistence fails. Active-controller edits replace the generation after commit; non-active edits and inserts have no session side effect. The selected controller UUID persists separately in `UserDefaults` and is restored after secrets load.

## Preference Flow

Language, appearance, and font scale are stored with `@AppStorage` and injected at the scene/root boundary through `micaAppPreferences`. Appearance is also applied to `NSApplication` and existing windows. Language changes relocalize cached presentation strings. Font scale updates SwiftUI Dynamic Type; control size remains bounded to native small/regular values, and workbench geometry is not multiplied by the text preference.

Overview persists one global immediate preference value: visible primary metrics, timeline window, and optional-module visibility. The existing v1 key now uses the `mica.overview.fixed-core.v1` envelope; old layout payloads, corrupt data, and unknown schemas reset to the fixed default without migration. There are no per-controller overrides or window drafts. Window runtimes retain only transient session-keyed chart/topology state and stable live-demand identity.

## Presentation Ownership

`WorkbenchNavigationModel` owns the current editor, its dirty/saving state,
pending navigation, and menu requests. Editor UUIDs reject callbacks from replaced
editors. Continuing to edit cancels the pending intent. SceneStorage remains the
single destination authority; the model returns accepted destination changes.

`ProxyWorkspaceModel` owns the accepted policy catalog, lookup indexes, visible
directory, one active member projection, bounded directory/member accessibility
indexes, and the cached active-group presentation. Directory search matches
group identity and does not block exact node navigation; member search stays within the active group. Neither depends on
the shell search or inspector. Activating another group
replaces the member index rather than retaining expanded catalogs. It accepts
explicit value inputs and has no AppModel or network dependency. The view owns
user intent, exact reveal, inline inspection, and command dispatch.

`ConnectionsWorkspaceModel`, `RulesWorkspaceModel`, `WorkbenchLogsModel`, and
`WorkbenchSourcesModel` own page activation, caches, selection, sorting, scroll
restoration, and bounded accessibility state. `WorkbenchSessionIdentity` scopes
updates and delayed work to a controller generation. Views assemble explicit
value inputs, persist preferences, and dispatch remote commands; page models do
not import SwiftUI or depend on AppModel. Connections coalesces metric sorting
while scrolling; Logs owns token-bound follow scheduling and preserves the
user's accessibility page across background snapshots. Inspectors resolve the
current model row rather than retaining a stale selected value.

`WorkbenchDataTableViewport` keeps SwiftUI Table rendering and uses a narrow
`WorkbenchNativeTableLifecycle` adapter for actual row positioning and native
scroll begin/end events. Paired view markers identify only its own Table.
Explicit requests resolve one row index; actual row-height changes can trigger
at most eight corrections, without a polling timer. User scrolling, generation
replacement, completion, and unmount cancel pending correction. Visible anchors
are queried by index only on scroll completion or unmount, not rebuilt per row
or per frame.

`OverviewViewportLayout` reserves 280–480 points for topology and 56–92 points
per trend plot. Telemetry uses one row: all enabled metrics share it if they fit,
otherwise the selected metric uses the shared chart. `OverviewMetricLayout`
positions the chart collection without depending on live traffic values.
Widening a short window does not inflate the reserved chart height. Dense
topologies exceed their viewport internally and remain scrollable in both axes.

Topology layout uses card bounds for labels, hit targets, and edge ports.
`OverviewTopologyOrdering` prepares a bounded, cancellable crossing refinement
off the main actor; the presentation cache reuses it for viewport changes.
`OverviewTopologyDensityStyle` limits line width and opacity by graph density
without filtering data. Old same-session geometry stays visible during layout
replacement to avoid scrollbar-width/loading feedback loops.

The topology summary groups each dense column into at most six display nodes;
its aggregate edges retain the exact source path IDs. This bounded presentation
does not change the canonical topology, path occurrence identities, reported
hop order, or unavailable route records. Drill-down resolves real paths from
those memberships instead of fabricating a representative route. The focused
list holds a captured snapshot and permits connection navigation only while
its generation and structural revision still match the live catalog.

AppModel remains the application coordinator for profile persistence, command
admission, and published session state; it does not own per-window page selection.
