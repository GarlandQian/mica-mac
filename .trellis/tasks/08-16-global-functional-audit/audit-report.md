# Mica Baseline Global Functional Audit Report

Audit date: 2026-08-16

## 1. Scope And Safety

This report audits the current Mica source before the approved Overview
replacement. Automated evidence is local-only: package compilation, unit and
integration tests, fixtures, in-process gRPC, source contracts, localization
parsing, and static/source review. No configured controller was contacted, no
remote action was invoked, and no network setting was changed.

The superseded Overview presentation/layout editor is excluded except for the
shared session, window-demand, controller-switching, publication, navigation,
and close-safety boundaries that the replacement must preserve.

## 2. Repository Inventory

- Swift tools: 6.2
- Deployment target: macOS 27.0
- Products: `Mica` executable and `MicaCore` library
- Production Swift sources: 128 files / 65,407 lines
- Swift tests: 38 files / 17,301 lines
- Supported controller boundaries: Mihomo, Nikki, OpenClash, CMFA, Stash,
  sing-box StartedService gRPC, and Surge HTTP API
- Workbench destinations: Overview, Proxies, Connections, Logs, Rules, Sources,
  Controllers, Configuration, Actions, and Diagnostics

Unrelated pre-existing untracked local skill links under `.agents/skills/` are
outside this audit and remain untouched.

## 3. Automated Baseline

| Check | Result | Evidence |
|---|---|---|
| Source script syntax | Pass | `node --check scripts/verify-real-controller-source.mjs` exited 0 |
| Source contract | Pass | `Mica native workbench source contract passed` |
| Swift build | Pass | Debug build completed on 2026-08-16 |
| Swift tests | Pass | 316 tests in 27 suites, 0 failures after remediation |
| Info.plist syntax | Pass | `plutil -lint` reported OK |
| Localization JSON | Pass | `Localizable.xcstrings` parsed as JSON |
| Diff whitespace | Pass | `git diff --check` exited 0 at baseline |

The first sandboxed Swift build attempt could not write the user clang module
cache. Re-running the same command with approved cache access succeeded. This
was an execution-environment restriction, not a Mica defect.

## 4. Coverage Matrix

Every row below has a terminal result backed by source review and local-only
automation.

| ID | Area | Controllers / surfaces | Primary evidence | Result |
|---|---|---|---|---|
| A01 | Package, dependencies, resources, Info.plist | App bundle | `Package.swift`, Info.plist, build, source verifier | Pass |
| A02 | Localization and dynamic language resolution | All visible surfaces | XCStrings, resolver/tests, source verifier | Pass |
| A03 | Router profile model and URL validation | All controllers | `RouterProfile`, profile-store tests | Pass — F-002 fixed |
| A04 | Secret storage and redaction boundaries | All controllers/exports | secret stores/tests, diagnostics/export source | Pass |
| A05 | Controller discovery and probe routing | Auto Detect/all families | resolver source and probe tests | Pass — F-001 fixed |
| A06 | Mihomo/Nikki/OpenClash HTTP and WebSocket | Mihomo family | clients, DTO tests, adapter/session tests | Pass — F-001 fixed |
| A07 | CMFA/Stash variant behavior | CMFA/Stash | capability, fallback, projection tests | Pass — F-004 fixed |
| A08 | Surge HTTP API and polling | Surge | client/adapter/session tests | Pass — F-001/F-004 fixed |
| A09 | sing-box StartedService gRPC | sing-box/Tailscale | client, in-process RPC, stream tests | Pass — F-002 fixed |
| A10 | Unified capabilities, ordering, optionality | All families | controller contract and capability tests | Pass — F-004 fixed |
| A11 | Selected controller and generation ownership | AppModel/live session | transaction/publication tests | Pass — F-003 fixed |
| A12 | Refresh lanes, retry, cancellation, reconnect | All live sessions | coordinator/runtime tests | Pass — F-001 fixed |
| A13 | Profile mutations and persistence transactions | Controllers/editor | transaction and failing-store tests | Pass — F-003 fixed |
| A14 | High-frequency runtime publication and buffers | Traffic/logs/connections/memory | runtime/buffer/performance tests | Pass |
| A15 | Window demand, Workbench shell, navigation, close | All destinations/windows | navigation/session/close source and tests | Pass |
| A16 | Proxies | Policy groups/nodes | projection/workspace/mutation tests | Pass |
| A17 | Connections | Active/closed/detail/navigation | mutation/cache/topology tests | Pass |
| A18 | Logs | Mihomo/sing-box streams | buffer/projection/follow tests | Pass |
| A19 | Rules | Supported controllers | projection/mutation/navigation source/tests | Pass |
| A20 | Sources | Providers/rule sources | provider batch and projection tests | Pass |
| A21 | Controllers and Configuration | Management/forms/runtime writes | management/capability/transaction tests | Pass — F-004 fixed |
| A22 | Actions and Tailscale | Capability-gated commands/sing-box | action/readiness/dispatcher tests | Pass — F-004 fixed |
| A23 | Diagnostics | All families/session states | projection, redaction, endpoint-check tests | Pass |
| A24 | Settings and application preferences | Language/appearance/font/GLOBAL | preference/localization tests | Pass |
| A25 | Accessibility, keyboard, privacy, export | All active UI | source contract, HIG/source review | Pass |
| A26 | Performance, cache keys, invalidation | High-volume Workbench/runtime | performance suites and source review | Pass |
| A27 | Preserved Overview integration boundaries | Session/window/navigation only | overview/session/navigation tests | Pass |
| A28 | Tests, verifier, docs, active Trellis contracts | Whole repository | baseline gates and contract mapping | Pass |

## 5. Findings Ledger

All verified Critical/High/Medium findings are resolved.

### F-001 — Medium — Cancellation crossed fallback and optional-read boundaries

- Evidence: `ControllerHTTPProbeResolver`, `ControllerProbeResolver`,
  `MihomoClient`, `SurgeHttpAPIClient`, unified adapters, and optional smart
  metadata paths could reclassify cancellation or continue into more endpoints.
- Impact: controller switch, window close, sleep, or a cancelled test could
  start unrelated transports, delay teardown, or publish a false failure/empty
  optional snapshot.
- Fix: normalize direct transport cancellation to `CancellationError`, stop
  HTTP/Surge/sing-box fallback immediately, use throwing bounded task groups,
  and tolerate optional endpoint errors only after excluding cancellation.
- Regression evidence: cancellation tests in probe resolvers, Mihomo delay and
  smart-weight fallbacks, Surge snapshot, and unified adapter snapshot.

### F-002 — Medium — Invalid persisted endpoints could terminate the app

- Evidence: decoded `RouterProfile` values were not validated and the former
  URL property used `preconditionFailure` when malformed state reached a client.
- Impact: a corrupt or user-edited `routers.json` could crash during automatic
  live-session startup; sing-box could create transport from an invalid target.
- Fix: typed throwing endpoint validation during decode, save, and every
  HTTP/gRPC client boundary; failure classification is terminal `invalidURL`.
- Regression evidence: profile-store, Mihomo, Surge, sing-box, and failure
  category tests reject invalid targets before transport.

### F-003 — Medium — Reentrant profile writes could overwrite newer data

- Evidence: profile edit/delete/reorder and successful-connection metadata each
  persisted a whole array across actor suspension without shared serialization.
- Impact: a background `lastConnectedAt` write could restore an older profile
  snapshot after the user saved another controller, leaving memory and disk
  inconsistent or losing the edit.
- Fix: `RouterProfileMutationCoordinator` serializes load, save, delete, reorder,
  and metadata transactions; each reads main-actor state only when its turn runs.
- Regression evidence: a controlled interleaving test retains both the edited
  profile and connection timestamp and observes no overlapping store write.

### F-004 — Medium — Runtime commands trusted UI-only capability gating

- Evidence: maintenance/configuration entry points could create transport after
  session state changed, and memory/core commands relied on hidden rows to avoid
  unsupported Stash/CMFA variants.
- Impact: a stale click or direct dispatcher call during reconnect/controller
  switch could issue an unsupported remote request.
- Fix: AppModel now revalidates live-session state plus concrete capability/type
  before creating tasks or clients.
- Regression evidence: connecting, Stash, and CMFA cases leave all task and
  in-flight markers nil and do not construct transport.

## 6. Investigation Notes (Not Findings)

- `@unchecked Sendable` exists in the current Overview UserDefaults box,
  sing-box cancellation helper, and XCStrings matcher. Each requires ownership
  review; generated protobuf annotations are upstream generated code.
- `nonisolated(unsafe)` exists in bundle-localization state and the exact-window
  close guard. These require synchronization/lifecycle review.
- The former `RouterProfile` precondition path was reachable and became F-002.
- Iterative `while true` loops exist in refresh/projection algorithms and must
  be checked for bounded exit and cancellation.
- Some bounded arrays use bulk `removeFirst`. Their caps and hot-path cost must
  be checked against performance contracts; presence alone is not a defect.

## 7. Parent Handoff

Baseline audit is complete. No unresolved Critical, High, or Medium defect
remains in the reviewed pre-refactor product. The approved Overview replacement
may begin while preserving the verified live-session, capability, ordering,
privacy, accessibility, and performance boundaries above.
