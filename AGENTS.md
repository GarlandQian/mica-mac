## Codex Workspace Rules

- All UI/design work in this repository must load the design skills before implementation. The native macOS skills are the FINAL authority: `macos-app-design`, `apple-hig-expert` (run its `hig_checker.py` for contrast/tap-target gates), and `swiftui-liquid-glass`. The `design-taste-frontend` skill (installed as `taste-skill`) is a supplementary anti-slop layer — borrow only its general principles (color, density, layout rhythm, contrast, shape consistency, pre-flight review). Note: `design-taste-frontend` explicitly scopes itself to landing pages/portfolios and NOT dashboards/data tables/multi-step product UI, which is exactly what Mica is — so its web/landing-page-specific rules do not apply; the native skills win every conflict.
- For any native macOS/SwiftUI surface, lead with `macos-app-design` + `apple-hig-expert` + `swiftui-liquid-glass`; use `design-taste-frontend` only for its general taste checks. Apple platform conventions and SparkXie-aligned data clarity always take precedence over web/landing-page guidance.
- Use the following Rose Pine Dawn-Main palette as Mica's fixed semantic tint and opaque-fallback token source. Keep light/dark values paired; do not invent a second palette or replace these values with arbitrary gradients. On macOS 27, native window, sidebar, toolbar, and Liquid Glass materials may provide the base background instead of an opaque palette fill:
  - `background`: light `#FAF4ED`, dark `#191724`
  - `groupedBackground` / `tabBarBackground`: light `#FFFAF3`, dark `#1F1D2E`
  - `secondaryGroupedBackground`: light `#F2E9E1`, dark `#26233A`
  - `tertiaryGroupedBackground`: light `#DFDAD9`, dark `#403D52`
  - `accent` / `purple` / `indigo`: light `#907AA9`, dark `#C4A7E7`
  - `red`: light `#B4637A`, dark `#EB6F92`
  - `orange` / `yellow`: light `#EA9D34`, dark `#F6C177`
  - `blue` / `green`: light `#286983`, dark `#31748F`
  - `teal` / `cyan`: light `#56949F`, dark `#9CCFD8`
- Use the palette semantically: accent for selection/focus, red for errors, orange/yellow for warnings, blue/green for healthy or active states, and teal/cyan for informational states. Preserve contrast in content tables and do not apply Liquid Glass to table rows, logs, long text, or other passive data content. Policy-group selector blocks are interactive controls and may use native Liquid Glass; their expanded member data remains a high-readability content layer.
- Active controller workspaces are full-visible UI surfaces. Do not hide, mask, hash, or replace controller business data there: controller endpoints/hosts, request URLs, connection IDs, provider names, node or policy names, rule payloads, route chains, and log messages must stay visible when the controller reports them.
- Keep only credentials and unsafe raw payloads out of exports: secrets, tokens, Surge X-Key values, subscription URLs, authorization headers, Keychain contents, raw response bodies, and raw stream bodies must not be copied into diagnostics/export reports unless the user explicitly asks for a separate raw export mode.
- Do not reintroduce user-facing "redacted", "masked", "safe summary", or "privacy boundary" copy for active UI data. The visible wording should say data is fully visible in the UI, while copied reports exclude credentials/raw response bodies.
- Current UI work is a full macOS 27 Liquid Glass rebuild on top of the SparkXie-aligned controller data contract. Do not preserve old Mica tab structures, compatibility shims, abstract deck/chart layers, or legacy visible terminology unless the user explicitly asks to restore them later.
- Prefer replacing old surfaces outright over layering adapters on top of them. Compatibility with previous UI architecture is not a goal during this rebuild.
- The current rebuild starts from the product goal again, not from the previous rewritten UI. Treat earlier tab layouts, command palette grouping, card titles, privacy-era wording, and chart abstractions as disposable unless the user explicitly asks to bring a specific piece back.
- Do not add backwards-compatible wrappers for removed UI concepts just to keep old names alive. Rename or delete the old concept, then update call sites and verifiers to the new product language.
- Avoid modal dialogs, popovers, sheets, and context menus for normal workbench interactions. Strategy/policy group browsing, node selection, and latency tests must happen inside the same main window through fixed-order Liquid Glass selectors plus an inline or adjacent detail region. Show fixed-selection cancellation there only when the controller reports a real fixed-selection state and action.
- Confirmation dialogs are acceptable only for destructive or high-risk operations, not for ordinary policy or node selection.
- Treat `.agents/skills/` as the canonical source for non-Trellis project skills shared by Codex and Claude. Each retained non-Trellis `.claude/skills/<name>` entry must be a relative symlink to `../../.agents/skills/<name>` so the two platforms cannot drift; keep `skills-lock.json` aligned with the canonical `.agents/skills/` installation. Keep every `trellis-*` skill as a real, platform-owned directory in its generated skill root and never replace it with a cross-platform symlink, because Trellis may render and update platform-specific content independently.
- Put development scratch files under `tmp/codex/` in this repository, not scattered through `/private/tmp` or other system temp directories.
- If an external tool must temporarily write outside the repository, migrate the useful output back into `tmp/codex/` as soon as possible and continue from the repository-local path.
- At the end of a development task, delete temporary files in `tmp/codex/` that are no longer needed for follow-up verification or handoff.
- Keep reference checkouts, generated JSON, DerivedData, smoke-test homes, logs, and similar disposable artifacts under `tmp/codex/`.

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
