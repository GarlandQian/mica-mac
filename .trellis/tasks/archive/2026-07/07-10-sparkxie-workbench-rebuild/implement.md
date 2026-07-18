# Implementation Plan: Mica SparkXie Workbench Rewrite

## Phase A: Evidence and Contract

- [x] Re-read this task's PRD/design and the local SparkXie reference checkout at `tmp/codex/sparxie-ui-reference`.
- [x] Inventory every Mica tab, snapshot model, controller endpoint, and existing fake/abstract presentation path.
- [x] Map each SparkXie data object to a Mica source model or mark it unavailable.
- [x] Record stable ordering rules for policy groups, nodes, providers, rules, connections, and logs.
- [x] Define the no-mock contract in source verification and tests.
- [x] Mark every unavailable SparkXie field explicitly; do not extend models with guessed defaults.
- [x] Confirm the Rose Pine Dawn-Main token table from `AGENTS.md` is the only palette used by the replacement UI.

## Phase B: New Workbench Shell

- [x] Replace the current root composition with stable macOS sidebar navigation and a single main workbench window.
- [x] Rebuild toolbar, tab title, refresh state, search, filtering, pagination, and inline inspector primitives.
- [x] Rebuild localization, appearance, font scale, keyboard navigation, VoiceOver labels, and SF Symbol usage around the new shell.
- [x] Remove obsolete command-palette/deck/chart abstractions rather than wrapping them.

## Phase C: Data-First Tab Rebuild

- [x] Rebuild Overview using only real controller snapshot data and explainable status sections.
- [x] Rebuild Policy Groups as stable ordered expandable blocks with inline strategy/node selection.
- [x] Rebuild Connections around SparkXie connection/process/rule/chain semantics and real traffic counters.
- [x] Rebuild Rules with payload-first hierarchy and truthful auxiliary-field availability.
- [x] Rebuild Sources with proxy-source/rule-set categories and real provider fields.
- [x] Rebuild Logs around real controller levels, timestamps, messages, pause/follow and clear behavior.
- [x] Rebuild Core Config around real writable mode/settings fields and truthful capability gates.
- [x] Rebuild Core Actions around risk-gated reload/update/restart/cache actions.
- [x] Rebuild conditional Tailscale state/actions only when the adapter reports support.
- [x] Rebuild Diagnostics around real controller messages, timestamps, capabilities, endpoint checks and export boundaries.
- [x] Rebuild Settings around language, appearance, font scale, controller profiles and app preferences.
- [x] Add charts only where a real time series exists and provide an accessible tabular fallback.

## Phase D: Command and Settings

- [x] Replace the current Command menu with a small set of real, state-aware commands mapped to visible workbench regions.
- [x] Keep ordinary policy/node selection and inspection inline; reserve confirmation for destructive/high-risk actions.
- [x] Verify language switching, system appearance, explicit light/dark, and all font scales across every rebuilt tab.
- [x] Verify menu/help/tooltip/accessibility localization and remove old English or awkward Chinese copy.
- [x] Verify full controller business data remains visible in active UI and only credential/raw-body boundaries apply to exports.

## Phase E: Removal and Verification

- [x] Delete obsolete UI-only models, wrappers, localization keys, and source verifier assumptions after call sites are migrated.
- [x] Add focused tests for stable ordering, filtering, availability states, and policy-group selection.
- [x] Run source verifier, localization parse, `git diff --check`, Swift build, Swift tests, runtime smoke, and UI smoke where permissions allow.
- [x] Keep all build/smoke output under `tmp/codex/`; remove disposable outputs at the end.
- [x] Run the final design-taste/macOS/HIG preflight over every primary tab and fix contrast, density, icon, and layout issues.

## Validation Commands

```text
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
node --check scripts/verify-runtime-smoke.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
git diff --check
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
node scripts/verify-runtime-smoke.mjs tmp/codex/swift-build/debug/Mica
```

## Review Gates

- No implementation begins until the PRD, design, and implementation plan are reviewed and the task is explicitly started.
- Each tab must be reviewed against SparkXie evidence before moving to the next tab.
- A surface fails review if it contains mock values, unstable order, unexplained fields, ordinary modal selection, or unreadable visual hierarchy.

## Completion Notes

- Source contract, runtime smoke, localization JSON, and `git diff --check` pass.
- Swift build passes; 18 unit tests pass, including raw policy order with `GLOBAL`, escaped quotes, and surrogate-pair Unicode names.
- UI smoke passed for `zh-Hans + dark + extraLarge` and `en + light + standard`; controller name and full endpoint remain visible and the startup profile-load banner is absent.
- Durable architecture, data-model, compatibility, UI, and development documentation was updated under `docs/`; reusable contracts were added under `.trellis/spec/`.
- Disposable build, screenshot, temporary-home, and helper-script output was removed. `tmp/codex/sparxie-ui-reference` remains intentionally as the continuing product reference.
- Implementation and verification are complete. The Trellis task remains `in_progress` only because Phase 3.4 has not created a work commit in this dirty shared worktree.
