# Research: Sparxie Rust/core 后端与 Dart FFI API 清单

- Query: 审计本地参考仓库 `tmp/codex/sparxie` 的 Rust/core 后端与 Dart FFI 契约；按 mihomo、CMFA、Stash、Surge、sing-box 列出真实 HTTP/WS/gRPC API、操作、状态流、缓存/分页/排序、错误处理、后台轮询或流式更新，重点覆盖策略选择、连接关闭、日志、流量、规则、provider、配置、DNS/cache、内存/runtime、升级/重启、Tailscale，并区分已实现、受后端限制、占位与仅声明。
- Scope: internal
- Date: 2026-07-17

## Findings

### 1. 审计边界与状态标签

- 本次只做静态代码审计；未启动任何 core/controller，未发起网络请求，也未修改 `tmp/codex/sparxie` 或 Mica 源码。
- 除明确写出 `tmp/codex/sparxie/...` 的路径外，本文后续 `core/...`、`lib/...`、`README.md` 锚点均相对于 `tmp/codex/sparxie/`。
- 本文使用以下标签：
  - **已实现**：存在可达的 Rust 实现，并调用真实 HTTP/WS/gRPC 接口或维护真实状态。
  - **已实现但受后端限制**：Rust/FFI 路径存在，但能力依赖具体后端版本、运行模式或返回字段；通常由 Dart 能力标志门控。
  - **占位/空结果**：统一 FFI 有函数，但某后端分支只返回空 JSON、空数组、默认值或固定字符串。
  - **FFI 已导出但当前 Dart UI 未调用**：后端实现存在，不是“仅声明”，但当前 `lib/` 的非生成代码没有调用点。
  - **仅声明**：只出现在 proto/契约中，没有找到 Rust 调用或 Dart 暴露/调用。

### 2. Files found

#### Trellis / task context

- `.trellis/tasks/07-17-sparxie-feature-parity/prd.md` — 本任务目标、限制与验收条件。
- `.trellis/spec/backend/controller-data-contract.md` — Mica 的控制器数据顺序、可用性和错误边界契约。
- `.trellis/spec/frontend/live-session-controller-contract.md` — Mica 的会话代际、轮询、暂停和陈旧数据契约。
- `.trellis/spec/frontend/workbench-ui-contract.md` — Mica 的工作台数据可见性、排序、轮询和凭证边界。

#### Rust unified backend / FFI boundary

- `tmp/codex/sparxie/core/src/backend/target.rs` — 三种统一后端类型及目标参数。
- `tmp/codex/sparxie/core/src/backend/api.rs` — flutter_rust_bridge 的 Rust 输入根。
- `tmp/codex/sparxie/core/src/backend/types.rs` — 跨后端 FFI 数据结构、排序枚举和能力标志。
- `tmp/codex/sparxie/core/src/backend/{proxies,proxy_delay,connections,streams,rules,providers,control,tailscale}.rs` — 跨后端分派与占位/unsupported 分支。
- `tmp/codex/sparxie/core/src/backend/retry.rs` — 5/10/20/30 秒重试退避。
- `tmp/codex/sparxie/core/src/utils/error.rs` — 跨 FFI 的结构化错误枚举。

#### Clash-compatible: mihomo / CMFA / Stash

- `tmp/codex/sparxie/core/src/clash/client.rs` — HTTP/IPC 请求、Bearer 鉴权、超时与响应错误映射。
- `tmp/codex/sparxie/core/src/clash/client/ws.rs` — TCP/IPC WebSocket、token/Bearer 鉴权和帧读取。
- `tmp/codex/sparxie/core/src/clash/client/transport.rs` — HTTP(S)、Unix socket、named pipe、Sparkle service 传输选择。
- `tmp/codex/sparxie/core/src/clash/api/backend.rs` — mihomo/CMFA/Stash 探测。
- `tmp/codex/sparxie/core/src/clash/api/{version,configs,cache,dns,upgrade,providers,rules,connections,storage}.rs` — 真实控制器 REST 操作。
- `tmp/codex/sparxie/core/src/clash/api/proxies/**` — 策略组、节点、provider 节点、测速、Rust 端成员缓存与分页。
- `tmp/codex/sparxie/core/src/clash/state/{traffic,logs,connections,stop}.rs` — WS 共享订阅、日志环、连接状态、重连和显式停止。

#### Surge

- `tmp/codex/sparxie/core/src/surge/client.rs` — REST 客户端与 `X-Key` 鉴权。
- `tmp/codex/sparxie/core/src/surge/api.rs` — Surge 统一能力、配置、流量、provider 占位和规则入口。
- `tmp/codex/sparxie/core/src/surge/api/{config,connections,policies,traffic}.rs` — Surge REST 操作与数据归一化。
- `tmp/codex/sparxie/core/src/surge/api/policies/**` — 策略组解析、选择、测速和缓存。
- `tmp/codex/sparxie/core/src/surge/state/{connections,logs,rules}.rs` — REST 轮询、闭合连接、日志去重环和规则分页。

#### sing-box

- `tmp/codex/sparxie/core/proto/daemon/started_service.proto` — 本地编译的 StartedService gRPC 契约。
- `tmp/codex/sparxie/core/src/sing_box/client.rs` — tonic HTTP/2 channel、Bearer metadata、TLS 和连接池。
- `tmp/codex/sparxie/core/src/sing_box/api.rs` — 版本、Clash mode、连接关闭及 unsupported 分支。
- `tmp/codex/sparxie/core/src/sing_box/api/{proxies,tailscale}.rs` — groups/URLTest/SelectOutbound 与 Tailscale RPC。
- `tmp/codex/sparxie/core/src/sing_box/state/{status,logs,connections}.rs` — status/log/connection gRPC 流与 Rust 状态。

#### Dart FFI and session orchestration

- `tmp/codex/sparxie/flutter_rust_bridge.yaml` — `crate::backend::api` 到 `lib/src/rust` 的生成配置。
- `tmp/codex/sparxie/lib/src/rust/backend/api/*.dart` — flutter_rust_bridge 2.12.0 生成的公开 Dart 契约。
- `tmp/codex/sparxie/lib/rust_api.dart` — 生成绑定的单一 re-export 面及 Controller→BackendTarget 映射。
- `tmp/codex/sparxie/lib/session.dart` — controller 切换、订阅、重试、3 秒策略轮询和能力门控。
- `tmp/codex/sparxie/lib/session/{connections,proxies,logs}.dart` — Dart 端可见窗口、overscan、暂停和镜像缓存。

### 3. 总体架构与 FFI 契约

#### 3.1 后端类型不是五种，而是三种

- Rust 和生成的 Dart 只有 `Clash`、`Surge`、`SingBox` 三种类型；CMFA 与 Stash 都被建模为 `Clash` 的运行时变体：`core/src/backend/target.rs:1-14`、`lib/src/rust/backend/api/target.dart:12-43`。
- Dart Controller 也只有三种类型，并把 secret、base URL、allow-insecure 原样投影进 FFI target：`lib/controller.dart:5-41`、`lib/rust_api.dart:21-31`。
- CMFA 通过 `/version.version` 是否包含 `cmfa` 判断；Stash 通过 `/version` 404 后读取 `/`，再检查 `appVersion` 判断：`core/src/clash/api/backend.rs:20-59`。

#### 3.2 flutter_rust_bridge 边界

- 生成入口是 `crate::backend::api`，输出到 `lib/src/rust`：`flutter_rust_bridge.yaml:1-3`；Rust 初始化函数位于 `core/src/backend/api.rs:34-37`。
- Dart 单一导入面重新导出 connections/control/providers/proxies/delay/resources/rules/streams/Tailscale/types/error：`lib/rust_api.dart:1-19`。
- 生成器版本固定为 flutter_rust_bridge 2.12.0：`core/Cargo.toml:19-21`，每个生成 Dart 文件头也标记 2.12.0，例如 `lib/src/rust/backend/api/connections.dart:1-3`。

#### 3.3 公开 FFI 模块

| FFI 模块 | 公开能力 | 锚点 |
|---|---|---|
| connections | raw snapshot、单个/全部/按链路/按分组关闭、frame stream、活动/闭合窗口、分组聚合、排序、清闭合缓存、停止流 | `lib/src/rust/backend/api/connections.dart:12-114` |
| control | CoreConfig、mode、log/tun/bool/port 更新、reload、Geo、DNS/FakeIP、升级/重启、版本与能力 | `lib/src/rust/backend/api/control.dart:14-116` |
| proxies | raw groups/proxies/detail、选择、取消固定、结构化 catalog、成员窗口 | `lib/src/rust/backend/api/proxies.dart:12-75` |
| proxy_delay | group/node/batch 测速、逐项 delay stream、可见窗口回传 | `lib/src/rust/backend/api/proxy_delay.dart:12-120` |
| providers | proxy/rule provider、更新/healthcheck、controller storage CRUD | `lib/src/rust/backend/api/providers.dart:12-78` |
| rules | count、load、无网络重筛选、窗口、disable | `lib/src/rust/backend/api/rules.dart:12-49` |
| streams | traffic、memory、logs、clear logs | `lib/src/rust/backend/api/streams.dart:12-32` |
| tailscale | status stream、logout、set exit node 及完整状态类型 | `lib/src/rust/backend/api/tailscale.dart:13-228` |

#### 3.4 跨后端 raw String API 不是稳定同形契约

- `groups()`：Clash 返回 `/group` JSON 字符串；Surge/sing-box 返回换行拼接的组名：`core/src/backend/proxies.rs:5-30`。
- `proxies()`：Clash 返回 `/proxies` JSON；Surge/sing-box 返回仅包含组名的 JSON 数组：`core/src/backend/proxies.rs:33-60`。
- `proxy_detail()`：Clash 返回真实 endpoint JSON；Surge/sing-box 只返回 `{ "name": ... }` 占位：`core/src/backend/proxies.rs:63-69`。
- `connections()`：Clash 与 Surge 返回真实 raw snapshot；sing-box 固定返回空 connections：`core/src/backend/connections.rs:13-18`。
- 当前主 UI 避开这些不稳定 raw 形状，使用 `proxyCatalog`、`connectionsStream`、window APIs 和结构化类型；相关调用集中在 `lib/session.dart:84-128,519-660`。

#### 3.5 关键跨 FFI 数据类型

- Connection 保留 ID、host、源/目的地址、进程、rule/payload、chains、connection logs、累计与速率、开始时间和闭合标志：`lib/src/rust/backend/api/types.dart:11-72`。
- ConnectionsFrame 只跨桥传 counts、totals、`isInitial`；实际行由 window API 拉取：`lib/src/rust/backend/api/types.dart:215-247`、`lib/session/connections.dart:284-310,420-449`。
- ProxyCatalog 只传组摘要和图标 URL；组成员通过 offset/limit 独立获取：`lib/src/rust/backend/api/types.dart:434-452,514-602`。
- RuleEntry 统一了 index/type/payload/proxy/extra params/disable/hit/miss/hasExtra：`lib/src/rust/backend/api/types.dart:642-693`。
- VersionInfo 暴露 CMFA/Stash 标志及 core config/actions/management/cache/memory/Tailscale 能力：`lib/src/rust/backend/api/types.dart:794-845`。
- FFI 错误是可模式匹配的 sealed enum，而非字符串：InvalidUrl、InvalidRegex、Upstream(status/body)、Network、InvalidJson、Other：`core/src/utils/error.rs:3-14`、`lib/src/rust/utils/error.dart:11-27`。

### 4. 能力总览

| 能力 | mihomo | CMFA | Stash | Surge | sing-box |
|---|---|---|---|---|---|
| 传输 | HTTP/HTTPS + WS/WSS；另有 Unix/pipe/Sparkle IPC | 同 mihomo | 同 Clash-compatible | HTTP/HTTPS REST，无 WS | gRPC/grpcs over HTTP/2，无 HTTP JSON/WS |
| 识别 | `/version` 或 root hello | `/version.version` 含 `cmfa` | `/version` 404 后 `/` 的 `appVersion` | `/v1/outbound` 可达即视为 Surge | `GetVersion` |
| 策略选择 | PUT `/proxies/{group}`；非 LoadBalance 可选择/固定 | 同一路径，后端依赖 | 同一路径，后端依赖 | POST `/v1/policy_groups/select` | `SelectOutbound` RPC |
| 取消固定 | DELETE `/proxies/{group}` | 同一路径，后端依赖 | 同一路径，后端依赖 | unsupported | unsupported |
| 连接更新 | `/connections?interval=` WS full snapshot | 同 | 同 | `/v1/requests/active` REST 轮询 | `SubscribeConnections` event stream |
| 单个/全部关闭 | 原生 DELETE 单个/全部 | 同 | 同 | kill 单个；全部为枚举+逐个 kill | 原生 RPC 单个/全部 |
| 按链路/分组关闭 | snapshot + 客户端过滤 + 并发 DELETE | 同 | 同 | snapshot + 客户端过滤 + 逐个 kill | unsupported |
| 日志 | `/logs?...format=structured` WS + 500 环 | 同 | 同 | `/v1/events` 每 5 秒轮询 + 去重 + 500 环 | `SubscribeLog` 直流，无 Rust replay 环 |
| 流量 | `/traffic` WS | 同 | 同 | `/v1/traffic` 每秒 REST | `SubscribeStatus` |
| 内存/runtime | `/memory` WS；inuse/oslimit，goroutines=0 | 能力标志为 true | 能力标志为 false | unsupported | status memory + goroutines + connectionsIn/Out |
| 规则 | GET `/rules`，本地 filter/window；有 extra 时可 PATCH disable | 同一路径，具体返回依赖后端 | 同一路径，具体返回依赖后端 | GET `/v1/rules`，本地 filter/window；disable unsupported | 占位为空/0，UI 隐藏 |
| provider | proxy/rule provider 查询、更新；proxy healthcheck | 同路径，后端依赖 | README 声明 provider 节点可用；更新能力仍取决于 endpoint | 空结果；更新/healthcheck unsupported | 空结果；更新/healthcheck unsupported |
| 配置 | GET/PATCH/PUT `/configs` | `supports_core_config=false` | 基础配置；PATCH 强制仅 mode/log-level/mixed-port | profile 读取；mode 与 log level；reload current profile | 仅 Clash mode status/set |
| DNS/cache | DNS query、DNS flush、FakeIP flush | cache flush 标志为 true | cache 标志 false | DNS flush only | unsupported |
| 升级/重启 | core/UI/Geo upgrade、restart、Geo refresh | management 标志 false | management 标志 false | unsupported | unsupported |
| Tailscale | 不支持 | 不支持 | 不支持 | 不支持 | status/logout/exit-node RPC |

能力标志的具体计算见 `core/src/clash/api/version.rs:30-50`、`core/src/surge/api.rs:31-41`、`core/src/sing_box/api.rs:27-42`。README 的产品级概述与代码一致地列出五类运行时：`README.md:5-13`。

### 5. mihomo / CMFA / Stash：Clash-compatible 实现

#### 5.1 传输、鉴权与基础错误

- TCP HTTP 客户端固定 15 秒超时，`allow_insecure` 可跳过证书校验；secret 使用 `Authorization: Bearer`：`core/src/clash/client.rs:27-51,62-76`。
- 非 2xx HTTP 响应保留 status 和完整 body 到 `MihomoError::Upstream`：`core/src/clash/client.rs:244-259`。
- mutating endpoint 的空响应或非 JSON 2xx body 被统一当作 `{ "ok": true }`，因此不会因成功响应体格式异常而失败：`core/src/clash/client.rs:262-268`。
- WS 同时把 secret 放进 `?token=` 与 `Authorization: Bearer`；支持 ws/wss，握手非成功映射为 Upstream：`core/src/clash/client/ws.rs:45-86,89-105`。
- 本地传输支持 `unix:`, `pipe:`, `sparkle-service`；Sparkle service 把控制器路径改写到 `/core/controller/...` 并添加签名头：`core/src/clash/client/transport.rs:37-51,53-90,116-140`。
- IPC 普通请求共享 HTTP/1 sender，失败后重建并重试一次；测速使用 isolated sender，避免长 healthcheck 串行化：`core/src/clash/client.rs:80-87,109-137,145-187`。

#### 5.2 HTTP/WS API inventory

| 区域 | 真实方法与路径 | 状态与语义 | 锚点 |
|---|---|---|---|
| 探测 | GET `/version`; 404 时 GET `/` | mihomo/CMFA/Stash 运行时分类 | `core/src/clash/api/backend.rs:20-59`; `core/src/clash/api/version.rs:18-34` |
| 配置读取 | GET `/configs` | 完整 JSON 后再投影为 CoreConfig | `core/src/clash/api/configs.rs:11-24`; `core/src/backend/control.rs:172-185` |
| 配置更新 | PATCH `/configs` | mihomo 可传子集；Stash 被过滤为 mode/log-level/mixed-port | `core/src/clash/api/configs.rs:26-43,88-103` |
| 配置重载 | PUT `/configs` 或 `/configs?force=true`，body 可带 path/payload | path 必须是后端主机路径；FFI 暴露 path/payload/force | `core/src/clash/api/configs.rs:45-67`; `lib/src/rust/backend/api/control.dart:64-74` |
| Geo refresh | POST `/configs/geo` | 与 upgrade Geo 是两个不同操作 | `core/src/clash/api/configs.rs:69-76` |
| DNS query | GET `/dns/query?name=&type=` | 默认 A；DNS 未启用时上游可返回 500 | `core/src/clash/api/dns.rs:5-16` |
| DNS/FakeIP cache | POST `/cache/dns/flush`; POST `/cache/fakeip/flush` | 仅 capability 标志为 true 时 UI 显示 | `core/src/clash/api/cache.rs:7-23`; `lib/screens/core_actions_screen.dart:165-188` |
| Core upgrade | POST `/upgrade[?channel=&force=true]` | 成功后上游会重启；FFI 只暴露 force，不暴露 channel | `core/src/clash/api/upgrade.rs:7-30`; `lib/src/rust/backend/api/control.dart:95-101` |
| UI upgrade | POST `/upgrade/ui` | Rust/FFI 已实现；当前 Dart UI 未找到调用 | `core/src/clash/api/upgrade.rs:33-40`; `lib/src/rust/backend/api/control.dart:103-104` |
| Geo upgrade | POST `/upgrade/geo` | Rust/FFI 已实现；当前 UI 使用 `/configs/geo` 而非该函数 | `core/src/clash/api/upgrade.rs:43-50`; `lib/screens/core_actions_screen.dart:133-140` |
| Restart | POST `/restart` | endpoint 立即返回，随后短期不可达 | `core/src/clash/api/upgrade.rs:53-61` |
| Proxy catalog | GET `/proxies` | raw 过滤和结构化 catalog 都基于该 endpoint | `core/src/clash/api/proxies.rs:16-57`; `core/src/clash/api/proxies/catalog.rs:19-31` |
| Proxy detail | GET `/proxies/{name}` | 已实现但当前 UI 未调用 raw detail | `core/src/clash/api/proxies.rs:59-62` |
| 策略选择 | PUT `/proxies/{group}`, body `{name}` | Dart 先乐观更新 now，失败回滚 | `core/src/clash/api/proxies.rs:64-78`; `lib/screens/proxies_screen.dart:96-129` |
| 取消固定 | DELETE `/proxies/{group}` | 用于非 Selector 自动组取消 fixed；Surge/sing-box 无此能力 | `core/src/clash/api/proxies.rs:80-91`; `lib/screens/proxies_screen.dart:100-104,132-145` |
| Groups raw | GET `/group` | 当前 UI 不依赖；Stash 没有 `/group` 时 raw API 可能失败 | `core/src/clash/api/groups.rs:14-17` |
| Group delay | GET `/group/{group}/delay?url=&timeout=&expected=` | 非 Selector 组调用会清 fixed；Stash 或 404 时 fallback | `core/src/clash/api/groups.rs:19-87` |
| Node delay | GET `/proxies/{name}/delay?...` | 普通节点；失败时单测路径把缓存 delay 置 0 | `core/src/clash/api/proxies/delay.rs:28-60,208-239` |
| Provider node delay | GET `/providers/proxies/{provider}/{name}/healthcheck?...` | provider 节点按缓存 provider 归属选择路径 | `core/src/clash/api/proxies/delay.rs:28-31,216-237` |
| Proxy providers | GET `/providers/proxies` | catalog 排除 Compatible；按 name 排序；HTTP provider 标为 updatable | `core/src/clash/api/providers.rs:30-65` |
| Proxy provider update | PUT `/providers/proxies/{name}` | 已实现；UI 可单个/全部顺序更新 | `core/src/clash/api/providers.rs:67-77`; `lib/screens/resources_screen.dart:203-225` |
| Proxy provider health | GET `/providers/proxies/{name}/healthcheck` | FFI 已导出，当前非生成 Dart 未找到调用 | `core/src/clash/api/providers.rs:79-92`; `lib/src/rust/backend/api/providers.dart:29-35` |
| Rule providers | GET `/providers/rules`; PUT `/providers/rules/{name}` | catalog 按 name 排序，HTTP provider 可更新 | `core/src/clash/api/providers.rs:94-138` |
| Rules | GET `/rules` | 全量抓取后 Rust filter/window；count 失败返回 0 | `core/src/clash/api/rules.rs:97-135` |
| Rule disable | PATCH `/rules/disable`, body `{index: bool}` | 成功后原地更新缓存；404 被注释为 embed feature gate | `core/src/clash/api/rules.rs:168-199` |
| Connections snapshot | GET `/connections` | raw API、按链路/分组关闭前的客户端筛选都使用 | `core/src/clash/api/connections.rs:9-12,67-100` |
| Close one/all | DELETE `/connections/{id}`; DELETE `/connections` | 原生 endpoint | `core/src/clash/api/connections.rs:14-34` |
| Close by chain/group | GET snapshot 后并发 DELETE `/connections/{id}` | best effort；单个 DELETE 失败被忽略，返回目标数量 | `core/src/clash/api/connections.rs:36-100` |
| Connections stream | WS `/connections?interval=<ms>` | 每帧是 full snapshot，Rust 保存活动/闭合状态 | `core/src/clash/state/connections/stream.rs:48-93` |
| Traffic | WS `/traffic` | 每 target/path 只开一个上游，再 broadcast fan-out | `core/src/clash/state/traffic.rs:1-11,91-105,194-203` |
| Memory | WS `/memory` | 与 traffic 同共享机制 | `core/src/clash/state/traffic.rs:206-216` |
| Logs | WS `/logs?level=&format=structured` | Rust 500 条 replay ring + delta broadcast | `core/src/clash/state/logs.rs:1-17,54-80,122-171` |
| Storage | GET/PUT/DELETE `/storage/{key}` | 1 MiB/JSON 限制由上游执行；FFI 已导出，当前 UI 未调用 | `core/src/clash/api/storage.rs:8-48`; `lib/src/rust/backend/api/providers.dart:54-78` |

#### 5.3 策略组缓存、分页和排序

- 结构化 catalog 每次 GET `/proxies`，过滤 hidden 和 group/member 文本；完整成员列表只保留在 Rust，Dart 只收组摘要：`core/src/clash/api/proxies/catalog.rs:19-31,39-84,111-124`。
- Sparxie 不是简单保留 `/proxies` 对象顺序：它读取 `GLOBAL.all` 建立 peer group 位置，并强制 GLOBAL 最后；不在 GLOBAL 列表的组再按原对象位置：`core/src/clash/api/proxies/catalog.rs:45-52,86-95,293-314`。
- Clash catalog cache 是**单一 active target slot** (`Option<(key, catalog)>`)，key 为 base URL + secret；切换目标会替换缓存：`core/src/clash/api/proxies/catalog/cache.rs:83-97,316-338`。
- 成员按 offset/limit 切片；排序支持 Original、Name、Delay，排序结果缓存；delay 更新会使受影响组的排序缓存失效：`core/src/clash/api/proxies/catalog/cache.rs:52-80,99-128,181-225`。
- Delay 排序把负值放最后，把 0 放在负值之前：`core/src/clash/api/proxies/catalog/cache/sort.rs:15-44`。
- provider 节点若 `/proxies` 没有详情，会延迟 GET `/providers/proxies` 合并 node type/delay/provider；失败被吞掉并继续返回已有缓存：`core/src/clash/api/proxies/catalog.rs:127-149,180-208`。
- 成员名称以 FNV-1a 风格 hash 生成 `membersHash`，用于 Dart 丢弃过期窗口：`core/src/clash/api/proxies/catalog/parse.rs:14-35,81-89`、`lib/session/proxies.dart:151-160,260-274`。
- Dart 默认每 3 秒刷新 catalog，refresh 是 single-flight；如果过滤条件在请求中变化，会再补一次 refresh：`lib/session.dart:58-63,469-476,519-552`。
- Dart proxy member window 最少 96 条、两侧 overscan 32、refetch margin 16；Rust 保存全量：`lib/session/proxies.dart:223-225,298-320`。
- Clash `ProxyGroupEntry.selectable` 仅对 `LoadBalance` 返回 false；其他自动组可通过 select 形成 fixed：`core/src/backend/convert.rs:125-138`。

#### 5.4 连接状态、闭合记录、分页和排序

- 每个 `(base URL, secret, interval)` 有一个连接 slot；同 slot 的多个 Dart 订阅共享一个 WS：`core/src/clash/state/connections.rs:45-89`。
- Rust active 是 ID→Connection map；closed 是 FIFO，容量 500：`core/src/clash/state/connections.rs:26-38`、`core/src/clash/state/connections/types.rs:3-5`。
- full snapshot 通过 ID 差集识别闭合连接，计算每秒上传/下载速率；removed row 被标记 closed、速度清零后入 FIFO：`core/src/clash/state/connections/stream.rs:96-168`。
- active window 使用缓存的 sorted ID 列表；只有 active version、sort 或 asc 改变时重排：`core/src/clash/state/connections.rs:111-143,174-194`。
- active 支持 Time/Upload/Download/UploadSpeed/DownloadSpeed/Process 排序；closed 窗口固定按 newest-first FIFO 读取，不使用当前 sort：`core/src/clash/state/connections.rs:123-142`、`core/src/clash/state/connections/ordering.rs:30-51`。
- 按进程分组；无进程时按 source IP；内部连接单独进入 `\0inner` / “内部连接”组：`core/src/clash/state/connections/groups.rs:6-39,95-121`。
- Dart 只持有可见连接窗口，overscan 为 5，50ms debounce；展开分组最多保留 top 100 rows：`lib/session/connections.dart:284-310,451-508`。
- `ConnectionsFrame.isInitial` 会清 Dart 当前窗口，再由 window API 重建；行级 byte/speed notifier 原地 patch：`lib/session/connections.dart:420-449,719-767`。

#### 5.5 日志、流量、内存和重连

- traffic/memory 每 target/path 一个上游 WS，broadcast 容量 64；最后一个 receiver 消失后自清理：`core/src/clash/state/traffic.rs:59-105,108-140`。
- logs 每 `(target, level)` 一个 500-entry ring；订阅时在同一锁下取得 snapshot + receiver，避免 snapshot/delta 间丢失或重复：`core/src/clash/state/logs.rs:29-39,54-80`。
- connections/logs/traffic/memory 的 Rust producer 均使用 5/10/20/30 秒退避，成功后 reset：`core/src/backend/retry.rs:1-27`、`core/src/clash/state/connections/stream.rs:16-45`、`core/src/clash/state/logs.rs:92-119`、`core/src/clash/state/traffic.rs:108-140`。
- Dart 取消 FRB stream 不会自动取消 Rust task，因此 controller 切换时显式调用 `stopTargetStreams`；Rust 用 generation + watch tick 唤醒阻塞读/退避：`core/src/clash/state/stop.rs:1-15,42-77`、`lib/session.dart:344-357`。
- MemorySample 对 Clash 只填 inuse/oslimit，goroutines 固定 0：`core/src/backend/convert.rs:20-27`。

#### 5.6 mihomo、CMFA、Stash 的能力差异

| 运行时 | 探测 | supports_core_config | supports_core_management | supports_cache_flush | supports_memory | 说明 |
|---|---|---:|---:|---:|---:|---|
| mihomo | `/version` 有 version，且非 CMFA | true | true | true | true | 完整配置、核心管理、cache、memory |
| CMFA | version 小写包含 `cmfa` | false | false | true | true | `supports_core_actions` 仍为 true，但仅由 cache 能力贡献 |
| Stash | `/version` 404，root 有 `appVersion` | true | false | false | false | 配置 PATCH 只允许 mode/log-level/mixed-port |

计算逻辑：`core/src/clash/api/version.rs:36-50`。Dart 实际用 management/cache/DNS/memory 分开控制 UI，而不是只看 `supportsCoreActions`：`lib/session.dart:480-500`、`lib/screens/core_actions_screen.dart:94-104`。

CMFA/Stash 不是独立 BackendType，因此多数 FFI 函数不会在 Rust 分派层硬拒绝：直接调用 upgrade/restart/cache/provider 等函数仍会尝试相同 Clash endpoint。当前产品安全主要依赖 VersionInfo 和 UI 门控，而不是 FFI 层的强能力校验：`core/src/backend/control.rs:84-169`、`core/src/backend/providers.rs:27-75`。

Stash 特化：

- 配置 PATCH 会过滤到 `mode`, `log-level`, `mixed-port`；过滤后为空则本地报错：`core/src/clash/api/configs.rs:9,35-43,88-103`。
- Stash 没有 `/group`，group delay 改用缓存成员并发调用 node/provider healthcheck；默认并发 64：`core/src/clash/api/groups.rs:19-43,90-113`。
- Dart 也明确在 `isStash` 时跳过 group API，改走逐项 `proxyGroupDelayStream`：`lib/screens/proxies_screen.dart:147-180`。

### 6. Surge 实现

#### 6.1 传输与鉴权

- Surge 只有 HTTP/HTTPS REST 客户端，无 WebSocket；固定 15 秒 timeout，secret 作为 `X-Key` header：`core/src/surge/client.rs:27-39,42-83`。
- 非 2xx 保留完整 body 为 Upstream；空成功 body 转 `{ "ok": true }`：`core/src/surge/client.rs:67-82`。

#### 6.2 HTTP API inventory

| 区域 | 方法与路径 | 状态与语义 | 锚点 |
|---|---|---|---|
| 能力探测/mode | GET `/v1/outbound` | version 固定显示 “Surge”；endpoint 可达即确认 | `core/src/surge/api.rs:27-41,62-67` |
| 设置 mode | POST `/v1/outbound`, `{mode}` | UI global↔Surge proxy 映射 | `core/src/surge/api.rs:69-75`; `core/src/surge/api/config.rs:32-45` |
| 当前配置 | GET `/v1/profiles/current?sensitive=0` | 解析 profile 字符串的 `[General]`，再补 mode | `core/src/surge/api.rs:44-60`; `core/src/surge/api/config.rs:5-29,48-76` |
| 日志级别 | POST `/v1/log/level` | `patch_configs` 唯一支持的通用配置更新 | `core/src/surge/api.rs:77-100` |
| Reload | POST `/v1/profiles/reload` | 仅重载当前 profile；path/payload/force 在统一层被拒绝 | `core/src/surge/api.rs:102-108`; `core/src/backend/control.rs:94-101` |
| DNS flush | POST `/v1/dns/flush` | Surge 唯一 cache/DNS action | `core/src/surge/api.rs:110-116` |
| Traffic | GET `/v1/traffic` | 解析 interface 或多种字段别名 | `core/src/surge/api.rs:118-121`; `core/src/surge/api/traffic.rs:7-47` |
| Policy groups | GET `/v1/policy_groups` | catalog 根数据 | `core/src/surge/api/policies.rs:26-39` |
| Policy order | GET `/v1/policies` | 提取 policy-groups 顺序 | `core/src/surge/api/policies/parse.rs:25-35` |
| Group detail | GET `/v1/policies/detail?policy_name=` | 解析 type/selectable/hidden/icon-url | `core/src/surge/api/policies/parse.rs:127-165` |
| Current selection | GET `/v1/policy_groups/select?group_name=` | 读取 `policy` | `core/src/surge/api/policies/parse.rs:167-181` |
| Select policy | POST `/v1/policy_groups/select` | `{group_name, policy}` | `core/src/surge/api/policies.rs:114-127` |
| Test group | POST `/v1/policy_groups/test` | 随即读取 benchmark results | `core/src/surge/api/policies/delay.rs:11-21` |
| Benchmark results | GET `/v1/policies/benchmark_results` | 支持 map/array 和多种 delay 字段 | `core/src/surge/api/policies/delay.rs:24-74` |
| Test named policies | POST `/v1/policies/test` | 仅 names 非空且 test URL 非空时触发 | `core/src/surge/api/policies.rs:149-176` |
| Active requests | GET `/v1/requests/active` | raw snapshot、轮询和 bulk close 都使用 | `core/src/surge/api/connections.rs:8-14,24-73` |
| Kill request | POST `/v1/requests/kill`, `{id}` | ID 尽量转 number，否则 string | `core/src/surge/api/connections.rs:16-21,94-98` |
| Events/logs | GET `/v1/events` | 每 5 秒轮询、反转为旧→新、去重 | `core/src/surge/state/logs.rs:85-128` |
| Rules | GET `/v1/rules` | string/object 两种解析；本地 cache/filter/window | `core/src/surge/state/rules.rs:41-67,97-163` |

#### 6.3 策略、缓存、分页、排序

- 一次 catalog refresh 至少请求 `/v1/policy_groups`、benchmark、`/v1/policies`；每个 group 还各请求 detail 和 selected，存在按组增长的 REST fan-out：`core/src/surge/api/policies.rs:31-60`。
- hidden 由 group detail 决定；filter 匹配组名或成员；组顺序优先 `/v1/policies`，未知组再按 name：`core/src/surge/api/policies.rs:39-87`。
- Surge policy cache 是按 target key 的 HashMap，可同时保留多个 target；成员窗口在 Rust 端 sort 后 offset/limit：`core/src/surge/api/policies/cache.rs:13-38`、`core/src/surge/api/policies.rs:94-112`。
- member sort 支持 Original/Name/Delay；负 delay 最后，0 会排在正延迟之前：`core/src/surge/api/policies/parse.rs:209-218`。
- group test 是 POST 后立即 GET benchmark results，没有额外等待/轮询确认测试完成：`core/src/surge/api/policies/delay.rs:11-21`。
- Surge 不支持 fixed/unfix；catalog 的 `fixed` 总为空：`core/src/surge/api/policies.rs:67-77,129-131`。

#### 6.4 连接、日志、流量后台状态

- Connections 是可配置 interval 的 REST poll，默认 1000ms；每次成功 snapshot 后 sleep interval，失败用 5/10/20/30 秒退避：`core/src/surge/state/connections.rs:44-79,197-217`。
- 每个连接 poll 除 GET active requests 外还额外 GET traffic；traffic 失败被降为默认值，不使连接 frame 失败：`core/src/surge/state/connections.rs:220-229`。
- active/closed 都在 fetch 时按当前 sort 排序；closed 容量统一 500：`core/src/surge/state/connections.rs:101-121,253-280`。
- 无上游 ID 时用 host/source/destination/port/start 拼 fallback ID：`core/src/surge/state/connections/parse.rs:179-190`。
- Close all、by chain、by group 都先 GET snapshot，再逐个 await kill；每个 kill 错误被忽略，整体返回成功：`core/src/surge/api/connections.rs:24-73`。
- Traffic FFI 在 Rust 中每秒 GET `/v1/traffic`，直到 sink 断开；单次错误会结束 FFI stream，再由 Dart 重订阅：`core/src/backend/streams.rs:27-33`。
- Logs 每 5 秒 GET `/v1/events`，按 time/level/message 去重，500-entry ring，按 level filter；无 WS：`core/src/surge/state/logs.rs:13-24,85-128,168-180`。
- Rules cache 与 Clash 相似，是单一 active target slot；filter 不请求网络，window 保留原顺序：`core/src/surge/state/rules.rs:9-39,51-95`。

#### 6.5 明确受限/占位能力

- VersionInfo：core config=true；core actions/management/cache/memory=false：`core/src/surge/api.rs:31-41`。Dart 再把 DNS flush 合并进 actions 可见性：`lib/session.dart:493-496`。
- Provider raw/catalog 固定返回空，更新和 healthcheck 在统一层返回 unsupported：`core/src/surge/api.rs:123-139`、`core/src/backend/providers.rs:27-75`。
- Rules disable、FakeIP、DNS query、Geo、upgrade/restart、memory stream 都 unsupported：`core/src/backend/rules.rs:48-59`、`core/src/backend/control.rs:104-169`、`core/src/backend/streams.rs:64-67`。
- Basic Config 面板对 Surge 设为 read-only；mode 由单独 outbound card 修改：`lib/widgets/basic_config_panel.dart:90-132,177-220`。

### 7. sing-box 实现

#### 7.1 不是 HTTP/WS API，而是 gRPC

- sing-box 地址只接受 `grpc/http` 或 `grpcs/https` scheme，并统一转换为 tonic HTTP/2 endpoint；connect timeout 5 秒、request timeout 20 秒：`core/src/sing_box/client.rs:78-123`。
- secret 作为 gRPC metadata `authorization: Bearer ...`：`core/src/sing_box/client.rs:25-59`。
- Channel 按 base URL + allow-insecure 池化；认证 interceptor 每次 client 单独创建：`core/src/sing_box/client.rs:62-76,125-140`。
- tonic status 被映射为近似 HTTP status 的 `MihomoError::Upstream`：`core/src/utils/error.rs:56-90`。

#### 7.2 StartedService RPC inventory

| RPC | 使用状态 | Sparxie 行为 | 锚点 |
|---|---|---|---|
| GetVersion | 已实现 | 返回 version；`apiVersion` 未投影到 FFI | `core/proto/daemon/started_service.proto:7-8,31-34`; `core/src/sing_box/api.rs:17-24` |
| SubscribeLog | 已实现 | 直读 server stream；本地按 level 过滤/清 ANSI | `core/proto/daemon/started_service.proto:9`; `core/src/sing_box/state/logs.rs:6-33,36-76` |
| GetDefaultLogLevel | **仅声明** | 未找到 Rust 调用或 Dart 暴露 | `core/proto/daemon/started_service.proto:10` |
| ClearLogs | 已实现 | clear logs RPC | `core/proto/daemon/started_service.proto:11`; `core/src/sing_box/state/logs.rs:14-17` |
| SubscribeStatus | 已实现 | traffic/memory/goroutines/connectionsIn/Out stream | `core/proto/daemon/started_service.proto:12,36-38,64-74`; `core/src/sing_box/state/status.rs:122-146` |
| SubscribeGroups | 已实现 | catalog 读取首帧；URLTest 前后各读一帧 | `core/proto/daemon/started_service.proto:13`; `core/src/sing_box/api/proxies.rs:143-169` |
| GetClashModeStatus | 已实现 | config/mode/options 与能力探测 | `core/proto/daemon/started_service.proto:15`; `core/src/sing_box/api.rs:27-32,45-68` |
| SubscribeClashMode | **仅声明** | 未找到 Rust 调用或 Dart 暴露 | `core/proto/daemon/started_service.proto:16` |
| SetClashMode | 已实现 | mode 更新 | `core/proto/daemon/started_service.proto:17`; `core/src/sing_box/api.rs:71-78` |
| URLTest | 已实现 | 对 group/outbound tag 触发；等待最多 30 秒的下一 Groups 帧 | `core/proto/daemon/started_service.proto:19,96-98`; `core/src/sing_box/api/proxies.rs:156-169` |
| SelectOutbound | 已实现 | 策略选择 | `core/proto/daemon/started_service.proto:20,100-103`; `core/src/sing_box/api/proxies.rs:48-61` |
| SubscribeConnections | 已实现 | event stream + reset/new/update/closed reducer | `core/proto/daemon/started_service.proto:22,114-136`; `core/src/sing_box/state/connections.rs:197-224` |
| CloseConnection | 已实现 | 原生单个关闭 | `core/proto/daemon/started_service.proto:23,171-173`; `core/src/sing_box/api.rs:84-90` |
| CloseAllConnections | 已实现 | 原生全部关闭 | `core/proto/daemon/started_service.proto:24`; `core/src/sing_box/api.rs:93-96` |
| SubscribeTailscaleStatus | 已实现 | Tailscale status stream；NotFound 转空状态并正常结束 | `core/proto/daemon/started_service.proto:26`; `core/src/sing_box/api/tailscale.rs:12-40` |
| SetTailscaleExitNode | 已实现 | endpointTag + stableID | `core/proto/daemon/started_service.proto:27,218-221`; `core/src/sing_box/api/tailscale.rs:43-57` |
| TailscaleLogout | 已实现 | endpointTag | `core/proto/daemon/started_service.proto:28,223-225`; `core/src/sing_box/api/tailscale.rs:59-69` |

#### 7.3 proto 中声明但当前逻辑忽略的字段

- `Version.apiVersion`：proto 有字段，VersionInfo 只保留 version string：`core/proto/daemon/started_service.proto:31-34`、`core/src/sing_box/api.rs:17-24`。
- `Log.reset`：proto 有 reset，`logs_stream` 只遍历 messages，未处理 reset：`core/proto/daemon/started_service.proto:50-58`、`core/src/backend/streams.rs:122-131`。
- `Status.trafficAvailable`：proto 有字段，status projection 未读取：`core/proto/daemon/started_service.proto:64-74`、`core/src/sing_box/state/status.rs:62-88`。
- `Group.isExpand` 与 `GroupItem.urlTestTime`：proto 有字段，catalog 只使用 tag/type/selectable/selected/items/urlTestDelay：`core/proto/daemon/started_service.proto:76-94`、`core/src/sing_box/api/proxies.rs:171-214`。

#### 7.4 策略、缓存、分页和测速

- `proxyCatalog` 每次打开 SubscribeGroups 并只读取第一帧，不持续订阅；Dart 的 3 秒 catalog poll 因而间接刷新 sing-box groups：`core/src/sing_box/api/proxies.rs:22-29,143-154`、`lib/session.dart:469-476`。
- catalog 保留 stream 返回顺序；filter 匹配 group/member；忽略 include_hidden 参数，因为 proto 没有 hidden：`core/src/sing_box/api/proxies.rs:22-29,171-224`。
- member cache 按 target 保存；window 先 sort 后 offset/limit；负 delay 最后：`core/src/sing_box/api/proxies.rs:15-20,31-46,238-271`。
- URLTest 先读 initial groups，发 RPC，再等 30 秒下一帧；超时、stream 结束或错误时回退 initial，而不是报测速失败：`core/src/sing_box/api/proxies.rs:156-169`。
- 单节点 delay 不是独立 node RPC：如果 `run_test=true`，实际重新测试整个 group，再从缓存取目标节点：`core/src/sing_box/api/proxies.rs:112-140`。
- unfix 不支持；catalog fixed 始终默认空：`core/src/sing_box/api/proxies.rs:64-66,202-214`。

#### 7.5 status、connections、logs 状态流

- SubscribeStatus interval 由毫秒乘 1,000,000 转为纳秒；同 target+interval 的 traffic/memory 共享一个 gRPC stream 和 broadcast：`core/src/sing_box/state/status.rs:36-59,122-146`。
- status cache 保存 traffic total、memory、goroutines、connectionsIn/Out；connection frame totals 从该 cache 读取：`core/src/sing_box/state/status.rs:62-103`、`core/src/sing_box/state/connections/event.rs:28-33`。
- SubscribeConnections 也是 target+interval 共享 slot；event.reset 会同时清 active 和 closed：`core/src/sing_box/state/connections.rs:58-76,197-224`、`core/src/sing_box/state/connections/event.rs:9-27`。
- new/update/closed event 支持 delta 速度；closed 事件进入 500 FIFO，并可追加 `closed_at=` 日志：`core/src/sing_box/state/connections/event.rs:36-104`、`core/src/sing_box/state/connections.rs:227-232`。
- active/closed fetch 都在每次请求时按当前 sort 排序并 offset/limit：`core/src/sing_box/state/connections.rs:102-125`。
- Logs 没有 Rust ring/replay/reconnect loop；FFI 直接消费 tonic stream，出错后依赖 Dart 5/10/20/30 秒重订阅。时间字段固定为空：`core/src/sing_box/state/logs.rs:6-33`、`lib/session.dart:641-660,672-737`。
- Clear logs 调用真实 RPC；Dart 同时清本地 mirror：`core/src/sing_box/state/logs.rs:14-17`、`lib/session.dart:663-670`。

#### 7.6 Tailscale

- 仅 `BackendType::SingBox` 分支允许 status/logout/set exit node；其他后端直接本地报 unsupported：`core/src/backend/tailscale.rs:53-92`。
- status 包含 endpoint state、auth URL、network、MagicDNS、自身、用户组/peers、当前 exit node 和 key-auth：`core/src/backend/tailscale.rs:6-51`。
- peer 保留 stable ID、hostname、DNS、OS、IPs、online/active/exit-node flags、流量、key expiry、SSH host keys、last seen：`core/src/sing_box/api/tailscale.rs:71-124`。
- `tonic::Code::NotFound` 被转为空 `TailscaleStatus` 并作为成功完成，不显示“RPC 不支持”错误：`core/src/sing_box/api/tailscale.rs:16-38`。
- Dart Tailscale screen 只按 controller type==singBox 门控，不检查 `supportsTailscale`，并直接打开该 stream：`lib/screens/tailscale_screen.dart:63-108`。

#### 7.7 明确占位/unsupported 能力

- Provider raw/catalog 返回空；provider update/healthcheck unsupported：`core/src/backend/providers.rs:5-75`。
- Rules count=0、load/filter 默认 summary、window 空；disable unsupported：`core/src/backend/rules.rs:5-59`。
- Raw `connections()` 返回空 JSON，但结构化 connection stream 是真实实现：`core/src/backend/connections.rs:13-18,103-114`。
- patch config、reload、Geo、DNS/FakeIP、upgrade/restart、按链路/分组关闭均 unsupported；仅 Clash mode 可配：`core/src/sing_box/api.rs:45-108`、`core/src/backend/control.rs:84-169`。

### 8. Dart 会话层：后台轮询、流式更新与状态流

#### 8.1 默认节奏

- Connections interval 默认 1000ms；proxy catalog poll 默认 3000ms；logs level 默认 info：`lib/session.dart:58-64`。
- controller 激活后同时启动 traffic、connections、logs、proxy poll，并只在切换时探测 version 和 rule count；memory 在 VersionInfo 宣告支持后再订阅：`lib/session.dart:359-414,480-517`。
- Dart 对 traffic/memory/connections/logs 各自维护 5/10/20/30 秒 retry、subscription epoch 和 controller identity，丢弃旧 controller/旧 epoch 回调：`lib/session.dart:19-24,564-660,672-756`。
- Rust 层也对 Clash connections/logs/traffic/memory、Surge connections/logs、sing-box status/connections 做退避；因此错误恢复可能发生在 Rust producer 内，只有 producer 返回时才触发 Dart 外层 retry：`core/src/backend/retry.rs:1-27`。

#### 8.2 controller 切换与 stop

- 切换 controller 会取消所有 Dart subscriptions、清可见状态、重建 target、启动新流；旧结果用 identity/epoch 丢弃：`lib/session.dart:344-439,740-764`。
- 显式 `stopTargetStreams` 只对 Clash 生效；Surge/sing-box 分支没有 stop 实现，只依赖 receiver_count 自清理：`core/src/backend/connections.rs:271-274`。
- Surge/sing-box producer 在 retry sleep 中没有 Clash 的 watch tick 提前唤醒；取消后可能等待当前请求或 backoff 结束才清 slot：`core/src/surge/state/connections.rs:197-217`、`core/src/sing_box/state/status.rs:105-119`。

#### 8.3 暂停语义

- `connectionsPaused` 只丢弃 visible connection frame，网络和 Rust 状态继续更新；恢复后等下一帧自然刷新：`lib/session.dart:164-167,607-638`。
- Logs pause 只阻止 Dart mirror 添加；Clash/Surge Rust ring 仍继续积累，重新订阅时可 replay；sing-box 无 Rust ring，暂停期间到达的日志会丢失：`lib/session/logs.dart:7-28`、`core/src/clash/state/logs.rs:163-170`、`core/src/sing_box/state/logs.rs:6-33`。

#### 8.4 当前 Dart UI 已用与仅 FFI 导出

当前已用的核心路径包括：

- `proxyCatalog`/member windows/选择/unfix/group+node delay：`lib/session.dart:253-309,519-552`、`lib/screens/proxies_screen.dart:96-214`。
- connections stream/window/groups/sort/close/clear：`lib/session.dart:84-128,607-638`、`lib/screens/connections_screen.dart:83-166,819`。
- rules load/filter/window/disable：`lib/screens/rules_screen.dart:92-138,199-250`。
- provider catalog/update：`lib/screens/resources_screen.dart:177-225,299-346`。
- config/actions/Tailscale：`lib/widgets/basic_config_panel.dart:71-127,177-220`、`lib/screens/core_actions_screen.dart:118-188`、`lib/screens/tailscale_screen.dart:80-108,160-178`。

仓库内非生成 Dart 未找到调用、但 Rust 实现/FFI 已存在的主要函数：raw `groups`, `proxies`, `proxyDetail`, `connections`, raw `version`, `configMode`, `dnsQuery`, `upgradeUi`, `upgradeGeo`, `proxyDelay`, `proxyBatchDelay`, `proxyGroupBatchDelay`, `proxyProviderHealthcheck`, raw provider getters、storage CRUD。它们应标为“FFI 已导出但当前 UI 未调用”，而不是“仅声明”；对应签名见 `lib/src/rust/backend/api/{proxies,proxy_delay,providers,control,connections}.dart`。

### 9. 跨后端缓存、分页与排序对照

| 领域 | Clash-compatible | Surge | sing-box |
|---|---|---|---|
| Proxy catalog cache | 单一 target slot；每 3s GET `/proxies` 替换；保留旧 node detail 做 provider 补全 | target→catalog HashMap；每 3s 多 REST fan-out | target→member map；每 3s 打开 SubscribeGroups 读首帧 |
| Group order | GLOBAL.all 映射 + GLOBAL last + source fallback | `/v1/policies` 顺序，未知按 name | proto stream 原顺序 |
| Member sort | Original/Name/Delay；0 在负值前 | Original/Name/Delay；负值最后 | Original/Name/Delay；负值最后 |
| Member pagination | Rust full list，Dart min 96 + overscan 32 | Rust cache offset/limit | Rust cache offset/limit |
| Rules cache | 单一 target；原顺序；filter contains；window | 单一 target；原顺序；filter contains；window | 空占位 |
| Connections state | WS full snapshot；active map + closed FIFO 500 | REST snapshot；active map + closed FIFO 500 | event reducer；active map + closed FIFO 500 |
| Active sort | 缓存 sorted IDs，按 version/sort 失效 | fetch 时复制并排序 | fetch 时复制并排序 |
| Closed sort | newest-first FIFO，忽略 sort | 使用当前 sort | 使用当前 sort |
| Logs cache | Rust ring 500 + replay | Rust ring 500 + dedupe + replay | 无 Rust ring |

### 10. 错误处理与降级行为

#### 10.1 结构化错误

- HTTP/gRPC 错误统一跨 FFI 为 `MihomoError`，Dart 格式化器显示中文并保留后端名称、status 和原始 body：`core/src/utils/error.rs:16-29`、`lib/error_format.dart:6-25`。
- Invalid regex 在 Rust 入口编译并带 pattern/message 返回：`core/src/utils/error.rs:7-13,47-53`。

#### 10.2 被吞掉或转为空的错误

- Clash/Surge `rules_count` 任意错误都返回 0，UI 无法区分“真 0 条”与“endpoint 失败”：`core/src/clash/api/rules.rs:97-111`、`core/src/surge/state/rules.rs:41-48`。
- Clash bulk close、Surge close all/by chain/by group 忽略单个 close 失败，整体 best effort：`core/src/clash/api/connections.rs:89-100`、`core/src/surge/api/connections.rs:24-73`。
- Clash group delay 在 `/group` 404 时自动 fallback；Stash 直接 fallback：`core/src/clash/api/groups.rs:33-70`。
- Clash proxy catalog 的 provider enrichment 失败被忽略，继续返回现有缓存：`core/src/clash/api/proxies/catalog.rs:192-207`。
- Surge policy benchmark/order/group detail/selected 的部分失败用空/default 降级，因此 catalog 可能仍成功但缺 delay/order/meta/now：`core/src/surge/api/policies.rs:31-60`。
- sing-box URLTest 等待失败/超时回退 initial groups；Tailscale NotFound 转空成功：`core/src/sing_box/api/proxies.rs:156-169`、`core/src/sing_box/api/tailscale.rs:16-38`。
- JSON/WS 无效帧通常被静默跳过，不会结束流：`core/src/clash/state/connections/stream.rs:82-90`、`core/src/clash/state/logs.rs:156-162`、`core/src/clash/state/traffic.rs:184-190`。
- Dart connection window fetch 错误被静默忽略，等待下一 frame 触发重试：`lib/session/connections.dart:692-716`。
- VersionInfo 和 rule-count 探测错误被 Dart 视为 non-critical 并吞掉；能力 UI 保持隐藏或 count=0：`lib/session.dart:480-517`。

#### 10.3 Last-data 行为

- 单个 stream 出错时，Dart `_scheduleRetry` 不清 traffic/memory/connections/logs 已有值，只显示 error 并重订阅；controller 切换才全量 reset：`lib/session.dart:359-439,672-729`。
- Proxy catalog refresh 失败保留现有 `ProxiesNotifier`，只更新 session error：`lib/session.dart:519-552`。
- 但 sing-box logs 无 Rust replay，stream 错误到 Dart retry 成功之间的日志不可恢复：`core/src/sing_box/state/logs.rs:6-33`。

### 11. 关键审计风险

1. **流错误日志可能泄露凭证。** 多个 slot/target key 把 secret/X-Key 拼入 key，错误日志又直接打印该 key：
   - Clash connections key 含 secret：`core/src/clash/state/connections.rs:56-62`；错误打印：`core/src/clash/state/connections/stream.rs:39-43`。
   - Clash logs/traffic key 含 secret：`core/src/clash/state/logs.rs:45-51,112-116`、`core/src/clash/state/traffic.rs:83-89,132-136`。
   - Surge `target_key` 含 X-Key：`core/src/surge/client.rs:86-92`；connections/logs 错误打印 key：`core/src/surge/state/connections.rs:212-215`、`core/src/surge/state/logs.rs:97-100`。
   - sing-box `target_key` 含 secret：`core/src/sing_box/client.rs:125-132`；status/connections 错误打印 key：`core/src/sing_box/state/status.rs:114-117`、`core/src/sing_box/state/connections.rs:189-192`。
   这与 Mica “exports/logging 不应包含凭证”的边界冲突，不能照搬。

2. **CMFA/Stash 能力门控不在 FFI 强制执行。** 它们仍是 BackendType::Clash；直接调用不受支持操作会实际打 endpoint，只是正常 UI 根据 VersionInfo 隐藏。锚点：`core/src/backend/target.rs:1-14`、`core/src/clash/api/version.rs:36-50`、`core/src/backend/control.rs:84-169`。

3. **某些统一 API 用“空成功”表示不支持。** sing-box raw connections/rules/providers，Surge providers 都可能让上层把“不支持”误判为“真实空数据”：`core/src/backend/connections.rs:13-18`、`core/src/backend/rules.rs:5-45`、`core/src/backend/providers.rs:5-67`。

4. **sing-box Tailscale capability 被无条件标为 true。** VersionInfo 不探测 RPC；screen 又只按 backend type 显示。旧 daemon/无 Tailscale 时 NotFound 被转为空状态：`core/src/sing_box/api.rs:27-42`、`core/src/sing_box/api/tailscale.rs:16-38`、`lib/screens/tailscale_screen.dart:71-88`。

5. **策略组顺序与 Mica 当前 durable contract 不同。** Sparxie 用 `GLOBAL.all` 重排 peer groups；Mica spec 要求 peer groups 保持 controller `proxyOrder`，GLOBAL 只做稳定 last partition：Sparxie `core/src/clash/api/proxies/catalog.rs:45-52,86-95,293-314`；Mica `.trellis/spec/backend/controller-data-contract.md:14-23`、`.trellis/spec/frontend/workbench-ui-contract.md:28-32`。功能对齐时不能机械复制 Sparxie 的排序。

6. **Controller secret 在 Sparxie Dart 配置 JSON 中直接序列化。** `Controller.toJson` 写入 `secret`：`lib/controller.dart:60-76`。Mica spec 明确禁止 secret 进入 RouterProfile/routers.json，而使用独立 SecretStore：`.trellis/spec/frontend/workbench-ui-contract.md:38-40`。该参考实现不可照搬。

7. **按策略切换自动关闭存在 sing-box 跨层不匹配。** UI 的 group close mode 在任何后端选择成功后 fire-and-forget 调 `closeConnectionsByChain`；sing-box 明确 unsupported，且该 Future 没有本地 catch：`lib/screens/proxies_screen.dart:109-119`、`core/src/sing_box/api.rs:98-104`。

8. **`stopTargetStreams` 只覆盖 Clash。** controller 切换时 Dart 对所有后端调用，但 Rust 仅停止 Clash；Surge/sing-box 依靠 receiver_count，无法在 backoff 中立即唤醒：`lib/session.dart:344-357`、`core/src/backend/connections.rs:271-274`。

### 12. External references / versions

- 未联网验证任何外部文档；以下只记录仓库内声明。
- README 声明 sing-box 状态、代理组、连接、日志、Tailscale 基于 `1.14.0-alpha.31`：`tmp/codex/sparxie/README.md:9-13`。
- Rust 关键依赖版本：flutter_rust_bridge 2.12.0、reqwest 0.12、tokio 1.52、tokio-tungstenite 0.29、tonic/prost 0.14：`tmp/codex/sparxie/core/Cargo.toml:19-41`。
- sing-box proto 在构建时用 vendored protoc 编译，仅生成 client，不生成 server：`tmp/codex/sparxie/core/build.rs:10-23`。
- Clash config 注释引用 mihomo `hub/route/configs.go` 作为完整 schema 来源，但本次未联网核对该链接或具体 commit：`tmp/codex/sparxie/core/src/clash/api/configs.rs:26-34`。
- Surge API 只从代码确认使用 `/v1/*`；仓库未固定 Surge app/API 版本，也未附官方 API 文档。

### 13. Related specs

- `.trellis/tasks/07-17-sparxie-feature-parity/prd.md` — 要求以真实数据源、请求、状态转换、操作和错误为证据，并禁止运行真实核心。
- `.trellis/spec/backend/controller-data-contract.md` — Mica 的 `/proxies` 顺序、hidden、nil 和错误契约；特别注意与 Sparxie GLOBAL 排序差异。
- `.trellis/spec/frontend/live-session-controller-contract.md` — Mica 的 generation、2/5/30 秒 lanes、pause、last-data、bounded buffers；Sparxie 的 1 秒 connections、3 秒 proxy poll、5 秒 Surge logs 和双层 retry 仅作为参考，不是 Mica 目标契约。
- `.trellis/spec/frontend/workbench-ui-contract.md` — 活动业务数据全可见、export 排除凭证/raw body、controller order 与 session cadence 的 durable contract。
- `.trellis/spec/guides/cross-layer-thinking-guide.md` — 本审计按 Controller→Dart target→FRB→Rust dispatch→HTTP/WS/gRPC→Rust cache→Dart window 的完整链路检查。

## Caveats / Not Found

- 未运行任何真实 mihomo/CMFA/Stash/Surge/sing-box controller，因此“真实 endpoint”表示代码会实际发出的请求/RPC，不代表所有目标版本都已运行验证。
- 未联网核对 mihomo、Stash、Surge 或 sing-box 官方 API 文档；版本兼容性只来自本地代码、proto 和 README。
- 没有找到独立 CMFA module、CMFA endpoint adapter 或 CMFA-specific parser；CMFA 只由 version 字符串与能力标志区分。
- 没有找到 Stash 独立连接/log/traffic/provider schema；除 config filter 和 group-delay fallback 外，Stash 复用 Clash parser，实际字段差异只能通过运行或 fixture 验证。
- `tmp/codex/sparxie` 中只找到 `test/widget_test.dart`，没有发现 Rust backend/API/state 单元测试或 fixture 测试；本清单中的 fallback、分页、重连和错误语义缺少本地自动化证明。
- “当前 Dart UI 未调用”的判断来自对 `tmp/codex/sparxie/lib` 非生成 Dart 的静态调用搜索；未来代码、插件或外部 package 仍可能直接调用这些 FFI。
- 生成的 Dart API 证明 FFI surface 存在，不证明目标 controller 支持；调用前仍需结合 BackendType、VersionInfo 和 endpoint-specific error。
- `MihomoError::Upstream` 与 Dart formatter保留并展示完整响应 body；若未来复制到诊断/导出路径，必须额外执行 Mica 的 raw response body 排除规则：`core/src/utils/error.rs:10-12`、`lib/error_format.dart:13-17`。
