# Research: Dependency performance audit

- Query: Audit Mica's direct and transitive Swift dependencies and Apple-framework usage; determine required/removable packages and evidence-backed performance/correctness candidates.
- Scope: mixed
- Date: 2026-07-29

## Findings

### Executive recommendation

Default dependency policy for this task:

1. Keep all four direct packages. They form one required sing-box StartedService stack and none can be removed independently without replacing generated protobuf messages, generated gRPC stubs, the gRPC core, or the HTTP/2 Network.framework transport.
2. Add no new third-party package by default. Current UI, charts, topology, HTTP/WebSocket, persistence, logging instrumentation, and bounded collections all have suitable Apple-framework or small-local-code paths.
3. The `swift-protobuf` default-traits A/B is complete. Disabling `BinaryDelimitedStreams` and `FieldMaskUtilities` changed clean Release time from 129.19s to 129.06s and executable size from 34,501,224 to 34,392,216 bytes. The result is not material, so retain upstream defaults.
4. Keep using `GRPCNIOTransportHTTP2TransportServices`, not the umbrella or POSIX transport product. It is the Apple-platform path backed by Network.framework and avoids compiling the NIOSSL/X509 transport target chain into Mica.
5. Do not fork or vendor a trimmed gRPC/NIO graph. Twelve resolved packages are not in Mica's production target dependency map, but they are pulled by upstream package manifests. A private manifest fork would trade modest resolution/disk savings for ongoing security and compatibility maintenance.
6. Use Apple `OSSignposter`/Instruments and test hooks for performance evidence. Do not add `swift-log`, an analytics SDK, or a custom metrics package for this task.

### Files found

| File | Role |
|---|---|
| `Package.swift` | Root Swift 6.2 manifest, four direct exact pins, target/product selection. |
| `Package.resolved` | Exact 22-package resolved graph and revisions. |
| `.build/arm64-apple-macosx/debug/description.json` | Existing SwiftPM target dependency map and compiler arguments. |
| `.build/checkouts/*/Package.swift` | Exact pinned upstream manifests used to explain transitive resolution and selected target dependencies. |
| `.build/checkouts/*/LICENSE*` | License texts for all 22 checkouts. |
| `.build/checkouts/*/NOTICE*` | Upstream notice files that must be considered for direct distribution. |
| `Sources/MicaCore/API/SingBoxGRPCClient.swift` | Runtime imports of GRPCCore, TransportServices transport, and SwiftProtobuf. |
| `Sources/MicaCore/Protocols/SingBox/started_service.proto` | 225-line schema with 17 RPCs and multiple streaming domains. |
| `Sources/MicaCore/Protocols/SingBox/Generated/.../started_service.pb.swift` | Checked-in generated protobuf messages, 1,995 lines. |
| `Sources/MicaCore/Protocols/SingBox/Generated/.../started_service.grpc.swift` | Checked-in generated gRPC client/service code, 3,409 lines. |
| `Tests/MicaCoreTests/SingBoxGRPCClientTests.swift` | In-process gRPC fixture using GRPCCore, GRPCInProcessTransport, and SwiftProtobuf. |
| `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift` | System Charts and SwiftUI Canvas implementation. |
| `Sources/MicaCore/API/MihomoClient.swift` | Foundation URLSession HTTP and WebSocket transport. |
| `Sources/MicaCore/API/SurgeHttpAPIClient.swift` | Foundation URLSession HTTP transport. |
| `Sources/MicaCore/Security/KeychainSecretStore.swift` | Security.framework Keychain implementation. |
| `Sources/Mica/App/AppPreferencesStore.swift` | The only direct Combine use: ObservableObject and four low-frequency Published preferences. |

### Direct package audit

Root declarations are exact pins at `Package.swift:15-20`; `MicaCore` directly selects the four runtime products at `Package.swift:22-30`, and tests additionally select the in-process transport at `Package.swift:46-55`.

| Package | Pin | Required evidence | Removal decision | Main cost |
|---|---:|---|---|---|
| `grpc-swift-2` | 2.4.2 | `SingBoxGRPCClient.swift:2`; generated service code imports GRPCCore at `started_service.grpc.swift:11`; tests import GRPCCore and GRPCInProcessTransport at `SingBoxGRPCClientTests.swift:2-3`. | Keep. Removing it requires replacing the gRPC client API, RPC status/error model, streaming interfaces, and test transport. | GRPCCore plus Swift Collections Deque support; test-only in-process transport. |
| `grpc-swift-nio-transport` | 2.9.0 | `SingBoxGRPCClient.swift:3` imports `GRPCNIOTransportHTTP2TransportServices`; root selects that exact product at `Package.swift:26`. | Keep. There is no system gRPC client; replacing it means implementing HTTP/2 gRPC framing, flow control, deadlines, status, TLS/trust behavior, cancellation, and streaming lifecycle. | Largest runtime transitive chain: NIO core, HTTP/2, NIOExtras, TransportServices, Atomics, Collections, and zlib shim. |
| `grpc-swift-protobuf` | 2.4.1 | Generated service code imports GRPCProtobuf at `started_service.grpc.swift:12`; root selects it at `Package.swift:27`. | Keep. Hand-written serializers for 17 RPCs would reduce correctness and schema compatibility. | Small runtime adapter over GRPCCore and SwiftProtobuf. Code-generation products exist upstream but are not selected by Mica's root target. |
| `swift-protobuf` | 1.38.0 | `SingBoxGRPCClient.swift:4`; generated message/service files import SwiftProtobuf at `started_service.pb.swift:11` and `started_service.grpc.swift:13`; root selects it at `Package.swift:28`. | Keep. The direct product is required because Mica's generated source imports the module directly. | Generated/runtime serialization code. Root currently enables two unused default traits. |

The schema is not a plausible small local replacement: `started_service.proto:7-29` declares 17 unary/server-streaming RPCs covering version, logs, status, groups, mode, URL tests, selection, connections, and Tailscale. The checked-in generated output totals 5,404 Swift lines. Replacing protobuf/gRPC locally would create a larger protocol-correctness and maintenance burden than the current packages.

### Resolved and production transitive graph

`Package.resolved` contains 22 packages. The existing `targetDependencyMap.Mica` in `.build/arm64-apple-macosx/debug/description.json` shows ten package identities contributing modules to the production executable: the four direct packages plus the following six transitives.

| Production transitive | Pin | Why it is present | Root-removable? |
|---|---:|---|---|
| `swift-nio` | 2.101.3 | NIOCore, NIOHTTP1, NIO/Posix/Embedded umbrella modules and Foundation compatibility used by transport/NIOExtras. | No; required by selected upstream products. |
| `swift-nio-http2` | 1.44.0 | HTTP/2 and HPACK implementation required by gRPC transport core. | No. |
| `swift-nio-transport-services` | 1.28.0 | Bridges SwiftNIO channels to Apple's Network.framework for the selected transport. | No. |
| `swift-nio-extras` | 1.34.3 | gRPC transport core selects `NIOExtras`; that target depends on NIO, NIOCore, and NIOHTTP1 (`.build/checkouts/swift-nio-extras/Package.swift:34-43`). | No. |
| `swift-atomics` | 1.3.1 | Required by SwiftNIO/NIOTransportServices internals. | No. |
| `swift-collections` | 1.6.0 | GRPCCore directly uses `DequeModule` (`.build/checkouts/grpc-swift-2/Package.swift:73-80`); SwiftNIO also uses Collections modules. | No. |

The other twelve pins are resolved through unconditional upstream package declarations but are not in the current Mica/MicaCore/MicaTests target dependency maps:

| Resolution-only for current Mica targets | Pin | Resolution source |
|---|---:|---|
| `swift-algorithms` | 1.2.1 | Declared by `swift-nio-extras`. |
| `swift-asn1` | 1.7.1 | Declared by gRPC NIO transport and NIOExtras/certificate packages. |
| `swift-async-algorithms` | 1.1.5 | Declared by `swift-nio-extras` and `swift-service-lifecycle`. |
| `swift-certificates` | 1.19.3 | Declared by gRPC NIO transport and NIOExtras for POSIX/TLS-related products. |
| `swift-crypto` | 4.5.1 | Declared by NIOExtras/certificates. |
| `swift-http-structured-headers` | 1.7.0 | Declared by `swift-nio-extras`. |
| `swift-http-types` | 1.6.0 | Declared by `swift-nio-extras`. |
| `swift-log` | 1.14.0 | Declared by `swift-nio-extras` and service lifecycle. |
| `swift-nio-ssl` | 2.37.2 | Declared by gRPC NIO transport and NIOExtras; not used by the selected TransportServices target. |
| `swift-numerics` | 1.1.1 | Declared by `swift-algorithms`. |
| `swift-service-lifecycle` | 2.11.0 | Declared by `swift-nio-extras`. |
| `swift-system` | 1.7.4 | Declared by `swift-nio`; no SystemPackage module appears in Mica's production dependency map. |

These twelve cannot be removed one-by-one from Mica's root manifest because Mica does not declare them. They can disappear only if upstream package manifests make those dependencies conditional/trait-gated, the selected transport drops them, or Mica carries a fork. The fork option is not recommended.

Important graph detail: selecting `GRPCNIOTransportHTTP2TransportServices` correctly avoids the `GRPCNIOTransportHTTP2Posix` target's NIOSSL/X509/SwiftASN1 target dependencies (`.build/checkouts/grpc-swift-nio-transport/Package.swift:126-149`). However, gRPC transport core still selects `NIOExtras`, whose `NIOExtras` target uses the `NIO` umbrella (`swift-nio-extras/Package.swift:34-43`); the umbrella itself includes NIOEmbedded and NIOPosix (`swift-nio/Package.swift:90-124`). This is upstream build-graph structure, not removable application code.

### License and redistribution audit

- Every resolved checkout has a local license file identifying Apache License 2.0.
- `swift-protobuf` additionally states the SwiftProtobuf runtime library exception at `.build/checkouts/swift-protobuf/Package.swift:5-9`.
- Thirteen checkouts include NOTICE/NOTICES files, including all three gRPC packages and major NIO/security packages.
- Mica's own `docs/DEVELOPMENT.md:20-35` already records the Apache-2.0 status and the requirement to include notices in future DMG/Sparkle packaging.
- Default recommendation: preserve the existing direct-distribution notice requirement. Do not assume the root `LICENSE` alone satisfies third-party attribution.

### Swift 6.2 and macOS 27 compatibility

High-confidence source evidence:

- Mica declares Swift tools 6.2 and macOS 27 at `Package.swift:1-10`.
- The pinned gRPC packages use Swift tools 6.1, Swift language mode 6, and availability mappings beginning at macOS 15: `grpc-swift-2/Package.swift:1,52-69`, `grpc-swift-nio-transport/Package.swift:1,72-89`, and `grpc-swift-protobuf/Package.swift:1,54-71`.
- Pinned SwiftProtobuf uses Swift tools 6.2 and Swift language mode 6 at `swift-protobuf/Package.swift:1,440`.
- All remaining pinned transitive manifests use tools versions from 5.7 through 6.2, so none requires a toolchain newer than the root's declared 6.2 language generation.
- Existing local build metadata targets `arm64-apple-macosx27.0`, proving the resolved graph has compiled in this workspace with the currently installed newer Swift toolchain.

This is not an exact Swift 6.2/macOS 27 verification. `swift --version` reports Apple Swift 6.3.3, and the existing build description references MacOSX26.5.sdk while emitting a macOS 27 deployment target. A clean build with the intended release Xcode/Swift 6.2 toolchain and a macOS 27 SDK remains required before claiming exact compatibility.

### System-framework usage

| Apple module/framework | Evidence | Assessment |
|---|---|---|
| SwiftUI | Workbench and app views import SwiftUI throughout; root navigation is `NavigationSplitView` at `WorkbenchChrome.swift:328`. | Keep. Native UI is a product requirement; no third-party UI framework is justified. |
| Charts | `WorkbenchDashboard.swift:1`, with charts at lines 524 and 667. | Keep. Bounded real samples and system rendering satisfy current contracts. No chart package candidate. |
| SwiftUI Canvas/CoreGraphics | Topology Canvas at `WorkbenchDashboard.swift:1148`. | Keep. Cached geometry plus one Canvas is the preferred small/native solution. |
| Foundation/CFNetwork | URLSession HTTP/WebSocket clients at `MihomoClient.swift:71-119,516-520` and Surge client at `SurgeHttpAPIClient.swift:42-65`. | Keep. No measured evidence supports replacing URLSession. |
| Network.framework | Weak-linked in the existing executable through NIOTransportServices; selected by the gRPC TransportServices product. | Keep indirectly. This is the appropriate Apple transport backend. |
| AppKit | Narrow infrastructure use: NSWorkspace sleep/wake at `WorkbenchChrome.swift:393-401`, NSPasteboard at `AppModelDiagnostics.swift:19-20`, plus app/window appearance and close lifecycle. | Keep. Uses system services SwiftUI does not fully expose; no parallel AppKit content UI. |
| Security | Keychain calls at `KeychainSecretStore.swift:17,46,53,64`. | Keep while KeychainSecretStore remains a supported implementation. It is a dynamic system framework, not bundled package weight. |
| Combine | `AppPreferencesStore.swift:2,6,12-33` for one low-frequency ObservableObject. | No dependency concern. A future Observation migration may simplify state consistency, but it is not a material performance priority and does not justify task scope by itself. |
| Observation | Imported by field-granular presentation/state types (`WorkbenchChrome.swift:3`, `OperationSessionModels.swift:3`). | Keep. It supports the project's narrow invalidation model. |
| Darwin | Used by GeoIP/runtime database code (`GeoIPResolver.swift:1`, `MaxMindDatabase.swift:1`). | Keep local/system implementation; no database package is justified by current bounded read-only use. |
| ObjectiveC runtime | Localization method exchange at `BundleLocalization.swift:2,55`. | Existing correctness mechanism, not a performance package candidate. Review separately only if localization behavior changes. |
| OSLog/OSSignposter | No current source import/use found. | Preferred candidate for low-overhead intervals/events required by performance baselining; system framework, removable instrumentation, no package. |

`otool -L` on the existing 48 MiB debug executable lists only Apple/system dynamic frameworks and libraries; there are no third-party dylibs. Therefore selected SwiftPM runtime products contribute statically to executable code rather than adding separately shipped dynamic libraries. The 48 MiB value is an unstripped debug artifact and must not be used as a release-size claim.

### Build and binary impact priorities

1. Measure a clean release build, not the existing debug artifact: total wall time, per-target frontend time, link time, stripped executable/app size, and incremental rebuild after a Mica-only source edit.
2. Measure `swift-protobuf` traits. The package defaults enable `BinaryDelimitedStreams` and `FieldMaskUtilities` (`swift-protobuf/Package.swift:46-53`), the root direct declaration does not opt out (`Package.swift:19`), and the existing SwiftProtobuf compiler arguments contain both defines. `rg` found no FieldMask, binary-delimited, InputStream, or OutputStream use in Mica sources/tests. This is the only current manifest-level reduction candidate with direct evidence.
3. Preserve checked-in generated code. Mica excludes the `.proto` from target compilation (`Package.swift:30`) and does not select a code-generation plugin. Ordinary builds therefore need runtime products, not protoc execution.
4. Do not optimize the twelve resolution-only packages with a local fork unless measurements show package resolution/fetching is a dominant developer cost. They are not current production target modules, so removing them cannot be assumed to reduce runtime CPU or launch time.
5. Profile before considering `swift-collections` in application code. It is already present transitively, but Mica's hot buffers do not currently demonstrate a need: logs use an O(1) fixed-slot ring (`SessionBuffers.swift:4-139`), timelines are capped at 300 (`SessionTimelineModels.swift:19-29,85-95`), closed connections at 200 (`SessionBuffers.swift:151-188`), and command history at 20 (`OperationSessionModels.swift:301-304`).

### Evidence-backed candidate libraries

No new third-party library currently clears the project's adoption bar.

- `swift-collections` is the only conditional package candidate worth retaining on a watch list because it is already resolved and GRPCCore already compiles Deque support. It should be used directly only if benchmarks show a specific application collection dominates CPU/copying and a Collections type wins a focused benchmark. Current bounded structures do not provide that evidence.
- `swift-async-algorithms`, `swift-log`, and the other resolution-only packages should not be promoted to direct dependencies. Existing publication scheduling/cancellation is generation-owned and tested; OSLog/OSSignposter is the native instrumentation path; promoting them would add application coupling without a measured bottleneck.
- No third-party charting, WebSocket, HTTP, persistence, cache, topology, or logging package is recommended.

### Default dependency recommendation

Keep this direct set, pinned and upgraded only as a coordinated, tested stack:

```text
grpc-swift-2 2.4.2
grpc-swift-nio-transport 2.9.0
grpc-swift-protobuf 2.4.1
swift-protobuf 1.38.0
```

Final implementation decision: retain `swift-protobuf` with upstream default traits. The isolated clean-build A/B produced no material build-time or executable-size benefit, so the temporary manifest edit was restored and no new compatibility surface was retained.

Do not remove a direct package, add a new package, switch transport products, or fork the graph without before/after measurements and the full sing-box protocol test matrix.

### External references

- Official gRPC Swift 2 releases: https://github.com/grpc/grpc-swift-2/releases
- Exact pinned gRPC Swift 2 manifest: https://github.com/grpc/grpc-swift-2/blob/2.4.2/Package.swift
- Exact pinned gRPC NIO transport manifest: https://github.com/grpc/grpc-swift-nio-transport/blob/2.9.0/Package.swift
- Exact pinned gRPC Protobuf manifest: https://github.com/grpc/grpc-swift-protobuf/blob/2.4.1/Package.swift
- Exact pinned SwiftProtobuf manifest: https://github.com/apple/swift-protobuf/blob/1.38.0/Package.swift
- Apple OSSignposter documentation: https://developer.apple.com/documentation/os/ossignposter
- Apple Swift Charts documentation: https://developer.apple.com/documentation/charts

The fetched official `grpc-swift-2` releases page showed 2.4.2 as the newest visible release. Current release/commit activity for the other repositories was not completed; see caveats.

### Related specs

- `.trellis/spec/backend/controller-data-contract.md:32-40` - typed, cancellable, capability-gated package boundary and dependency adoption checks.
- `.trellis/spec/frontend/live-session-controller-contract.md:31-66` - generation validation, structured gRPC task tree, bounded buffers, and publication cadence that replacements must preserve.
- `.trellis/spec/frontend/workbench-ui-contract.md:67-154,219-224` - native Charts/Canvas, performance boundaries, and third-party package rules.
- `.agents/skills/mica-controller-development/references/project-constraints.md:119-149` - dependency, compatibility, license, and distribution constraints.
- `.agents/skills/mica-controller-development/references/architecture.md:45-54,156-171` - package products, direct gRPC dependencies, injection, cancellation, and concurrency ownership.

## Caveats / Not Found

- GrokSearch-rs returned no verifiable sources for the broad release query. A fallback web search also failed, and the follow-up GitHub API fetch was interrupted. Only the official `grpc-swift-2` releases page was successfully fetched before the stop request.
- Current upstream release numbers, commit cadence, unresolved security advisories, and manifest improvements were not independently verified for `grpc-swift-nio-transport`, `grpc-swift-protobuf`, SwiftProtobuf, or the 18 transitive repositories. The audit uses exact pinned local checkouts as authoritative for the installed graph.
- No clean build, release build, stripped package, launch-time test, or before/after trait experiment was run because this research agent may write only in the task research directory. Build and binary savings are therefore candidates to measure, not claimed improvements.
- Existing `.build` artifacts may include products from prior broad builds or tooling. Classification above uses `targetDependencyMap.Mica`, `MicaCore`, and tests, not the mere presence of an object/module on disk.
- Exact Swift 6.2 compiler and macOS 27 SDK/runtime validation remains unknown; the local compiler is Swift 6.3.3 and existing build metadata references MacOSX26.5.sdk.
- Real-controller throughput, reconnect behavior, and Instruments traces were not exercised. No runtime performance acceptance claim is made.
