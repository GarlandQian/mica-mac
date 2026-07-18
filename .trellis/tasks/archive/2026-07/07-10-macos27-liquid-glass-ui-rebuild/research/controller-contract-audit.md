# Controller Contract Audit

## Preserve

- `/proxies` object order and each group's member order; filtering changes visibility only and never sorts.
- Same-window strategy/node selection, latency testing, paging, and capability-gated Mihomo/Surge actions.
- Distinct no-controller, unavailable, empty, filtered-empty, loading, partial, error, live, and paused states.
- Full controller business data in the active UI: endpoints, URLs, IDs, payloads, chains, addresses, source/policy/node names, and log messages.
- Export boundary: credentials, authorization values, subscription URLs, raw response bodies, and raw stream bodies remain excluded.
- English and Simplified Chinese, system/light/dark appearance, four font scales, keyboard commands, help, and accessibility labels.

## Correct During Rebuild

- Strategy and node labels currently middle-truncate; replace with full-width/wrapping/detail presentation.
- Policy groups need an explicit unsupported/unavailable state distinct from an empty supported response.
- Overview counters must check availability before displaying a controller-projected zero.
- Runtime smoke validates metadata but not rendered row visibility or Liquid Glass behavior; add UI-level evidence.
- `verify-real-controller-source.mjs` references an archived task path and status; move durable assertions to spec/docs-backed source checks.
