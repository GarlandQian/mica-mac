# Controllers And Data Boundaries

## Contents

- [Controller identity](#controller-identity)
- [Capability differences](#capability-differences)
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

`ControllerProbeResolver` resolves the HTTP family first. A successful Mihomo/CMFA/Stash/Surge response is accepted immediately; a conclusive unavailable HTTP port is returned immediately instead of waiting for sing-box's wait-for-ready RPC. Only an HTTP response that does not identify a controller, or an ambiguous transport failure, falls through to the StartedService version probe. The HTTP resolver probes Surge only after the Clash-compatible path does not identify a controller. Authentication and terminal target errors are never converted into another backend. A successful probe sets the detected runtime kind for the selected generation without rewriting the stored profile kind.

Connection tests use that resolved kind rather than the stored Auto Detect case: Mihomo-family profiles read the Mihomo version endpoint, Surge profiles read the Surge control snapshot, and sing-box profiles call StartedService `GetVersion` over gRPC. Keep the operation injectable for offline tests, and keep connection-test reports backend-specific so an RPC failure is never labeled as a JSON failure.

## Capability Differences

`ControllerCapabilities` for the effective runtime type gates shared controller
operations. Exact flags live in `UnifiedControllerModels.swift`; enum presence
is not support. Dedicated sing-box Tailscale controls additionally use their
own readiness/availability state.

| Runtime family | Distinct implemented boundary |
|---|---|
| Mihomo/Nikki/OpenClash | Clash HTTP/WebSocket data, policy/provider/configuration and maintenance operations; no OpenWrt/LuCI/SSH management. |
| CMFA | Mihomo-compatible transport with a narrower runtime-write matrix. |
| Stash | Mihomo-compatible transport with Stash-specific configuration and latency fallback; no inherited Mihomo memory/maintenance assumptions. |
| Surge | Active requests, outbound mode, policy test/selection, DNS flush, profile reload, and log-level change; no Mihomo provider/config semantics. |
| sing-box | StartedService gRPC streams, policy/mode/connection/log and Tailscale operations; no rules, providers, fixed-selection clear, or Mihomo maintenance. |
| Probe/unknown/unsupported | Probe/readiness only or no operations until a concrete runtime family resolves. |

CMFA and Stash share DTOs with Mihomo but never inherit its capability set.
Tailscale availability and failure state are independent and sing-box-only.

## Connection And Authentication

`RouterProfile` builds an HTTP/HTTPS target from scheme, host, and port.

| Family | Authentication and stream transport |
|---|---|
| Mihomo-compatible | Bearer authorization; REST plus `ws`/`wss` streams. |
| Surge | `X-Key`; HTTP(S) request/response API. |
| sing-box | Bearer gRPC metadata; plaintext/TLS HTTP/2 StartedService. |

`.allowSelfSigned` is profile-scoped; never broaden trust globally. Credentials
are cached by profile UUID, while `RouterProfile` stores only
`secretReference`. `FileSecretStore`, not Keychain, is currently the default.

## Protocol Surfaces

The endpoint/RPC enum or generated method is the wire-operation authority;
client code owns request construction, authentication, status validation, and
decoding. Add an endpoint only through the complete client, capability,
AppModel, presentation, localization, and test path.

Keep Surge active requests Surge-specific until presentation. Keep generated
StartedService protobuf messages inside the sing-box adapter and regenerate
checked-in Swift only with `scripts/generate-sing-box-grpc.sh`.

Connection deletion requires a non-blank reported ID before URL construction
or transport dispatch. A confirmed write followed by refresh failure is partial
success, not a rollback.

## Errors And Retries

`MihomoClientError`, `SurgeHttpAPIError`, and `SingBoxGRPCError` preserve
transport-specific failures. `RouterTrialFailureCategory` owns user-facing
classification and retry disposition:

- DNS/refused/timeout/network, HTTP 408/429/5xx, and gRPC unavailable are
  transient.
- Authentication, wrong target, malformed payload, invalid URL, TLS, and
  terminal HTTP failures do not retry as outages.
- Cancellation remains cancellation.

Reuse `SessionRetryPolicy`; concurrent live-channel failures share one retry
reservation per failure wave. Local validation fails before transport starts.
Never expose credentials or raw response/stream bodies in error reports.

## DTO And Domain Conversion

Keep endpoint/RPC, authenticated transport, backend DTO, neutral
`UnifiedControllerSnapshot`, and full-fidelity Workbench presentation as
distinct layers.

Mihomo `/proxies` uses `decodePreservingProxyOrder`; keep that wire order in the
DTO, then arrange Dashboard groups by matching names in `GLOBAL.all`, followed
by unlisted groups in wire order and `GLOBAL` last. Preserve each group's member
order.
Preserve reported selectable/hidden/unknown/optional fields plus provider test
URL and subscription metadata. Read-only groups stay visible but cannot select.

Keep Surge IDs/shapes backend-specific until presentation. Convert generated
sing-box messages before AppModel, preserving stream order, reported fields,
and every log level including `trace`. A later Tailscale-only failure retains
prior data as partial/stale.

Views never decode or cast protocol payloads. The complete executable model
contract lives in `.trellis/spec/backend/controller-data-contract.md`.

## Session Publication

The selected controller owns one `ControllerSession.generation`; all REST
lanes, Mihomo WebSockets, Surge polling, sing-box structured streams, and
operations belong to it. Every publication validates controller ID, generation,
and cancellation; `LiveSessionRuntime` domain publications also validate
revision.

Operations use one capability gate and task slot, refresh authoritative state
when appropriate, and treat confirmed-write/refresh failure as partial success.
Pause freezes presentation, not networking; later endpoint failure retains last
successful rows as stale. Exact cadence, buffers, reconnect, and transaction
rules live in the live-session contract.
