# Mica Project Constraints

## Contents

- [Product and safety boundary](#product-and-safety-boundary)
- [Visible data and export boundary](#visible-data-and-export-boundary)
- [Ordering and session invariants](#ordering-and-session-invariants)
- [Navigation and interaction conventions](#navigation-and-interaction-conventions)
- [Visual and preference conventions](#visual-and-preference-conventions)
- [Dependency decisions](#dependency-decisions)
- [Compatibility and build facts](#compatibility-and-build-facts)
- [Distribution facts](#distribution-facts)
- [Repository hygiene](#repository-hygiene)
- [Pending confirmation](#pending-confirmation)

## Product And Safety Boundary

Mica is a native remote-controller workbench. It connects only to controller APIs the user has already enabled.

Do not make Mica:

- download, bundle, install, launch, supervise, or replace a local proxy core;
- modify macOS proxy settings, environment variables, firewall rules, routing, or network extensions;
- administer OpenWrt, LuCI, SSH, `ubus`, service state, or controller host files;
- run real controller/core actions during automated validation;
- introduce mock controller business data into production UI.

Remote restart/upgrade/cache/config actions already represented in source are controller API calls, not local-core management. Keep them capability-gated and never invoke them during tests or visual checks.

## Visible Data And Export Boundary

Active Workbench UI shows controller-reported business data in full: endpoints,
URLs, IDs, names, rules, chains, process/address metadata, and logs. Do not
mask, hash, replace, or middle-truncate it.

Diagnostics/export excludes credentials, tokens, authorization values,
subscription URLs, secret-store contents, and raw response/stream bodies. Do
not restore privacy-era masking copy for ordinary active UI.

## Ordering And Session Invariants

- Preserve Mihomo `proxyOrder` in the DTO and each group's member order. Its
  Dashboard catalog follows matching group names in `GLOBAL.all`, then unlisted
  groups in `proxyOrder`, with `GLOBAL` last. Other backends preserve their
  reported group order.
- Filtering changes visibility only. Never alphabetize or latency-rank groups
  unless a future explicit user-controlled presentation sort is added.
- User sorting applies to copied presentation projections. Logs preserve
  incoming order.
- Controller profile order is manual persisted order. Recent-controller history is separate and never reorders profiles.
- Row selection in Controllers is management selection; only explicit Use changes the active session.
- Exactly one selected controller owns the live generation. Mica does not automatically fail over to another controller after a network failure.
- The first/restored controller may become active after persisted profiles and credentials load; do not let non-active edits steal the session.

Detailed policy workspace and table behavior lives in the Workbench UI
contract.

## Navigation And Interaction Conventions

- Keep the current ten-destination Workbench and collapsed inline controller
  switcher; Controllers remains the full management page. Application
  preferences live only in the native Settings scene and are not duplicated in
  the Workbench sidebar.
- Keep add/edit, policy/node work, tests, inspection, and ordinary
  configuration in the main window. Use inspectors for on-demand detail.
- Use native confirmation only for destructive/high-risk actions and dirty
  window close.
- Scope delayed editor/confirmation actions to controller ID plus generation,
  and give each Add/Edit presentation fresh identity.
- Keep connection-test progress profile-scoped; one running row must not disable
  unrelated controller rows.
- Shared unavailable/retry commands consume the same capability, pause, and
  busy gates as other command surfaces.
- Do not recreate removed navigation, command-palette/deck abstractions, or
  compatibility wrappers.

## Visual And Preference Conventions

Native design skills supply generic guidance. Mica-specific UI authority is
`.trellis/spec/frontend/workbench-ui-contract.md`, with maintained summary in
`docs/UI_GUIDELINES.md`.

- Use native window chrome and opaque Workbench content surfaces; no custom
  content glass, decorative gradients, nested cards, or fabricated charts.
- Use existing Workbench primitives, SF Symbols, semantic text styles, and the
  accessible Rose Pine-inspired tokens defined by the UI contract and
  `MicaStyle`.
- Visible copy is English and Simplified Chinese. Dynamic localization reads
  `micaAppLanguage`; text scale uses injected Dynamic Type without multiplying
  control/layout geometry.
- Observe narrow domain catalogs. `WorkbenchRootView` alone owns visible-domain
  publication; child lifecycle callbacks do not.
- Distinguish unloaded, empty, filtered-empty, unsupported, stale, and failed
  states. Center full-page states in the remaining content region.

## Dependency Decisions

Add a package only for a measured correctness, performance, security, protocol,
or maintenance benefit after checking system/local alternatives, compatibility,
maintenance, license, transitive/build cost, and concurrency. Keep it behind a
typed boundary and record the decision and tests. Current direct packages serve
the sing-box gRPC/protobuf boundary; Workbench charts use system frameworks.

## Compatibility And Build Facts

- Swift tools 6.2 and macOS 27 are deliberate minimums.
- Mica is a SwiftPM executable plus `MicaCore`; there is no tracked hand-built
  Xcode project.
- `Package.swift` and `Info.plist` own current versions, bundle identity, and
  direct dependency pins. Node is used by the source verifier; Swift
  build/test are the compile gates.

Do not silently lower the deployment target or Swift tools version to satisfy an older local SDK. Treat that as a separate compatibility decision.

## Distribution Facts

Direct DMG distribution with Sparkle is the product direction, not an
implemented pipeline. The repository currently has no Sparkle dependency,
feed/key, appcast, signing/notarization, DMG script, or release workflow. Use
the global release skills in a dedicated task; never invent keys or identities.

## Repository Hygiene

- Put all disposable agent/build/verification output under `tmp/codex/` and
  remove it when no longer needed.
- Do not use `git clean`, destructive reset/checkout, or revert unrelated dirty worktree changes.
- Use `rg` for search and `apply_patch` for manual edits.
- For project Skill maintenance, `.agents/skills/` is canonical. Retained non-Trellis `.claude/skills/<name>` entries are relative symlinks to it; keep `skills-lock.json` aligned. Keep `trellis-*` Skills as platform-owned directories.
- Do not add auxiliary project-Skill files without a real runtime need.

## Pending Confirmation

Keep these explicit until the repository changes:

- Automated validation uses fixtures/in-process gRPC, not a real
  controller/version matrix.
- `FileSecretStore` remains the production default although a Keychain store
  exists; changing it requires an explicit security decision.
- Use only Trellis contracts marked active; generic placeholders are not
  project truth.
