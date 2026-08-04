# Mica Development Workflows

## Contents

- [Before editing](#before-editing)
- [Add a controller family](#add-a-controller-family)
- [Add or change an API](#add-or-change-an-api)
- [Add an AppModel operation](#add-an-appmodel-operation)
- [Add a Workbench page or surface](#add-a-workbench-page-or-surface)
- [Change persistence or authentication](#change-persistence-or-authentication)
- [Add a third-party package](#add-a-third-party-package)
- [Localization](#localization)
- [Tests and validation](#tests-and-validation)
- [Release-related changes](#release-related-changes)

## Before Editing

Read the active contract for the affected layer:

- controller decoding/API: `.trellis/spec/backend/controller-data-contract.md`;
- selected session/profile transaction: `.trellis/spec/frontend/live-session-controller-contract.md`;
- visible workbench/navigation/design: `.trellis/spec/frontend/workbench-ui-contract.md`.

Use `rg` to trace the model, capability, operation, presentation, localization,
tests, and verifier before editing.

## Add A Controller Family

An enum case is not support until the complete path exists:

1. Add persisted `ControllerKind`, decode compatibility, and only required
   profile fields.
2. Add `UnifiedControllerType`, a truthful boundary summary, and granular
   capabilities.
3. Implement typed MicaCore transport/models and register a real adapter.
4. Add side-effect-free probing only when an identifying endpoint exists.
5. Add generation-owned session producers/operations and backend-specific
   presentation without flattening required fields.
6. Gate all command surfaces through the effective capability.
7. Add editor/localization support plus protocol, capability, session-switch,
   and visible-state tests.
8. Update the verifier and compatibility docs only after implementation.

Current families and their differences are listed in `controllers.md`.

## Add Or Change An API

1. Add the exact endpoint/RPC and typed request/response model in `MicaCore`.
2. Preserve upstream optionality, order, and unknown fields required by UI.
3. Match existing authentication, status, malformed/empty response, TLS, and
   cancellation behavior.
4. Add capability, AppModel/session ownership, presentation, localization, and
   UI in that order.
5. Re-read authoritative state after mutation when supported.
6. Test exact HTTP or gRPC wire behavior with injected/in-process transports;
   never require a live controller.

For ordered JSON objects such as Mihomo proxies/providers, use the existing order-preserving decode path rather than a generic `request<T>` helper.

## Add An AppModel Operation

Use an existing domain operation file such as `AppModelSurgeOperations`,
`AppModelSingBoxOperations`, `AppModelRuntimeOperations`, or
`AppModelConfigurationOperations`; add a focused extension only for a genuinely
new ownership boundary.

1. Reuse a domain operation file and task slot; add a slot only for distinct
   ownership.
2. Guard selected controller, pause rules, and effective capability.
3. Capture prior optimistic state, controller ID, and generation.
4. Revalidate after every suspension before publication.
5. Confirmed write plus failed refresh is partial success; only write failure
   rolls back.
6. Clear busy/command state only for the task that owns it.

Connection close also validates a non-blank reported ID at presentation,
AppModel, and transport boundaries. Policy selection revalidates reported
`selectable` and current membership before starting a write.

## Add A Workbench Page Or Surface

1. Prefer an existing destination. A new top-level destination must update the
   complete `WorkbenchDestination` routing/persistence/search contract.
2. Keep state/network ownership in AppModel and pure Workbench projections.
3. Follow the native same-window patterns, data states, ordering, preferences,
   accessibility, and performance boundaries in the Workbench UI contract.
4. Add presentation/layout tests and verifier assertions for durable rules.
5. Run measurable HIG contrast and hit-target checks.

Do not add AppKit content, view-owned networking/decoding, a second navigation
model, or compatibility wrappers for removed UI concepts.

## Change Persistence Or Authentication

Keep credentials outside `RouterProfile`. Credential/profile writes commit
before observable/session mutation and roll back on persistence failure.
Active-profile changes replace the generation only after commit; non-active
changes do not steal the session. Test with in-memory/failing stores, never real
user Application Support or Keychain state.

## Add A Third-Party Package

Record the measurable need first. Check system frameworks and existing
dependencies, then verify macOS/Swift compatibility, maintenance, license,
transitive/build cost, concurrency, and cancellation. Pin it behind a typed
Mica boundary, add boundary tests, and record the durable decision in
`docs/DEVELOPMENT.md`.

## Localization

- Add visible copy for `en` and `zh-Hans` in `Localizable.xcstrings`.
- Use `MicaStrings`/`XCStringsResolver` and relocalize cached presentation state
  when language changes.
- Preserve controller-reported names; localize surrounding UI and states.

## Tests And Validation

Follow the complete, current verification matrix in `docs/DEVELOPMENT.md`.
Minimum package gates are:

```bash
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
```

Use focused tests while iterating, then run the source, localization, HIG,
performance, or Xcode gates relevant to the change. Runtime smoke is optional
and requires explicit permission. Validation never contacts a controller or
invokes remote actions.

## Release-Related Changes

Load the global `macos-auto-update` or `macos-release` skill for generic Sparkle, signing, notarization, DMG, and appcast procedures. Then apply the verified Mica facts from `project-constraints.md`.

Do not claim the current repository already has Sparkle or a working DMG release pipeline. Add release dependencies/configuration only in a dedicated task with explicit owner decisions and validation.
