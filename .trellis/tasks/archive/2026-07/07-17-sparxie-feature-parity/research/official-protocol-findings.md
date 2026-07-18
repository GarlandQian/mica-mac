# Official protocol findings

- Date: 2026-07-17
- Sparxie reference commit: `32bd802c546d14ebead1cd9e618c3bba4c484fc8`
- Scope: verify high-risk Mica request contracts against primary upstream documentation.

## Mihomo external-controller

Primary source: https://wiki.metacubex.one/en/api/

### Confirmed contracts

- `GET /memory` supports a persistent GET/WS stream and pushes `inuse` and `oslimit` once per second. Both values are bytes.
- `GET /logs` supports GET/WS. `level=info|warning|error|debug` controls the upstream log level, and `format=structured` exposes `time`, `level`, `message`, and `fields`; standard mode uses `type` and `payload`.
- `GET /traffic` supports GET/WS and pushes `up`, `down`, `upTotal`, and `downTotal` once per second; rates are bytes/s and totals are bytes.
- `GET /connections` supports GET/WS with an optional `interval` query; each response includes aggregate `memory`, totals, and connection metadata/counters.
- `GET /group/{group}/delay` returns a top-level JSON object mapping member names directly to millisecond values. It does not wrap the map in a `delay` property.
- `GET /connections` supports GET/WS and includes aggregate memory plus per-connection counters.
- `/rules` includes rule index and may include `extra.disabled`, hit/miss counters, and timestamps.
- `/proxies` exposes substantially more metadata than Mica currently retains, including health history, alive state, fixed selection, test URL, provider, interface, and transport flags.

### Confirmed Mica defects or gaps

- `Sources/MicaCore/API/MihomoClient.swift:146` treats `/memory` as a one-shot JSON request, while the endpoint is a persistent stream.
- `Sources/Mica/App/OperationSessionModels.swift:545` names byte values as KB, and `Sources/Mica/App/AppModelRuntimeOperations.swift:303` multiplies them by 1024 when formatting.
- `Sources/MicaCore/Models/MihomoModels.swift:410` expects `{ "delay": { ... } }`, which does not match the official group-delay response.
- `Sources/MicaCore/API/MihomoEndpoint.swift:57` and `Sources/MicaCore/API/MihomoClient.swift:155` do not send `level` or `format=structured`, so the log-level control is only a local filter and controller timestamps/fields are discarded.
- `Sources/MicaCore/API/MihomoClient.swift:146` also treats `/memory` as a finite response even though the documented endpoint continuously pushes frames; `/connections` is currently consumed as a finite response by `connections()` and has no stream adapter.
- The current Mica proxy, rule, connection, and provider models intentionally decode only a subset of the official fields; this conflicts with the full-visible active-workspace product requirement.

## Surge HTTP API

Primary source: https://manual.nssurge.com/others/http-api.html

### Confirmed contracts

- Surge HTTP API uses GET and POST only.
- Change a select group with `POST /v1/policy_groups/select` and body `{ "group_name": "...", "policy": "..." }`.
- Test a policy group with `POST /v1/policy_groups/test` and body `{ "group_name": "..." }`.
- Kill an active request with `POST /v1/requests/kill` and body `{ "id": ... }`.
- `GET /v1/dns` and `POST /v1/dns/flush` are valid.
- `POST /v1/profiles/reload` reloads the current profile, and `POST /v1/log/level` changes the current session log level.

### Confirmed Mica defects or gaps

- `Sources/MicaCore/API/SurgeHttpAPIClient.swift:299` sends policy selection to `/v1/policy_groups/{group}` with the wrong body shape.
- `Sources/MicaCore/API/SurgeHttpAPIClient.swift:303` sends a GET to `/v1/policy_groups/{group}/test`, which is not the official endpoint.
- `Sources/MicaCore/API/SurgeHttpAPIClient.swift:307` sends DELETE `/v1/requests/active/{id}` even though Surge only accepts GET/POST and requires `POST /v1/requests/kill`.
- Mica does not expose official profile reload or log-level operations.
- Several Mica Surge response types assume narrow fixed JSON shapes; Sparxie uses tolerant parsers for policy, request, rules, and traffic variants. Fixture coverage is needed before claiming parity.

## Verification consequence

The existing Mica source verifier and 90 tests pass while the request contracts above remain wrong. Future acceptance must include upstream-shaped fixtures and endpoint method/path/body tests, not only source-string guards and presentation-model tests.
