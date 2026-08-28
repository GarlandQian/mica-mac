# 清理过时文档与 AI 集成

## Goal

Remove documentation that is demonstrably empty or inapplicable, align the
remaining project documentation with current source and active Trellis
contracts, and archive completed task records through Trellis. Preserve every
working Codex, Claude Code, and Pi integration, valid macOS skill, historical
record, and task that still requires acceptance.

This is a documentation and workflow-hygiene task. Current source, tests,
`Package.swift`, `AGENTS.md`, and active Mica contracts remain authoritative.

## Requirements

### R1. Evidence-Based Cleanup

- Delete only artifacts whose current contents prove they are empty templates,
  repository-external examples, or statements contradicted by current source.
- Do not infer staleness from age, naming, duplication across supported AI
  platforms, or an unregistered optional hook alone.
- Preserve Git history and use Trellis task archival instead of deleting
  completed task evidence.

### R2. Remove Empty Specification Templates

Delete these eight placeholder-only files:

- `.trellis/spec/backend/database-guidelines.md`
- `.trellis/spec/backend/directory-structure.md`
- `.trellis/spec/backend/error-handling.md`
- `.trellis/spec/backend/quality-guidelines.md`
- `.trellis/spec/backend/logging-guidelines.md`
- `.trellis/spec/frontend/hook-guidelines.md`
- `.trellis/spec/frontend/quality-guidelines.md`
- `.trellis/spec/frontend/type-safety.md`

Rewrite the backend and frontend indexes so they list only active,
Mica-specific contracts and do not advertise `To fill` material.

### R3. Replace Inapplicable Thinking-Guide Content

- Keep `.trellis/spec/guides/index.md` and its two stable guide paths because
  Trellis loads this directory during development.
- Replace Trellis-source-repository examples such as `src/templates/**`,
  `packages/cli/**`, JavaScript/React payload examples, registry/versioned-doc
  workflows, and duplicated sections with concise Mica-specific guidance.
- The resulting guides must cover Mica's controller-to-session-to-projection-to-
  UI data path, generation/capability/order/optionality boundaries, search-first
  reuse, and verification against current owners.

### R4. Align Maintained Documentation

- Update `AGENTS.md` to reference the current `MicaTheme`/Workbench primitives
  instead of the removed `MicaStyle` owner.
- Update `README.md` to describe the current ten Workbench destinations and
  native Settings ownership, the implemented controller families including
  sing-box/Tailscale, the Mica Ops visual system, and default versus explicitly
  authorized runtime verification.
- Update `docs/README.md` to name the current Mica Ops tokens.
- Update `docs/DEVELOPMENT.md` to document Codex, Claude Code, and Pi, including
  their distinct Trellis hook mechanisms, and keep runtime smoke separate from
  the default non-runtime gate.
- Update `docs/UI_GUIDELINES.md` so topology ordering, flow-width ribbons, and
  long-chain horizontal scrolling match the current source and active Workbench
  contract.
- Update only the stale visual-owner wording in
  `.agents/skills/mica-controller-development/references/project-constraints.md`
  from Rose Pine/`MicaStyle` to Mica Ops/`MicaTheme`.
- Retain `docs/ARCHITECTURE.md`, `docs/CONTROLLER_COMPATIBILITY.md`, and
  `docs/DATA_MODEL.md` unless implementation review finds a concrete conflicting
  statement.

### R5. Preserve Supported AI Integrations And Skills

- Preserve Trellis-managed Codex, Claude Code, and Pi files.
- Preserve Codex's unregistered `.codex/hooks/session-start.py`; the Trellis
  default uses `UserPromptSubmit` and `SubagentStart`, while retaining this
  upstream template.
- Preserve Claude Code's registered `SessionStart` behavior and Pi's extension-
  based session lifecycle.
- Preserve every resolving macOS skill symlink and all project-specific Mica and
  Trellis skills.
- The one project-skill wording correction named in R4 is the only permitted
  edit under `.agents/skills`; it changes guidance, not skill behavior.
- Do not run a force update or manually collapse required platform copies.

### R6. Archive Only Completed Tasks

- Archive `08-16-global-functional-audit`,
  `08-16-post-refactor-integration-audit`, and their completed parent
  `08-16-dashboard-visual-hover-details` through `task.py archive --no-commit`.
- Preserve the full contents and parent/child history in the archive.
- Keep `08-04-workbench-native-ui-system` and `08-23-overview-flow-ribbons`
  active because their user/runtime acceptance remains incomplete.

### R7. Bounded Verification

- Verify documentation links and index references resolve.
- Verify no placeholder markers or Trellis-source-repository examples remain in
  active Mica specs.
- Verify all supported platform hook/config files remain parseable and expected
  skill links resolve.
- Verify task listing contains the cleanup task and the two retained active
  tasks, while the three completed 08-16 tasks appear in the archive.
- Run `git diff --check`; do not launch Mica, contact a controller, run runtime
  smoke, push, or modify product source.

## Acceptance Criteria

- [x] AC-01: The eight named placeholder files are absent and no active index
      links to them.
- [x] AC-02: Backend/frontend spec indexes list only real Mica contracts with
      accurate active descriptions.
- [x] AC-03: Thinking guides contain no duplicated Trellis product-repository,
      React, registry, or versioned-doc examples and instead encode current Mica
      cross-layer and reuse checks.
- [x] AC-04: `AGENTS.md`, README, maintained docs, and the Mica project skill
      agree with current destination, controller, theme owner, topology,
      verification, and three-platform integration behavior.
- [x] AC-05: Codex, Claude Code, and Pi hooks/agents/skills remain present and
      retain their platform-specific Trellis defaults.
- [x] AC-06: Every macOS skill symlink resolves; no valid skill is deleted.
- [x] AC-07: The completed 08-16 parent and two child tasks are archived with
      their contents intact; the 08-04 and 08-23 tasks remain active.
- [x] AC-08: Historical task archives, developer journals, and unexpired task
      evidence are not deleted.
- [x] AC-09: Documentation/link/reference checks and `git diff --check` pass,
      with no product-source or runtime-controller operation performed.

## Out Of Scope

- Product code, tests, dependencies, UI behavior, and controller behavior.
- Deleting archived task history, `.trellis/workspace` journals, valid local
  skill links, or Trellis-managed platform files.
- Closing tasks that still require user or runtime acceptance.
- Network access, controller smoke, application launch, release work, commits,
  or remote pushes before their normal workflow stage.

## Open Questions

None. The user approved the conservative cleanup boundary on 2026-08-28.
