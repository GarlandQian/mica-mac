# 全局重构后集成复审

## Goal

Audit the final combined Mica code after the baseline global audit and the
Overview replacement are complete. Prove that the new fixed cyber-neon Overview,
global preferences, window runtime, policy-node HUD, and removed compatibility
architecture integrate correctly with every controller family, shared
live-session flow, Workbench destination, Settings, accessibility path, and
performance contract.

Fix every verified Critical, High, and Medium regression found in this final
pass. Low style or maintainability observations remain report-only.

## Preconditions And Position

This is phase 3 and the final gate of parent task
`08-16-dashboard-visual-hover-details`.

It starts only after:

1. `08-16-global-functional-audit` is complete and has no unresolved
   Critical/High/Medium finding;
2. the parent Overview implementation is code-complete, including legacy
   removal, localization, tests, source verifier, and contract updates.

The parent task cannot be marked complete until this child task passes.

## Confirmed Constraints

- Audit the final working tree, not a design approximation or the pre-refactor
  snapshot.
- Mica remains Swift 6.2, macOS 27, and supports Mihomo, Nikki, OpenClash,
  CMFA/Stash, sing-box, and Surge.
- Automated checks must not contact real controllers, invoke remote actions,
  alter networking, or add production mock business data.
- Preserve selected-controller identity, session generation validation,
  capability gates, reported ordering, optionality, and secret exclusion.
- The replacement is still product v1. The old Overview architecture must be
  absent, not dormant behind aliases or compatibility shims.
- Runtime visual smoke remains user-run and requires explicit permission.

## Requirements

### R1. Final Full-Application Matrix

Re-run a complete production audit matrix across:

- package/build/resources/Info.plist/localization/source contracts;
- profiles, secrets, persistence, import/export, and AppModel transactions;
- probes/adapters/transports for every controller family;
- selected live controller, window demand, generation/revision validation,
  refresh lanes, cancellation, reconnect, and teardown;
- Workbench shell, navigation, commands, controller selector, and close guard;
- Overview, Proxies, Connections, Logs, Rules, Sources, Controllers, Actions,
  Diagnostics, management/Tailscale, and Settings;
- accessibility, keyboard/focus, localization, privacy, performance caches,
  dense-data behavior, and source-verifier contracts.

Use the baseline audit report for comparison, but independently verify the final
code and record new evidence.

### R2. Refactor Integration Seams

Explicitly verify:

- `MicaApp` owns one shared global Overview preference store;
- each window owns one stable live-session demand/window runtime;
- multiple windows and controller switches share preferences without sharing
  transient chart/topology interaction state;
- controller switches and stale async completions cannot leak data or pinned HUD
  state across sessions;
- the fixed Overview order is telemetry, full topology, then enabled optional
  modules, with no old grid/preset/size/reorder behavior;
- old stored layout data resets to the redesigned v1 default without migration;
- policy-group HUD lookup uses already-published catalog data and performs no
  controller request;
- hover, pin, Escape, blank clear, keyboard, VoiceOver, Proxies navigation, and
  Connections navigation preserve graph geometry and session correctness;
- pause, inactive window, and Reduce Motion eliminate recurring animation work;
- shared Workbench visual primitive changes do not regress other destinations;
- dirty-close behavior still protects router editing while removed Overview
  layout drafts no longer participate.

### R3. Legacy Removal Proof

- Confirm no superseded Overview preset, module-size, row-packer, generic layout,
  migration, per-controller override, draft, conflict, commit, or old detail
  inset implementation remains in production or test code.
- Confirm localization, documentation, Trellis contracts, and the source
  verifier describe only the final v1 architecture.
- A negative source-verifier assertion may name removed symbols solely to reject
  their reintroduction.

### R4. Regression And Performance Evidence

- Re-run all existing tests plus focused tests added by both preceding phases.
- Verify dense topology operation counts, cache invalidation, hit testing, chart
  selection, optional-module laziness, and stable view identity do not regress.
- Verify bounded effects settle and do no recurring work while idle, paused,
  inactive, or under Reduce Motion.
- Review empty, stale, partial, unsupported, narrow, wide, light, dark,
  high-contrast, larger-font, and dense-data states using source/fixture evidence.
- Treat visual runtime smoke as an explicitly labeled manual/user-run item, not
  a hidden automated dependency.

### R5. Findings And Remediation

- Use the same evidence schema and severity definitions as the baseline audit.
- Fix every verified Critical, High, and Medium regression at its root-cause
  boundary and run a focused regression check.
- Record Low observations separately without broad cleanup.
- Update the final audit report and any durable contract affected by a verified
  correction.

## Acceptance Criteria

- [x] AC-01: Both preconditions are recorded complete before this audit starts.
- [x] AC-02: Every final matrix row has inspected files/flows, evidence, and an
      explicit pass, finding, or not-applicable result.
- [x] AC-03: All six controller families pass adapter/session/capability/order/
      optionality review against the final combined code.
- [x] AC-04: Overview preferences are global across windows/controllers while
      transient runtime and interaction state remain window/session scoped.
- [x] AC-05: Controller switching, reconnect, close, and stale async completion
      paths do not publish or display data from the wrong generation.
- [x] AC-06: Telemetry, complete topology, optional modules, policy HUD, and
      cross-tab navigation satisfy every parent-task acceptance criterion.
- [x] AC-07: No hover, pin, chart interaction, preference edit, or optional
      module action initiates an unintended controller request or geometry
      rebuild.
- [x] AC-08: Idle, paused, inactive, and Reduce Motion states have no perpetual
      animation or avoidable recurring invalidation.
- [x] AC-09: The superseded Overview architecture and compatibility layers are
      absent from source, tests, localization, docs, and active contracts.
- [x] AC-10: Shared Workbench styling/runtime changes do not regress any other
      destination, Settings, accessibility, localization, or close safety.
- [x] AC-11: Every verified Critical, High, and Medium final finding is fixed and
      validated; Low observations are report-only.
- [x] AC-12: Source verifier, localization/HIG checks, Swift build, full tests,
      focused performance tests, and `git diff --check` pass.
- [x] AC-13: No automated check contacts a real controller, changes networking,
      invokes remote actions, or records sensitive values/raw bodies.
- [x] AC-14: The final report maps all parent and child acceptance criteria to
      evidence and contains no unresolved completion blocker.

## Out Of Scope

- New features or visual directions beyond the approved parent requirements.
- Changing controller protocol/authentication/capability semantics or adding
  automatic failover.
- Real-controller smoke without explicit user authorization.
- Automatically fixing Low findings or introducing dependencies for cleanup.
- Reintroducing any compatibility layer for the deleted Overview architecture.

## Deliverables

- `integration-audit-report.md` with final matrix, regression findings,
  remediation evidence, and parent acceptance-criterion mapping.
- Focused fixes/tests for verified Critical/High/Medium regressions.
- Final confirmation that the three-phase parent delivery is complete.

## Open Questions

None. Entry conditions, coverage, evidence standard, remediation threshold, and
completion gate are confirmed.
