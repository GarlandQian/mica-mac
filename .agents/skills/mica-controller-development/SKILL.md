---
name: mica-controller-development
description: Project-specific architecture and development workflow for Mica. Use when modifying or reviewing Mica controller kinds, adapters, HTTP/WebSocket/gRPC APIs, DTOs, capabilities, authentication, profile persistence, live-session state, AppModel operations, Workbench navigation/pages, localization, project build/test configuration, or Mica-specific release constraints.
---

# Mica Controller Development

## Start

1. Read `AGENTS.md` and the active Trellis task context before editing.
2. Treat `Package.swift`, current source, tests, and active `.trellis/spec/` contracts as authoritative. Verify documentation claims against code when they differ.
3. Load only the references needed for the change:
   - [architecture.md](references/architecture.md): modules, data flow, state ownership, dependency injection, SwiftUI/AppKit boundary.
   - [controllers.md](references/controllers.md): controller families, capabilities, authentication, errors, DTO/domain boundaries, session publication.
   - [development-workflows.md](references/development-workflows.md): steps for adding a controller, API, operation, page, localization, tests, and verification.
   - [project-constraints.md](references/project-constraints.md): safety, data visibility, ordering, UI conventions, compatibility, temporary files, and release facts.

## Core Workflow

1. Trace the full change path before editing: endpoint and transport -> decoded model -> capability -> generation-owned AppModel operation/session -> presentation projection -> SwiftUI surface -> localization -> tests and source verifier.
2. Keep controller protocol code in `MicaCore`. Keep selected-session coordination, persistence transactions, presentation state, and UI composition in `Mica`.
3. Gate every backend-specific control through `ControllerCapabilities` and the effective runtime controller type. Do not expose an action because another backend has a similarly named endpoint.
4. Validate controller ID plus session generation before every asynchronous publish. Reuse the existing task slot, lane, pause, stale-data, write-vs-refresh transaction, and command-log patterns.
5. Preserve controller-reported order and optionality. Do not fabricate business rows, values, chart samples, or fallback capabilities.
6. Keep views declarative: consume AppModel state and pure presentation projections; do not decode responses or create network tasks in a view.
7. Add focused protocol/state/presentation tests and update `scripts/verify-real-controller-source.mjs` when a durable project contract changes.

## Global Skill Boundary

Use the installed global skills for generic SwiftUI, Swift concurrency, Swift Testing, macOS patterns, settings, Sparkle, release, and code-review guidance. This skill only supplies Mica-specific facts and integration steps. For UI work, also load the repository-required native design skills named in `AGENTS.md`.

## Uncertainty Rule

Mark unverified behavior as `待确认` in plans or documentation. Do not infer support from enum cases, placeholder capability families, ignored artifact extensions, or third-party reference projects.
