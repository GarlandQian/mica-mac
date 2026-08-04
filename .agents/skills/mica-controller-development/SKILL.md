---
name: mica-controller-development
description: Mica-specific controller and Workbench development guide. Use when changing controller families, HTTP/WebSocket/gRPC APIs, DTOs, capabilities, authentication, profile persistence, live-session state, AppModel operations, Workbench surfaces, localization, build/test configuration, or release constraints.
---

# Mica Controller Development

## Start With

Treat `Package.swift`, current source, tests, and active `.trellis/spec/` contracts as authoritative. Read the active Trellis task, then load only the relevant reference:

- [architecture.md](references/architecture.md): modules, data flow, state ownership, dependency injection, SwiftUI/AppKit boundary.
- [controllers.md](references/controllers.md): controller families, capabilities, authentication, errors, DTO/domain boundaries, session publication.
- [development-workflows.md](references/development-workflows.md): adding a controller, API, operation, page, localization, tests, and verification.
- [project-constraints.md](references/project-constraints.md): safety, data visibility, ordering, UI conventions, compatibility, temporary files, and release facts.

## Workflow

1. Trace the full change path before editing: endpoint and transport -> decoded model -> capability -> generation-owned AppModel operation/session -> presentation projection -> SwiftUI surface -> localization -> tests and source verifier.
2. Keep controller protocol code in `MicaCore`. Keep selected-session coordination, persistence transactions, presentation state, and UI composition in `Mica`.
3. Gate shared controller operations through `ControllerCapabilities` and the effective runtime type. Gate dedicated surfaces such as sing-box Tailscale through their own readiness/availability state.
4. Validate controller ID and session generation before asynchronous publication; live-domain envelopes also validate monotonic revision. Reuse existing task slots, refresh lanes, runtime publication, pause, stale-data, and confirmed-write patterns.
5. Preserve controller-reported order and optionality. Do not fabricate business rows, values, chart samples, or fallback capabilities.
6. Keep views declarative: consume AppModel state and pure presentation projections; do not decode responses or create network tasks in a view.
7. Add focused protocol/state/presentation tests and update `scripts/verify-real-controller-source.mjs` when a durable project contract changes.

## Global Skill Boundary

Use installed global skills for generic SwiftUI, concurrency, testing, macOS design, settings, release, and review guidance. This skill contains only Mica-specific facts and integration steps.

## Uncertainty Rule

Mark unverified behavior as pending confirmation. Do not infer support from enum cases, placeholder capabilities, documentation plans, or external reference projects.
