# Controller Data Model

## Truthful Availability

Controller fields are optional when the backend does not report them. Presentation code renders a localized unavailable/not-reported state; it must not invent counts, delays, hit rates, connection rows, chart samples, labels, or fallback node names.

Active controller workspaces display reported business data in full, including endpoint/host, request URL, connection ID, process and address fields, provider/source name, policy and node name, rule payload, route chain, and raw log message. Export/copy paths exclude credentials, authorization headers, subscription URLs, Keychain data, raw response bodies, and raw stream bodies.

## Policy-Group Ordering

Mihomo `/proxies` is a JSON object whose key order is the controller's presentation order. `ProxiesResponse.decodePreservingProxyOrder(from:decoder:)` captures that source order before dictionary storage loses it. `policyGroups` then filters the ordered sequence to entries with members and never sorts it. The `GLOBAL.all` array is data for that group, not permission to reorder peer groups.

Policy-group filters only change visibility. Expand/collapse, refresh, node selection, latency tests, pagination, and tab changes must preserve group IDs and source order. Candidate nodes preserve the controller's `all` array order.

Surge policy arrays and sing-box group/item streams also preserve their reported order. `GLOBAL` is changed only by the Workbench presentation rule: when visible, it is stable-partitioned last without changing the relative order of peer groups.

## Activity And Resource Ordering

Connections, logs, and rules retain the array order supplied to the presentation layer. Search and level/category filters only remove nonmatching rows. Duplicate rule identities receive occurrence-qualified view IDs without changing order or payload. Source rows are not sorted in the UI; where an upstream dictionary has already lost controller order, Mica does not claim that the remaining order is a remote business contract.

## Primary Objects

- Overview: current traffic sample, totals, connection count, memory/runtime, version, mode, and endpoint health.
- Policy Groups: name, type, current selection, ordered members, delay, selected/fixed state, and reported hidden state.
- Connections: full ID, host, network/type, process/path, source/destination, inbound, DNS/sniff fields, rule/payload, chain, totals, speed, and start time when reported.
- Rules: payload first, then type, proxy/outbound, extra fields, disabled state, and real hit/miss/size fields when supported.
- Sources: proxy sources and rule sets with name, kind, type, vehicle, behavior/format, item count, update time, and update capability.
- Logs: timestamp, level, and original controller message.
- sing-box Tailscale: endpoint state, auth URL, network/MagicDNS state, self, users, peers, current exit node, counters, and reported peer metadata.

## Capability Gating

Unsupported data and actions stay unavailable rather than appearing as disabled imitations of another backend. A resolved sing-box StartedService session exposes Tailscale in the Configuration surface; its failed/partial state is independent from the rest of the live session. Capability flags for readable logs, remote log-level change, fixed-selection cancellation, provider update/health check, and runtime writes remain separate.
