# Directory Structure

> How frontend code is organized in this project.

---

## Overview

Mica is a single SwiftPM package with two targets: `MicaCore` (the controller
protocol/data layer) and `Mica` (the macOS app, including all UI). There is no
separate web frontend; "frontend" means the SwiftUI app target. The exact
Workbench file list and per-file ownership rules live in
[workbench-ui-contract.md](./workbench-ui-contract.md).

---

## Directory Layout

```
Sources/
├── Mica/                       # macOS app target (SwiftUI)
│   ├── App/                    # MicaApp scene, AppModel, live-session runtimes,
│   │                           # preferences stores, app services
│   ├── Design/                 # Mica Ops design system:
│   │                           #   MicaTheme.swift (tokens) +
│   │                           #   MicaThemeComponents.swift (shared primitives)
│   ├── Features/
│   │   ├── Workbench/          # main-window IA: chrome, sidebar, inspector,
│   │   │                       # all ten destinations (exact list in the UI contract)
│   │   ├── Routers/Views/      # router editor presentation
│   │   ├── Settings/           # empty; the Settings scene view lives in
│   │   │                       # Workbench/WorkbenchSettings.swift
│   │   └── Dashboard/          # empty; dashboard surfaces are the Workbench Overview
│   └── Resources/              # Localizable.xcstrings (EN + zh-Hans)
└── MicaCore/                   # controller HTTP/WebSocket/gRPC clients, models,
    ├── API/                    # persistence, protocols, security
    ├── Models/
    ├── Persistence/
    ├── Protocols/
    └── Security/
Tests/
├── MicaTests/                  # app-level tests (projections, session, performance)
└── MicaCoreTests/              # core protocol/model tests
```

---

## Module Organization

- New main-window UI belongs in `Sources/Mica/Features/Workbench/` and must
  follow the per-file ownership rules in the Workbench UI contract; do not add
  compatibility shims or one-file-per-small-component sprawl.
- Anything reusable across features (tokens, shared primitives) belongs in
  `Sources/Mica/Design/`, not inside a feature.
- Controller protocol, decoding, capability, and persistence work belongs in
  `MicaCore`; the app target consumes `MicaCore` snapshots and never reimplements
  them.

---

## Naming Conventions

- Workbench files carry the `Workbench` prefix followed by their destination or
  shell role (`WorkbenchConnections.swift`, `WorkbenchStatusBar.swift`).
- Shared design-system types carry the `Mica` prefix (`MicaPanel`,
  `MicaStatusBadge`); Workbench-scoped shared primitives keep the `Workbench`
  prefix (`WorkbenchSection`, `WorkbenchStateView`).
- Pure projection/presentation types are named after what they produce
  (`WorkbenchConnectionProjection`, `OverviewPolicyInspectionProjection`) and
  stay free of SwiftUI dependencies.

---

## Examples

- `Sources/Mica/Features/Workbench/` — the reference feature layout; its file
  list is enforced by the UI contract and the source verifier.
- `Sources/Mica/Design/` — the smallest possible shared-system example: one
  token file, one primitives file.
