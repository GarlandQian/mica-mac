# Code Reuse Thinking Guide

Reuse in Mica is about preserving one owner for behavior, not about forcing
unrelated controller families into one abstraction. Before adding code, search
the current source and active contracts with `rg`, then identify the existing
owner and its tests.

## Search First

Search for the business field, capability, command, presentation type, and
localization key you intend to change. Follow the data from its controller
adapter through the session runtime and projection before choosing a file.

```bash
rg "existingName|capability|controllerField" Sources Tests .trellis/spec
```

Ask:

- Does a typed adapter or client already own this controller behavior?
- Does `AppModel` or the generation-owned runtime already own this command?
- Does a projection or cache already provide the row, timeline, or catalog?
- Does `MicaTheme` or `MicaThemeComponents` already provide the visual primitive?
- Does a formatter or localization key already express the visible value?

## Reuse Boundaries

- Extend the owning typed controller adapter when transport or backend fields
  change. Do not duplicate endpoint parsing in a view or merge distinct
  capability matrices merely because transports look similar.
- Keep session mutation in `AppModel`/`LiveSessionRuntime` with controller ID
  and generation validation. Views request capability-gated operations; they do
  not mutate published collections.
- Reuse pure presentation projections and bounded indexes for tables, policy
  groups, topology inspection, and timeline readouts. A view may format an
  already projected value, but it must not recreate business rules in `body`.
- Compose existing Mica Ops tokens and Workbench primitives. A new control is
  justified only when no existing primitive expresses the interaction and the
  new ownership is clear.
- Reuse established formatters and localized strings. Keep endpoints, IDs,
  payloads, and protocol values monospaced, and render missing controller
  fields as localized unavailable values rather than invented defaults.

## Do Not Abstract Prematurely

Do not create an abstraction for a one-off, trivial value or a pair of similar
lines. Do create one when the logic is complex, appears in multiple owners, or
would otherwise allow controller semantics to drift. Backend-specific order,
optionality, cancellation, and capability behavior are meaningful differences,
not duplication to erase.

## Batch-Change Checklist

- [ ] Searched all current owners and related tests before editing.
- [ ] Kept one typed decoder/projection/formatter owner for repeated behavior.
- [ ] Reused the shared command capability and generation validation path.
- [ ] Reused MicaTheme, Workbench primitives, and existing localization.
- [ ] Preserved controller order, optionality, backend fields, and semantics.
- [ ] Checked every affected consumer after the change and ran offline tests.
