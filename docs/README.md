# Mica Durable Documentation

This directory describes the current implementation and its verified behavior.

## What Belongs Here

- `ARCHITECTURE.md`: module ownership, data flow, state boundaries, and persistence.
- `DATA_MODEL.md`: controller objects, response fields, availability states, and ordering contracts.
- `CONTROLLER_COMPATIBILITY.md`: backend families, supported operations, and truthful unavailable boundaries.
- `UI_GUIDELINES.md`: macOS/SwiftUI conventions, controller data presentation, theme tokens, accessibility, and interaction rules.
- `DEVELOPMENT.md`: build, test, smoke, temporary-file, and release-development workflow.

Create a file only when it contains durable knowledge. Do not add dated plans, chat transcripts, temporary research, or progress checklists here.

## Maintenance

When changing a stable project behavior:

1. Read this index and identify the document affected by the task.
2. Update the relevant document in the same task when a stable project fact changed.
3. Keep temporary experiments and verification output under `tmp/codex/`.

Durable documents must describe the current code and verified behavior, not aspirational future work. Remove or correct stale statements when implementation changes. Keep examples concrete and avoid copying secrets, tokens, raw response bodies, or other unsafe controller payloads.

## Source Of Truth

- Implementation and executable behavior: `Sources/` and `Tests/`
- Stable project knowledge: this directory
- Temporary research and verification output: `tmp/codex/`
