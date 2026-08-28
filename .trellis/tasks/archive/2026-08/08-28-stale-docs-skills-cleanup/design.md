# Technical Design: Stale Documentation And Skill Cleanup

## 1. Authority And Classification

Classify each candidate against this authority order:

1. current source, tests, and `Package.swift`;
2. `AGENTS.md` and active Mica Trellis contracts;
3. maintained `docs/` summaries;
4. completed task evidence and historical journals.

An artifact is deletable only when its complete contents are a placeholder or
inapplicable template. A contradictory maintained document is rewritten. A
working generated integration, valid skill link, task record, or journal is
kept even when similar copies exist elsewhere.

## 2. Cleanup Matrix

| Class | Action | Evidence |
|---|---|---|
| Eight placeholder backend/frontend specs | Delete | Every substantive section says `To be filled`; several assume databases, React hooks, or JS validators absent from Mica. |
| Backend/frontend indexes | Rewrite | They advertise placeholder files and mark real Mica documents as unfinished. |
| Thinking-guide index and two guide paths | Rewrite in place | Trellis expects stable guide paths, but current bodies include duplicated Trellis product-source workflows unrelated to Mica. |
| `AGENTS.md`, `README.md`, selected maintained docs, and one Mica project-skill reference | Targeted rewrite | Current source and active contracts disprove specific owner, destination, controller, theme, platform, and topology statements. |
| Other maintained Mica docs | Keep | Audit found no concrete conflict requiring deletion. |
| Codex/Claude Code/Pi integrations and valid skill links | Keep unchanged | Current Trellis 0.6.15 defaults and all links resolve. |
| Completed 08-16 task family | Archive | All three task metadata records are `completed`; archival preserves evidence. |
| 08-04 and 08-23 tasks | Keep active | Acceptance remains incomplete. |

## 3. Specification Shape

The backend index becomes a short Mica controller/data-contract index. The
frontend index lists the existing Mica-specific directory, component, state,
live-session, and Workbench contracts with `Active` status.

The stable thinking-guide paths remain:

- `cross-layer-thinking-guide.md`: trace controller wire data through adapter,
  session generation, published snapshot/projection, cache invalidation, and
  final UI; cover commands/capabilities, secrets, localization, and tests.
- `code-reuse-thinking-guide.md`: search current owners first; reuse adapter,
  AppModel, projection/cache, Workbench primitives, formatting, and localization
  boundaries; avoid abstractions that merge controller semantics.

These are concise decision aids, not copies of Trellis's own implementation
documentation.

## 4. Maintained Documentation Alignment

Each correction has a source anchor:

- destinations and grouping: `WorkbenchDestination` in
  `WorkbenchChrome.swift`;
- design-system owner: `MicaTheme.swift` and the source verifier's required
  deletion of the old `MicaStyle.swift` compatibility surface;
- implemented controller families and Tailscale: current adapters, tests, and
  `docs/CONTROLLER_COMPATIBILITY.md`;
- visual tokens: `MicaTheme.swift` and the active UI contract;
- topology ordering, ribbons, and horizontal overflow: current topology source
  plus `.trellis/spec/frontend/workbench-ui-contract.md`;
- verification boundaries: `AGENTS.md` and `docs/DEVELOPMENT.md`;
- AI platform lifecycle: current `.codex`, `.claude`, and `.pi` configuration.

Edits remain local to the contradicted paragraphs. Do not broaden this task into
product redesign or speculative documentation expansion.

## 5. AI Integration Preservation Fence

The implementation agent must not edit or delete `.codex`, `.claude`, `.pi`,
or `.agents/skills` content, except for the exact stale wording in
`mica-controller-development/references/project-constraints.md`. Integration
verification is read-only:

- parse JSON settings/hooks;
- confirm expected hook registrations by platform;
- resolve symlinks;
- run Trellis's dry-run drift report only if it remains local and non-mutating.

The presence of `.codex/hooks/session-start.py` without a `SessionStart`
registration is expected and is not cleanup evidence.

## 6. Task Archival

Archive completed children before their parent using `--no-commit`, then verify
both active and archive listings. Archival is a tracked directory move managed
by Trellis and retains every task artifact. It must not implicitly finish or
archive the current cleanup task or the two retained active tasks.

## 7. Verification Model

Verification is static and offline:

1. inventory changed/deleted files and reject product-source changes;
2. search active specs/docs for removed placeholder and irrelevant terms;
3. validate Markdown relative links in the edited documentation/spec set;
4. parse JSON hook/settings files and inspect platform registrations;
5. resolve tracked and local skill symlinks;
6. inspect Trellis active/archive task state;
7. run `git diff --check`.

No Swift build is required because no Swift/package/resource file changes. No
runtime smoke or controller operation is permitted.
