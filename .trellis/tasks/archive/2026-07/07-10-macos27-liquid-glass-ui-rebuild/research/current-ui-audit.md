# Current UI Audit

## Hierarchy

`MicaApp` creates a `WindowGroup` and a separate `Settings` scene. The main window is `ContentView` -> `NavigationSplitView` -> `WorkbenchSidebarView` plus either `RouterEditorView` or `WorkbenchRootView`. `WorkbenchRootView` owns search, toolbar actions, an operation strip, and destination routing.

## Primary Problems

- `MicaStyle`, `MicaSurface`, `MicaPanel`, and custom button styles make opaque fills, one-pixel borders, and rounded cards the dominant visual language.
- Existing `glassEffect` usage is fragmented, extremely low prominence, and layered after custom fills/borders instead of defining the control hierarchy.
- The native unified toolbar competes with a custom top operation strip.
- Sidebar selection is recreated with plain buttons, custom fills, and an accent rail inside a native `List`.
- Connections/rules/sources/logs use hand-built fixed-width grids instead of native table semantics.
- Strategy and node names use middle truncation despite the full-visible data contract.
- Settings uses manual sections and hard label widths instead of a semantic macOS `Form`.

## Replaceable UI Layer

- `MicaSurface`, `MicaSurfaceRole`, `MicaPanel`, `MicaPanelTint`, and `micaGlass`.
- `MicaGlassIcon`, `MicaStatusBadge`, `MicaEditorButtonStyle`, and `MicaShellButtonStyle` after call-site migration.
- `MicaSetupDetailLayout` and `micaNativeListChrome` after editor/data-surface migration.
- Current sidebar/root/destination type names and command-group terminology.

Controller models, operations, preference propagation, and localization infrastructure are not part of the replaceable visual layer.
