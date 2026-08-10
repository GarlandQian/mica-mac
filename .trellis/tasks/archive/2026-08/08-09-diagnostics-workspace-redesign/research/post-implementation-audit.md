# Post-Implementation Correctness And Performance Audit

Date: 2026-08-10

## Scope And Constraints

The adopted scope fixes confirmed Diagnostics/Actions correctness issues first, then performs a measured full-Workbench performance pass. Automated work must not launch Mica, contact a controller, execute remote mutations, add production mock data, change live publication cadence, add a package, or weaken controller ID/generation checks.

## Confirmed Functional Findings

### Unsafe evidence fallback

`WorkbenchDiagnosticsProjection.displayableText` correctly rejects machine assignments and API paths, but the generic helper at `WorkbenchDiagnosticsPresentation.swift:725` currently stores `displayableText(value) ?? value`. A rejected value therefore returns to visible issue evidence. Existing tests assert the helper directly and do not assert the projected issue evidence.

Planned contract: every free-form value uses a localized unavailable fallback; typed endpoint status labels may be explicit safe fallbacks.

### Checking conflicts with adapter failure

`snapshot` derives `isChecking`, suppresses only controller-access, then still calls `adapterIssue`. `.smartProbe` is classified as a critical adapter issue. Auto Detect can therefore show checking and critical adapter failure simultaneously.

Planned contract: first-baseline checking is a failure-projection gate, not merely an overall-state label.

### Static capabilities publish Available Now too early

Before a unified snapshot exists, `selectedUnifiedCapabilities` may derive capabilities from detected controller kind. `availableAreas` gates only controller-access with no last success, so explicit profiles can advertise product domains during the first connection attempt.

Planned contract: no Available Now before a committed baseline.

### Retained controller failures do not causally deduplicate

`suppressDomainIssues` currently requires controller-access and `lastSuccessAt == nil`. After a previous success, a controller-wide failure may be shown together with endpoint/domain failures caused by the same outage.

Planned contract: controller-access always suppresses its causal endpoint/domain duplicates; `lastSuccessAt` controls retained freshness only.

### Actions state is internally inconsistent

`WorkbenchActionsProjection.snapshot` converts an empty ready/partial command state to unsupported for the final snapshot, but builds recovery from the original availability. Availability, recovery copy, related destinations and rendered canvas can disagree.

Planned contract: derive one effective availability and feed every downstream field from it.

### Severity is not explicit to assistive technology

The issue row combines children and hides the selection rail/chevron, but the severity symbol is not hidden and there is no localized severity label/value. VoiceOver output can depend on the SF Symbol's system name.

Planned contract: hide the decorative symbol and expose localized severity, title, impact count and selected state explicitly.

## Performance Evidence

Reports:

- `tmp/codex/performance/diagnostics-audit-before/mica-performance.json`
- `tmp/codex/performance/diagnostics-audit-before-repeat/mica-performance.json`

Both runs used deterministic offline fixtures and the Release configuration. Benchmark execution was about 3.27 seconds; first-time dependency compilation is not a product metric.

| Case | First median / p95 ms | Repeat median / p95 ms | Interpretation |
| --- | ---: | ---: | --- |
| connection rows, 10,000 | 125.41 / 158.61 | 123.98 / 125.65 | Median stable; first p95 is an outlier |
| connection rows, 5,000 | 60.52 / 61.15 | 62.17 / 63.73 | About 4.2% p95 spread |
| keyed connection metric, 10,000 / 1 changed | 2.90 / 3.33 | 2.30 / 2.79 | Already bounded to one candidate |
| log end-to-end, 2,000 + 32 deltas | 38.91 / 40.31 | 39.51 / 39.74 | Stable, but setup is inside timing |
| hidden log ingestion, 10,000 | 12.84 / 12.88 | 12.93 / 13.04 | Stable |
| runtime connection frame, 10,000 | 6.86 / 7.12 | 6.75 / 7.06 | Stable |
| unique topology, 2,000 | 11.54 / 13.57 | 12.39 / 13.29 | Stable p95 |

The existing log delta case initializes and fully formats 2,000 rows inside every measured operation before applying 32 deltas. It is an end-to-end case, not a steady-state delta measurement. A prepared-state benchmark is required before changing the log cache.

## Selected Optimization Candidate

`WorkbenchStableRowIdentityBuilder.make` receives an eager fallback array. Connections construct a large fallback array for every row even when the controller-reported ID is unique and the fallback is never hashed. The builder also touches occurrence bookkeeping for the common unique-ID case and does not reserve catalog-sized capacity.

The selected first slice is:

- lazy fallback evaluation;
- a collision-safe unique-ID fast path;
- capacity reservation;
- unchanged duplicate/missing/reserved collision behavior and order.

This utility is shared by Connections, Logs, Rules and Sources. It is lower risk than page-specific caching and directly targets allocations performed by the measured full projections.

## Deferred Or Rejected Paths

- Do not rewrite Logs around a new ring/deque until a setup-free steady-state benchmark proves a material cost. The bounded runtime buffer and missed-revision fallback remain authoritative.
- Do not change Proxies scheduling. Its latest-update retention, idle commit and scroll-time hover suppression already have regression coverage.
- Do not add a new AppModel actions state solely because Actions reads 17 fixed runtime rows and broad operation busy state. These values are bounded and not driven by traffic/log frames; first prove an invalidation problem.
- Do not optimize a single p95 outlier. Use two before and two after reports, stable checksums/work units, median plus p95, and a 10% repeated improvement threshold for the selected connection case.
- Do not run SwiftUI Instruments or real-controller smoke as part of automated validation. Those require separate authorization and cannot contact a controller automatically.

## Regression Map

- Final projected evidence rejects machine assignments/API paths.
- Auto Detect `.smartProbe` + `.connecting` has checking state, no issues and no available areas.
- Explicit detected controller + first connection has no available areas before success.
- Retained controller-wide failure has one causal issue and retained freshness.
- Empty command inventory yields internally consistent unsupported Actions state.
- Issue rows expose localized severity semantics.
- Unique IDs do not evaluate fallback; duplicate/missing/reserved collisions retain existing stable identities.
- Prepared log delta benchmark measures only valid sequential deltas and preserves checksums/work units.

## Implemented Audit Outcome

Correctness and accessibility fixes are retained:

- checking now gates all provisional Diagnostics failures and Available Now;
- controller-access causally suppresses endpoint/domain derivatives for both
  first-load and retained failures;
- rejected free-form evidence uses localized unavailable copy;
- Actions derives recovery and rendering from one effective availability and
  shows related workspaces only for unsupported/few-command compositions;
- issue rows announce localized severity/title/affected count and selected
  state without relying on their decorative SF Symbol.

Observation review found that Actions unconditionally consumed full diagnostic
runtime rows, whose evidence read `controllerSession`. Actions now receives
evidence-free rows only for Mihomo, Nikki, OpenClash, and CMFA; full Diagnostics
rows enrich evidence separately. Typed Diagnostics/Actions inputs remain free
of connection rows, log entries, traffic timelines, and catalog snapshots.

After reports:

- `tmp/codex/performance/diagnostics-audit-after/mica-performance.json`
- `tmp/codex/performance/diagnostics-audit-after-repeat/mica-performance.json`

| Case | First after median / p95 ms | Repeat after median / p95 ms | Decision |
| --- | ---: | ---: | --- |
| connection rows, 10,000 | 117.41 / 118.25 | 118.15 / 118.31 | 6.38% / 4.71% median gain; reject below 10% gate |
| log steady-state delta, 2,000 + 32 deltas | 27.13 / 28.74 | 27.26 / 27.50 | Keep benchmark; no cache rewrite justified |

All matching legacy cases retained identical checksums and work units. No
unrelated case regressed by more than 10% in both paired comparisons. The lazy
fallback/unique-ID/capacity optimization and its temporary focused test were
removed; the prepared-state benchmark remains.

Final automated verification: source contract, JS syntax checks, localization
JSON, `git diff --check`, Swift build, and 312 tests passed. HIG signal checks
passed text contrast on content surfaces; light amber on the page background is
used only as supplemental non-text geometry and exceeds the 3:1 graphical
threshold. Runtime smoke, app launch, controller contact, remote mutation, and
SwiftUI Instruments were not run.
