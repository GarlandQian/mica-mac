# Cross-Layer Thinking Guide

Most Mica defects occur when controller truth changes meaning between layers.
Map the complete path before changing a field, command, stream, or visible
state:

```
controller wire data -> typed decoder/adapter -> generation-owned session runtime
  -> published presentation snapshot/catalog -> projection/cache -> SwiftUI view
```

Commands travel the reverse direction through the same capability and
generation gates. A view is the final renderer, not a second data contract.

## Boundary Questions

| Boundary | Check |
|---|---|
| Wire data -> DTO | Are required and optional fields decoded without sorting, dropping, or fabricating values? |
| DTO -> adapter | Does the runtime variant retain its backend-specific fields and capability matrix? |
| Adapter -> live session | Is controller ID, session generation, cancellation, and revision preserved? |
| Runtime -> presentation | Does publication use the correct cadence and retain stale/error state truthfully? |
| Presentation -> projection/cache | Are order, semantic units, source identity, and invalidation rules preserved? |
| Projection -> SwiftUI | Does the view use the shared primitive, localization, accessibility value, and correct empty state? |

## Required Checks

### Controller truth

- Preserve controller-reported collection order and optionality. Filter or sort
  only a presentation copy, and document the owner of that transformation.
- Keep read and mutation capabilities separate. A readable or testable item is
  not automatically selectable or mutable.
- Validate endpoints, IDs, and required fields at the boundary before transport
  work. Propagate `CancellationError`; do not turn cancellation into an empty
  or unavailable response.
- Keep credentials, authorization values, subscription URLs, Keychain data,
  and raw response/stream bodies out of exports and diagnostics.

### Session and publication

- Every asynchronous apply validates the controller ID and live-session
  generation before mutating observable state.
- Trace the revision that drives the visible event. Structure revisions must
  not substitute for traffic, metric, log, or timeline revisions.
- Preserve cadence and stale markers. Hidden domains may defer publication,
  but resume must catch up to the latest real frame without fake samples.
- Check that timeline values retain their semantic unit: rates, cumulative
  totals, counts, and timestamps are not interchangeable merely because they
  share a primitive type.

### Presentation and UI

- Pure projections own filtering, indexing, field grouping, and derived labels;
  SwiftUI bodies consume those models instead of parsing raw payloads.
- Use `MicaTheme` and shared Workbench primitives. Keep visible copy localized
  in English and Simplified Chinese and expose numeric/tabular fallbacks for
  charts and topology.
- Distinguish unloaded, empty, filtered-empty, unsupported, stale, and failed
  states. Do not fabricate chart points, rows, latency, or controller fields.
- Route detail through the workspace inspector and keep commands in the shared
  capability path. Do not create a page-level inspector or a second action
  owner.

## Before and After Checklist

Before implementation:

- [ ] Mapped the complete wire-to-view data path and command path.
- [ ] Identified each layer's input/output format and validation owner.
- [ ] Recorded capability, order, optionality, cancellation, and revision rules.

After implementation:

- [ ] Traced one real fixture through decoding, runtime publication, projection,
      cache invalidation, and the final visible value.
- [ ] Covered empty, missing, invalid, stale, cancelled, and unsupported cases.
- [ ] Confirmed async results cannot cross controller or generation boundaries.
- [ ] Confirmed consumers use shared decoders/projections instead of local casts.
- [ ] Confirmed localization, accessibility, export privacy, and offline tests.
