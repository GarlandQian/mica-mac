# Mica Durable Documentation

This directory stores stable project knowledge that should survive after a Trellis task is archived. It is not a second task tracker.

## What Belongs Here

- `ARCHITECTURE.md`: module ownership, data flow, state boundaries, and persistence.
- `DATA_MODEL.md`: controller objects, response fields, availability states, and ordering contracts.
- `CONTROLLER_COMPATIBILITY.md`: backend families, supported operations, and truthful unavailable boundaries.
- `UI_GUIDELINES.md`: macOS/SwiftUI conventions, SparkXie data presentation, Rose Pine tokens, accessibility, and interaction rules.
- `DEVELOPMENT.md`: build, test, smoke, temporary-file, and release-development workflow.

Create a file only when it contains durable knowledge. Do not add dated plans, chat transcripts, temporary research, or progress checklists here.

## Maintenance Contract

Every Trellis task performs a durable-document pass before completion:

1. Read this index and identify the document affected by the task.
2. Update the relevant document in the same task when a stable project fact changed.
3. Keep task-specific requirements and unresolved decisions in `.trellis/tasks/`.
4. If no durable document is affected, record `No durable docs change` and the reason in the task journal or finish notes.

Durable documents must describe the current code and verified behavior, not aspirational future work. Remove or correct stale statements when implementation changes. Keep examples concrete and avoid copying secrets, tokens, raw response bodies, or other unsafe controller payloads.

## Source Of Truth

- Current task plan and acceptance criteria: `.trellis/tasks/`
- Permanent repository rules: `AGENTS.md`
- Reusable implementation contracts: `.trellis/spec/`
- Stable project knowledge: this directory
- Temporary research and verification output: `tmp/codex/`
