# Mica Project Constraints

## Contents

- [Product and safety boundary](#product-and-safety-boundary)
- [Visible data and export boundary](#visible-data-and-export-boundary)
- [Ordering and session invariants](#ordering-and-session-invariants)
- [Navigation and interaction conventions](#navigation-and-interaction-conventions)
- [Visual and preference conventions](#visual-and-preference-conventions)
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

Active workbench UI is full-visible. When the controller reports a business value, keep it visible and selectable/wrappable as appropriate:

- endpoint/host and request URL;
- connection/request IDs;
- provider/source names;
- policy group and node names;
- rule payloads;
- route/provider chains;
- process, address, inbound, and metadata fields;
- controller log messages.

Do not mask, hash, redact, replace, or middle-truncate those values in active UI.

Copied diagnostics/export must exclude:

- credentials, secrets, tokens, Surge `X-Key`, and authorization headers;
- subscription URLs;
- Keychain contents or `secrets.json` values;
- raw response bodies and raw stream bodies.

Do not restore user-facing privacy-era wording such as “redacted”, “masked”, or “safe summary” for ordinary visible controller data.

## Ordering And Session Invariants

- Preserve Mihomo `/proxies` JSON object-key order through `proxyOrder`.
- Preserve each policy group's `all` member order.
- Filtering changes visibility only.
- `GLOBAL` is a presentation-only stable partition: when shown, place it last without changing peer order or decode order.
- Multiple policy groups may stay expanded; each owns its filter and bounded reveal state.
- Native table user sorting applies to a copied presentation projection and never mutates source arrays.
- Controller profile order is manual persisted order. Recent-controller history is separate and never reorders profiles.
- Row selection in Controllers is management selection; only explicit Use changes the active session.
- Exactly one selected controller owns the live generation. Mica does not automatically fail over to another controller after a network failure.
- The first/restored controller may become active after persisted profiles and credentials load; do not let non-active edits steal the session.

## Navigation And Interaction Conventions

- Keep the eleven `WorkbenchDestination` cases as the active top-level information architecture unless a dedicated product decision changes it.
- Keep the sidebar for destinations, not controller rows. Use the toolbar switcher for the active controller and Controllers for the full list.
- Keep controller add/edit in the main-window detail region.
- Keep policy browsing, node selection, latency tests, connection/source/rule inspection, and ordinary configuration in the same window.
- Use `.inspector` for on-demand detail instead of a permanently empty secondary pane.
- Avoid sheets, popovers, context menus, and dialogs for ordinary workflows.
- Allow native confirmation only for destructive/high-risk actions and dirty main-window close.
- Keep controller table actions at the far trailing edge with compact visible glyphs and adequate hit regions/help/accessibility labels.
- Use distinct unloaded, empty, filtered-empty, unsupported, stale, and error copy. Center `ContentUnavailableView` in the remaining content region after fixed headers/toolbars.
- Do not recreate removed command palette, command bar, deck/chart abstraction, old tab hierarchy, sidebar controller list, snapshot/sync mode, or compatibility wrappers for those concepts.

## Visual And Preference Conventions

Native macOS design skills named in `AGENTS.md` are the UI authority. Project-specific facts:

- Use system window/sidebar/toolbar/material behavior as the base.
- Use `MicaGlassSelectionSurface` as the only custom Liquid Glass selection primitive.
- Do not apply Liquid Glass to table rows, logs, long text, inspectors, or passive data content.
- Use `MicaContentCard` for the existing material content-card vocabulary; its current shared radius is 14 points. Do not invent another card system or nest content cards.
- Use the Rose Pine Dawn/Main semantic families defined in `AGENTS.md`. `MicaStyle` currently uses contrast-adjusted light-mode foreground derivatives for semantic text/icons.
- Use accent/purple for selection, blue/green for healthy state, cyan/teal for information/live state, amber for warnings, and red for failures/destructive state.
- Avoid decorative gradients, orbs, forced-dark islands, glass-on-glass, and one-off icon chrome.
- Use SF Symbols and native controls.
- Keep all visible copy in `Localizable.xcstrings` with English and Simplified Chinese.
- Support Follow System/English/Simplified Chinese language resolution, Follow System/Light/Dark appearance, and Standard/Comfortable/Large/Extra Large font scales.
- Scale explicit layout/fonts with the injected preference environment; do not create unscaled fixed text islands.
- Build charts only from real received samples or real categorical aggregates; never fabricate a time series.

## Compatibility And Build Facts

- `Package.swift` declares `// swift-tools-version: 6.2`.
- The package deployment target is `.macOS("27.0")`.
- `Info.plist` also declares `LSMinimumSystemVersion` `27.0`.
- The current bundle identifier is `dev.mica.mica`.
- The current bundle version strings are `0.29`.
- The app is a SwiftPM executable plus `MicaCore` library; there is no tracked hand-authored Xcode project.
- The local generated Xcode workspace under `.swiftpm/` is disposable/ignored.
- Node.js is required for the source verifier; Swift build/test are the primary compile gates.
- Native sing-box transport pins `grpc-swift-2` 2.4.2, `grpc-swift-nio-transport` 2.9.0, `grpc-swift-protobuf` 2.4.1, and `swift-protobuf` 1.38.0. Their checked-out license files are Apache-2.0; future packaging must carry required notices.

Do not silently lower the deployment target or Swift tools version to satisfy an older local SDK. Treat that as a separate compatibility decision.

## Distribution Facts

The owner-declared distribution direction is direct distribution, not the Mac App Store, using DMG packaging and Sparkle updates.

Current repository verification status:

- `.gitignore` excludes `*.dmg`, `*.xcarchive`, `artifacts/`, and `dist/`.
- `Package.swift` has no Sparkle dependency.
- `Info.plist` has no `SUFeedURL` or `SUPublicEDKey`.
- No appcast, signing/notarization script, DMG packaging script, entitlements file, or release workflow is present.
- GitHub Actions currently runs only Swift test/build.

Therefore treat DMG + Sparkle as the approved product direction but **not an implemented release pipeline**. Use the global `macos-auto-update` and `macos-release` skills for a future dedicated implementation task; do not invent missing keys, feed URLs, signing identities, or release automation in unrelated work.

## Repository Hygiene

- Put agent scratch, reference checkouts, generated JSON, logs, smoke homes, build scratch, and DerivedData under `tmp/codex/`.
- Move useful external-tool output back under `tmp/codex/` promptly.
- Remove disposable `tmp/codex/` artifacts when a task no longer needs them.
- Do not use `git clean`, destructive reset/checkout, or revert unrelated dirty worktree changes.
- Use `rg` for search and `apply_patch` for manual edits.
- Do not create project-skill README, CHANGELOG, installation guide, examples, scripts, or assets unless the skill genuinely needs them.

## Pending Confirmation

Keep these explicit until the repository changes:

- `CLAUDE.md` is absent; `AGENTS.md` plus `.trellis/` are the current project-memory sources.
- Sparkle/DMG/signing/notarization configuration is not implemented despite the approved distribution direction.
- HTTP fixture coverage exists under `Tests/MicaCoreTests/Fixtures/`; sing-box protocol coverage uses an in-process gRPC service rather than checked-in response JSON.
- No real controller/version matrix has been exercised by automated validation; protocol compatibility beyond the fixtures and checked-in StartedService schema remains to be confirmed against user endpoints.
- `KeychainSecretStore` exists, but `AppModel` defaults to plaintext `FileSecretStore`; changing the production default needs an explicit security/product decision.
- Several generic `.trellis/spec/` files remain placeholders; use only the contracts marked Active in the spec indexes unless their content is completed.
