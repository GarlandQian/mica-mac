# Technical Design: Post-Refactor Integration Audit

## 1. Purpose

This audit validates integration on the final codebase. It is not a repeat of
the baseline audit and not a visual-polish phase. Its core question is whether
the Overview replacement and shared cleanup altered behavior elsewhere or
broke preserved controller/session contracts.

The baseline report supplies the comparison point. The parent PRD/design and
implementation diff supply the change surface. Current source/tests remain the
authority.

## 2. Entry Gate

Before auditing:

- confirm the baseline child task is complete;
- confirm its report has no unresolved Critical/High/Medium finding;
- confirm the parent implementation and legacy deletion are code-complete;
- capture the final changed-file inventory without staging or modifying
  unrelated work;
- map parent acceptance criteria to candidate code/tests.

If these conditions are not true, return to the preceding task rather than
auditing a partial architecture.

## 3. Final Report Model

Create `integration-audit-report.md` with:

1. entry-condition evidence;
2. a complete final application coverage matrix;
3. a dedicated Overview integration-seam matrix;
4. a legacy-removal proof table;
5. findings and focused remediation evidence;
6. parent/child acceptance-criterion mapping;
7. automated results and clearly separated user-run visual smoke items.

Use the same finding schema and severity definitions as the baseline audit so
the two reports can be compared directly.

## 4. Change-Surface And Regression Mapping

Start from the final diff and trace every changed shared owner to its consumers:

```text
MicaApp / shared preferences
    -> ContentView / window injection
    -> WorkbenchChrome / live demand
    -> Overview composition and customizer

AppModel live snapshots
    -> telemetry projection/cache
    -> topology structure/layout/cache
    -> policy inspection index
    -> HUD and cross-tab navigation

Shared Workbench primitives
    -> all Workbench destinations
    -> Settings/native controls where consumed
```

For each edge, verify ownership, lifetime, isolation, invalidation, capability,
and localization/accessibility behavior.

## 5. Multi-Window And Session Scenarios

Use fixtures/in-process models to exercise:

- two windows observing the same global preference change;
- independent chart hover/pin/pause and topology HUD state per window;
- selected-controller switch while data work is in flight;
- disconnect/reconnect and generation replacement;
- closing one window without ending another window's demand;
- router-edit dirty-close behavior after Overview draft removal;
- old persisted Overview data and corrupt current preference data.

Expected behavior is one shared preference value, window-local transient state,
and session-generation-safe published business data.

## 6. Overview Functional Scenarios

Verify with source, focused tests, and bounded fixtures:

- fixed composition and default-hidden optional region;
- immediate preference persistence and reset;
- chart real-sample-only behavior, selection, pause, and finite latest pulse;
- complete topology paths, cache keys, hit priority, keyboard stepping, pause,
  expand, and navigation;
- unique/ambiguous/missing policy resolution;
- compact transient and expanded pinned HUD contents;
- HUD placement/clamping for graph edges and dense obstacles;
- transient hover precedence and pinned restoration;
- blank/Escape clear and accessible equivalents;
- no network work or structure/layout rebuild caused by inspection.

## 7. Cross-Destination Regression Pass

Revisit the shell and every non-Overview destination after shared changes:

- navigation/controller selector/status and commands;
- Proxies/Connections cross-navigation from the HUD;
- Logs, Rules, Sources, Controllers, Actions, Diagnostics,
  management/Tailscale, and Settings;
- empty/error/stale/unsupported states;
- capability gates, selection identity, localization, accessibility, exports,
  and close behavior.

Compare against baseline matrix evidence. A difference requires explanation and
is a finding if it violates a contract or observable expected behavior.

## 8. Performance And Invalidation Pass

Verify architectural boundaries, not just frame appearance:

- global preference writes do not rebuild unrelated live-session state;
- traffic sample changes do not invalidate policy inspection or optional
  modules unnecessarily;
- policy catalog changes do not rebuild topology structure/layout;
- hover/pin changes affect only interaction/highlight/HUD subtrees;
- `nodeGeometryByID` avoids repeated node searches;
- optional modules are not constructed while hidden;
- finite animation state settles and recurring timers are absent;
- dense topology operation-count and hit-test thresholds remain within existing
  limits or an explicitly justified replacement threshold.

## 9. Legacy-Removal Proof

Use repository-wide source searches plus source-verifier assertions to prove
that deleted models and flows have no active references. Inspect production,
tests, localization, docs, and Trellis specs. Negative assertions may retain
symbol names solely as guards against reintroduction.

Do not accept aliases, dormant branches, lossy migration adapters, or unused
compatibility wrappers as removal.

## 10. Remediation And Exit

Each verified Critical/High/Medium regression is repaired at the narrowest
root-cause boundary, receives focused validation, and is added to the final
report. Low observations remain report-only.

After fixes, run the consolidated gate once. The parent can complete only when
all matrix rows and acceptance mappings are resolved and no required finding
remains.
