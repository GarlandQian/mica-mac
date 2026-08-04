# Research: Third-party dependency audit

- Query: Audit Mica's current direct and transitive Swift packages, their purpose and necessity, and mature candidates for the confirmed performance hotspots. Recommend a new package only when verified performance or correctness evidence outweighs system/local alternatives and dependency cost.
- Scope: mixed
- Date: 2026-07-29

## Findings

### Decision

The PRD's default conclusion stands: **add no new runtime or benchmark package for this task**.

- Keep all four direct packages. They are one typed sing-box StartedService gRPC/Protobuf stack and none is independently removable without replacing protocol generation/runtime, gRPC semantics, or the Apple HTTP/2 transport.
- Keep `GRPCNIOTransportHTTP2TransportServices` as the selected transport product. It uses the Network.framework-backed path and avoids compiling the POSIX `NIOSSL`/`X509` target chain into Mica.
- Do not promote any currently transitive package into application code. The current Mica-specific ordered index, fixed byte-budgeted ring, generation-owned actors/tasks, `Synchronization.Mutex`, `OSSignposter`, Swift Charts, Canvas, and URLSession match the confirmed hotspots more closely.
- The dependency-specific `swift-protobuf traits: []` experiment is complete and rejected: clean Release time changed by 0.1% and executable size by 0.32%, so the root manifest keeps upstream defaults.
- Treat available patch/minor updates inside the existing graph as a separate correctness-maintenance decision, not evidence for adding a package. In particular, inspect `swift-nio-http2` 1.45.0 and `swift-protobuf` 1.38.1 in isolated upgrades after the performance baseline is stable.

No verified counterevidence was found that challenges the PRD's no-new-package default.

### Files found

| File | Description |
|---|---|
| `Package.swift` | Swift 6.2/macOS 27 root manifest, four exact direct dependencies, selected products, and test-only in-process gRPC transport. |
| `Package.resolved` | Exact 22-repository resolved graph. |
| `.build/arm64-apple-macosx/debug/description.json` | Current SwiftPM target dependency maps and compile arguments, including selected production modules and enabled SwiftProtobuf traits. |
| `.build/checkouts/*/Package.swift` | Exact pinned upstream manifests used to trace resolution and target-product selection. |
| `.build/checkouts/*/LICENSE*`, `NOTICE*` | Exact installed license and notice texts. |
| `Sources/MicaCore/API/SingBoxGRPCClient.swift` | Runtime gRPC core, TransportServices, and SwiftProtobuf imports and channel ownership. |
| `Sources/MicaCore/Protocols/SingBox/started_service.proto` | 17-RPC StartedService schema. |
| `Sources/MicaCore/Protocols/SingBox/Generated/.../started_service.pb.swift` | Checked-in 1,995-line generated protobuf model source. |
| `Sources/MicaCore/Protocols/SingBox/Generated/.../started_service.grpc.swift` | Checked-in 3,409-line generated gRPC service/client source. |
| `Tests/MicaCoreTests/SingBoxGRPCClientTests.swift` | In-process GRPCCore/SwiftProtobuf protocol and cancellation fixture. |
| `Sources/Mica/App/LiveSessionRuntime.swift` | Generation-owned actor with Mica-specific ordered connection storage and log deltas. |
| `Sources/Mica/App/SessionBuffers.swift` | Fixed-slot 2,000-entry/8 MiB log ring. |
| `Sources/Mica/App/PerformanceObservation.swift` | System `OSSignposter` plus `Synchronization.Mutex` instrumentation. |
| `Tests/MicaTests/MicaPerformanceBenchmarkTests.swift` | Existing opt-in offline Release benchmark harness. |
| `.trellis/tasks/07-29-comprehensive-performance-optimization/research/*.md` | Existing algorithmic, UI, concurrency, dependency, candidate, and baseline evidence. |

### Current graph and selected boundary

`Package.swift:15-20` declares four exact direct packages. `MicaCore` selects only `GRPCCore`, `GRPCNIOTransportHTTP2TransportServices`, `GRPCProtobuf`, and `SwiftProtobuf` at `Package.swift:22-30`; `MicaCoreTests` additionally selects `GRPCInProcessTransport` at `Package.swift:46-55`.

The direct package boundary is real source usage, not manifest convenience:

- `SingBoxGRPCClient.swift:1-4` imports Foundation, GRPCCore, the TransportServices product, and SwiftProtobuf.
- Generated service code imports GRPCCore, GRPCProtobuf, and SwiftProtobuf at `started_service.grpc.swift:11-13`; generated messages import SwiftProtobuf at `started_service.pb.swift:11`.
- The schema contains 17 unary/server-streaming RPCs at `started_service.proto:7-29`; generated output totals 5,404 Swift lines. A hand-written local gRPC/protobuf replacement would increase protocol, framing, cancellation, status, and schema-compatibility risk.
- Tests directly use GRPCCore, GRPCInProcessTransport, and SwiftProtobuf at `SingBoxGRPCClientTests.swift:1-6`.

The current target dependency map begins at `.build/arm64-apple-macosx/debug/description.json:41979` for `Mica` and `:42165` for `MicaCore`. It shows modules from ten package repositories in the production executable: the four direct repositories plus `swift-nio`, `swift-nio-http2`, `swift-nio-transport-services`, `swift-nio-extras`, `swift-atomics`, and `swift-collections`. No Mica source directly imports those six transitive modules.

### Direct package audit

Official GitHub repository/release metadata was queried on 2026-07-29. All four repositories are unarchived and had 2026 activity.

| Package | Pin / latest stable | Last official push | License | Purpose and necessity | Decision |
|---|---|---:|---|---|---|
| `grpc-swift-2` | 2.4.2 / 2.4.2 | 2026-07-28 | Apache-2.0 | Supplies `GRPCCore`; generated code and tests depend on its typed RPC, status, streaming, and in-process APIs. Its manifest directly selects `DequeModule` at `.build/checkouts/grpc-swift-2/Package.swift:73-80`. | Keep. No system gRPC core exists. |
| `grpc-swift-nio-transport` | 2.9.0 / 2.9.0 | 2026-07-29 | Apache-2.0 | Supplies HTTP/2 transport. The selected TransportServices target depends on transport core, GRPCCore, and NIOTransportServices at `.build/checkouts/grpc-swift-nio-transport/Package.swift:141-149`. | Keep the TransportServices product. Replacing it means owning gRPC framing, HTTP/2 flow control, TLS/trust, status, deadlines, streaming, and cancellation. |
| `grpc-swift-protobuf` | 2.4.1 / 2.4.1 | 2026-07-29 | Apache-2.0 | Supplies generated RPC serializers/deserializers over GRPCCore and SwiftProtobuf at `.build/checkouts/grpc-swift-protobuf/Package.swift:88-95`. | Keep. Hand-written serializers would weaken schema correctness. Code-generation products are not selected by Mica. |
| `swift-protobuf` | 1.38.0 / 1.38.1 | 2026-07-13 | Apache-2.0 with Swift Runtime Library Exception | Supplies generated message runtime and `Google_Protobuf_Empty`. Mica's checked-in generated sources import it directly. | Keep. Evaluate 1.38.1 as a separate correctness update; evaluate `traits: []` separately for build/size. |

The three gRPC pins are the latest stable releases visible on the audit date. `swift-protobuf` is one patch behind. Version 1.38.1 contains stricter protobuf JSON validation and merge-correctness fixes, but Mica's StartedService path is binary protobuf and no current Mica defect or performance gain was demonstrated. Upgrade only with generated-message, all-RPC, cancellation, and in-process fixture validation.

### Production transitive packages

These six repositories contribute modules to the current `Mica`/`MicaCore` target map. They are required by the selected upstream products and cannot be removed from Mica's root manifest individually.

| Package | Pin / latest stable | Last official push | License | Selected role | Assessment |
|---|---|---:|---|---|---|
| `swift-nio` | 2.101.3 / 2.101.3 | 2026-07-29 | Apache-2.0 | Channel/event-loop, HTTP/1 compatibility, embedded/Posix umbrella, and foundation compatibility used by gRPC transport/NIOExtras. NIOCore selects Atomics and DequeModule at `.build/checkouts/swift-nio/Package.swift:64-79`. | Required upstream. Do not import directly for Mica HTTP. |
| `swift-nio-http2` | 1.44.0 / 1.45.0 | 2026-07-22 | Apache-2.0 | HTTP/2 and HPACK implementation used by gRPC transport core. | Required upstream. 1.45.0 adds malformed-header validation; evaluate as an isolated lock refresh for correctness, not performance. |
| `swift-nio-transport-services` | 1.28.0 / 1.28.0 | 2026-05-29 | Apache-2.0 | Network.framework-backed NIO channels for Apple platforms. | Required and preferred over the POSIX/NIOSSL transport product. |
| `swift-nio-extras` | 1.34.3 / 1.34.3 | 2026-07-20 | Apache-2.0 | `NIOExtras` is selected by gRPC transport core; its target uses NIO/NIOCore/NIOHTTP1 at `.build/checkouts/swift-nio-extras/Package.swift:34-43`. | Required upstream, though its broad manifest causes resolution-only packages below. |
| `swift-atomics` | 1.3.1 / 1.3.1 | 2026-06-23 | Apache-2.0 with Swift Runtime Library Exception | Low-level atomics used by SwiftNIO internals. | Required transitively. Do not expose it as a Mica application primitive without a focused benchmark. |
| `swift-collections` | 1.6.0 / 1.6.0 | 2026-07-23 | Apache-2.0 with Swift Runtime Library Exception | GRPCCore uses `DequeModule`; SwiftNIO also uses Collections internals. | Required transitively. Do not add `OrderedCollections` or `HeapModule` merely because the repository is already resolved. |

### Resolution-only packages for current Mica targets

These twelve repositories are present in `Package.resolved` because upstream manifests declare them, but their products do not appear in the current `Mica`, `MicaCore`, `MicaTests`, or `MicaCoreTests` target dependency maps. They add resolution/fetch/checkout cost, not current production executable modules.

| Package | Pin / latest stable | Last official push | License | Why resolved / current necessity |
|---|---|---:|---|---|
| `swift-algorithms` | 1.2.1 / 1.2.1 | 2026-07-22 | Apache-2.0 with Swift Runtime Library Exception | Unconditionally declared by NIOExtras; no Mica target selects `Algorithms`. |
| `swift-asn1` | 1.7.1 / 1.7.1 | 2026-06-08 | Apache-2.0 | Declared by gRPC transport/NIOExtras for certificate and POSIX TLS paths; not selected by TransportServices. |
| `swift-async-algorithms` | 1.1.5 / 1.1.5 | 2026-07-23 | Apache-2.0 with Swift Runtime Library Exception | Declared by NIOExtras and ServiceLifecycle; no Mica target selects it. |
| `swift-certificates` | 1.19.3 / 1.19.4 | 2026-07-28 | Apache-2.0 | Declared for the gRPC POSIX `X509` path and NIOExtras. The selected TransportServices target does not use it. |
| `swift-crypto` | 4.5.1 / 4.5.1 | 2026-07-16 | Apache-2.0 | Certificate/NIOExtras crypto dependency; no current Mica target selects it. |
| `swift-http-structured-headers` | 1.7.0 / 1.7.0 | 2026-07-27 | Apache-2.0 | Unconditionally declared by NIOExtras; no selected Mica product uses it. |
| `swift-http-types` | 1.6.0 / 1.6.0 | 2026-06-22 | Apache-2.0 | Unconditionally declared by NIOExtras; no selected Mica product uses it. |
| `swift-log` | 1.14.0 / 1.14.0 | 2026-07-24 | Apache-2.0 | Declared by NIOExtras/ServiceLifecycle; no Mica target selects `Logging`. Mica now uses system OSLog. |
| `swift-nio-ssl` | 2.37.2 / 2.37.2 | 2026-07-15 | Apache-2.0 | Required only by the unselected gRPC POSIX transport and NIOExtras products. |
| `swift-numerics` | 1.1.1 / 1.1.1 | 2026-01-29 | Apache-2.0 with Swift Runtime Library Exception | Pulled by Swift Algorithms; no selected Mica product uses it. |
| `swift-service-lifecycle` | 2.11.0 / 2.11.0 | 2026-07-14 | Apache-2.0 | Unconditionally declared by NIOExtras; its own manifest pulls SwiftLog and AsyncAlgorithms at `.build/checkouts/swift-service-lifecycle/Package.swift:20-44`. |
| `swift-system` | 1.7.4 / 1.7.5 | 2026-07-28 | Apache-2.0 with Swift Runtime Library Exception | Declared by SwiftNIO at `.build/checkouts/swift-nio/Package.swift:18-20,626-628`; `SystemPackage` is absent from Mica's current target map. |

NIOExtras declares most of this broad resolution graph unconditionally at `.build/checkouts/swift-nio-extras/Package.swift:328-339,351-356`. Removing these repositories would require upstream conditional dependencies/traits or a maintained fork. A fork is not justified: it would trade checkout/resolution savings for continuous compatibility and security maintenance while leaving current runtime modules unchanged.

### License and redistribution

- Official GitHub repository metadata reported Apache-2.0 for all 22 resolved repositories. Exact local license texts refine seven Swift project packages to Apache-2.0 with the Swift Runtime Library Exception: Algorithms, Async Algorithms, Atomics, Collections, Numerics, SwiftProtobuf, and Swift System.
- Thirteen exact checkouts contain `NOTICE`/`NOTICES` files: the three gRPC packages, SwiftASN1, SwiftCertificates, SwiftCrypto, Swift HTTP Types, SwiftLog, SwiftNIO, NIOExtras, NIOHTTP2, NIOSSL, and ServiceLifecycle.
- `docs/DEVELOPMENT.md:20-35` already records the direct package license/notice requirement. Future DMG/Sparkle packaging must aggregate applicable licenses and notices; the app's root license alone is not sufficient attribution evidence.

### Swift 6.2 and macOS 27 compatibility

Manifest-level evidence supports the pinned graph:

- Mica declares Swift tools 6.2 and macOS 27 at `Package.swift:1-10`; `Info.plist` repeats the 27.0 minimum at `Sources/Mica/App/Info.plist:19-20`.
- Exact pinned package manifests use tools versions from 5.7 through 6.2. None requires a newer tools version than Mica's declared 6.2.
- The three direct gRPC manifests use tools 6.1, Swift language mode 6, and availability mappings beginning at macOS 15: `.build/checkouts/grpc-swift-2/Package.swift:1,52-69`, `.build/checkouts/grpc-swift-nio-transport/Package.swift:1,72-89`, and `.build/checkouts/grpc-swift-protobuf/Package.swift:1,54-71`.
- Pinned SwiftProtobuf uses tools 6.2 and Swift language mode 6 at `.build/checkouts/swift-protobuf/Package.swift:1,440`.
- The highest explicit transitive deployment minimum found is Swift System's macOS 26 declaration at `.build/checkouts/swift-system/Package.swift:96`, below Mica's macOS 27 target.
- The existing offline baseline compiled the graph in Release for the macOS 27 application target, but with Apple Swift 6.3.3, not an exact Swift 6.2 compiler.

Conclusion: the pinned graph is **manifest- and deployment-compatible** with Swift 6.2/macOS 27, but exact compiler validation remains pending until built with the intended Swift 6.2 release toolchain and macOS 27 SDK.

### Observed build and binary cost

- The resolved source checkouts occupy 241,160 KiB (about 235.5 MiB) in `.build/checkouts`. The twelve resolution-only repositories account for about 69.0 MiB of that source checkout footprint.
- The existing deterministic cold Release build took 144.19 seconds with the current graph: `research/offline-release-baseline.md:13-19`.
- The resulting raw SwiftPM Release executable is 38,086,232 bytes. This is not a stripped/notarized app/DMG size and cannot attribute bytes to one package.
- `otool -L` lists Apple/system dynamic libraries only; package code is statically linked rather than shipped as separate third-party dylibs.
- The current production target map includes a substantial NIO/gRPC module chain, while the twelve resolution-only repositories do not contribute production modules. Per-package build time and linked size cannot be inferred from checkout size or intermediate object size; only an isolated manifest A/B can establish savings.

### SwiftProtobuf trait experiment

The root dependency at `Package.swift:19` accepts SwiftProtobuf's default traits. SwiftProtobuf defines `BinaryDelimitedStreams` and `FieldMaskUtilities` as defaults at `.build/checkouts/swift-protobuf/Package.swift:46-54`. The current debug and Release build descriptions contain both `-DBinaryDelimitedStreams` and `-DFieldMaskUtilities`, for example `.build/arm64-apple-macosx/debug/description.json:30883-30884`.

No use of binary-delimited stream APIs, FieldMask utilities, `InputStream`, or `OutputStream` was found in Mica source/tests. Upstream `grpc-swift-2` and `grpc-swift-protobuf` already opt out of SwiftProtobuf default traits in their own dependency declarations at `.build/checkouts/grpc-swift-2/Package.swift:42-47` and `.build/checkouts/grpc-swift-protobuf/Package.swift:44-49`; Mica's direct root declaration re-enables the defaults for the unified package.

The authorized isolated `traits: []` clean-Release A/B was completed on
2026-07-29 with separate scratch directories. Default traits built in 129.19s
and produced a 34,501,224-byte executable; `traits: []` built in 129.06s and
produced a 34,392,216-byte executable. The 0.1% build-time difference and
109,008-byte (0.32%) executable reduction are not material, so `Package.swift`
retains the upstream defaults. Because the candidate was rejected before
retention, no package/feature boundary changed and no additional compatibility
surface was introduced.

### Confirmed hotspots and candidate packages

Current code strengthens the no-new-package conclusion:

- The generation-owned actor now contains a Mica-specific ordered connection store at `LiveSessionRuntime.swift:633-695`.
- The log owner publishes append/drop mutations from a fixed-slot count/byte ring at `SessionBuffers.swift:4-168` and `LiveSessionRuntime.swift:108-112`.
- Performance counters use system `Synchronization.Mutex`, and observation uses system `OSSignposter`, at `PerformanceObservation.swift:1-3,265-310,379-413`.
- The repository has an opt-in offline Release benchmark harness at `MicaPerformanceBenchmarkTests.swift:34-151` and a recorded baseline.
- Swift Charts and Canvas remain the actual renderers at `WorkbenchDashboard.swift:1,524,1148`; the measured hotspot is input projection/invalidation and topology normalization, not a demonstrated renderer defect.
- HTTP/WebSocket clients remain URLSession-based and injectable at `MihomoClient.swift:68-123` and `SurgeHttpAPIClient.swift:34-80`. Repeated client/session ownership is a local lifecycle problem, not evidence that URLSession lacks required transport capability.

| Candidate | Official status and compatibility | Hotspot fit | Build/binary/lifecycle cost | Decision |
|---|---|---|---|---|
| `apple/swift-collections` 1.6.0 | Active; latest 1.6.0; tools 6.2; Apache-2.0 with Swift exception; repository already resolved and some modules already compile transitively. | `OrderedDictionary`, `Deque`, or `Heap` for connections, logs, and Top-K. | `OrderedCollections` and `HeapModule` are not in Mica's current target map. Existing focused Release results favored the Mica indexed array by about 25-66% and the fixed ring by about 4.3x: `research/third-party-performance-candidates.md:36-70`. | Do not add a direct product. Reopen only if an end-to-end hotspot benchmark reverses the result or local correctness burden becomes material. |
| `apple/swift-async-algorithms` 1.1.5 | Active; latest 1.1.5; tools 6.2; Apache-2.0 with Swift exception; currently resolution-only. | Throttle/debounce/channels for ingestion/publication. | Adds AsyncAlgorithms/stream modules and generic task/sequence boundaries. Its operators do not encode Mica's latest-only coalescing, critical-state bypass, generation validation, one-flight ownership, or no-replay contract. | Do not promote. Keep explicit actor/coordinator state machines. |
| `apple/swift-atomics` 1.3.1 | Active; latest 1.3.1; tools 5.10; Apache-2.0 with Swift exception; already compiled through NIO. | Lock-free counters/schedulers. | Direct use would couple Mica to low-level memory-ordering correctness. System `Synchronization.Mutex` and actor ownership already satisfy current instrumentation/session needs. | Do not import directly without a focused contention benchmark. |
| `apple/swift-log` 1.14.0 | Active; latest 1.14.0; tools 6.2; Apache-2.0; currently resolution-only. | Performance logging/metrics. | Adds an application logging abstraction while Instruments requires signposts, not server logging. | Do not promote. Current `OSSignposter` is the native low-overhead path. |
| `ordo-one/package-benchmark` 1.36.2 | Active release 2026-07-24; Apache-2.0; manifest tools 6.1/macOS 13, compatible with the root. | Percentiles, ARC/CPU/memory metrics, CI thresholds. | Adds Swift System, Argument Parser, TextTable, HDRHistogram, Atomics, default Jemalloc, command/build plugins, and executable benchmark plumbing. Mica's internal executable-target presentation types would still require target extraction or wider architecture changes. | Do not add initially. The current opt-in Release harness already produces deterministic median/p95 evidence; reconsider only for a required metric or durable CI threshold it cannot provide. |
| `Alamofire` 5.12.0 | Active; latest release 2026-05-05; MIT. Exact latest manifest requires Swift tools 6.3, so it fails the task's Swift 6.2 gate. | HTTP ergonomics, retry, validation. | Wraps URLSession and would not remove gRPC or the current WebSocket/session ownership work. Pinning an older line solely for compatibility adds maintenance with no measured gain. | Reject. |
| `swift-server/async-http-client` 1.36.0 | Active release 2026-07-23; Apache-2.0; tools 6.2. | HTTP pooling/streaming. | Latest manifest declares ten package dependencies, including NIO/SSL/HTTP2/Extras/TransportServices, Logging, Atomics, Algorithms, distributed tracing, configuration, and service context. It adds a second client lifecycle/transport model and does not replace sing-box gRPC. | Reject. Reuse one generation-owned URLSession/client bundle. |
| `ChartsOrg/DGCharts` 5.1.0 | Unarchived with 2026 repository activity; latest release remains 2024-02-16; Apache-2.0; tools 5.3/macOS 10.12. | Replace Swift Charts. | Adds a separate AppKit-style rendering/interaction/accessibility surface. The measured cost is projection/invalidation/topology preparation, not a proven Swift Charts renderer bottleneck. | Reject. Keep system Charts/Canvas and optimize their bounded inputs. |

No separate graph package is recommended for topology. The confirmed shared-route issue is domain-specific collection copying and indexing, not a missing general graph algorithm; a local near-linear adjacency/path index preserves complete controller-reported routes with less integration and binary cost.

### System and small-local alternatives

| Need | Preferred boundary |
|---|---|
| HTTP, WebSocket, pooling | One generation-owned set of existing URLSession-backed typed clients. |
| gRPC/HTTP2/Protobuf | Existing four-package stack; no system gRPC implementation. |
| Connection order plus O(1) lookup | Mica's ordered array/tombstone/index store. |
| Bounded logs | Existing fixed-slot, byte-budgeted ring with append/drop deltas. |
| Top-K | Small bounded insertion buffer while `k` remains about five. |
| Publication coalescing and cancellation | Generation-owned actor/coordinator using structured concurrency and explicit state. |
| Counters/locking | System `Synchronization.Mutex` or actor isolation. |
| Performance intervals | System OSLog/OSSignposter and Instruments. |
| Charts/topology rendering | Swift Charts plus SwiftUI Canvas with cached bounded inputs/geometry. |
| Offline benchmarks | Existing opt-in Release test harness with deterministic fixtures and explicit output. |

### Existing-graph maintenance watch list

The lock file is not fully current as of the audit date:

- `swift-nio-http2` 1.44.0 -> 1.45.0: official release notes add stricter malformed-header and HPACK update validation. This package contributes production modules, so an isolated lock refresh is reasonable for protocol correctness after current performance measurements are stable.
- `swift-protobuf` 1.38.0 -> 1.38.1: official release notes include JSON validation and merge-correctness fixes. This requires changing the direct exact pin; it is maintenance, not a demonstrated performance improvement.
- `swift-certificates` 1.19.3 -> 1.19.4 and `swift-system` 1.7.4 -> 1.7.5: both are currently resolution-only for Mica's selected targets, so no current production runtime benefit is established.

Do not combine these upgrades with the `traits: []` performance experiment; separate changes preserve causal build/size and correctness evidence.

### External references

Official primary sources queried through GrokSearch-rs:

- Direct stack releases/manifests: https://github.com/grpc/grpc-swift-2/releases/tag/2.4.2, https://github.com/grpc/grpc-swift-nio-transport/releases/tag/2.9.0, https://github.com/grpc/grpc-swift-protobuf/releases/tag/2.4.1, https://github.com/apple/swift-protobuf/releases/tag/1.38.1
- Existing graph update notes: https://github.com/apple/swift-nio-http2/releases/tag/1.45.0, https://github.com/apple/swift-certificates/releases/tag/1.19.4, https://github.com/apple/swift-system/releases/tag/1.7.5
- Candidate repositories/manifests: https://github.com/apple/swift-collections, https://github.com/apple/swift-async-algorithms, https://github.com/apple/swift-atomics, https://github.com/apple/swift-log, https://github.com/ordo-one/package-benchmark/releases/tag/1.36.2, https://raw.githubusercontent.com/ordo-one/package-benchmark/1.36.2/Package@swift-6.2.swift, https://github.com/Alamofire/Alamofire/releases/tag/5.12.0, https://raw.githubusercontent.com/Alamofire/Alamofire/5.12.0/Package.swift, https://github.com/swift-server/async-http-client/releases/tag/1.36.0, https://raw.githubusercontent.com/swift-server/async-http-client/1.36.0/Package.swift, https://github.com/ChartsOrg/Charts/releases/tag/5.1.0, https://raw.githubusercontent.com/ChartsOrg/Charts/5.1.0/Package.swift
- Official repository metadata for every package named in `Package.resolved` was read from its GitHub API repository and latest-release endpoints on 2026-07-29.

### Related specs

- `.trellis/spec/backend/controller-data-contract.md:32-40` - typed, cancellable, generation-safe dependency boundary and adoption checks.
- `.trellis/spec/frontend/live-session-controller-contract.md:31-66` - generation ownership, structured gRPC task tree, bounded buffers, and publication cadence.
- `.trellis/spec/frontend/workbench-ui-contract.md:99-166,219-224` - indexed projections, native Charts/Canvas, performance boundaries, and third-party adoption gate.
- `.agents/skills/mica-controller-development/references/architecture.md` - package products, transport boundary, dependency injection, and concurrency ownership.
- `.agents/skills/mica-controller-development/references/project-constraints.md:124-151` - dependency, compatibility, license, build, and distribution constraints.
- `.agents/skills/mica-controller-development/references/controllers.md` - HTTP/WebSocket/gRPC protocol and cancellation contracts that candidate replacements must preserve.
- `.trellis/tasks/07-29-comprehensive-performance-optimization/prd.md:34-41,100-104,125-130` - default no-new-package decision and evidence gate.
- `.trellis/tasks/07-29-comprehensive-performance-optimization/design.md:329-362` - package decisions and rollback conditions.

## Caveats / Not Found

- No manifest change was retained and `Package.resolved` was not changed. The temporary `traits: []` edit was restored after two isolated clean Release builds.
- No package update, stripped app packaging, launch measurement, or candidate integration was retained.
- The 144.19-second build and 38.1 MB executable describe one local Swift 6.3.3/macOS 27 baseline. They do not isolate package cost or prove Swift 6.2 compiler compatibility.
- Official GitHub release/repository metadata establishes current maintenance activity and declared licenses, not absence of vulnerabilities. No authenticated GitHub advisory, OSV, SBOM, or notarized-distribution scan was available in this audit.
- Four newer releases exist inside the resolved graph. Their release notes were reviewed, but compatibility and behavior against Mica remain unverified until isolated build/test runs are authorized.
- Real-controller throughput, reconnect behavior, and Instruments traces remain outside this audit, consistent with the task PRD.
