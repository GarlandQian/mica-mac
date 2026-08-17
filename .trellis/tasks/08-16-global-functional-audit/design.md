# Technical Design: Baseline Global Functional Audit

## 1. Audit Strategy

The audit is a traceable engineering review, not a broad cleanup pass. It uses
four complementary evidence sources:

1. automated baseline results;
2. contract-to-source inspection;
3. cross-layer data/control-flow tracing;
4. focused regression evidence for verified defects.

No single source is sufficient by itself. Tests can miss a path, static search
can produce false positives, and source inspection can overlook runtime
interactions. A finding becomes actionable only when impact and reach are
demonstrated.

## 2. Audit Deliverable Model

Create `audit-report.md` during execution with two linked tables.

### Coverage Matrix

Each row contains:

- area ID and subsystem/destination;
- controller families or platform surface involved;
- relevant product/spec contracts;
- inspected files and tests;
- automated/manual evidence;
- result: Pass, Finding IDs, or Not Applicable;
- notes and remaining validation.

No row may be left blank. Not Applicable requires a reason.

### Findings Ledger

Each finding uses this shape:

```text
ID:
Severity:
Status: verified | fixed | validated
Affected area/controllers/surfaces:
User-visible or contract impact:
Reproduction or source execution path:
File/line anchors:
Violated contract:
Root cause:
Fix boundary:
Focused validation:
Consolidated validation:
```

Investigation notes that do not meet the evidence threshold are recorded in a
separate non-defect section and never inflate defect counts.

## 3. Inventory And Baseline Pass

Build the matrix from production sources rather than from navigation labels
alone:

- enumerate Swift targets, resources, scripts, Info.plist inputs, localization,
  and test targets;
- enumerate controller families, probe paths, transports, DTOs, and capability
  declarations;
- enumerate AppModel state owners, refresh lanes, tasks, callbacks, and
  persistence boundaries;
- enumerate all Workbench destinations, Settings panes, commands, exports, and
  window-scoped coordinators;
- map existing tests and source-verifier assertions to those rows.

Run the documented baseline commands before source-driven remediation. Existing
failures are captured exactly and classified only after their root cause is
understood.

## 4. Contract-To-Source Pass

Read the active controller/session, Workbench, persistence, security, and UI
contracts next to their implementations. Trace at least these invariants:

- one selected live controller and no automatic failover;
- controller ID and session generation validation after async work;
- capabilities gate every action and unsupported states remain explicit;
- reported ordering and optional fields survive decode, projection, and UI;
- profile mutations are transactional and leave selected identity consistent;
- secrets remain references at persistence/UI/export boundaries;
- stream/task teardown cannot publish into a replacement session;
- empty, error, stale, reconnecting, and unsupported states remain truthful.

The old Overview presentation is not audited. Only the shared demand/publication
and navigation boundaries that its replacement will consume are traced.

## 5. Controller And Transport Pass

For each supported family—Mihomo, Nikki, OpenClash, CMFA/Stash, sing-box, and
Surge—review:

- URL construction, normalization, authentication application, and redaction;
- probe sequencing and family detection;
- HTTP status and decode errors;
- WebSocket/gRPC startup, cancellation, reconnect/backoff, and terminal state;
- DTO optionality, stable order, unknown enum/value handling, and capabilities;
- action request gating, response publication, and generation validation.

Use existing fixtures and in-process transports only. Tests must never resolve
or contact configured controller addresses.

## 6. AppModel And Persistence Pass

Trace lifecycle transitions for:

- initial load, controller selection, profile add/edit/delete/import;
- connect, disconnect, retry, refresh, controller switch, and window demand;
- session generation/revision changes and stale async completion rejection;
- concurrent refresh lanes and publication ordering;
- UserDefaults/profile storage and secret reference reconciliation;
- export construction and redaction.

Review explicit concurrency escape hatches, fatal assumptions, and detached or
long-lived tasks individually. Their presence is only a review lead; a finding
requires proof that isolation, lifetime, or failure behavior violates a
contract.

## 7. Workbench And Settings Pass

For the shell and each destination, inspect:

- availability/capability gating and navigation selection;
- loading, empty, stale, unsupported, error, and reconnect states;
- refresh and mutation actions, duplicate submission, cancellation, and result
  feedback;
- stable identity, selection persistence, sorting/filtering, and controller
  switch behavior;
- keyboard, focus, accessibility values/actions, localization, selectable
  business values, and secret-safe copy/export;
- high-volume view/projection/cache paths and unnecessary broad invalidation.

The destination list includes Proxies, Connections, Logs, Rules, Sources,
Controllers, Actions, Diagnostics, management/Tailscale, Settings, the shell,
and preserved Overview integration boundaries.

## 8. Security, Privacy, And Data Integrity Pass

Inspect all paths where sensitive or controller-provided values cross:

- persistence;
- logging/error presentation;
- clipboard/export/share;
- diagnostics bundles;
- URLs and request headers;
- localization or debug descriptions.

Verify redaction behavior using synthetic sentinel values in tests or source
review. Never print or inspect real stored secrets. A known architectural choice
is not changed merely because a stronger design exists; it becomes a defect
only when it violates the current contract or leaks/corrupts protected data.

## 9. Performance Pass

Use existing operation-count, cache, projection, and dense-data tests where
available. Review:

- cache-key completeness and invalidation breadth;
- repeated sorting/index construction in render paths;
- unbounded buffers or retained stream state;
- main-actor blocking work;
- row/view identity churn;
- task storms, retry loops, and duplicate refresh work.

Performance findings need repeatable evidence: an existing threshold failure,
operation-count proof, bounded benchmark/fixture, or a complete hot-path cost
argument. A micro-optimization opportunity without material impact is Low.

## 10. Remediation Design

Remediate by finding rather than by file:

- isolate the demonstrated root cause;
- keep batches small enough to review independently when practical;
- add focused regression coverage for stable, likely-to-recur failures;
- preserve unrelated working-tree changes;
- rerun only the affected check after each correction;
- run consolidated validation after all related corrections.

If a fix would intentionally change a controller or product contract, stop and
return it to planning rather than silently broadening this audit.

## 11. Handoff To The Parent Refactor

The report ends with a parent handoff containing:

- shared session/controller/navigation boundaries proven by this audit;
- regression tests the Overview replacement must keep passing;
- fixed findings whose files overlap the parent task;
- unresolved Low observations that require no parent action;
- confirmation that no Critical/High/Medium finding remains.

This handoff is an input to the parent implementation and the final integration
audit, not a substitute for either.
