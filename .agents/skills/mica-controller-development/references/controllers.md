# Controllers And Data Boundaries

## Contents

- [Controller identity](#controller-identity)
- [Implemented capability matrix](#implemented-capability-matrix)
- [Connection and authentication](#connection-and-authentication)
- [Protocol surfaces](#protocol-surfaces)
- [Errors and retries](#errors-and-retries)
- [DTO and domain conversion](#dto-and-domain-conversion)
- [Session publication](#session-publication)

## Controller Identity

`RouterProfile.controllerKind` is the persisted user/configuration choice. `UnifiedControllerType` is the controller-neutral type used by adapters, capability reporting, diagnostics, and UI gating.

Current mapping:

| `ControllerKind` | `UnifiedControllerType` | Runtime status |
|---|---|---|
| `mihomoCompatible` | `mihomoCompatible` | Implemented. |
| `nikkiMihomoCompatible` | `nikkiMihomoCompatible` | Implemented through the Mihomo-compatible adapter/API boundary. |
| `openClashMihomoCompatible` | `openClashMihomoCompatible` | Implemented through the Mihomo-compatible adapter/API boundary; no LuCI/SSH/ubus management. |
| `surgeCompatible` | `surgeHTTPAPI` | Implemented through Surge HTTP API. |
| `autoDetect` | `smartProbe` until resolved | Probe-only persisted kind; selected session records a separate detected runtime kind. |
| `singBoxCompatible` | `singBoxCompatible` | Implemented through native Swift StartedService gRPC. |
| `cmfaCompatible` | `cmfaCompatible` | Implemented through the Clash-compatible HTTP/WebSocket boundary with CMFA-specific capabilities. |
| `stashCompatible` | `stashCompatible` | Implemented through the Clash-compatible HTTP/WebSocket boundary with Stash-specific capabilities and latency fallback. |
| `stashCmfaCompatible` | `stashCmfaCompatible` until resolved | Legacy persisted hint; probe resolves it to concrete CMFA or Stash before operations. |
| `unknown` | `unknown` | No operations beyond readiness context. |
| `unsupported` | `unsupported` | No controller operations. |

`ControllerProbeResolver` runs the side-effect-free HTTP-family resolver and sing-box StartedService version probe concurrently. A valid HTTP controller identity wins when both respond; otherwise a successful StartedService probe resolves sing-box. The HTTP resolver distinguishes Mihomo, CMFA, Stash, and Surge without turning authentication or transport failures into a different backend. A successful probe sets the detected runtime kind for the selected generation without rewriting the stored profile kind.

## Implemented Capability Matrix

`ControllerCapabilities` is the runtime gate. UI and operations must call the effective capability path; enum presence alone is not support.

### Mihomo, Nikki, and OpenClash-compatible profiles

Implemented flags currently include:

- snapshots, rules, providers, policy groups, connections, traffic;
- mode, controller log level, LAN, IPv6, TCP concurrent, TUN, and port updates;
- policy selection, fixed-selection clearing, latency testing;
- provider update;
- DNS flush;
- single/all connection termination.

Not implemented in this matrix:

- Surge active-request and outbound-mode semantics;
- Surge profile reload.

### CMFA and Stash variants

Both use the Mihomo-compatible transport and preserve the same response models, but their runtime capability matrices remain distinct:

- CMFA keeps snapshot/rules/providers/policies/connections/traffic/logs/memory, provider actions, cache actions, latency testing, and connection termination; runtime mode/configuration/log-level writes remain unavailable.
- Stash keeps snapshot/rules/providers/policies/connections/traffic/logs, mode/log-level/port writes, provider actions, latency testing, and connection termination; memory and Mihomo maintenance/cache writes remain unavailable.
- Stash group latency bypasses the unsupported group endpoint and uses bounded member/provider requests in controller order.
- A `stashCmfaCompatible` profile has no direct operations until probing resolves a concrete runtime variant.

### Surge HTTP API profiles

Implemented flags currently include:

- snapshots, rules, policy groups, active requests, traffic;
- outbound mode, policy selection, policy testing;
- active-request termination;
- DNS flush;
- current-profile reload;
- controller log-level change.

Not implemented for Surge:

- Mihomo provider catalog/update;
- Mihomo connections endpoint semantics;
- Mihomo mode/LAN/IPv6/TCP/TUN/port configuration.

### sing-box StartedService

Implemented state and operations include:

- version, status/traffic/memory, policy groups, Clash mode, connections, logs, and Tailscale status streams;
- policy selection, single/group URL tests, mode change, single/all connection termination, and local/remote log clear;
- Tailscale exit-node selection and logout.

Not implemented for sing-box:

- rules or providers;
- Clash fixed-selection cancellation;
- remote log-level mutation;
- Mihomo configuration, cache, GeoData, profile, or provider maintenance actions.

### Probe and unavailable families

- `probeReadiness` only exposes readiness/snapshot probing until a concrete backend is detected.
- the unresolved legacy Stash/CMFA hint, unknown, and unsupported return no operation capabilities.
- Tailscale controls appear only for a resolved sing-box StartedService session and use the independent Tailscale readiness/error state.

## Connection And Authentication

`RouterProfile` builds the controller base URL from `scheme`, `host`, and `port`. Implemented schemes are HTTP and HTTPS.

### Mihomo-compatible

- REST uses `http`/`https`; streams rewrite to `ws`/`wss`.
- Non-empty credentials use `Authorization: Bearer <secret>`.
- Read requests accept JSON; write requests with a body send JSON content type.
- WebSocket streams use `AsyncThrowingStream` with `.bufferingNewest(64)` and cancel the URLSession WebSocket task on termination.

### Surge HTTP API

- REST uses `http`/`https` only.
- Non-empty credentials use `X-Key: <apiKey>`.
- The protocol fixture initializer injects a data loader and records real `URLRequest` method/path/header/body values.

### sing-box StartedService

- The profile still stores `http` or `https`; the gRPC client maps that to plaintext or TLS HTTP/2 transport.
- Non-empty credentials use gRPC metadata `authorization: Bearer <secret>`.
- StartedService streams use bounded `AsyncThrowingStream` bridges and cancel the underlying RPC when the consumer terminates.

### TLS

- `.system` uses normal URLSession trust evaluation.
- `.allowSelfSigned` installs a controller-client-specific URLSession delegate that accepts server trust.
- Do not broaden self-signed trust outside the explicitly configured profile.

### Credential persistence

- Credentials are cached in AppModel by profile UUID for client construction.
- `RouterProfile` contains only `secretReference`.
- The default store is `FileSecretStore`, not Keychain; see `architecture.md` and `project-constraints.md`.

## Protocol Surfaces

### Mihomo client

Implemented reads/streams include:

- `/version`, `/configs`, `/proxies`, `/connections`, `/rules`;
- `/providers/proxies`, `/providers/rules`;
- WebSocket `/traffic`, `/logs`, `/memory`, `/connections`.

Implemented writes/operations include:

- `PATCH /configs` for typed `MihomoConfigPatch` subsets;
- policy selection and fixed-selection clearing under `/proxies/{group}`;
- group delay under `/group/{group}/delay`;
- single/all connection deletion;
- proxy/rule provider updates;
- rule disabled-state patch;
- DNS and FakeIP cache flush;
- remote restart and remote upgrade endpoints.

Do not assume a path exists because Sparxie or upstream Mihomo implements it. Add it to `MihomoEndpoint`, `MihomoClient`, capability gating, AppModel, tests, and UI explicitly.

### Surge client

Implemented reads include:

- events, outbound mode, policies, policy groups;
- active/recent requests;
- rules, traffic, and DNS cache.

Implemented operations include:

- outbound mode change;
- policy selection and group test;
- active-request kill;
- DNS flush;
- current-profile reload;
- log-level change.

Surge request/response shapes remain Surge-specific until projection. Do not rename a Surge active request into a Mihomo connection at the transport layer.

### sing-box client

`SingBoxGRPCClient` implements the generated StartedService contract for version/default log level/log clear, status, logs, groups, Clash mode, URL test, outbound selection, connections, connection close, and Tailscale operations. `started_service.proto` is excluded as source input; the checked-in generated Swift files are the build inputs and `scripts/generate-sing-box-grpc.sh` is the explicit regeneration path.

Keep generated protobuf messages inside the transport adapter. Convert them to `SingBox*` DTO/domain values before AppModel or SwiftUI consumes them.

## Errors And Retries

Transport error enums:

- `MihomoClientError`
- `SurgeHttpAPIError`
- `SingBoxGRPCError`

Both distinguish invalid URL, authentication rejection, unexpected HTTP status, empty read response, non-HTTP response, malformed JSON, and categorized connection failure.

Status handling:

- `200..<300`: success.
- `401`/`403`: unauthorized.
- other statuses: `unexpectedStatus`.

`RouterTrialFailureCategory` converts transport errors into project behavior:

| Category | Typical disposition |
|---|---|
| DNS, refused connection, timeout, network unavailable/failure | transient retry |
| HTTP 408, 429, or 5xx | transient retry |
| generic local failure | retry once |
| auth failure, wrong target, malformed JSON, invalid URL, TLS, other terminal HTTP | terminal |
| cancellation | cancelled |

`SessionRetryPolicy` uses bounded delays of 2, 4, 8, 15, and 30 seconds with bounded jitter. Do not retry terminal configuration/auth/target errors as if they were transient outages.

User-facing failure copy comes from `RouterTrialFailureCategory` and localization. Do not expose credentials or raw response/stream bodies through diagnostics.

gRPC status mapping keeps cancellation, deadline exceeded, authentication/permission failure, unavailable, and transport/network failure distinct. Invalid stream intervals fail locally before an RPC starts.

## DTO And Domain Conversion

Keep these layers distinct:

1. **Endpoint/RPC description**: `MihomoEndpoint`, `SurgeEndpoint`, or the generated StartedService method owns the wire operation.
2. **Transport client**: client constructs authenticated requests, validates status, and decodes.
3. **Controller response/DTO**: models under `Sources/MicaCore/Models/` preserve upstream optionality and backend-specific fields.
4. **Unified summary**: `UnifiedControllerSnapshot` normalizes health, capabilities, counts, mode, and traffic for cross-backend diagnostics.
5. **Presentation domain**: `DashboardSnapshot` and Workbench view-state types map full controller data into visible native UI state.

Mihomo model rules:

- Decode `/proxies` with `ProxiesResponse.decodePreservingProxyOrder(from:)`; generic dictionary decoding loses the controller's visible order.
- Preserve group member order from `all`.
- Preserve unknown proxy, rule, connection, and metadata fields with `MihomoJSONValue`/`ControllerJSONValue` where implemented.
- Keep missing optional fields `nil`; presentation decides localized not-reported treatment.
- Provider `updatable` defaults from HTTP vehicle type only when the response does not report it.

Surge model rules:

- Accept the implemented wrapper/alias variants in `SurgeModels.swift` without swallowing malformed shapes.
- Preserve opaque request IDs and unknown fields.
- Project active requests to shared connection presentation only in `DashboardSurgeProjectionModels.swift`.

sing-box model rules:

- Convert generated protobuf messages in `SingBoxStartedServiceAdapter`/`SingBoxModels`; never expose generated messages to views.
- Preserve group and node order from the stream.
- Keep connection/process, log, mode, status, peer, user, and exit-node fields that the StartedService reports.
- Tailscale failure after prior data is partial/stale and retains the prior value; failure before first data is failed/unavailable.

Views must not cast raw dictionaries or decode JSON. Add a typed DTO field or a presentation helper instead.

## Session Publication

The selected controller owns one `ControllerSession.generation`.

- Fast lane: 2-second Surge active-request refresh; Mihomo fast REST lane is skipped because connections stream.
- Medium lane: 5-second policy/proxy state.
- Slow lane: 30-second version/config/rules/providers or Surge rules/DNS state.
- Mihomo live tasks: traffic, structured logs, memory, and connections WebSocket streams.
- Surge live task: 1-second near-live polling of traffic, events, active requests, and best-effort recent requests.
- sing-box live task: one structured task group owning status, groups, mode, connections, logs, and Tailscale streams plus the StartedService channel.

Before publishing any result:

```swift
guard isCurrentSession(routerID: router.id, generation: generation),
      !Task.isCancelled else { return }
```

Operations should follow the existing pattern:

1. capability and selected-session guard;
2. cancel the prior operation task slot;
3. record command and busy marker;
4. capture controller ID/generation and credential;
5. perform remote operation;
6. re-read authoritative state when applicable;
7. validate generation before publishing;
8. publish success/partial/error and clear markers;
9. report confirmed-write/refresh failure as partial success without rolling back the confirmed write; roll back only when the write itself failed.

Presentation pause does not stop networking. It stores the newest pending projection and bounded buffered data, then publishes on resume. Endpoint failure after prior success keeps the last successful rows and marks stale/unavailable state.
