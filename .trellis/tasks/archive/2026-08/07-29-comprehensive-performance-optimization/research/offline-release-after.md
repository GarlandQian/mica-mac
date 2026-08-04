# Offline Release Performance Result

Date: 2026-07-29

## Method

- Command: `scripts/run-performance-benchmarks.sh after`
- Configuration: SwiftPM Release, deterministic synthetic fixtures
- Toolchain: Apple Swift 6.3.3
- Host OS: macOS 27.0 build 26A5388g
- Input/output: repository-local `tmp/codex/performance/`
- Network: no profile read, controller connection, core launch, or system-network change

The durable comparison is matching benchmark cases and fixture sizes. Build wall
time is excluded because the before and after invocations did not both start from
an explicitly clean identical scratch directory.

## Median Comparison

| Case | Fixture | Before | After | Change |
|---|---:|---:|---:|---:|
| Connection row projection | 1,000 | 8.94 ms | 7.54 ms | -15.6% |
| Connection row projection | 5,000 | 44.73 ms | 37.84 ms | -15.4% |
| Connection row projection | 10,000 | 90.07 ms | 75.69 ms | -16.0% |
| Log ring materialization | 2,000 | 14.76 ms | 10.83 ms | -26.7% |
| Full-ring incremental log projection | 2,000 x 32 updates | 67.26 ms | 65.84 ms | -2.1% |
| Shared-route topology | 1,000 | 20.71 ms | 4.40 ms | -78.8% |
| Shared-route topology | 2,000 | 73.93 ms | 9.08 ms | -87.7% |
| Unique-route topology | 1,000 | 6.94 ms | 6.23 ms | -10.3% |
| Unique-route topology | 2,000 | 14.18 ms | 11.84 ms | -16.5% |

New actor-boundary support cases have no before equivalent:

| Case | Fixture | After median |
|---|---:|---:|
| Hidden log ingestion and forced publication | 10,000 | 12.10 ms |
| Runtime connection frame | 1,000 | 0.70 ms |
| Runtime connection frame | 5,000 | 3.29 ms |
| Runtime connection frame | 10,000 | 6.73 ms |

## Interpretation

- High-frequency raw ingestion now scales away from SwiftUI and publishes by
  visible domain at bounded cadence.
- Connection structure, metrics, and aggregate traffic revisions prevent
  rate-only frames from rebuilding static row/search/close-group state.
- Log append/drop publication and stable-ID row reuse keep full-ring updates
  bounded without changing incoming order or complete visible payloads.
- Indexed topology accumulation removes the shared-route quadratic behavior;
  the 2,000-route case improves by about 8.1x.
- Compact Mica-owned binary byte formatting removes repeated runtime catalog and
  Foundation formatter work while retaining `B/KB/MB/GB` technical units and
  localized `/s` versus `/秒` suffixes.

## Dependency Decision

No package was added. Existing gRPC/protobuf packages remain required for the
native sing-box StartedService boundary. Observation, actors, Swift Charts,
Canvas, bounded rings, indexed arrays/dictionaries, and local caches satisfy the
measured workloads with less build, binary, license, and cancellation risk than
the researched package candidates.

An isolated existing-dependency experiment also compared `swift-protobuf`'s
default traits with `traits: []`. Clean Release build time was 129.19s versus
129.06s, and the executable changed from 34,501,224 to 34,392,216 bytes. The
0.1% time difference and 0.32% size reduction were not material, so the manifest
keeps the upstream default traits.

## Limitations

- Results are offline synthetic evidence, not a real-controller Instruments trace.
- Wall-clock values vary by host load; operation ownership, scaling slope, and
  focused tests are the durable acceptance evidence.
- UI smoke and real-controller profiling were intentionally not run in this task.
