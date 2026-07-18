# Sparxie 功能对齐技术设计

## Design Read

原生 macOS 专业控制器工具，面向高频扫描、筛选和操作；视觉密度高、动效克制、层级由系统 sidebar/toolbar/table/material 与少量交互式 Liquid Glass 构成。`macos-app-design`、`apple-hig-expert` 和 `swiftui-liquid-glass` 是最终设计权威，`design-taste-frontend` 只用于反模板化、节奏、对比度和形状一致性检查。

## Architecture Fit

- **选择**：Clean Architecture 式边界 + 单向 session event/reducer + SwiftUI `@Observable` presentation state。
- **Fit**：任务跨协议、实时流、状态机和全部工作台页面，需要可替换 transport、严格 generation 隔离和确定性测试；单纯扩展当前大型 `AppModel` 会继续放大耦合。
- **不采用**：Flutter、Rust、TCA 或兼容旧 UI 的 adapter wrapper。状态与协议全部由原生 Swift 6.2 独立实现。

## System Boundaries

### MicaCore

负责纯 Swift、无 UI 的协议和领域层：

1. `Transport`
   - `ControllerHTTPTransport`：可注入的 HTTP 请求执行器，生产环境使用 `URLSession`，测试使用 recording transport。
   - `ControllerWebSocketTransport`：将 URLSession WebSocket 转换为有界 `AsyncThrowingStream<Data, Error>`。
   - `SingBoxGRPCTransport`：使用 gRPC Swift 2、SwiftNIO HTTP/2 transport 和 SwiftProtobuf 连接 sing-box StartedService。
2. `Protocol`
   - Mihomo/Clash-compatible、Surge HTTP API、sing-box gRPC 的 request builder、decoder、stream decoder 和 action client。
   - CMFA、Stash、OpenClash、Nikki 是运行时 variant，不复制同一协议的客户端。
3. `Domain`
   - 完整业务模型、运行时后端描述、细粒度能力集合、endpoint 状态和 action 定义。
   - 数组保存上游顺序；字典只用于按 ID 查找，不作为可见顺序来源。
4. `Session`
   - `ControllerSessionEngine` actor 持有一个 controller ID + generation + detected backend。
   - actor 统一启动/取消 REST lanes、WebSocket、gRPC stream 和 Surge polling，并输出 `AsyncStream<ControllerSessionEvent>`。

### Mica executable

负责主线程状态与原生界面：

1. `AppModel` 只管理 profile 事务、当前 session identity、菜单能力和 presentation root。
2. `ControllerWorkspaceState` 是当前 generation 的完整可见状态，按 domain 拆成 overview、policies、connections、logs、rules、providers、configuration、actions 和 Tailscale。
3. session event 通过一个 reducer 落地；每次 apply 先验证 controller ID + generation。
4. SwiftUI view 只读取 presentation projection 和发送 intent，不直接创建网络 task、排序源集合或解析协议。

## Backend Identity And Probe

`RouterProfile.controllerKind` 是用户 hint，不再直接等同于运行时后端。新增两层身份：

```swift
enum ControllerProtocolFamily {
    case clashHTTP
    case surgeHTTP
    case singBoxGRPC
}

enum ControllerRuntimeVariant {
    case mihomo
    case openClash
    case nikki
    case cmfa
    case stash
    case surge
    case singBox
    case unknown
}
```

- 显式类型先验证对应 family，再探测 variant 和能力。
- Auto Detect 使用无副作用、带短超时的 probe；第一个具备身份凭据的成功结果成为该 generation 的 backend descriptor。
- probe 完成前只显示 checking，不启动错误 family 的流。
- probe 完成后立即按能力启动 streams/lanes；重新探测改变 backend 时创建新 generation，不在原 generation 内热换协议。
- unknown/unsupported 不回退到 Mihomo，必须保留可诊断 endpoint 结果。

## Capability Model

用 `Set<ControllerCapability>` 取代不断膨胀的 Bool struct。能力按读、流和动作拆分，例如：

- 数据：version、configuration、policyGroups、connections、closedConnections、logs、rules、proxyProviders、ruleProviders、memory、traffic、tailscale。
- 实时：trafficStream、memoryStream、connectionStream、logStream、groupStream、tailscaleStream。
- 动作：selectNode、clearFixedSelection、testNode、testGroup、closeConnection、closeAllConnections、setRuleEnabled、updateProvider、healthCheckProvider、setMode、setLogLevel、setTun、setLAN、setIPv6、setTCPConcurrent、setPort、reloadConfiguration、updateGeoData、flushDNS、flushFakeIP、setTailscaleExitNode、tailscaleLogout。

UI 可见性和 enabled 状态只消费这一个集合。能力由 probe + runtime response 共同产生，不以页面类型或 controller hint 猜测。

## Domain Data Contract

### Policies

- `PolicyGroup` 保存 name/type/now/all/hidden/icon/testURL/fixed/provider/alive/history 和 controller order index。
- `PolicyNode` 保存完整名称、类型、延迟历史、alive、UDP、transport/provider/fixed 等上游字段。
- decode 层保留 source order；presentation 仅稳定地把可见 `GLOBAL` 追加到末尾。
- 组内过滤大小写不敏感，作用于完整成员集合，保留重复和原始顺序；分页窗口在过滤后执行。

### Traffic And Memory

- 所有流量/内存内部单位为 bytes；格式化只发生在 presentation。
- `TrafficSample` 保存远端或接收时间、上下行速率和可用累计值。
- `MemorySample` 保存 in-use、limit、goroutines 和后端特有计数；禁止 KB 命名和二次换算。

### Connections

- 保留完整 ID、metadata、source/destination、host、process、rule、chains、special proxy/rules、remote destination、累计字节、速率和时间。
- 活动连接按 ID 合并 snapshot/event；closed buffer 保留最新重复 ID，并遵守 1000 条/16 MiB 预算。
- 排序和筛选只生成 presentation projection，不改变 session source collection。

### Logs

- `ControllerLogEntry` 只表示控制器日志，保存远端时间、level、message 和 structured fields。
- 应用运行状态进入独立 `AppEventLog`，不出现在 Logs 工作区。
- upstream level 改变会重建日志订阅；本地内容筛选不重建订阅。

### Rules And Providers

- 规则保存 index/type/payload/proxy/extra/disabled/hit/miss/timestamps。
- provider 保存 vehicle/behavior/format/count/updatedAt/updatable/healthCheck 和后端附加字段。
- action availability 由每条记录和 capability 共同决定。

### Configuration And Tailscale

- 配置字段是可选 typed values，并分别带 read/write capability；不存在或只读时不显示可写控件。
- Tailscale 保存 endpoint 状态、认证 URL、网络、self、用户组、peers、exit node 和字节计数；放在 Configuration 的 capability-gated 同窗 section，不增加常驻 sidebar destination。

## Protocol Implementation

### Mihomo / CMFA / Stash / OpenClash / Nikki

- REST：version、configs、proxies、rules、providers 和动作。
- WebSocket/stream：traffic、memory、connections、logs。
- group delay 按顶层 node-to-delay object 解码。
- logs 发送 upstream level 和 `format=structured`。
- variant probe 决定 config/actions/provider/rule toggle/connection-log 等细分能力。

### Surge

- 只使用官方 GET/POST。
- 选策略、组测速、关闭请求采用官方固定 endpoint 和 body。
- traffic 1 秒、logs 5 秒等 near-live polling 由 session actor 调度；相同 endpoint 单飞并合并一次 follow-up。
- response decoder 对官方和已观察到的可选字段保持容错，但不吞掉类型错误。

### sing-box

- 原生 Swift gRPC client 使用 StartedService proto，支持 version、status、groups、mode、URL test、select outbound、connections、logs 和 Tailscale。
- 依赖采用 gRPC Swift 2 系列：`grpc-swift-2`、`grpc-swift-nio-transport`、`grpc-swift-protobuf`。实施时先做 Swift 6.2/macOS 27 编译 spike，再固定相互兼容的精确版本。
- `.proto` 作为协议来源提交；生成 Swift 文件通过可复现脚本生成并提交，普通构建不要求用户本机安装 protoc。
- gRPC stream cancellation 必须由 generation task tree 传播到底层 client channel。

## Session State Machine

```text
idle -> probing -> connecting -> live
                     |           |
                     v           v
                   partial <-> reconnecting
                     |
                     v
                   failed
```

- `SessionIdentity` 包含 controller ID、generation 和 backend descriptor。
- `ControllerSessionEngine` 是 task owner；不在各 view 或 AppModel extension 中散落裸 `Task {}`。
- lanes 和 streams 使用 structured child tasks；所有 stream 明确有界，并在 termination 时取消底层 request。
- endpoint 成功更新 value/lastSuccessAt；后续失败保留 value 并标记 stale。只有从未成功的 endpoint 才进入 error empty state。
- active profile save/delete、选择变化、sleep、final-window close 都先 invalidate generation，再取消 task tree。

## Pause Semantics

- 全局 Presentation Pause 继续遵循现有规范：网络继续、所有可见业务数据冻结，resume 原子发布最新 pending state。
- Connections 和 Logs 增加各自的局部暂停；只冻结该 surface，不影响 Overview 或其他页面。
- 局部暂停不丢数据：session buffer 继续有界更新，resume 时一次发布当前 state。该行为比 Sparxie 丢帧实现更符合 Mica 的全量可见目标。

## Action Transactions

- 每个 action 由 `ControllerActionExecutor` actor 接收 `SessionIdentity` 和 typed payload。
- maintenance/destructive action 每 controller 串行；节点/组测速按资源 ID 单飞，互不相关的低风险动作可并行。
- 网络完成后只发出带 identity 的 event；reducer 再次验证 generation。
- 乐观更新仅用于节点选择、规则开关等可安全回滚动作；失败恢复原值并保留 inline error。
- 普通操作同窗完成；关闭全部、重启远程服务或其他高风险动作才允许 native confirmation。

## Workbench Mapping

- 保留现有十一项 sidebar 信息架构，避免再次扩大导航。
- Overview：真实 traffic/memory/connection trend 与 inventory；无数据时不画伪图表。
- Proxies：固定 staggered Liquid Glass selector blocks；多展开、组内过滤、节点操作均在同窗。
- Connections/Rules/Sources：native Table + on-demand inspector，字段全量可选和可换行。
- Logs：高可读内容层，不使用 glass row；独立暂停、等级、过滤、清空和回到底部。
- Configuration：动态配置表单 + sing-box Tailscale section。
- Actions：仅列出当前 backend 真实可用的远程动作。
- Diagnostics：endpoint、probe、generation 和 stale 信息；不承担普通业务操作。
- 所有新增空状态使用不同 title/description，并在保留 toolbar 后居中于剩余内容区。

## Dependency And License Policy

- Mica 保持 MIT。不得复制、改写后粘贴或链接 Sparxie GPLv3 源码。
- 允许使用 Apache-2.0/BSD/MIT 等兼容的原生 Swift package；加入依赖前记录版本、许可证和必要性。
- gRPC Swift 依赖只服务 sing-box transport，不扩散到 presentation target。

## Verification Design

1. Request construction tests：method/path/query/header/body。
2. Upstream-shaped fixture tests：官方成功、可选字段、空结果、认证失败、错误 body 和 malformed body。
3. Stream tests：frame decode、buffer budget、termination、retry、cancellation 和 generation rejection。
4. Reducer tests：probe transition、stale retention、global/local pause、controller replacement/delete/sleep/window close。
5. Presentation tests：order、GLOBAL-last、过滤、排序 projection、full-visible long text、empty/error/stale distinction。
6. UI source/HIG checks：44pt hit target、Rose Pine contrast、VoiceOver labels、Reduce Motion/Transparency、语言/外观/字体注入。
7. 不运行真实核心，不修改系统配置，不执行 runtime smoke；协议行为通过 fixture transport 验证。

## Migration And Rollback

- 先引入新 transport/domain/session types和测试，再按 endpoint/domain 逐步切换 AppModel；每个阶段删除对应旧 abstraction，不保留双写或长期 compatibility wrapper。
- P0 协议修复独立提交，不能等待 sing-box/UI 全部完成。
- 每阶段以测试 gate 收口。若 sing-box dependency spike 失败，只回滚该阶段的 Package/proto 变更，不回滚已完成的 Mihomo/Surge 正确性修复。
- 不迁移或保留旧运行时缓存；profile 和 secret persistence schema 除非必要保持不变。

## Key Risks

- gRPC Swift 2 与 Swift 6.2/macOS 27 的版本组合需要先验证。
- Surge 与 Stash 的真实响应存在版本差异，需要宽容 decoder 和多 fixture，而不是 `try?` 吞错。
- 从大型 AppModel 拆 session actor 时最容易出现双 task owner；迁移期间每个 endpoint 必须只有一个生产者。
- 全字段模型会增加内存压力；必须依靠窗口化 projection 和有界 buffer，而不是丢字段。
