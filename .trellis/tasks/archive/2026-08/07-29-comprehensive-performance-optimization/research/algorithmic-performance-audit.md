# Research: Algorithmic and Storage Performance Audit

- Query: Audit algorithmic and storage performance across SessionBuffers, timelines, catalogs, rule/log/connection/source projections, proxy search, topology normalization/layout, formatters, localization caches, and persistence. Identify repeated O(n log n)/O(n^2), materialization, unstable keys, unbounded state, and missing performance tests; propose benchmark contracts.
- Scope: internal
- Date: 2026-07-29

## Findings

### Top priorities

1. **P0 - Topology accumulation has a structural O(n^2) copy path for shared routes.** `Accumulator.admit` reads a dictionary value containing `pathIDs`, appends to the copied struct, then writes it back for every shared node and edge (`Sources/Mica/App/ConnectionTopologyModel.swift:295`, `Sources/Mica/App/ConnectionTopologyModel.swift:315`). Because the dictionary still owns the old Swift `Array` buffer while the local copy is mutated, highly shared nodes/edges repeatedly trigger copy-on-write growth. A fixture where all connections share one route is the adversarial case.
2. **P0 - Topology highlighting recomputes and reallocates the selected path set inside every draw-loop iteration.** `highlightedPathIDs` is a computed property (`Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:1134`) used separately for every edge and node (`Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:1248`). Its implementation searches flattened nodes or edges and creates a `Set` (`Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:2072`). With an active selection this can become O((nodes + edges) x graph-size) per Canvas draw.
3. **P0 - Insight refresh performs a full sort and unrelated aggregate rebuilds on the 2 Hz connection path.** Connection publication calls `replaceConnections` / sing-box status projection (`Sources/Mica/App/AppModelLiveSession.swift:231`), which refreshes the complete insight snapshot (`Sources/Mica/App/DashboardSessionModels.swift:406`). The insight constructor groups all connections, flattens all group delays, filters the delay list once per grade, and fully sorts all connections to retain five (`Sources/Mica/App/DashboardInsightModels.swift:36`). This is repeated O(C log C) work and recomputes group/rule/provider-derived values even when only connections or traffic changed.
4. **P0 - The full log ring is materialized and scanned repeatedly at the 5 Hz publication boundary.** `BoundedLogBuffer.entries` copies every retained entry (`Sources/Mica/App/SessionBuffers.swift:19`); publication requests that array (`Sources/Mica/App/AppModelLiveSession.swift:189`); catalog synchronization then compares the full array to derive a revision and compares it again through `LogsCatalogSnapshot.==` before assignment (`Sources/Mica/App/AppModel.swift:408`, `Sources/Mica/App/DashboardSessionModels.swift:268`). The UI's append-delta path still scans IDs, builds a `Set`, validates overlap, and creates a new row array (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1383`). The 2,000-entry cap bounds memory, but not the repeated O(L) work.
5. **P0 - Topology hit-index construction can approach O(E x vertical-span) time and memory.** Each edge uses its full bounding rectangle as a hit region (`Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:1984`), then is inserted into every 96-point grid cell covered by that rectangle with nested loops (`Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:2053`). Long edges spanning many rows create a large number of duplicate `HitTarget` entries; adversarial alternating top/bottom routes can make this quadratic in graph height.

### Session buffers and timelines

- The log ring's append/eviction path is genuinely O(1) and bounded at 2,000 entries / 8 MiB (`Sources/Mica/App/SessionBuffers.swift:4`, `Sources/Mica/App/SessionBuffers.swift:101`). The expensive boundary is snapshot extraction/equality, not insertion.
- `BoundedLogBuffer.replace` constructs another fixed 2,000-slot ring, performs deep equality, and then copies its storage (`Sources/Mica/App/SessionBuffers.swift:51`). This is acceptable for rare replacement, but Surge rebuilds the entire log set more often: it materializes the ring twice, filters/maps it, concatenates, sorts by timestamp, then replaces the buffer (`Sources/Mica/App/AppModelLiveSession.swift:1208`). That path is O(L log L) per staged Surge snapshot.
- Both timelines run a predicate removal across the retained array and may then remove from the front on every append (`Sources/Mica/App/SessionTimelineModels.swift:63`, `Sources/Mica/App/SessionTimelineModels.swift:122`). Capacity 300 bounds the cost, but steady-state insertion remains O(T) rather than O(1).
- Closed-connection retention is bounded to 200/30 minutes, but every record normalizes by materializing `incoming + existing`, sorting it, deduplicating, and sorting incoming duplicates first (`Sources/Mica/App/SessionBuffers.swift:275`, `Sources/Mica/App/SessionBuffers.swift:309`). Read access also filters anew, and `snapshots` maps the filtered copy (`Sources/Mica/App/SessionBuffers.swift:159`).

### Catalogs and projections

- Connection catalog revisions require full connection-array equality before each publication (`Sources/Mica/App/AppModel.swift:396`). Log revisions repeat the same pattern despite `BoundedLogBuffer.rawRevision` already existing. Source-owned revisions would avoid content hashing/scans at publication time.
- `RoutingCatalogSnapshot` combines rules and providers (`Sources/Mica/App/DashboardSessionModels.swift:273`), and AppModel replaces that single observable value when either collection changes (`Sources/Mica/App/AppModel.swift:420`). Rules and Sources therefore share an Observation root even though their expensive row projections are separate.
- Connection projection fully maps each connection, canonical-JSON-encodes two metadata dictionaries, assembles long search/fallback strings, and then filters/sorts (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:948`, `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1020`, `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:752`). On each active connection revision, the view also rebuilds close groups and two ID sets (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:2146`). With a sort descriptor this is repeated O(C log C), plus per-row encoding/string allocation.
- The rule-to-connection index is correctly O(C) and cached by controller, generation, and connection revision (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1109`, `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1149`). However every connection revision still recreates every rule row, localized status, static metadata JSON, and search string (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:2633`, `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:2949`). Static rule fields are not separated from the changing active-count projection.
- Source rows correctly avoid reprojection on query/kind-only changes, but a source refresh parses dates and recomputes health/subscription JSON text for every row (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1266`). `providerUpdatedAt` constructs a new `ISO8601DateFormatter` per parsed row (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:774`), and provider JSON text constructs a new encoder per access (`Sources/Mica/App/DashboardSessionModels.swift:1078`).
- Log projection caches formatted rows, but its append path remains linear and allocates a replacement row array even for a one-entry delta (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1383`). Filtering is appropriately bypassed for the all/empty case (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1436`).

### Proxy search and cache identity

- The proxy catalog index precomputes search text, which is the right ownership boundary, but rebuilding it concatenates every group member and every member's metadata text (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:1726`, `Sources/Mica/Features/Workbench/WorkbenchProxies.swift:2139`). The view reconstructs and deep-compares this index whenever the full policy catalog changes; there is no cheap catalog revision key (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:233`).
- Workspace reconciliation loops all groups and materializes each group's full member occurrence array merely to validate one stored selected member (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:1891`). This is O(total members) allocation on every catalog reconciliation and bypasses the active-group-only index.
- Active member indexing is correctly limited to the active group and query filtering uses precomputed normalized text (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:2030`). This is a retained good pattern.
- Duplicate group/member identities are occurrence-based (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:1642`). They are deterministic for an unchanged controller order, but inserting/removing an earlier duplicate shifts later IDs and invalidates workspace cache entries. Topology has the same order-derived identity for blank/duplicate connection IDs (`Sources/Mica/App/ConnectionTopologyModel.swift:16`).

### Stable text, formatters, and localization

- `ControllerLogEntry.structuredFieldsText` creates a new `JSONEncoder` on every access and does not request `.sortedKeys` (`Sources/Mica/App/DashboardSessionModels.swift:573`). Buffer byte accounting and log projection access it repeatedly (`Sources/Mica/App/SessionBuffers.swift:133`, `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1360`, `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1452`). For blank/duplicate IDs this non-canonical text participates in fallback identity generation, so key stability is not documented and encoding work is duplicated.
- Rule metadata JSON is also recomputed through new sorted-key encoders each time the computed properties are read (`Sources/Mica/App/DashboardSessionModels.swift:1033`). Connection projection similarly creates a new encoder per metadata dictionary (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:752`).
- The string catalog itself is loaded once and is bounded by bundled resources (`Sources/Mica/App/XCStringsResolver.swift:23`), which is good. Exact key lookup is dictionary-based.
- Interpolated localization reflects every `String.LocalizationValue` to recover arguments (`Sources/Mica/App/AppLanguage.swift:181`, `Sources/Mica/App/AppLanguage.swift:208`). Every explicit lookup also updates a global language under an `NSLock` (`Sources/Mica/App/AppLanguage.swift:243`, `Sources/Mica/App/BundleLocalization.swift:12`), including row-projection loops where the requested language is already known.
- `relocalizedText` scans every catalog key and translation (`Sources/Mica/App/XCStringsResolver.swift:94`); matching interpolated templates builds and compiles a fresh regular expression (`Sources/Mica/App/XCStringsResolver.swift:232`). A language change applies this repeatedly across operation state, failure dictionaries, health, trial sessions, and snapshots (`Sources/Mica/App/AppModelPresentationLanguage.swift:5`). There is no reverse exact-string index or compiled-template cache.
- Byte/date formatting is split across several helpers with repeated formatter construction, including per-provider `ISO8601DateFormatter` and two separate per-call `ByteCountFormatter` instances in runtime diagnostics (`Sources/Mica/App/AppModelRuntimeOperations.swift:346`, `Sources/Mica/App/AppModelDiagnosticsRuntimeOperations.swift:283`). Correctness tests exist, but construction count and row-scale cost are not measured.

### Persistence and storage I/O

- `FileSecretStore.secret(for:)` loads and decodes the complete secrets file for one key (`Sources/MicaCore/Security/FileSecretStore.swift:26`, `Sources/MicaCore/Security/FileSecretStore.swift:44`). Startup then calls it serially once per profile with a secret (`Sources/Mica/App/AppModelRouterProfiles.swift:258`). For P profiles and a P-entry file, startup performs P full reads/decodes: O(P^2) processed bytes plus P serialized filesystem operations.
- Every secret save/remove also reloads the whole map and atomically rewrites pretty-printed, sorted JSON (`Sources/MicaCore/Security/FileSecretStore.swift:30`, `Sources/MicaCore/Security/FileSecretStore.swift:57`). This is simple and safe for small profile counts, but no in-actor cache or bulk-load API exists.
- `JSONRouterProfileStore` similarly reads/writes the whole profile array and uses pretty printing plus sorted keys (`Sources/MicaCore/Persistence/RouterProfileStore.swift:13`, `Sources/MicaCore/Persistence/RouterProfileStore.swift:26`). The first successful connection rewrites all profiles to update one timestamp (`Sources/Mica/App/AppModelRouterProfiles.swift:281`).
- No database is used; `.trellis/spec/backend/database-guidelines.md` is a placeholder. Storage conclusions are therefore about JSON/UserDefaults persistence, not query planning.

### Bounded and unbounded state

- Explicitly bounded: log ring, timelines, closed history, and per-controller command log. Their behavioral caps are tested.
- Intentionally uncapped controller truth: active connections, rules, providers, policy memberships, and complete topology. The UI contract requires all active paths and business rows to remain visible, so truncation is not an acceptable optimization.
- Topology duplicates every path ID into each traversed node and edge while also retaining complete path stages/edge IDs (`Sources/Mica/App/ConnectionTopologyModel.swift:91`, `Sources/Mica/App/ConnectionTopologyModel.swift:136`). Memory is O(total path hops) with a high constant and no workload ceiling. Catalog and projection arrays add further retained copies/search strings. This needs scale and allocation contracts rather than arbitrary caps.
- Rebuild scheduling is full-snapshot and restart-driven: each connection revision/width bucket changes the topology task identity (`Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:1015`), and normalization plus layout restart from the complete connection array (`Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:1080`). Normalization checks cancellation every 64 rows, but layout checks only before and after its synchronous build (`Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:1913`). Under sustained churn, work may be repeatedly discarded or cancellation delayed.

### Proposed benchmark contracts

Use deterministic synthetic fixtures and Release builds. Prefer operation/allocation counters and scaling slopes over a single machine-specific wall-clock threshold; report median and p95 wall time as supporting evidence. Automated benchmarks must not contact real controllers.

1. **Topology shared-route slope:** Build 250/500/1,000/2,000 connections sharing the same 4-6 stages. Doubling input must remain near-linear (target <= 2.5x median), and node/edge membership append work must be O(total path hops), not cumulative array-copy volume.
2. **Topology unique-route slope:** Build the same sizes with unique nodes/edges. Verify exact row/path preservation, cancellation, peak allocations, and O(total path hops) growth.
3. **Topology hit index:** Use alternating top-to-bottom edges. Track total indexed cell entries and peak memory; doubling rows/edges must not exhibit quadratic growth. Hit testing must remain correct for 44-point targets.
4. **Topology scheduling:** Instrument started/completed/cancelled builds. At most one build may execute concurrently; intermediate revisions coalesce; the latest revision eventually publishes; cancellation is observed inside both normalization and layout loops.
5. **Insight projection:** For 1k/5k/10k connections, connection-only updates must not rebuild unchanged latency/rule/provider aggregates. Top-five selection must demonstrate near-linear scaling rather than a full O(C log C) sort.
6. **Full-ring log publication:** Starting with 2,000 entries, publish 100 one-entry append/evict deltas. Count ring materializations, collection equality scans, formatted rows, JSON encodes, and allocated bytes. After warmup, formatted rows should be proportional to the delta, not 2,000 per publication.
7. **Timeline steady state:** Append at full 300-sample capacity for 10k iterations. Per-append work must be independent of retained count, with no front-shift operation.
8. **Closed history:** Record large duplicate-heavy batches against a full 200-row history. Measure normalization slope and prove reads do not repeatedly filter/map unchanged state.
9. **Connection projection:** Project 1k/5k/10k rows with representative nested metadata. Query-only changes must perform no JSON re-encoding/date parsing; active sorting may be O(C log C), while unsorted refresh remains O(C).
10. **Rule projection:** For R rules and C connections, build the connection index once per revision. Connection-only changes must not re-encode static rule metadata or rebuild static search text for all R rows.
11. **Source projection:** Query/kind changes must reuse parsed dates and serialized metadata. Formatter/encoder construction count after warmup should be zero for unchanged `(raw value, locale)` inputs.
12. **Proxy catalog:** Use 100 groups x 1,000 members with shared details. Build group search index once per catalog revision; query changes only scan cached normalized text; active-group changes index only that group's members; workspace reconciliation must not materialize every group's row projection.
13. **Localization:** Exact key lookup remains O(1). Language-switch relocalization should use a bounded reverse/template index keyed by catalog identity/language rather than scanning all keys and recompiling regexes per string. Track lock acquisitions, reflection calls, regex compilations, and cache size.
14. **Persistence I/O:** With 10/100/1,000 profiles and secrets, startup must read/decode each JSON file at most once. A single secret mutation performs at most one logical load and one atomic write. Record bytes read/written, encode/decode count, and elapsed actor occupancy.
15. **End-to-end projection memory:** At maximum log retention plus 10k active connections/rules and a complete topology, record peak allocated bytes and retained copies for raw session state, catalogs, presentation rows, search text, and topology. The contract should require memory to return near baseline after generation invalidation.

### Existing test coverage and gaps

- Buffer/timeline tests prove FIFO, byte/count/age caps, revisions, and reset behavior, but contain no timing/allocation assertions (`Tests/MicaTests/SessionStreamStateTests.swift:19`, `Tests/MicaTests/WorkbenchTimelineAndProxyTests.swift:7`).
- The 2,000-log cache test proves projection counters and functional reuse, not that the incremental path is sublinear or allocation-bounded (`Tests/MicaTests/WorkbenchDataProjectionTests.swift:441`).
- The 798-member proxy test proves active-group scoping and cached filtering, not catalog/reconciliation scaling (`Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift:25`).
- Topology tests prove completeness at 80 unique paths, shared membership for two paths, determinism, and pre-cancel behavior (`Tests/MicaTests/ConnectionTopologyTests.swift:88`, `Tests/MicaTests/ConnectionTopologyTests.swift:139`, `Tests/MicaTests/ConnectionTopologyTests.swift:291`). They do not exercise a large shared route, hit-index growth, in-build cancellation latency, repeated revision churn, or allocations.
- Secret-store tests cover one/two-key correctness and cross-instance persistence only (`Tests/MicaCoreTests/FileSecretStoreTests.swift:22`). No profile-store performance test or startup I/O-count test was found.
- Localization tests verify key availability and preference persistence (`Tests/MicaTests/WorkbenchPreferencesTests.swift:41`), not reverse lookup, reflection, lock, regex compilation, or cache behavior.
- Repository-wide search found no `measure`, XCTest metric, benchmark target/package, `ContinuousClock` timing contract, or allocation/signpost performance suite for these paths.

### Files found

- `Sources/Mica/App/SessionBuffers.swift` - bounded log and closed-connection storage.
- `Sources/Mica/App/SessionTimelineModels.swift` - traffic and memory sample retention.
- `Sources/Mica/App/DashboardSessionModels.swift` - catalogs, dashboard mutation, proxy/rule/provider presentation models.
- `Sources/Mica/App/DashboardInsightModels.swift` - connection/traffic/latency insight aggregation.
- `Sources/Mica/App/AppModel.swift` - catalog synchronization and revision derivation.
- `Sources/Mica/App/AppModelLiveSession.swift` - visible-domain publication, Surge log rebuild, topology inputs.
- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift` - connection/rule/source/log projections and caches.
- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift` - proxy catalog/member indexing, search, workspace reconciliation.
- `Sources/Mica/App/ConnectionTopologyModel.swift` - topology normalization and graph accumulation.
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift` - topology scheduling, layout, hit index, Canvas drawing.
- `Sources/Mica/App/AppLanguage.swift`, `Sources/Mica/App/XCStringsResolver.swift`, `Sources/Mica/App/BundleLocalization.swift` - localization lookup, relocalization, and global language routing.
- `Sources/MicaCore/Persistence/RouterProfileStore.swift`, `Sources/MicaCore/Security/FileSecretStore.swift`, `Sources/Mica/App/AppModelRouterProfiles.swift` - JSON persistence and startup secret loading.
- `Tests/MicaTests/SessionStreamStateTests.swift`, `Tests/MicaTests/WorkbenchDataProjectionTests.swift`, `Tests/MicaTests/WorkbenchTimelineAndProxyTests.swift`, `Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift`, `Tests/MicaTests/ConnectionTopologyTests.swift`, `Tests/MicaCoreTests/FileSecretStoreTests.swift` - current functional coverage relevant to the audit.

### External references

- No external source was required for this source-level audit.
- Package/runtime facts verified locally: Swift tools 6.2, macOS 27, and the pinned gRPC/Protobuf dependencies in `Package.swift`.

### Related specs

- `.trellis/spec/frontend/workbench-ui-contract.md` - active performance boundaries, complete topology, cached projections, and 5/4/2/1 Hz publication budgets.
- `.trellis/spec/frontend/live-session-controller-contract.md` - bounded buffers, generation safety, publication cadence, and session clearing.
- `.trellis/spec/backend/controller-data-contract.md` - order preservation and complete controller-data semantics.
- `.trellis/spec/guides/cross-layer-thinking-guide.md` - source-to-projection boundary checks.
- `.trellis/spec/guides/code-reuse-thinking-guide.md` - duplicate formatter/serialization ownership guidance.

## Caveats / Not Found

- This is a source audit, not an Instruments result. No claim is made about real-device CPU, frame hitches, or RSS improvement.
- Controller dataset ceilings are unknown. The code and specs intentionally preserve complete controller-reported collections, so benchmarks must cover realistic user fixtures before setting absolute latency/RSS gates.
- SwiftUI Observation invalidation and Foundation formatter internals should be confirmed with signposts/Instruments; the cited source establishes repeated calls and materialization, not their exact runtime cost on macOS 27.
- The topology dictionary-value Array copy-on-write finding is based on Swift value semantics and the shown get-mutate-set pattern; a microbenchmark/allocation test should be the first implementation-phase confirmation.
- No application code, PRD, specs, task manifests, or git state were modified.
