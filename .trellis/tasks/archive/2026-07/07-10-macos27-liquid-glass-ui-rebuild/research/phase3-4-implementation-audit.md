# Phase 3-4 Implementation Audit

## Scope completed

- Overview now records a maximum of 60 real received traffic samples in an application-layer `TrafficTimeline`. It resets when live observation starts or stops and when the controller changes. The chart is linear and appears only when that timeline contains genuine samples.
- Proxies now separates fixed-order glass policy selection from a same-window, high-readability detail layer. Search filters visible selectors only; selection reconciliation always uses the full `dashboard.groups` snapshot.
- Policy and member labels wrap and remain selectable. The member layer does not use glass, and Mihomo/Surge selection, group latency tests, and pagination remain inline and capability-gated. Fixed-selection cancellation is omitted until a controller exposes a real state and action.

## Durable-document decision

No additional durable-document change was required for this vertical slice. The existing `.trellis/spec/frontend/workbench-ui-contract.md` already states the five-area navigation, policy ordering, full-visible data, selector-only Liquid Glass, preference, and verifier contracts implemented here. The source verifier was updated to make the real timeline and selection-identity requirements executable.

## Verification

- `node --check scripts/verify-real-controller-source.mjs`
- `node --check scripts/verify-runtime-smoke.mjs`
- `node scripts/verify-real-controller-source.mjs`
- `swift build --scratch-path tmp/codex/build-phase34`
- `swift test --scratch-path tmp/codex/test-phase34`
- `node scripts/verify-runtime-smoke.mjs tmp/codex/build-phase34/debug/Mica`
