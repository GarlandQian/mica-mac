# Controller Data Contract

## 1. Scope / Trigger

Use this contract whenever a controller response is decoded, normalized, or projected into a Workbench snapshot. It prevents dictionary iteration, fabricated fallbacks, and backend-specific assumptions from changing visible controller truth.

## 2. Signatures

```swift
public static func ProxiesResponse.decodePreservingProxyOrder(
    from data: Data,
    decoder: JSONDecoder = JSONDecoder()
) throws -> ProxiesResponse

public func MihomoClient.proxies() async throws -> ProxiesResponse
```

`MihomoClient.proxies()` must call `decodePreservingProxyOrder`; it must not decode `/proxies` through a generic request helper.

## 3. Contracts

- `proxyOrder` is the source JSON key order from the `/proxies` object.
- `policyGroups` filters `proxyOrder` to snapshots whose `all` array is non-empty.
- `policyGroups` remains a wire-order DTO projection and never sorts by name or `GLOBAL.all`.
- The Mihomo DTO-to-Dashboard conversion uses exact group names in `GLOBAL.all`
  as configuration order. Listed ordinary groups come first in that order;
  unlisted groups retain their relative `proxyOrder`; `GLOBAL` comes last.
- Generic Workbench presentation does not re-rank the converted catalog.
- Node options preserve each group's `all` array order.
- `ProxySnapshot.hidden` preserves the controller-reported hidden flag.
- Missing optional fields remain `nil`; presentation chooses localized unavailable copy.
- Proxy provider `testURL` and `subscriptionInfo` survive DTO-to-dashboard
  projection. They are visible controller business metadata and must not be
  dropped from the active Sources inspector.
- Active UI may show full controller business data. Export code excludes credentials and raw response/stream bodies.
- Surge policy/request arrays and sing-box group/item/event streams preserve their reported order and backend-specific fields until presentation projection.
- A concrete runtime variant owns its capability matrix. A CMFA or Stash snapshot must not inherit the full Mihomo matrix merely because it shares the transport client.
- Read capability and mutation capability stay separate, including logs vs remote log-level change and policy groups vs fixed-selection cancellation.
- A policy group reporting `selectable == false` is readable/testable data, not
  permission to issue a selection mutation.
- Connection delete endpoints require a non-blank reported ID. Reject blank IDs
  before URL construction or transport dispatch.
- Backend/controller capabilities may add a mature Swift package when it materially improves protocol correctness, security, performance, or maintenance. The package boundary must remain typed, capability-gated, cancellable, and generation-safe; macOS 27/Swift 6.2 support, maintenance, license, transitive cost, and tests are required before adoption.

## 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Empty response body | Throw `MihomoClientError.emptyResponse`. |
| Invalid controller JSON | Throw `MihomoClientError.malformedResponse("/proxies")`. |
| Valid JSON with escaped/Unicode keys | Decode the names and preserve their source order. |
| Non-group proxy entry | Keep it in `proxies`; omit it from `policyGroups`. |
| `GLOBAL.all` order differs from object order | Keep the DTO in `proxyOrder`; arrange Mihomo Dashboard groups by matching names in `GLOBAL.all`, then append unlisted groups in `proxyOrder` and `GLOBAL` last. |
| CMFA/Stash uses Mihomo-compatible DTOs | Project the resolved CMFA/Stash capability matrix, not `.mihomoCompatible`. |
| sing-box reports groups/items/events | Preserve protobuf stream order; do not synthesize fixed selection, rules, or providers. |
| sing-box reports a trace log | Preserve the `trace` level; do not collapse it into `debug`. |
| A group reports `selectable: false` | Preserve members and test data; reject node-selection writes. |
| A connection ID is blank | Keep the row visible, but reject deletion before any request is sent. |

## 5. Good / Base / Bad Cases

- Good: `/proxies` contains emoji or escaped names; `proxyOrder` and
  `policyGroups` preserve the wire sequence, while Mihomo Dashboard groups use
  the controller-reported `GLOBAL.all` configuration order and keep unlisted
  groups stable.
- Base: direct/non-group entries remain addressable in `proxies` but do not become policy-group blocks.
- Bad: sorting by dictionary/name/latency, dropping unlisted groups, changing
  member `all` order, or applying Mihomo `GLOBAL` semantics to other backends.

## 6. Tests Required

- Assert raw controller order survives refresh decoding.
- Assert Mihomo Dashboard groups follow matching names in `GLOBAL.all`, with
  unlisted groups retaining `proxyOrder` and visible `GLOBAL` last.
- Assert escaped quotes and surrogate-pair Unicode keys preserve order.
- Assert hidden state and node array order survive decoding.
- Assert each group's candidate nodes remain in its reported `all` order.
- Assert malformed and empty responses use the client error boundary.
- Assert resolved CMFA/Stash snapshots retain their variant capabilities.
- Assert sing-box group/node ordering and unsupported fixed-selection capability.
- Assert provider test URL/subscription metadata and sing-box trace survive
  their DTO-to-presentation boundaries.
- Assert read-only groups cannot start selection writes and blank connection IDs
  cannot reach the HTTP transport.

## 7. Wrong vs Correct

```swift
// Wrong: alphabetically sorting the DTO destroys controller truth.
proxies.values.filter { !$0.all.isEmpty }.sorted { $0.name < $1.name }

// Correct DTO boundary: preserve object order.
proxyOrder.compactMap { name in
    guard let proxy = proxies[name], !proxy.all.isEmpty else { return nil }
    return proxy
}

// Correct generic presentation boundary: consume the backend-specific catalog
// order and place GLOBAL last when visible.
ProxyProjection.arrangedGroups(groups, mode: mode, visibility: visibility)
```
