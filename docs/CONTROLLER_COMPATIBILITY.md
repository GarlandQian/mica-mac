# Controller Compatibility

## Mihomo-Compatible Controllers

Base reads use `/version`, `/configs`, `/proxies`, and `/connections`. Enhanced reads use `/rules`, `/providers/proxies`, `/providers/rules`, `/traffic`, `/logs`, and `/memory` when supported. Real write paths include config mode updates, policy selection, group delay, connection close, provider update, DNS/FakeIP cache flush, remote restart, and remote upgrade.

`MihomoClient.proxies()` must decode through `ProxiesResponse.decodePreservingProxyOrder(from:)` so the UI does not reorder policy groups.

CMFA and Stash share this transport boundary but have separate runtime capability matrices. CMFA keeps cache and memory support while hiding unsupported runtime writes. Stash hides memory and Mihomo maintenance/cache actions, and group latency uses bounded per-member/provider requests instead of the unsupported group endpoint. The legacy combined Stash/CMFA profile is probe-only until resolved to one of those variants.

## Surge-Compatible Controllers

Surge requests use the controller's HTTP API and authenticate with `X-Key`. Mica exposes only operations represented by the Surge capability model. Surge policy selection, policy testing, request termination, outbound mode, DNS state, and near-live data remain adapter-specific rather than being relabeled as Mihomo operations.

## sing-box Controllers

sing-box uses the remote StartedService gRPC API over HTTP/2 and authenticates with optional Bearer metadata. Mica implements version, status/traffic/memory, groups, mode, connections, logs, URL tests, outbound selection, connection closure, and Tailscale status/exit-node/logout. It does not expose rules, providers, fixed-selection cancellation, remote log-level changes, or Mihomo maintenance/configuration controls for sing-box.

Auto Detect runs the HTTP-family resolver and StartedService version probe concurrently. A concrete HTTP identity wins if both respond; authentication and transport errors remain diagnostic failures instead of being silently reclassified.

## Safety Boundary

Mica controls an already-running remote controller. It does not download, bundle, launch, or supervise a local core. It does not alter macOS proxy settings, environment variables, firewall state, OpenWrt/LuCI, SSH, or `ubus`.
