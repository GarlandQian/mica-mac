# Implementation Plan: Post-Refactor Integration Audit

## Preconditions And Ordering

- Run only after `08-16-global-functional-audit` is complete and the parent
  Overview implementation is code-complete.
- Load `trellis-before-dev`, `mica-controller-development`, and all relevant
  frontend/backend/UI skills and contracts before changing code.
- Preserve unrelated working-tree changes and untracked local skill links.
- Do not contact controllers or modify networking during automated checks.

## Step 1. Verify Entry Conditions

- Read the baseline `audit-report.md` and confirm no unresolved
  Critical/High/Medium finding.
- Read the final parent PRD/design/implementation evidence.
- Inventory final changed files and map each to shared consumers.
- Create `integration-audit-report.md` with the structures defined in
  `design.md`.

Gate: do not continue against a partial refactor or incomplete legacy deletion.

## Step 2. Establish The Final Automated Baseline

Run the final code once before audit remediation:

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 .agents/skills/apple-hig-expert/scripts/hig_checker.py batch scripts/color-contrast-audit.json
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
```

Record failures as evidence and adjudicate their root causes. Do not run real
controller smoke.

## Step 3. Audit Preference, Window, And Session Ownership

- Verify one app-owned global preference store and one window-owned runtime per
  window.
- Exercise multi-window preference propagation and independent transient state.
- Exercise controller switch, reconnect, stale completion, teardown, and window
  close paths with fixtures/in-process models.
- Verify router-editor close safety remains while Overview layout dirty state is
  absent.

## Step 4. Audit Final Overview Behavior

- Verify fixed telemetry/topology/optional order and fresh default state.
- Verify immediate customizer persistence, reset, invalid-data fallback, and no
  compatibility migration.
- Verify telemetry samples, chart interaction, pause, finite motion, and cache
  isolation.
- Verify complete topology, policy inspection, HUD placement/content/pinning,
  keyboard/accessibility actions, clear behavior, and cross-tab navigation.
- Verify hover/pin/catalog changes cause no network request or topology geometry
  rebuild.

## Step 5. Audit Every Other Destination Against Baseline

- Re-run shell/navigation/controller selector/command scenarios.
- Review Proxies, Connections, Logs, Rules, Sources, Controllers, Actions,
  Diagnostics, management/Tailscale, and Settings.
- Compare availability, actions, errors, controller switching, selection,
  localization, accessibility, exports, and close behavior to baseline evidence.
- Investigate every unexplained behavior difference.

## Step 6. Audit Controller And Data Contracts

- Re-check all supported family adapters/probes/transports and capabilities
  touched directly or indirectly by the refactor.
- Verify ordering/optionality, secret exclusion, generation validation, and
  publication boundaries across final projections.
- Confirm HUD and optional modules consume published data only.

## Step 7. Prove Performance And Motion Boundaries

- Run focused topology/chart/cache/operation-count tests.
- Verify catalog-only, hover/pin, sample-only, width-only, and preference-only
  invalidation boundaries.
- Verify hidden optional modules are not constructed.
- Verify idle, paused, inactive, and Reduce Motion states have no recurring
  animation work.
- Review dense/narrow/wide fixture behavior and stable view identity.

## Step 8. Prove Legacy Removal And Contract Consistency

- Search production, tests, localization, docs, and specs for all superseded
  Overview symbols and concepts.
- Confirm only explicit negative verifier assertions may name them.
- Confirm current v1 terminology, preference ownership, HUD behavior, and
  motion rules agree across code, source verifier, localization, docs, and
  Trellis contracts.

## Step 9. Triage And Fix Final Findings

For every candidate:

1. establish reproducible impact or complete source proof;
2. record severity, scope, anchors, and violated contract;
3. fix verified Critical, High, and Medium regressions;
4. add/update a focused regression test when required;
5. run the smallest relevant check and record evidence;
6. keep Low observations report-only.

Do not add new features or reintroduce compatibility to avoid fixing a final
architecture defect.

## Step 10. Consolidated Final Gate

Run after all required fixes:

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 .agents/skills/apple-hig-expert/scripts/hig_checker.py batch scripts/color-contrast-audit.json
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
```

Then:

- complete all final matrix rows;
- map every parent and child acceptance criterion to evidence;
- verify reports/artifacts contain no sensitive values or raw bodies;
- label runtime visual smoke as pending user-run unless explicitly authorized;
- confirm no Critical/High/Medium finding remains.

## Completion Gate

This child and the parent delivery are complete only when:

- all PRD acceptance criteria have recorded evidence;
- all required findings are fixed and validated;
- consolidated checks pass;
- the old Overview architecture is absent;
- all controller/session and non-Overview behaviors remain correct;
- the final report contains no unresolved blocker.
