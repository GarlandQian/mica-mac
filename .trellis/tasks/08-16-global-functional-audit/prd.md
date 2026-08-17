# Mica 全局功能审计与缺陷修复

## Goal

Perform an evidence-based baseline audit of the current Mica application before
the Overview replacement begins. Cover every production subsystem and active
Workbench destination, identify reproducible functional, security,
data-integrity, concurrency, and performance defects, and remediate every
verified Critical, High, and Medium finding without changing Mica's controller
or live-session product contracts.

This task deliberately avoids polishing or repairing the superseded Overview
presentation that the parent task will replace. It audits only the shared
controller/session/data boundaries that the replacement must preserve.

## Position In The Parent Delivery

This is phase 1 of the parent task
`08-16-dashboard-visual-hover-details`:

1. complete this baseline audit and required remediations;
2. implement the parent Overview refactor;
3. complete `08-16-post-refactor-integration-audit` against the final combined
   code.

The parent implementation must not begin until blocking baseline findings are
resolved or explicitly shown not to affect the refactor boundary.

## Confirmed Constraints

- Current source, tests, `Package.swift`, and active Trellis contracts are the
  evidence authority.
- Mica remains a Swift 6.2 SwiftPM macOS 27 application.
- Mica controls already-running remote controllers. Automated checks must not
  contact a real controller, change networking, invoke remote actions, or add
  production mock controller data.
- Mihomo, Nikki, OpenClash, CMFA/Stash, sing-box, and Surge remain supported.
- Controller-reported ordering and optionality, capability gates, selected
  controller identity, and session generation checks must be preserved.
- Credentials, authorization values, subscription URLs, Keychain contents, and
  raw response/stream bodies must not appear in exports, logs, fixtures, or the
  audit report.
- The old Overview layout/editor/persistence UI is scheduled for deletion by
  the parent task. Do not spend remediation effort on that presentation unless
  a defect crosses a preserved shared boundary.
- Existing unrelated untracked AI-skill links are not part of this task.

## Severity And Remediation Policy

- **Critical**: verified credential disclosure, destructive or unauthorized
  remote behavior, unrecoverable persisted-data corruption, or a defect that
  makes a core workflow broadly unusable. Fix before any parent implementation.
- **High**: verified crash, wrong-controller action/data publication, broken
  authentication/capability enforcement, major data loss, or repeatable core
  workflow failure. Fix before parent implementation unless isolated from the
  refactor and tracked as an explicit blocking exception.
- **Medium**: verified incorrect behavior, stale/cross-session data, cancellation
  or race defect, accessibility blocker, or material performance regression
  with bounded impact. Fix during this task.
- **Low**: style, naming, duplication, speculative hardening, or maintainability
  concerns without demonstrated user-visible or contract impact. Record only;
  do not expand implementation automatically.

Severity is based on demonstrated impact and reach, not suspicious syntax. A
static risk marker is not a finding until its execution path and impact are
verified.

## Requirements

### R1. Complete Audit Matrix

Create an auditable matrix covering:

- package graph, build settings, resources, Info.plist behavior, localization,
  and source-verifier assumptions;
- `MicaCore` profile identity, URL/config validation, authentication references,
  persistence transactions, import/export, and secret handling;
- controller discovery/probing and all supported HTTP, WebSocket, and gRPC
  adapters, DTO conversion, errors, retries, cancellation, capability mapping,
  ordering, and optional values;
- `AppModel` selected-controller ownership, profile mutations, generation and
  revision guards, refresh lanes, publication, task cancellation, backoff, and
  teardown;
- Workbench shell behavior: navigation, commands, controller selector, status
  presentation, window demand, and close safety;
- Proxies, Connections, Logs, Rules, Sources, Controllers, Actions,
  Diagnostics, management/Tailscale surfaces, and Settings;
- localization, accessibility, privacy/export redaction, keyboard behavior,
  empty/error/stale/unsupported states, and user-action capability gates;
- cache keys, view invalidation, high-volume projections, task lifetime, and
  known performance-sensitive paths;
- existing unit/integration/source-contract coverage and any contract-to-code
  gap that can hide a real defect.

For the current Overview, audit only the live-session demand, shared model
publication, controller switching, navigation, and other boundaries retained by
the parent replacement.

### R2. Evidence-Led Findings

Every finding must record:

- stable finding ID and severity;
- affected subsystem, controller families, and user-visible surfaces;
- observable impact;
- deterministic reproduction, failing test, or complete source execution path;
- file and line anchors;
- violated product/spec contract;
- remediation decision and focused validation result.

Unverified suspicions stay in a separate investigation-notes section and are
not counted as defects.

### R3. Required Remediation

- Fix all verified Critical, High, and Medium findings in this task.
- Keep each fix scoped to its demonstrated root cause and preserve controller,
  session, persistence, ordering, and optionality contracts.
- Add or change a regression test only when the defect is reproducible and
  likely to recur, or when a core/cross-module contract changes.
- Reuse in-process transports and existing fixtures. Do not add production mock
  business data or introduce a new test framework.
- Record Low findings without opportunistic cleanup.

### R4. Verification And Safety

- Establish the pre-change automated baseline before adjudicating failures.
- After a fix, run the smallest focused check that proves the defect is
  resolved, then run consolidated project checks once all related fixes are
  complete.
- Treat a passing test suite as one evidence source, not proof that an unaudited
  path is correct.
- Do not expose secrets in command output or task artifacts.
- Runtime smoke against a real controller is excluded unless the user later
  authorizes it explicitly.

### R5. Parent Handoff

- Produce a baseline audit report with one explicit pass/finding result for
  every matrix row.
- Identify preserved Overview/shared boundaries the parent must regression-test.
- List resolved findings and any Low observations carried forward.
- Do not mark this task complete while an unresolved Critical, High, or Medium
  finding remains.

## Acceptance Criteria

- [ ] AC-01: The audit matrix includes every production subsystem, supported
      controller family, and active Workbench/Settings destination.
- [ ] AC-02: Every matrix row contains inspected files/flows, evidence used,
      and an explicit pass, finding, or not-applicable result.
- [ ] AC-03: Each defect includes severity, impact, reproduction or full source
      proof, file/line anchors, affected surfaces/controllers, and validation.
- [ ] AC-04: Static-risk markers are adjudicated individually and are not
      reported as bugs solely because they use an escape hatch.
- [ ] AC-05: Every verified Critical, High, and Medium finding is fixed and
      passes a focused regression check; Low findings are report-only.
- [ ] AC-06: Fixes preserve selected-controller identity, generation checks,
      capability gating, controller ordering, optionality, and secret handling.
- [ ] AC-07: No automated check contacts a controller, invokes remote actions,
      changes networking, or introduces production mock controller data.
- [ ] AC-08: The build, complete existing test suite, source verifier,
      localization checks, and `git diff --check` pass after remediation.
- [ ] AC-09: The audit report contains no credential, token, authorization
      value, subscription URL, Keychain value, or raw controller body.
- [ ] AC-10: The parent handoff names all shared boundaries that must survive
      the Overview refactor and contains no unresolved blocking finding.

## Out Of Scope

- Redesigning, polishing, or restoring the old Overview layout, customization,
  detail inset, or persistence UI that the parent task will delete.
- Changing controller protocols, supported controller families, authentication
  semantics, or automatic failover behavior.
- Real-controller runtime smoke, OpenWrt/LuCI/SSH/`ubus` work, or system-network
  modification.
- Automatically fixing Low style or maintainability findings.
- Adding third-party dependencies or broad architecture rewrites without a
  verified finding that requires them.

## Deliverables

- `audit-report.md` created during execution with the completed matrix,
  findings ledger, remediation evidence, and parent handoff.
- Focused fixes and regression tests for verified Critical/High/Medium defects.
- Any durable contract update required by a verified correction.

## Open Questions

None. Scope, evidence standard, remediation threshold, and execution order are
confirmed.
