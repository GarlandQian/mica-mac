# Frontend Development Guidelines

Mica's frontend is a SwiftUI Workbench backed by one generation-validated live
controller session. The active contracts below describe the current ownership
and interaction boundaries.

## Active Contracts

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | SwiftPM target layout and Workbench file ownership | Active |
| [Component Guidelines](./component-guidelines.md) | Mica Ops primitives, projection boundaries, inspectors, and accessibility | Active |
| [State Management](./state-management.md) | AppModel, window stores, session presentation, and publication ownership | Active |
| [Live Session And Controller Transaction Contract](./live-session-controller-contract.md) | Session generation, refresh, stale data, capabilities, and editor transaction safety | Active |
| [Workbench UI Contract](./workbench-ui-contract.md) | Navigation, design system, topology, data surfaces, preferences, and verification | Active |

Read the contract that owns the change before editing a feature. Cross-cutting
work must satisfy both the live-session and Workbench contracts. Keep
controller-reported order and optionality intact, derive view data through pure
projections, and route detail through the single workspace inspector.

**Language**: All documentation should be written in **English**.
