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
- `policyGroups` never sorts by name or by `GLOBAL.all` membership.
- Node options preserve each group's `all` array order.
- `ProxySnapshot.hidden` preserves the controller-reported hidden flag.
- Missing optional fields remain `nil`; presentation chooses localized unavailable copy.
- Active UI may show full controller business data. Export code excludes credentials and raw response/stream bodies.
- Surge policy/request arrays and sing-box group/item/event streams preserve their reported order and backend-specific fields until presentation projection.
- A concrete runtime variant owns its capability matrix. A CMFA or Stash snapshot must not inherit the full Mihomo matrix merely because it shares the transport client.
- Read capability and mutation capability stay separate, including logs vs remote log-level change and policy groups vs fixed-selection cancellation.

## 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Empty response body | Throw `MihomoClientError.emptyResponse`. |
| Invalid controller JSON | Throw `MihomoClientError.malformedResponse("/proxies")`. |
| Valid JSON with escaped/Unicode keys | Decode the names and preserve their source order. |
| Non-group proxy entry | Keep it in `proxies`; omit it from `policyGroups`. |
| `GLOBAL.all` order differs from object order | Preserve object order for peer policy groups. |
| CMFA/Stash uses Mihomo-compatible DTOs | Project the resolved CMFA/Stash capability matrix, not `.mihomoCompatible`. |
| sing-box reports groups/items/events | Preserve protobuf stream order; do not synthesize fixed selection, rules, or providers. |

## 5. Good / Base / Bad Cases

- Good: `/proxies` contains emoji or escaped names; `proxyOrder` and `policyGroups` match the source sequence.
- Base: direct/non-group entries remain addressable in `proxies` but do not become policy-group blocks.
- Bad: sorting `proxies.values`, using dictionary order, or reordering groups from `GLOBAL.all`.

## 6. Tests Required

- Assert raw controller order survives refresh decoding.
- Assert `GLOBAL.all` does not reorder peer groups.
- Assert escaped quotes and surrogate-pair Unicode keys preserve order.
- Assert hidden state and node array order survive decoding.
- Assert malformed and empty responses use the client error boundary.
- Assert resolved CMFA/Stash snapshots retain their variant capabilities.
- Assert sing-box group/node ordering and unsupported fixed-selection capability.

## 7. Wrong vs Correct

```swift
// Wrong: dictionary order and alphabetical sort are presentation inventions.
proxies.values.filter { !$0.all.isEmpty }.sorted { $0.name < $1.name }

// Correct: filter the controller sequence without reordering it.
proxyOrder.compactMap { name in
    guard let proxy = proxies[name], !proxy.all.isEmpty else { return nil }
    return proxy
}
```
