# Mica Agent Guide

## Start Here

- Treat current source, tests, and `Package.swift` as authoritative; active Trellis contracts come next. `docs/` is a maintained summary, not a substitute for code.
- Load `mica-controller-development` before changing or reviewing Mica. Its references own project architecture, controller behavior, workflows, and detailed constraints.
- Read the active task and relevant `.trellis/spec/` before implementation. Inspect `git status --short` and preserve unrelated work.
- Mica is a Swift 6.2 SwiftPM app targeting macOS 27. Do not lower either target without an explicit compatibility decision.

## Non-Negotiable

- Mica controls already-running remote controller APIs. Never download, bundle, launch, or manage a local core; never modify system networking, OpenWrt, LuCI, SSH, or `ubus`. Automated checks must not contact a controller or invoke remote actions. Do not add mock controller business data to production UI.
- Keep controller-reported business data visible and selectable in active UI. Exports exclude credentials, tokens, authorization values, subscription URLs, Keychain contents, and raw response or stream bodies.
- Preserve controller order and optionality. Gate actions through capabilities; validate controller ID and session generation after asynchronous work. Mica has one selected live controller and does not fail over automatically.
- For macOS UI work, load `macos-app-design`, `apple-hig-expert`, and `swiftui-liquid-glass`. Use the current `MicaTheme` and Workbench primitives with the UI contract; no custom content glass, fabricated charts, or ordinary modal workflows. Keep visible copy in English and Simplified Chinese.
- Add a Swift package only for a verified material benefit; record the rationale, compatibility, license, cost, and boundary tests in the active task and durable documentation.
- Keep scratch output under `tmp/codex/`, then remove disposable artifacts. Do not use destructive Git commands or revert unrelated changes. Run runtime smoke only when the user or task explicitly permits it.

## Detailed Context

- Project skill: `.agents/skills/mica-controller-development/SKILL.md`
- Controller/session contract: `.trellis/spec/backend/controller-data-contract.md`, `.trellis/spec/frontend/live-session-controller-contract.md`, and `.trellis/spec/frontend/live-command-scope-contract.md`
- Workbench UI/performance contract: `.trellis/spec/frontend/workbench-ui-contract.md`
- Durable project documentation and verification commands: `docs/README.md`

<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:
- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->
