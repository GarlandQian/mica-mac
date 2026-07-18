# Sparxie 功能对齐与缺陷修复

## Goal

以 Sparxie 的实际控制器能力和数据语义为功能参照，修正 Mica 已证实的协议、会话和交互缺陷，并在不引入本地核心生命周期的前提下，让远程控制器工作台达到可验证、可理解、业务数据完整可见的功能对齐。

## Background

- 参考项目：`https://github.com/UruhaLushia/sparxie`，本次审计固定在提交 `32bd802c546d14ebead1cd9e618c3bba4c484fc8`。
- Mica 保持原生 macOS 27 / Swift / SwiftUI / Liquid Glass 架构。Sparxie 只用于对照控制器功能、字段语义和用户工作流，不复制或链接其 Flutter/Rust 实现，也不复制其页面布局。
- 活动控制器工作区中的主机、请求 URL、连接 ID、来源名、节点名、策略名、规则内容、链路和日志文本必须全量可见。普通诊断导出仍排除凭证、令牌、X-Key、订阅 URL、授权头、Keychain 内容及原始响应/流正文。
- 研究资料位于 `research/sparxie-ui-feature-inventory.md`、`research/sparxie-backend-api-inventory.md`、`research/official-protocol-findings.md`、`research/sing-box-native-swift-transport.md` 和 `research/sparxie-license-boundary.md`；固定参考 checkout 在研究完成后已按临时目录规则从 `tmp/codex/` 清理。
- 当前静态契约检查和 90 个 Swift 测试全部通过，但没有覆盖下列真实协议错误。这证明后续验收必须加入上游响应形状和 method/path/body 级 fixture 测试，不能只依赖源码字符串检查。

## Confirmed Defects

### P0: 自动检测没有完成后端识别，并阻断实时流

- `testSelectedRouter` 和实时会话只在配置值明确为 Surge 时进入 Surge 分支；`Auto Detect` 固定走 Mihomo 探测与流通道：`Sources/Mica/App/AppModel.swift:631`、`Sources/Mica/App/AppModel.swift:662`、`Sources/Mica/App/AppModelLiveSession.swift:214`、`Sources/Mica/App/AppModelLiveSession.swift:741`。
- 自动检测初始 capability 把 traffic/log 等实时能力置为不可用；刷新后即使形成真实快照，也不会重新启动流：`Sources/Mica/App/AppModelReadiness.swift:595`、`Sources/Mica/App/AppModelReadiness.swift:763`。
- 用户影响：默认自动检测配置可能能加载一次 Mihomo 快照，但不会启动 traffic/log WebSocket，也无法真正识别 Surge 或 sing-box。
- 修复要求：建立一次明确、可缓存、可失效的后端 probe；probe 结果必须驱动 REST/WS/gRPC 分派与能力矩阵，并在能力从未知转为可用后启动相应流。

### P0: Mihomo 策略组测速响应解码错误

- 官方 `GET /group/{group}/delay` 返回顶层 `{ "node": milliseconds }`，Mica 却要求 `{ "delay": { ... } }`：`Sources/MicaCore/Models/MihomoModels.swift:410`、`Sources/MicaCore/API/MihomoClient.swift:202`。
- 用户影响：真实 Mihomo 的策略组测速可能稳定失败。
- 修复要求：按官方顶层映射解码，同时用上游形状 fixture 验证成功、超时、缺失成员和非法值。

### P0: Mihomo 内存传输和单位均错误

- 官方 `/memory` 是持续 GET/WS 流，`inuse`、`oslimit` 的单位是 bytes；Mica 将其作为一次性请求：`Sources/MicaCore/API/MihomoClient.swift:146`。
- Mica 模型把值命名为 KB，并在显示前再次乘以 1024：`Sources/Mica/App/OperationSessionModels.swift:545`、`Sources/Mica/App/AppModelRuntimeOperations.swift:303`、`Sources/Mica/App/AppModelDiagnosticsRuntimeOperations.swift:261`。
- 用户影响：请求可能超时；即使解码成功，显示值也可能放大 1024 倍。
- 修复要求：使用受会话生命周期管理的内存流，内部统一存储 bytes，并补齐取消、重连、后端切换和格式化测试。

### P0: Surge 三个关键动作使用了错误端点

- 选策略应为 `POST /v1/policy_groups/select`，body 为 `{group_name, policy}`；Mica 使用 `POST /v1/policy_groups/{group}`：`Sources/MicaCore/API/SurgeHttpAPIClient.swift:299`。
- 组测速应为 `POST /v1/policy_groups/test`，body 为 `{group_name}`；Mica 使用 `GET /v1/policy_groups/{group}/test`：`Sources/MicaCore/API/SurgeHttpAPIClient.swift:303`。
- 关闭请求应为 `POST /v1/requests/kill`，body 为 `{id}`；Mica 使用 `DELETE /v1/requests/active/{id}`：`Sources/MicaCore/API/SurgeHttpAPIClient.swift:307`。
- 用户影响：Surge 选策略、组测速和关闭连接在真实控制器上不可用。
- 修复要求：修正 method/path/body，增加请求构造测试和常见响应变体 fixture；Surge API 仅使用官方 GET/POST 契约。

### P0: 异步动作缺少完整 generation 隔离

- 多个模式切换、节点选择、测速、关闭连接、provider 更新、规则/来源刷新任务只检查取消或控制器 ID，没有同时验证控制器 ID 与 session generation：`Sources/Mica/App/AppModel.swift`、`Sources/Mica/App/AppModelSurgeOperations.swift`、`Sources/Mica/App/AppModelRuntimeOperations.swift`。
- 替换或删除当前控制器时会离开 live session，但不会取消全部 operation task：`Sources/Mica/App/AppModelSelectionState.swift:264`、`Sources/Mica/App/AppModelLiveSession.swift:65`。
- 用户影响：编辑同 ID 控制器、删除控制器、休眠或关闭最后窗口后，旧请求可能把结果写入新会话或已失效界面。
- 修复要求：所有异步 apply 统一验证 controller ID + generation；控制器替换、删除、睡眠、最后窗口关闭时取消关联操作并禁止旧结果落地。

### P1: 日志不是纯控制器日志，暂停和跟随语义错误

- 控制器日志与应用内部的刷新/启动状态共用同一 `BoundedLogBuffer`，并会构造“已加载”日志：`Sources/Mica/App/AppModelLiveSession.swift:632`、`Sources/Mica/App/AppModelLiveSession.swift:749`、`Sources/Mica/App/AppModelLiveSession.swift:884`、`Sources/Mica/App/DashboardSessionModels.swift:146`、`Sources/Mica/App/DashboardSurgeProjectionModels.swift:48`。
- `/logs` 未发送上游 `level` 和 `format=structured`，远端时间与结构化字段被丢弃：`Sources/MicaCore/API/MihomoEndpoint.swift:57`、`Sources/MicaCore/API/MihomoClient.swift:155`。
- 日志页“暂停”调用全局工作台暂停，而不是仅暂停日志呈现：`Sources/Mica/App/WorkbenchRulesSourcesLogsViews.swift:590`。
- 跟随底部没有根据用户滚动位置自动解除，查看旧日志时可能被新日志强制拉回。
- 修复要求：分离应用状态和控制器日志；订阅时传递等级并保留远端时间/字段；日志暂停、清空和跟随仅作用于日志域。

### P1: 来源更新能力门控错误

- 当前 provider 模型未保留 `updatable`/format 等字段；检查器在后端一般支持更新时为所有来源启用按钮：`Sources/MicaCore/Models/MihomoModels.swift:475`、`Sources/MicaCore/Models/MihomoModels.swift:557`、`Sources/Mica/App/WorkbenchRulesSourcesLogsViews.swift:407`。
- 用户影响：File/Compatible 等不可更新来源会显示无效动作并产生可避免的失败。
- 修复要求：保留上游能力字段，按具体来源决定更新、健康检查和批量动作是否可用。

## Feature Parity Requirements

### R1: 能力探测与后端矩阵

- 区分“导航可见”“数据可读”“动作可写”“流式可用”，不得因页面存在或 API 类型存在就宣称支持。
- Mihomo、CMFA、Stash、Surge、sing-box 的 probe 结果必须产生明确能力矩阵；未知后端显示可诊断的受限状态，不得误走其他协议。
- 保留 Mica 既定行为：首个控制器可自动连接但不抢占已有会话；不自动故障转移。

### R2: 策略组与节点

- 策略组保持控制器报告的源顺序，`GLOBAL` 稳定放在最后；不得复制 Sparxie 对组顺序的二次重排。
- 同窗支持多组展开、横向顺序的错落网格、组内节点过滤、节点选择、固定状态/取消固定、单节点测速和组测速。
- 节点必须保留上游可见字段，包括 alive、history、icon、test URL、provider、fixed 和传输能力；筛选无匹配时显示正确空状态。

### R3: 概览、流量与内存

- 显示上传/下载当前速率、累计流量、近期趋势、连接数、内存与后端可提供的 goroutine/入站/出站指标。
- 不以虚构日志或占位业务数据填充概览；首次加载、暂时无帧、流错误和暂停必须是不同状态。

### R4: 连接

- 使用后端最适合的实时机制；Mihomo 不应仅靠固定 2 秒轮询替代可用连接流。
- 保留每连接上传/下载累计与速度、完整 metadata、规则、代理链、特殊代理/规则、remote destination、建立时间和可用的连接日志。
- 支持活动/已关闭、筛选、排序、按进程/来源分组、单条关闭、关闭全部和关闭来源组；关闭后的保留窗口遵循已确认的产品规则。

### R5: 日志

- 日志等级必须影响上游订阅，支持内容过滤、独立暂停、清空、远端时间/结构字段和用户滚离底部后的“回到底部”。
- 无源日志与无匹配日志分别显示，不得混入应用内部运行日志。

### R6: 规则与来源

- 规则保留 index、disabled、hit/miss 和时间字段；支持过滤、窗口化呈现，并仅在后端真实支持时提供启用/禁用。
- proxy/rule provider 保留类型、behavior、format、更新时间、数量和 updatable；支持单项/全部更新、目录刷新及后端可用的健康检查。

### R7: 配置与操作

- 按后端能力提供出站模式、日志级别、TUN、LAN、IPv6、TCP concurrent 和端口读写；不支持的字段不显示可编辑控件。
- 对齐远程可执行动作：配置重载、GeoData 更新、DNS/FakeIP 清理、provider/rule 刷新，以及后端真实支持且不涉及 Mica 本地核心生命周期的远程维护动作。
- 所有破坏性/高风险动作可确认；普通策略、节点和筛选操作保持同窗完成。

### R8: CMFA、Stash、sing-box 与 Tailscale

- 当前 Mica 仅对 Mihomo/Nikki/OpenClash 和 Surge 提供真实适配；CMFA/Stash/sing-box 仍是 capability-only 或 unavailable：`Sources/MicaCore/API/UnifiedControllerAdapters.swift:142`、`Tests/MicaCoreTests/UnifiedControllerModelsTests.swift:19`。
- 本任务补齐这些远程后端的状态、策略组、连接、日志和各自能力；sing-box 还包括 Tailscale 状态与操作。
- 不把 Sparxie 后端自身标记 unsupported 的动作包装成可用功能。

### R9: 会话、错误和数据一致性

- 控制器切换、编辑、删除、睡眠、窗口关闭、断线重连和暂停都必须有明确状态机；旧会话结果不得污染新会话。
- 错误不得无条件清空仍有效的旧数据；首次加载、刷新失败、无数据、无匹配和能力不支持必须分别表达。
- Active UI 全量显示业务数据；导出边界仅保护凭证和原始 payload。

## Recommended Delivery Phases

1. **协议与会话正确性**：修复自动检测、Mihomo delay/memory/log/connection streams、Surge 动作端点、generation 隔离，并建立上游形状 fixture。
2. **现有后端数据完整性**：补齐 Mihomo/Surge 的代理、连接、日志、规则、provider、配置和动作字段及工作流。
3. **远程后端功能对齐**：补齐 CMFA、Stash、sing-box 和 Tailscale；共用统一能力矩阵，但各后端保持真实协议边界。
4. **跨页面验收与回归**：验证切换/暂停/重连/错误/空状态、筛选排序、全量可见和 macOS 原生交互。

每个阶段应可独立测试和提交，P0 正确性不得等待后续 UI 扩展完成。

## Scope Decision

- 采用完整远程功能对齐：本任务纳入 Mihomo、Surge、CMFA、Stash、sing-box 和 Tailscale；“完整”指远程控制器可提供的状态、数据流、配置和操作。
- 交付顺序固定为：协议与会话正确性、现有后端数据完整性、远程后端扩展、跨页面回归。
- Mica 不管理本地核心进程、不下载或升级本地核心，也不接管系统代理。
- 用户已明确要求原生 Swift。Mica 保持 MIT，通过独立 Swift 实现完成协议、状态和功能对齐。

## License Boundary

- Sparxie 在固定参考提交中使用 GPLv3；Mica 当前根许可证为 MIT。
- MIT 代码可以进入 GPLv3 组合，但如果直接复制 Sparxie 源码或把其 Rust 状态引擎作为同一应用的紧密链接组件分发，组合后的应用通常需要遵守 GPLv3，包括对应源代码、修改声明和许可证通知等义务。
- 不把 Sparxie GPLv3 源码复制、改写后粘贴或链接进 Mica；只研究其公开行为、协议和数据契约，并使用原生 Swift 独立实现。
- 证据与影响记录在 `research/sparxie-license-boundary.md`。此记录不是针对具体发行场景的法律意见。

## Acceptance Criteria

- [x] AC1: 自动检测能识别支持的远程后端，按 probe 结果启动正确数据流；能力变化后不会停留在初始不可用状态。
- [x] AC2: Mihomo group delay、memory、logs、connections 使用官方响应/流契约，并由上游形状 fixture 覆盖。
- [x] AC3: Surge 选策略、组测速和关闭请求使用官方 method/path/body，并由请求构造测试覆盖。
- [x] AC4: 所有异步结果在写入前验证 controller ID + generation；控制器替换/删除和生命周期事件取消旧任务。
- [x] AC5: 策略组源顺序稳定、`GLOBAL` 最后；多展开、组内过滤、选点、固定/取消固定及单点/组测速均可用。
- [x] AC6: 概览、连接、日志、规则、来源、配置和操作显示其后端实际返回的完整业务字段，不包含模拟或构造业务数据。
- [x] AC7: 日志暂停不冻结其他页面；控制器日志与应用状态分离，过滤、等级、清空和滚动跟随语义正确。
- [x] AC8: UI 只对真实可用的规则/provider/配置/维护动作提供控件，失败有明确且不破坏旧数据的反馈。
- [x] AC9: 每个纳入范围的后端都有能力矩阵、协议 fixture、适配器测试和跨控制器切换回归测试。
- [x] AC10: 现有静态 verifier、Swift 测试及新增协议/状态测试通过；不得通过真实核心、系统代理或危险系统改动验证。
- [x] AC11: `prd.md`、`design.md`、`implement.md` 通过收敛检查，`implement.jsonl` 与 `check.jsonl` 包含真实研究/规范上下文，并在实施前获得用户批准。
- [x] AC12: 临时资料集中在 `tmp/codex/`，任务完成时清理不再需要的 checkout、build 和日志。

## Verification Outcome

- `swift build --scratch-path tmp/codex/sparxie-parity-build` passed.
- `swift test --scratch-path tmp/codex/sparxie-parity-build` passed: 83 XCTest cases plus 103 Swift Testing cases.
- Xcode workspace build and test passed with repository-local DerivedData. The expected local-SDK warning remains because the project intentionally targets macOS 27 while the installed SDK advertises support through 26.5.99.
- `scripts/verify-real-controller-source.mjs`, localization JSON validation, `git diff --check`, project Skill `quick_validate.py`, reference/symlink checks, and the Apple HIG batch all passed; HIG score was 100 with no violations.
- Runtime smoke and real-controller/core execution were intentionally not run. No system proxy, firewall, environment, OpenWrt, SSH, LuCI, or `ubus` state was changed.

## Out Of Scope

- 复制或链接 Sparxie 的 GPLv3 Flutter/Rust 源码，以及复制其 Web/Flutter 风格布局或像素级外观。
- 在 Mica 内下载、捆绑、启动、升级或管理本地代理核心。
- 修改系统代理、环境变量、防火墙、OpenWrt、LuCI、SSH 或 ubus。
- 复制 Sparxie 将 secret 明文写入配置、可能泄露流 key/日志或其已知筛选/空状态缺陷的行为。
- 改变已确认的策略组源顺序、`GLOBAL` 最后、控制器选择或自动故障转移规则。
