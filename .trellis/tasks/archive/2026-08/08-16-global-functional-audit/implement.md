# Implementation Plan: Baseline Global Functional Audit

## Preconditions And Ordering

- This child task runs before product implementation in
  `08-16-dashboard-visual-hover-details`.
- Before code changes, load `trellis-before-dev`,
  `mica-controller-development`, and the layer-specific contracts for the files
  being reviewed or changed.
- Preserve unrelated untracked `.agents/skills/` links and all unrelated user
  changes.
- Automated checks must remain local and fixture/in-process only.

## Step 1. Build The Coverage Matrix

- Enumerate production/test Swift files, package targets, resources, scripts,
  localization, and Info.plist inputs.
- Map every supported controller family and transport implementation.
- Map AppModel/live-session/persistence owners and public operations.
- Map the Workbench shell, every destination, Settings, commands, exports, and
  window coordinators.
- Map active Trellis contracts and existing tests/source assertions to each row.
- Create `audit-report.md` using the coverage and finding formats from
  `design.md`.

Gate: every required area has a row before findings are triaged.

## Step 2. Establish The Automated Baseline

Run once before remediation:

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
```

- Record exact failures without immediately assuming they are product defects.
- If UI-affecting findings are later fixed, add the existing HIG/color checks
  relevant to those files to the final gate.
- Do not run runtime smoke or any request against a configured controller.

## Step 3. Audit Package, Resources, Localization, And Contracts

- Inspect target/resource membership, generated/source exclusions, Info.plist
  values, localization key/signature parity, and source-verifier coverage.
- Verify documentation/spec assertions against current code where they define a
  product contract.
- Record pass/finding evidence for each matrix row.

## Step 4. Audit Profiles, Secrets, And Persistence

- Trace profile validation, ID stability, add/edit/delete/import transactions,
  selected-controller reconciliation, and rollback behavior.
- Trace secret references and sensitive values through storage, logging,
  clipboard/export, diagnostics, and error presentation.
- Verify URL/auth normalization and invalid-input behavior without printing
  actual credentials.

## Step 5. Audit Controller Families And Transports

- Review probes/adapters for Mihomo, Nikki, OpenClash, CMFA/Stash, sing-box, and
  Surge.
- Trace HTTP/WebSocket/gRPC request creation, decode, cancellation,
  reconnect/backoff, errors, capabilities, ordering, and optional fields.
- Use focused fixture/in-process tests to prove suspected defects.
- Do not call real controller endpoints.

## Step 6. Audit AppModel And Live-Session State

- Trace selected controller, generation/revision guards, refresh lanes,
  publication, retry, cancellation, disconnect, and teardown.
- Exercise controller-switch and stale-completion paths with existing fakes.
- Adjudicate concurrency escape hatches and fatal assumptions using complete
  execution paths rather than syntax alone.

## Step 7. Audit Workbench And Settings Surfaces

- Review the shell, navigation, commands, selector/status, window demand, and
  close guard.
- Review Proxies, Connections, Logs, Rules, Sources, Controllers, Actions,
  Diagnostics, management/Tailscale, and Settings.
- Cover empty/error/stale/unsupported states, capability-gated actions,
  selection identity, keyboard/accessibility/localization, export safety, and
  controller switching.
- For Overview, review only shared model/session/navigation boundaries that the
  parent replacement retains.

## Step 8. Audit Performance-Sensitive Paths

- Review cache keys, invalidation, indexes/sorts, high-volume projections,
  buffers, task lifetime, and main-actor work.
- Run existing dense-data/operation-count tests and focused bounded fixtures.
- Record optimization ideas without demonstrated material impact as Low only.

## Step 9. Triage And Remediate Verified Findings

For each candidate:

1. establish reproduction or complete source proof;
2. assign severity from the PRD;
3. record affected surfaces/controllers and file/line anchors;
4. fix verified Critical, High, and Medium findings at the root-cause boundary;
5. add or update focused regression coverage where required by project policy;
6. run the smallest relevant check and record its result;
7. leave Low findings report-only.

Prefer independent, reviewable fix batches. Do not refactor unrelated code or
repair presentation code that the parent task will delete.

## Step 10. Consolidated Validation And Handoff

After all required fixes:

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
```

Additionally:

- run focused HIG/localization checks if UI code changed;
- confirm no audit artifact contains sensitive values or raw bodies;
- confirm no automated test contacted a controller or changed networking;
- complete every coverage-matrix row;
- list every resolved Critical/High/Medium finding with focused evidence;
- write the parent handoff and preserved-boundary checklist.

## Completion Gate

This child task is complete only when:

- all PRD acceptance criteria have evidence in `audit-report.md`;
- every verified Critical, High, and Medium finding is fixed and validated;
- Low findings remain clearly separated from required remediation;
- consolidated checks pass;
- the parent handoff contains no unresolved blocker.
