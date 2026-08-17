# Controller Data Model

## Truthful Availability

Controller fields are optional when the backend does not report them. Presentation code renders a localized unavailable/not-reported state; it must not invent counts, delays, hit rates, connection rows, chart samples, labels, or fallback node names.

Active controller workspaces display reported business data in full, including endpoint/host, request URL, connection ID, process and address fields, provider/source name, policy and node name, rule payload, route chain, and raw log message. Export/copy paths exclude credentials, authorization headers, subscription URLs, Keychain data, raw response bodies, and raw stream bodies.

## Policy-Group Ordering

Mihomo `/proxies` is a JSON object whose key order is the wire order. `ProxiesResponse.decodePreservingProxyOrder(from:decoder:)` captures it before dictionary storage loses it, and `policyGroups` filters that sequence without mutating the DTO. During Mihomo DTO-to-Dashboard conversion, exact group names listed by `GLOBAL.all` become the ordinary-group configuration order; groups not listed there retain their relative `proxyOrder`, and `GLOBAL` is appended last. This matches the controller-derived ordering used by Zashboard without applying the Mihomo rule to other backends.

Policy-group filters run after arrangement and only change visibility. Opening/closing tabs, refresh, node selection, latency tests, and active-tab changes must preserve group occurrence IDs and arranged order. Candidate nodes preserve the controller's `all` array order. Multiple groups may remain open, but only the active group's virtualized member list is projected and rendered.

Surge policy arrays and sing-box group/item streams preserve their reported order at the transport/model boundary. Presentation keeps that reported order and only moves a visible `GLOBAL` group to the end.

## Activity And Resource Ordering

Connections, logs, rules, and sources retain the array order supplied to the presentation layer. Search and level/category filters only remove nonmatching rows. Native table sorting for Connections, Rules, and Sources operates on copied presentation projections and never mutates those source arrays; Logs never sort. Duplicate rule identities receive occurrence-qualified view IDs without changing order or payload. Where an upstream dictionary has already lost controller order, Mica does not claim that the remaining order is a remote business contract.

## Primary Objects

- Overview: selected controller identity and session health; four current live readouts sourced from the latest received rate/count/memory samples; generation-scoped real traffic, memory, and active-connection timelines; short ordered latency, rule-hit, and active-connection summaries; compact controller/network facts; and a complete topology containing every active connection plus every reported route-chain hop. Connection aggregate totals remain totals and are never relabeled as rates. Missing route metadata remains an explicit unavailable path without fake edges. Retained closed history and full connection fields belong to Connections.
- Policy Groups: name, type, current selection, ordered members, delay, selected/fixed state, reported hidden state, and reported selection capability. Read-only groups remain inspectable/testable but cannot switch nodes.
- Connections: full ID, host, network/type, process/path, source/destination, inbound, DNS/sniff fields, rule/payload, provider/policy chain, totals, speed, start/close time, logs, and structured additional fields when reported. The current-result pulse follows active/closed scope and search filtering; active rows may contribute reported rates, while closed rows contribute historical totals only. Rows without IDs remain visible but cannot be closed; a confirmed close followed by refresh failure remains a partial success.
- Rules: payload first, then type, proxy/outbound, extra fields, disabled state, and real hit/miss/size fields when supported.
- Sources: proxy sources and rule sets with name, kind, type, vehicle, behavior/format, item count, update time, update capability, reported test URL, and subscription metadata. Update All preserves this visible source order, skips read-only entries, and retains per-source outcomes.
- Logs: transport receipt timestamp, exact reported level, and original controller message. Incoming order is preserved in a generation-owned O(1) ring capped at 2,000 entries/8 MiB; sing-box `trace` remains distinct from `debug`.
- Closed connections: current-session receipt records, newest first, capped at 200 rows and 30 minutes. They never contribute to active totals and clear on explicit session end/controller replacement.
- sing-box Tailscale: endpoint state, auth URL, network/MagicDNS state, self, users, peers, current exit node, counters, and reported peer metadata.

## Capability Gating

Unsupported data and actions stay unavailable rather than appearing as disabled imitations of another backend. A resolved sing-box StartedService session exposes Tailscale in the Configuration surface; its failed/partial state is independent from the rest of the live session. Capability flags for readable logs, remote log-level change, fixed-selection cancellation, provider update/health check, and runtime writes remain separate.
