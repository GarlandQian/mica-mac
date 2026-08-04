# Research: Third-Party Performance Candidates

- Query: Determine whether a mature Swift package can materially improve Mica's
  measured runtime or performance-regression workflow without weakening native
  macOS architecture, controller semantics, or build maintenance.
- Scope: official upstream repositories plus a local Release microbenchmark.
- Date: 2026-07-29

## Decision Summary

No new runtime dependency currently clears Mica's adoption gate.

The implementation plan must remain open to a package when a Phase 0 focused
before/after benchmark demonstrates material benefit, but package popularity or
API convenience is not sufficient. The current preferred implementation is:

- local ordered array plus ID index for active connections;
- the existing fixed byte-budgeted log ring;
- explicit generation-scoped coordinators for refresh/publication scheduling;
- system `OSSignposter`, `ContinuousClock`, XCTest/Swift Testing fixtures, and
  Instruments for performance evidence;
- system Swift Charts, Canvas, URLSession, and the existing gRPC stack.

## Candidate Matrix

| Candidate | Maturity / compatibility | Possible Mica use | Finding | Decision |
|---|---|---|---|---|
| `apple/swift-collections` 1.6.0 | Apple project, source-stable stable modules, Swift >= 6.0.3, no deployment minimum, Apache-2.0. Already resolved by gRPC. | `OrderedDictionary` for active connections; `Deque` for timelines/logs; `Heap` for Top-K. | Focused Release benchmark favored Mica-specific local structures. `DequeModule` is already in the production dependency graph, but `OrderedCollections` is not. For Top-K where k is about five, a small local bounded insertion buffer is simpler than adding `HeapModule`. | Do not add a direct product now. Reopen only if the real implementation benchmark reverses the result or a correctness burden becomes material. |
| `apple/swift-async-algorithms` 1.1.5 | Apple project, source-stable 1.x, Apache-2.0, already present in `Package.resolved` but absent from Mica production target dependencies. | `throttle`, `debounce`, `AsyncChannel`, `AsyncThrowingChannel`. | Mica needs latest-only coalescing with critical-state bypass, generation validation, one owned flight, explicit cancellation, and no historical replay. Generic throttle/debounce/channel composition does not encode those contracts and would add task/stream boundaries to already over-layered ingestion. | Do not promote to a direct dependency. |
| `apple/swift-atomics` 1.3.1 | Apple project, source-stable, Swift 5.10+ for 1.3, Apache-2.0, already linked transitively through NIO. | Lock-free counters or custom schedulers. | The upstream project explicitly warns that atomics are low-level and should be avoided when higher-level constructs work. Mica's counters are test/instrumentation state; actors, locks, and signposts are sufficient. | Do not import directly into Mica code. |
| `ordo-one/benchmark` 1.36.2 | Active releases through 2026-07-24, Apache-2.0, explicit Swift 6.2 manifest, macOS support, percentile/CPU/ARC/memory metrics. | Dedicated long-lived performance benchmark runner and thresholds. | Technically capable, but the Swift 6.2 manifest adds Swift System, Argument Parser, TextTable, HDR Histogram, Atomics, and default Jemalloc plus command/build plugins. Its executable benchmark model cannot directly benchmark Mica's internal executable-target presentation types without extracting another library target or broadening architecture. | Do not add in this task initially. Use a small opt-in Release harness; reconsider only if native counters cannot provide a required metric or CI threshold. |
| `Alamofire/Alamofire` 5.11 | Mature, Swift 6.0/6.1/6.2 manifests, macOS support. | HTTP requests, validation, retries, WebSocket wrapper. | Alamofire is built on URLSession. Mica's bottleneck is repeated client/session ownership and duplicate cadence, not missing HTTP ergonomics. Migration would add abstraction without removing the underlying transport cost or gRPC stack. | Reject. Keep generation-owned URLSession clients. |
| `swift-server/async-http-client` 1.34+ | Swift Server project, Swift 6.1+, Apache-2.0, NIO-based. | HTTP pooling and streaming. | Designed around SwiftNIO client ownership and shutdown. Mica is a native Apple client already using URLSession/Network.framework and NIO only for required gRPC. Adoption would add another transport model and lifecycle while not replacing WebSocket or gRPC semantics. | Reject. |
| `ChartsOrg/DGCharts` 5.x | Mature cross-Apple chart library with macOS demo and SPM support. | Replace Overview Swift Charts. | AppKit/UIKit-style chart system with a separate interaction/rendering model. The audited bottleneck is repeated projection/invalidation before rendering, not a proven Swift Charts renderer defect. Adoption would create a non-native content boundary and duplicate accessibility/style work. | Reject. Keep Swift Charts and optimize its inputs. |

## Local `swift-collections` Evaluation

### Method

- Swift Release build using the repository's existing local
  `.build/checkouts/swift-collections` at resolved version 1.6.0.
- Nine measured runs per case; reported value is the median.
- 10,000 ordered connection records, 50,000 indexed updates, and removal of
  1,000 records while preserving order.
- 1,000,000 bounded appends into a 2,000-element fixed ring or `Deque`.
- The fixture is a focused adoption proxy, not an end-to-end Mica performance
  claim. It intentionally measures the concrete operations proposed by the
  architecture rather than generic collection throughput.

### Results

| Operation | Mica-specific local structure | Package structure | Result |
|---|---:|---:|---|
| 10k reset x20 | indexed array: 4.877 ms | `OrderedDictionary`: 6.546 ms | local about 25% lower median time |
| 50k updates | indexed array: 1.075 ms | `OrderedDictionary`: 3.134 ms | local about 2.9x faster |
| remove 1k of 10k preserving order | indexed array rebuild: 0.523 ms | `OrderedDictionary` rebuild: 0.797 ms | local about 34% lower median time |
| 1m bounded appends | fixed ring: 0.902 ms | `Deque`: 3.908 ms | local about 4.3x faster |

The custom connection store remains small and testable: an ordered value array,
an ID-to-slot dictionary, one-pass reset, O(1) update lookup, and batched ordered
removal/reindex. The existing log ring additionally enforces byte and count caps,
which `Deque` would not provide without another ownership wrapper.

### Build-Graph Detail

Mica's existing production dependency map already contains `DequeModule`,
`ContainersPreview`, and `InternalCollectionsUtilities` through GRPCCore. It does
not contain `OrderedCollections`, `HeapModule`, or `AsyncAlgorithms`. Direct use of
those products would therefore add compiled application modules even though their
repositories are already resolved transitively.

## Package Adoption Gate During Implementation

A package may still be introduced when all of the following are recorded in this
task before the manifest edit:

1. The exact Mica hotspot and native/local baseline are identified.
2. A focused Release benchmark shows a material improvement in latency, scaling,
   allocations, correctness risk, or maintenance burden.
3. The package has an active supported release, redistributable license, Swift 6.2
   and macOS 27 compatibility, and an acceptable transitive graph.
4. The package is isolated to the smallest target and does not force a second UI,
   networking, persistence, or state architecture.
5. Full build/test, release-size, launch/build-time, cancellation, generation, and
   controller-order contracts pass after adoption.
6. The package is removed again when the measured gain is inconclusive.

## Official Sources

- Swift Collections repository and stability/toolchain table:
  https://github.com/apple/swift-collections
- Swift Async Algorithms repository and supported algorithms:
  https://github.com/apple/swift-async-algorithms
- Swift Async Algorithms releases:
  https://github.com/apple/swift-async-algorithms/releases
- Swift Atomics repository and usage warning:
  https://github.com/apple/swift-atomics
- Swift Atomics releases:
  https://github.com/apple/swift-atomics/releases
- Benchmark repository and metrics/workflow:
  https://github.com/ordo-one/benchmark
- Benchmark Swift 6.2 manifest and transitive dependencies:
  https://github.com/ordo-one/benchmark/blob/main/Package@swift-6.2.swift
- Benchmark releases:
  https://github.com/ordo-one/benchmark/releases
- Alamofire repository and Swift/platform requirements:
  https://github.com/Alamofire/Alamofire
- AsyncHTTPClient repository and Swift support table:
  https://github.com/swift-server/async-http-client
- DGCharts repository and macOS/SPM architecture:
  https://github.com/ChartsOrg/Charts

## Caveats

- GrokSearch-rs returned no verifiable search sources, so official repository pages
  were fetched directly with the available web reader.
- The local collection benchmark is an adoption gate, not a claim about final app
  frame time, CPU, RSS, or every payload shape.
- Upstream package behavior may change. Any later adoption must repeat version,
  manifest, license, and focused benchmark checks against the exact selected tag.
- No application source, Package.swift, or resolved dependency was changed during
  this research.
