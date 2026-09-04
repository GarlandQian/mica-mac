# Live Command Scope Contract

## 1. Scope / Trigger

Apply this contract to a SwiftUI `Binding`, inspector control, accessibility
action, staged confirmation, or other handler that can survive the render event
where it obtained an editable value or controller entity. Such a handler must
prove that its originating controller generation is still current before it
changes local workspace state or invokes AppModel command work.

Immediate Test and Refresh commands are deliberate exceptions: they carry no
old business entity or edit value, and activation means operate the controller
selected at click time. Do not capture render-generation scope for them.

## 2. Signatures

```swift
struct LiveCommandScope: Equatable, Sendable {
    let controllerID: RouterProfile.ID
    let generation: UUID
}

func matchesCurrentCommandScope(_ scope: LiveCommandScope) -> Bool
func updateControllerConfig(_ mutation: ControllerConfigMutation, scope: LiveCommandScope)
func setMode(_ mode: String, scope: LiveCommandScope)
func setControllerLogLevel(_ level: LogSessionLevel, scope: LiveCommandScope)
func selectNode(_ node: String, in groupID: String, scope: LiveCommandScope)
func clearFixedSelection(in groupID: String, scope: LiveCommandScope)
func measureDelay(in groupID: String, scope: LiveCommandScope)
func measureDelay(for node: String, in groupID: String, scope: LiveCommandScope)
func setRuleDisabled(_ rule: RuleViewState, disabled: Bool, scope: LiveCommandScope)
func selectSurgePolicy(_ policy: String, in group: String, scope: LiveCommandScope)
func testSurgePolicyGroup(_ group: String, scope: LiveCommandScope)
```

## 3. Contracts

- Capture `LiveCommandScope` from the originating view/payload's selected
  controller ID and presentation generation. The retained closure passes that
  value unchanged; it must not reconstruct scope from AppModel when invoked.
- `matchesCurrentCommandScope` requires the selected ID, presentation ID and
  generation, and raw `ControllerSession` ID and generation all to match.
- Scope validation is the first command/page-dispatch guard. On mismatch, return
  silently before changing a workspace selection, local editor value, command
  history, operation outcome, owner marker, optimistic snapshot, task, stream,
  or client.
- AppModel APIs listed above require scope with no default and no unscoped
  overload. After identity admission they still enforce readiness, pause,
  capability, owner, and exact-current-target rules.
- Rules/Table AX and Proxy AX carry their payload's scope. Proxy group toggle,
  Locate Current, group/member tests, fixed-selection clear, and member
  selection all preserve that same identity, including purely local workspace
  effects.
- Existing typed delayed intents for Connections, Actions, and Tailscale may
  synchronously revalidate their captured ID/generation immediately before a
  non-suspending AppModel call. There may be no `await` or current-identity
  substitution between validation and command entry.
- `testSelectedRouter()` and `refreshSelectedRouter()` resolve the current
  selected controller on activation. Their safety comes from current readiness,
  capability, and owner-token admission rather than a retained render scope.

## 4. Validation & Error Matrix

| Input or event | Required result |
| --- | --- |
| Scope matches selected, presentation, and raw session identity | Continue to readiness/capability/owner/target validation |
| Same controller ID, older generation | Silent rejection with zero local or remote side effects |
| Different controller ID | Silent rejection with zero local or remote side effects |
| Scope current but session is connecting/reconnecting | Reject before task/client; current command gate may publish its defined unavailable outcome |
| Scope current but command family already owns work | Preserve the existing task/token/marker; do not cancel or replace it |
| Scope current but rule/group/member no longer resolves exactly | Reject stale target; do not reuse a raw index or first matching ID |
| Old Proxy AX tree requests toggle or Locate Current | Do not mutate the replacement generation's workspace |
| User activates Test/Refresh after generation replacement | Operate the currently selected session subject to its shared gate |

## 5. Good / Base / Bad Cases

- Good: a generation-A Rules named action fires after same-controller
  generation B starts; AppModel receives A's scope and performs no mutation.
- Good: a current Surge Logs Picker passes current scope, then the ordinary
  capability/owner path changes the remote log level.
- Base: a toolbar Refresh after reconnection targets the current session and
  joins the shared refresh coordinator without a captured scope.
- Bad: a Binding reads `controllerSessionPresentation.generation` inside its
  setter and thereby relabels an old value as a generation-B intent.
- Bad: an old Proxy AX group action changes B's disclosure/selection because it
  was considered local and skipped scope validation.

## 6. Tests Required

- `AppModelCommandBoundaryTests`: capture scope A, begin the same controller as
  generation B with unchanged data, invoke configuration, mode, Rules, proxy,
  ordinary log-level, and Surge log-level intents, then assert no task/marker,
  transport, snapshot, workspace, or operation outcome mutation.
- Owner regressions: duplicate Test, Refresh, configuration, mode, Rules,
  provider, Surge, and runtime intents cannot cancel or clear the current owner.
- Projection/AX tests: stale Table, Proxy group/member, Connections confirmation,
  Actions confirmation, and Tailscale intent identities reject before effects.
- Source verification: every listed AppModel entry requires scope; persistent
  Workbench handlers capture at render/payload construction; Proxy AX carries
  scope through all six effectful callbacks; Test/Refresh remain unscoped.

## 7. Wrong vs Correct

```swift
// Wrong: invocation-time identity turns an old Binding into a current command.
Binding(
    get: { value },
    set: { next in
        let scope = LiveCommandScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
        appModel.updateControllerConfig(.allowLAN(next), scope: scope!)
    }
)

// Correct: retain the identity that rendered the editable value.
let commandScope = LiveCommandScope(
    controllerID: appModel.selectedRouterID,
    generation: appModel.controllerSessionPresentation.generation
)
Binding(
    get: { value },
    set: { next in
        guard let commandScope else { return }
        appModel.updateControllerConfig(.allowLAN(next), scope: commandScope)
    }
)
```

```swift
// Correct AppModel boundary: identity rejection precedes every side effect.
guard matchesCurrentCommandScope(scope),
      task == nil,
      canBeginLiveAction(action, router: router) else { return }
task = Task { /* controller work */ }
```
