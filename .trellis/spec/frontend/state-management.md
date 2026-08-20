# State Management

> How state is managed in this project.

---

## Overview

Mica uses SwiftUI-native state only — no third-party state framework. The
ownership ladder is:

1. `AppModel` (`@Observable`) — the application authority: controller profiles,
   the one selected live controller (ID + session generation), capability
   state, and the field-granular `controllerSessionPresentation` mirror.
2. Per-window stores — `WorkbenchWorkspaceStore` (`@Observable`) owns
   window-level workspace state; `OverviewWindowRuntime` owns session-keyed
   telemetry/topology runtimes and the window's live-demand identity.
3. App-owned singletons — `AppPreferencesStore` (language, appearance, font
   scale via `@AppStorage`) and `OverviewPreferencesStore` (the single
   `mica.overview.fixed-core.v1` Overview preference value).
4. View-local `@State` — transient interaction only (hover, disclosure,
   in-flight text edits).

---

## State Categories

- **Controller (server) state** is ingested by `LiveSessionRuntime` off the
  main actor and republished as immutable per-domain snapshots or log deltas
  carrying controller ID, generation, revision, and receipt time. Views never
  read the raw runtime; they read AppModel presentation mirrors.
- **Workspace state** (search text, filters, sort, selection, open proxy
  groups, active tab) lives in `WorkbenchWorkspaceStore`, is keyed per
  controller/destination, and is coalesced into persistence without live
  session state.
- **Inspector state** lives in `WorkbenchWorkspaceStore`: the typed
  `WorkbenchInspectorSelection`, the `isInspectorPresented` visibility flag,
  and the live row resolvers (`connectionRowResolver`, `ruleRowResolver`,
  `logEntryResolver`, `sourceRowResolver`) that destination pages register so
  the inspector renders current-generation data. Inspector selection is
  window-level and session-bound — it clears with the session and is never
  persisted. Controller detail resolves its profile directly from AppModel.
- **Derived state** is computed by pure projection types (no SwiftUI
  dependencies) from real controller snapshots; views never re-derive business
  data in a body.

---

## When to Use Global State

Promote state above view-local `@State` only when at least one is true:

- another window or destination must observe it (AppModel / workspace store);
- it must survive view recreation (workspace store, keyed persistence);
- it participates in session validation (AppModel generation-tracked state).

Everything else stays in the smallest owning view.

---

## Server State

- One selected controller session at a time; every async command revalidates
  controller ID + session generation before mutating observable state.
- Publication budgets: logs 5 Hz, traffic 4 Hz, connections 2 Hz, memory 1 Hz;
  hidden domains retain raw state and flush once on entry.
- Endpoint failures retain the last successful values with a stale marker; only
  never-loaded domains become an error empty state.
- Views observe `controllerSessionPresentation` and domain catalogs rather than
  the broad `controllerSession`, so high-frequency frames cannot invalidate
  unrelated surfaces.

---

## Common Mistakes

- Observing `AppModel.controllerSession` directly from a view (use the
  field-granular presentation state).
- Storing inspector selection or other session-bound state in persistence.
- Mutating controller-reported collections from a view; projections filter/sort
  copies only.
- Letting a delayed async command run without re-checking controller ID and
  session generation.
