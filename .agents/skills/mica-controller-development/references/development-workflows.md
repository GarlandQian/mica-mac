# Mica Development Workflows

## Contents

- [Before editing](#before-editing)
- [Add a controller family](#add-a-controller-family)
- [Add or change an API](#add-or-change-an-api)
- [Add an AppModel operation](#add-an-appmodel-operation)
- [Add a Workbench page or surface](#add-a-workbench-page-or-surface)
- [Change persistence or authentication](#change-persistence-or-authentication)
- [Localization](#localization)
- [Tests and validation](#tests-and-validation)
- [Release-related changes](#release-related-changes)

## Before Editing

1. Read `AGENTS.md`.
2. Run the Trellis pre-development flow and read the active task `prd.md`, `design.md`, and `implement.md` when present.
3. Read the active spec matching the layer:
   - controller decoding/API: `.trellis/spec/backend/controller-data-contract.md`;
   - selected session/profile transaction: `.trellis/spec/frontend/live-session-controller-contract.md`;
   - visible workbench/navigation/design: `.trellis/spec/frontend/workbench-ui-contract.md`.
4. Inspect `git status --short`; preserve unrelated user changes.
5. Search with `rg` for the action, model, localization key, capability, and verifier assertion before changing it.
6. Trace the cross-layer path described in `SKILL.md`; do not stop at a client method or a visible button.

## Add A Controller Family

Follow this order. An enum case remains capability-only until the complete transport, state, operation, presentation, and test path exists.

1. Add or update persisted identity in `Sources/MicaCore/Models/RouterProfile.swift`:
   - `ControllerKind` case, decode compatibility, label/badge;
   - any family-specific profile fields only when actually needed.
2. Add neutral identity and boundary text in `UnifiedControllerModels.swift`:
   - `UnifiedControllerType` mapping;
   - adapter source and boundary summary;
   - granular `ControllerCapabilities`.
3. Implement transport and response models under `Sources/MicaCore/API/` and `Sources/MicaCore/Models/`.
4. Implement a real `ControllerAdapterProtocol` adapter and register it in `UnifiedControllerAdapterRegistry.makeAdapter`.
5. Update AppModel runtime resolution:
   - effective kind/type/capabilities;
   - Auto Detect probe only if a side-effect-free identifying endpoint exists;
   - session refresh lanes and streams/polling;
   - generation validation and cancellation.
6. Add backend-specific projection into Dashboard/workbench state without flattening away needed fields.
7. Gate every menu, toolbar, Actions, table, and inspector control through the effective capability.
8. Extend controller editor choices and all English/Simplified Chinese copy.
9. Add adapter, capability, protocol, session-switch, and visible-state tests.
10. Update the static source verifier and compatibility documentation only after the implementation exists.

Current concrete families are Mihomo/Nikki/OpenClash, Surge, CMFA, Stash, and sing-box StartedService. The legacy combined Stash/CMFA profile remains probe-only until it resolves a concrete runtime variant. Never infer support from those cases alone; use the runtime capability matrix and backend-specific readiness state.

## Add Or Change An API

1. Add the exact method/path/query shape to `MihomoEndpoint`/`SurgeEndpoint`, or update the checked-in StartedService proto/generated adapter boundary for sing-box.
2. Add request/response DTOs in the matching MicaCore model file.
3. Preserve optional and unknown controller fields where the active UI must expose them.
4. Add the client method with existing authentication, status validation, empty-body, malformed-response, TLS, and cancellation behavior.
5. Add or update a `UnifiedControllerAction` and granular capability only if the operation is actually available for that backend.
6. Add the AppModel operation or session producer; do not call the client from a view.
7. Re-read authoritative controller state after a mutation when the endpoint contract supports it.
8. Add presentation projection and UI only after the state path exists.
9. Add localization, help, accessibility labels, and inline error/partial state.
10. Test the exact request method/path/query/header/body or gRPC metadata/message/stream behavior and decoder variants. Use injected URL loading or gRPC in-process transports; never require a live controller.

For ordered JSON objects such as Mihomo proxies/providers, use the existing order-preserving decode path rather than a generic `request<T>` helper.

## Add An AppModel Operation

Use existing operation files by domain (`AppModelSurgeOperations`, `AppModelRuntimeOperations`, `AppModelConfigurationOperations`, or a focused new extension file).

Checklist:

1. Add a specific `TrialCommandAction` and localized title if command history needs to expose it.
2. Add a task slot and observable busy marker only when an existing slot cannot represent ownership safely.
3. Include the marker in `isBusy`, cancellation, controller reset, and transaction/session tests.
4. Guard selected controller, presentation pause rules, and effective capability.
5. Capture previous state for optimistic operations.
6. Capture `router.id` and `controllerSession.generation` before starting the task.
7. Validate generation after every await that precedes a publish.
8. On success, refresh/cache authoritative data and finish the command.
9. On refresh-after-write failure, report partial success without rolling back a confirmed write.
10. On write failure, roll back optimistic state and publish a categorized error.

Never let an old controller task clear the new controller's busy marker or state.

## Add A Workbench Page Or Surface

1. Decide whether the feature belongs in an existing destination. New top-level pages require evidence that the eleven-destination information architecture is insufficient.
2. For a real new destination, update `WorkbenchDestination` completely:
   - case, fixed group/order, title key, symbol, search behavior, controller requirement;
   - shortcut/menu behavior only when intended;
   - migration behavior if persisted navigation changes.
3. Route the page in `WorkbenchRootView` and sidebar sections.
4. Keep network/state ownership in AppModel and pure projection helpers under `Features/Workbench`.
5. Use native SwiftUI `Table`, `Form`, `Section`, `LabeledContent`, `ContentUnavailableView`, toolbar, and `.inspector` patterns already present.
6. Keep ordinary workflows in the main window; reserve confirmation for destructive/high-risk actions.
7. Preserve complete business text, controller ordering, localized empty/no-match/stale/unsupported states, keyboard access, help, and accessibility labels.
8. Apply project preference environments and font multiplier to explicit layout metrics.
9. Add presentation/layout tests and source-verifier assertions for durable navigation or UI rules.
10. Run HIG contrast/tap-target checks for measurable UI changes.

Do not add an AppKit content view, local decoder, view-owned network task, second navigation abstraction, command home, or compatibility wrapper for removed workbench concepts.

## Change Persistence Or Authentication

1. Update the protocol (`RouterProfileStore` or `SecretStore`) only when every implementation and test seam can follow it.
2. Keep credentials out of `RouterProfile` and `routers.json`; retain only `secretReference`.
3. Preserve save/delete transaction order:
   - write/remove credential;
   - persist the complete next profile array;
   - roll back credential on profile-store failure;
   - mutate observable arrays/session only after persistence succeeds.
4. Active-profile edits replace the live generation after commit. Non-active edits/inserts do not steal the session.
5. Active deletion selects the next item at the old index, otherwise the previous item.
6. Inject in-memory or failing actor stores in tests; do not use real user Application Support or Keychain state in unit tests.

## Localization

- Add visible copy to `Sources/Mica/Resources/Localizable.xcstrings` for both `en` and `zh-Hans`.
- Resolve dynamic keys through `MicaStrings`/`XCStringsResolver`; SwiftPM ships the catalog as a runtime JSON resource.
- Relocalize cached operation, snapshot, health, live-session, and command strings when language changes.
- Keep protocol/controller names verbatim when they are reported business values; localize UI labels and states around them.
- Validate the catalog as JSON after edits.

## Tests And Validation

Keep disposable output in `tmp/codex/`.

Fast source checks:

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
git diff --check
```

Swift package checks:

```bash
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
```

Focused test iteration:

```bash
swift test --scratch-path tmp/codex/swift-build --filter MihomoModelsTests
swift test --scratch-path tmp/codex/swift-build --filter SurgeHttpAPIClientTests
swift test --scratch-path tmp/codex/swift-build --filter SingBoxGRPCClientTests
swift test --scratch-path tmp/codex/swift-build --filter LiveSessionTransactionTests
swift test --scratch-path tmp/codex/swift-build --filter WorkbenchPresentationTests
```

Generated Xcode workspace checks, when `.swiftpm/xcode/package.xcworkspace` exists:

```bash
xcodebuild -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme Mica -destination platform=macOS \
  -derivedDataPath tmp/codex/xcode-derived build
xcodebuild -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme Mica -destination platform=macOS \
  -derivedDataPath tmp/codex/xcode-derived test
```

Measurable UI audit:

```bash
python3 .agents/skills/apple-hig-expert/scripts/hig_checker.py \
  batch tmp/codex/hig-audit.json
```

`scripts/verify-runtime-smoke.mjs` is optional and must run only when the user/task explicitly permits it. It must never contact a controller or trigger remote actions. The current GitHub Actions workflow runs `swift test` then `swift build` on `macos-15`; it does not package or release the app.

## Release-Related Changes

Load the global `macos-auto-update` or `macos-release` skill for generic Sparkle, signing, notarization, DMG, and appcast procedures. Then apply the verified Mica facts from `project-constraints.md`.

Do not claim the current repository already has Sparkle or a working DMG release pipeline. Add release dependencies/configuration only in a dedicated task with explicit owner decisions and validation.
