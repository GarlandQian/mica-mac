# Implementation Plan: Stale Documentation And Skill Cleanup

## Preconditions

- Read task research, this PRD/design, `AGENTS.md`, and active Mica controller,
  live-session, and Workbench contracts.
- Confirm the working tree contains only this task's planning artifacts or
  unrelated user work that will be preserved.
- Treat `.codex`, `.claude`, `.pi`, and `.agents/skills` as read-only except for
  the single Mica project-constraint wording correction approved in the PRD.

## Step 1. Record The Final Evidence Inventory

- Consolidate the research classification into exact delete/rewrite/keep paths.
- Reconfirm every delete candidate is entirely placeholder content.
- Reconfirm all skill symlinks resolve and no backup/reject files exist.
- Record current active/completed task status before archival.

## Step 2. Clean Backend And Frontend Specs

- Delete the eight files named in PRD R2.
- Rewrite `.trellis/spec/backend/index.md` around the controller data contract.
- Rewrite `.trellis/spec/frontend/index.md` around the five existing Mica-
  specific documents.
- Search for references to every removed file and remove stale links.

## Step 3. Replace Generic Thinking Guides

- Rewrite the guides index as a compact Mica-oriented router.
- Replace both guide bodies with the Mica-specific boundaries in `design.md`.
- Remove duplicated and irrelevant `src/templates`, `packages/cli`, React,
  registry, version-routing, and Trellis product-maintenance examples.

## Step 4. Correct Maintained Project Documentation

- Replace the removed `MicaStyle` reference in `AGENTS.md` with the current
  `MicaTheme`/Workbench ownership.
- Update `README.md` destinations, Settings ownership, supported controllers,
  Tailscale, visual system, and verification commands.
- Update `docs/README.md`, `docs/DEVELOPMENT.md`, and the topology paragraph in
  `docs/UI_GUIDELINES.md`.
- Correct only the stale Rose Pine/`MicaStyle` sentence in the Mica project
  skill reference; preserve the rest of the skill.
- Compare all changed claims with their source/contract anchors.
- Leave other maintained documents untouched unless a concrete contradiction is
  recorded first.

## Step 5. Archive The Completed 08-16 Task Family

Run Trellis archival with `--no-commit` for:

1. `08-16-global-functional-audit`;
2. `08-16-post-refactor-integration-audit`;
3. `08-16-dashboard-visual-hover-details`.

Verify their complete directories moved to the archive and that
`08-04-workbench-native-ui-system`, `08-23-overview-flow-ribbons`, and this task
remain active.

## Step 6. Static Quality Gate

- [x] Confirm the changed-file set contains only task records, docs, and specs.
- [x] Check deleted-file references and stale marker searches.
- [x] Validate relative Markdown links in edited docs/specs.
- [x] Parse `.codex/hooks.json`, `.claude/settings.json`, and `.pi/settings.json`.
- [x] Verify expected per-platform hook mechanisms and resolving skill links.
- [x] Run `git diff --check`.
- [x] Do not build/launch Mica or run controller/runtime smoke.

## Step 7. Review And Completion Evidence

- [x] Dispatch a `trellis-check` agent against the final diff and acceptance
  criteria.
- [x] Fix any verified cleanup regression without touching product behavior.
- [x] Check off PRD and implementation criteria with evidence.
- Keep task completion, commit, and final archival in the normal Trellis finish
  phase; do not push unless the user explicitly requests it.
