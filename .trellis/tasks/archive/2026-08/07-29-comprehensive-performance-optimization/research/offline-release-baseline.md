# Offline Release Baseline

Captured on 2026-07-29 with:

```bash
zsh scripts/run-performance-benchmarks.sh before
```

The command used deterministic synthetic fixtures, disabled automatic package
resolution, kept HOME/build/module caches under `tmp/codex/performance/`, and did
not launch Mica or contact a controller.

## Environment

- macOS: 27.0 (26A5388g)
- Swift: Apple Swift 6.3.3
- configuration: Release
- cold Release build: 144.19 seconds with the existing gRPC/NIO dependency graph
- report: `tmp/codex/performance/before/mica-performance.json`

## Baseline Results

| Case | Fixture | Median | p95 | Scaling observation |
|---|---:|---:|---:|---|
| Connection row projection | 1,000 | 8.94 ms | 9.17 ms | baseline |
| Connection row projection | 5,000 | 44.73 ms | 45.97 ms | approximately linear |
| Connection row projection | 10,000 | 90.07 ms | 91.87 ms | approximately linear, but too expensive for broad repeat publication |
| Log ring materialization, 32 append/read cycles | 2,000 | 14.76 ms | 14.79 ms | repeated full-ring materialization remains measurable |
| Log full-ring incremental projection, 32 updates | 2,000 | 67.26 ms | 68.04 ms | current delta discovery still receives full arrays |
| Shared-route topology | 1,000 | 20.71 ms | 20.74 ms | baseline |
| Shared-route topology | 2,000 | 73.93 ms | 74.66 ms | 3.57x time for 2x input; confirms near-quadratic shared-membership copying |
| Unique-route topology | 1,000 | 6.94 ms | 6.98 ms | baseline |
| Unique-route topology | 2,000 | 14.18 ms | 14.36 ms | approximately linear |

## Interpretation

- The connection row projector scales close to linearly, but a 10,000-row full
  rebuild already consumes about 90 ms. The optimization target is therefore
  structural/dynamic delta reuse and narrower invalidation, not merely a faster
  all-row mapper.
- The log cache formats only appended rows after warmup, but its caller still
  materializes and supplies the complete 2,000-entry ring for every revision. The
  target is an explicit append/drop publication contract.
- Shared topology membership is the strongest confirmed algorithmic hotspot.
  Unique paths scale linearly while shared paths do not, matching the audited
  dictionary value copy-append-set implementation.

## Limitations

- These are offline wall-clock results, not a real-controller Instruments trace.
- Absolute timings are supporting evidence. The durable acceptance contract will
  use operation counters and scaling ratios after instrumentation is integrated.
- SwiftUI scroll and interaction acceptance remains deferred until the user
  separately authorizes real-session capture.
