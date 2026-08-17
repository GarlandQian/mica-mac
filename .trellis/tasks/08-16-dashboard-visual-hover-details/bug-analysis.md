# Bug Analysis: Overview Liveness And Truncated Policy HUD

## 1. Root Cause Category

- **Category**: B — Cross-Layer Contract
- **Specific cause**: Overview rate-labelled readouts consumed
  `ConnectionsCatalogSnapshot.traffic`, whose Mihomo/sing-box values are
  connection aggregates/cumulative totals, rather than the latest received
  traffic-rate sample. Surge near-live ticks updated the generation-owned raw
  snapshot but called the visible publisher with `domains: []`, so the visible
  timelines and catalog could remain on an older frame.
- **Category**: C — Change Propagation Failure
- **Specific cause**: Topology energy was triggered only by the structure
  revision. Traffic and metric frames intentionally avoided rebuilding topology
  structure, but no separate live signal reached the energy layer.
- **Category**: D — Test Coverage Gap
- **Specific cause**: Existing tests independently verified publication cadence,
  timeline projection, topology invalidation, and HUD placement. They did not
  assert the complete source-to-visible path for a current Surge frame or verify
  that hover and pinned HUD states exposed the same uncapped fields.
- **Category**: E — Implicit Assumption
- **Specific cause**: The implementation treated “pinned expands” as permission
  to hide actual node fields during hover, and encoded a three-field metadata cap
  even though the user asked to inspect the node's field composition on hover.

## 2. Why The Previous Verification Missed It

1. **Component-only verification**: Timeline caches and actor publications passed
   in isolation, but the final visible readout source and Surge publication
   domain were not asserted together.
2. **Wrong source contract**: The source verifier required compact hover fields
   and expanded pinned fields, so it enforced the implementation mismatch rather
   than the user outcome.
3. **Revision mental model**: Structure revision was correctly used to protect
   topology layout performance, then incorrectly reused as the only trigger for
   live route energy.
4. **Semantic primitive collision**: Rates and cumulative totals are both
   integers; review checked type compatibility without checking unit/cadence.

## 3. Prevention Mechanisms

| Priority | Mechanism | Specific action | Status |
|---|---|---|---|
| P0 | Architecture | Current Overview values read latest published timeline samples; plot caches own history only | DONE |
| P0 | Architecture | Surge near-live publishes `.connections` and advances visible rate/count/timestamp state together | DONE |
| P0 | Test coverage | Added Surge source-to-visible publication regression | DONE |
| P0 | Test coverage | Added cache replacement test for reused IDs with new receipt times | DONE |
| P0 | Test coverage | Hover HUD test now requires complete sections, false transport states, and all additional fields | DONE |
| P1 | Source contract | Reject cumulative connection totals in rate-labelled Overview readouts | DONE |
| P1 | Source contract | Require topology energy to consume structure plus traffic/metrics live signal | DONE |
| P1 | Documentation | Added unit/revision/source-event checks to the cross-layer guide and live-session/UI specs | DONE |

## 4. Systematic Expansion

- **Similar issues checked**: Searched all rate formatters and upload/download
  labels. Connection-table speed fields already use explicit per-row speed
  values; the incorrect cumulative-total formatting was isolated to the Overview
  instrument rail.
- **Controller families**: Mihomo-family and sing-box actor publications already
  advance their visible timelines. Surge needed the explicit near-live
  `.connections` publication fixed here.
- **Design improvement**: Keep structure, metrics, traffic, and interaction
  triggers separate. Performance isolation must not remove factual liveness.
- **Process improvement**: For monitoring UI, every audit must trace one real
  frame through ingestion → published AppModel state → cache → visible value and
  verify semantic units, not only type shape.

## 5. Knowledge Capture

- [x] Updated `.trellis/spec/frontend/live-session-controller-contract.md`.
- [x] Updated `.trellis/spec/frontend/workbench-ui-contract.md`.
- [x] Updated `.trellis/spec/guides/cross-layer-thinking-guide.md`.
- [x] Updated durable UI guidance and the active task PRD/design.
- [x] Updated executable source-verifier assertions.
- [ ] Commit remains a user-controlled workflow step; no commit or push was
      performed by this regression fix.
