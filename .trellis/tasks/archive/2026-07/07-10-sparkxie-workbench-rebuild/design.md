# Technical Design: Mica SparkXie Workbench Rewrite

## Design Direction

Treat the current dashboard presentation layer as disposable. Keep only verified controller transport and domain facts that are still useful; rebuild the navigation, tab composition, state presentation, strategy-group interaction, command entry, and visual tokens around the SparkXie data audit.

The product is a native macOS pro-tool workbench: stable sidebar navigation, system toolbar controls, dense readable tables, inline inspectors, and expandable policy-group sections. Liquid Glass is reserved for the navigation and control layers. Data content uses solid, high-contrast surfaces and consistent row geometry.

## Boundaries

- `MicaCore` owns controller requests, decoding, capabilities, and truthful availability.
- `Mica` owns snapshot presentation, filters, stable ordering, tab composition, localization, appearance, font scale, keyboard commands, and accessibility.
- The view layer must not invent fields that are absent from `MicaCore` responses.
- Existing old dashboard/deck/chart/command abstractions are not compatibility boundaries. Replace or delete them when they conflict with the new information architecture.

## Information Architecture

1. Overview: controller identity, current health, last update, real speed/totals, connections, memory/runtime, version and endpoint status.
2. Policy Groups: stable ordered expandable sections with current selection and inline candidate selection.
3. Connections: current connections, process/rule/chain inspection, and real traffic counters.
4. Rules: payload-first table with type, target/outbound, and only adapter-supported auxiliary fields.
5. Sources: proxy sources and rule sets using real provider/source fields.
6. Logs: level/timestamp/message rows with real filter and pause/follow behavior.
7. Core Config: real mode and writable configuration fields reported by the adapter.
8. Core Actions: capability-gated reload/update/restart/cache actions with risk confirmation.
9. Tailscale: conditional sing-box Tailscale state and actions when supported.
10. Diagnostics: controller capabilities, request status, errors, availability and export boundary.
11. Settings: language, appearance, font scale, endpoint profiles, and app preferences only.

## State and Ordering

- Every tab has an explicit loading, loaded, unavailable, empty, filtered-empty, and error state.
- Stable ordering is a data contract. Store the server sequence or stable ID order; user filtering must not mutate the source order.
- Search/filter pipelines are explicit: select category, filter real fields, apply stable sort only when requested, then paginate.
- Strategy-group selection is an inline state transition in the same window. No ordinary modal presentation.
- Policy-group order is immutable from the UI perspective: filtering changes visibility only; no view-level sort or refresh-side reorder is allowed.
- Settings changes are injected at the root so localization, appearance and font scale invalidate every tab immediately.

## Data and Privacy

- Active UI displays full controller business data when present, including endpoint/host, request URL, IDs, provider/node/policy names, payloads, chains, and log messages.
- Export/copy code excludes credentials and unsafe raw payloads only.
- Unknown or unavailable values use a localized unavailable state and are never replaced with zero, sample, placeholder, or inferred values.

## Visual System

- Apply `design-taste-frontend` anti-slop checks before each surface is finalized.
- Use the fixed Rose Pine Dawn-Main token palette from `AGENTS.md`: background `#FAF4ED` / `#191724`, grouped surfaces `#FFFAF3` / `#1F1D2E`, secondary grouped surfaces `#F2E9E1` / `#26233A`, tertiary grouped surfaces `#DFDAD9` / `#403D52`, accent `#907AA9` / `#C4A7E7`, plus the semantic red/orange/blue/teal pairs recorded there. Do not create an alternate palette.
- Use restrained accent use, semantic status colors, and a single radius scale. Run a contrast check on content tables and controls in both appearances.
- Use SF Symbols from one consistent family and native macOS controls where possible.
- Keep cards for true repeated objects such as policy groups; avoid cards nested inside cards and decorative glass content containers.

## Migration Strategy

This is a replacement migration inside the existing repository, not a compatibility migration. Implement tab by tab behind the new root composition, then remove obsolete presentation files and localization keys once no call sites remain. Do not add wrappers solely to preserve old names.

## Operational Constraints

- Do not download, bundle, start, or run a real core.
- Do not modify system proxy, firewall, OpenWrt/LuCI, SSH, ubus, or unrelated environment settings.
- Keep scratch output in `tmp/codex/` and remove disposable artifacts after validation.
