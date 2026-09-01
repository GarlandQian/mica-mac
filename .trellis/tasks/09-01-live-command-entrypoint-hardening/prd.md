# Harden live command entrypoint guards

## Goal

Add defense-in-depth capability, busy, selected-controller, and session-generation validation to AppModel Refresh/Test command entry points, with offline transport-spy tests for stale and non-live callers.

## Requirements

- `AppModel.refreshSelectedRouter()` and `testSelectedRouter()` must revalidate
  their own command boundary instead of relying on the calling view's enabled
  state.
- Validation must use the selected controller ID, current live-session
  controller ID and generation, `allowsLiveCommands`, busy state, and the same
  capability/pause predicates exposed by `canRefreshSelectedRouter` and
  `canTestSelectedRouter`.
- Refresh remains unavailable while dashboard presentation is paused. Testing
  preserves the existing contract that it may remain available while
  presentation is paused when the live-session test gate permits it.
- A controller or generation change before dispatch or during asynchronous
  preparation must reject the stale intent without creating a client,
  transport, task marker, operation result, or mutation against the new
  session.
- UI affordances continue to consume the shared gates; command-boundary checks
  are defense in depth for stale or non-UI callers, not a second policy system.
- Automated coverage must use offline injected clients/transports and must not
  load a user profile, contact a controller, or invoke a remote action.

## Acceptance Criteria

- [ ] AC1: direct Refresh/Test calls with no selected live controller, a
  mismatched controller, or a non-command session state create no client or
  transport work and leave all in-flight markers empty.
- [ ] AC2: busy calls are rejected; paused Refresh is rejected; paused Test
  follows the existing shared test gate.
- [ ] AC3: a controller/generation replacement cannot let an old intent start,
  complete, clear, or overwrite work for the new session.
- [ ] AC4: valid current-generation calls still use the existing controller
  family/capability dispatch and preserve operation reporting.
- [ ] AC5: focused offline tests cover stopped, connecting, stale reconnecting,
  failed, paused, busy, controller mismatch, and generation replacement without
  network access.
- [ ] AC6: source verifier, complete Swift build/tests, localization validation,
  and Trellis validation pass with no compatibility layer or new dependency.

## Notes

- Origin: `09-01-workbench-cross-surface-acceptance` audit F8 residual.
- This is a cross-layer command-safety task. Add `design.md` and
  `implement.md` before starting implementation.
