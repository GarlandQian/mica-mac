# Sparxie 功能对齐实施计划

## Execution Rules

- 当前任务已获用户批准并处于 `in_progress`；本文件记录最终实施与验收结果。
- 所有产品代码使用原生 Swift/SwiftUI；不复制、改写后粘贴或链接 Sparxie GPLv3 源码。
- 不下载、捆绑、启动或运行真实代理核心；不改系统代理、环境变量、防火墙、OpenWrt、LuCI、SSH 或 ubus。
- 不运行 runtime smoke；使用 fixture transport、协议请求断言、Swift 测试、静态 verifier 和 HIG batch 检查。
- 临时 checkout、生成文件、构建缓存和日志统一放在 `tmp/codex/`；任务完成清理不再需要的内容。
- 用户要求在 `main` 上继续并在累计改动后提交；最终使用一个受验证的工作提交收口，不改动或回退无关工作树内容。

## Ordered Checklist

### 0. Baseline and contract freeze

- [x] 读取 `prd.md`、`design.md`、相关 `.trellis/spec` 和三份 research；确认当前工作树和任务状态。
- [x] 记录现有静态 verifier、Swift build/test 的基线；将临时 build 输出放到 `tmp/codex/`。
- [x] 明确新的 domain/session 类型将替换哪些旧 abstraction，避免并行双写和兼容 wrapper。
- [x] 将 `.trellis/tasks/07-17-sparxie-feature-parity/` 的真实研究条目注入 implement/check context。

### 1. Transport and fixture harness

**Ownership: MicaCore transport/protocol test infrastructure**

- [x] 新增可注入 HTTP transport、请求 recording 和响应 fixture loader。
- [x] WebSocket 流保留 URLSession 生产边界；用 session/state tests 覆盖 finish、cancel、bounded buffering、retry 与 generation replacement，gRPC 使用 in-process transport。
- [x] 将现有 Mihomo/Surge client 改为可注入 transport；生产实现仍由 URLSession 提供。
- [x] 建立上游-shaped fixture 目录，包含成功、空、认证失败、错误 body、可选字段和 malformed response。
- [x] 增加请求 method/path/query/header/body 断言 helper。

**Gate 1**

- [x] 旧功能测试仍通过。
- [x] fixture transport 能在不打开真实控制器的情况下驱动一个完整 request/stream 测试。

### 2. P0 protocol and session correctness

#### 2.1 Auto Detect and capability resolution

- [x] 新增无副作用 probe resolver，区分 clash HTTP、Surge HTTP、sing-box gRPC 和 unknown。
- [x] probe 结果产生 runtime variant + granular capabilities；不再把 Auto Detect 固定投递到 Mihomo。
- [x] capability 从 probe-ready 变为真实可用后，立即启动正确 lanes/streams。
- [x] 错误 family 不得回退到另一个协议；诊断保留 endpoint 状态。

#### 2.2 Mihomo protocol fixes

- [x] 修正 `/group/{group}/delay` 顶层映射解码。
- [x] 将 `/memory` 改为 session-owned persistent stream，内部统一 bytes，补充取消和重连。
- [x] `/logs` 发送 upstream level 和 `format=structured`，保留远端时间和 fields。
- [x] 将 `/connections` 从固定轮询迁移到可用 stream，保留 aggregate memory、速率和完整 metadata。
- [x] fixture 覆盖官方 shape、缺失可选字段、未知字段、断流和重复 connection ID。

#### 2.3 Surge protocol fixes

- [x] `selectPolicy` 改为 `POST /v1/policy_groups/select` + `{group_name, policy}`。
- [x] `testPolicyGroup` 改为 `POST /v1/policy_groups/test` + `{group_name}`。
- [x] `killActiveRequest` 改为 `POST /v1/requests/kill` + `{id}`。
- [x] 增加 profile reload 和 log-level action 的 protocol contract；只有真实能力存在时显示。
- [x] 为 Surge policy/request/traffic/log variants 增加宽容但不吞错的 decoder fixtures。

#### 2.4 Generation isolation

- [x] `ControllerSession` 以 controller ID + generation 作为统一身份，后端 runtime kind 归属当前 generation；sing-box 事件统一经过 generation-checked handoff。
- [x] 所有 async apply 验证 ID + generation；删除只检查 selected ID 的 guard。
- [x] controller replacement/delete/sleep/final-window-close 统一 invalidate + cancel operation task tree。
- [x] 旧请求完成、旧 stream frame、旧 retry 都必须被 drop，不得改变新 session。

**Gate 2 / P0 checkpoint**

- [x] 自动检测、Mihomo delay/memory/logs、Surge 三个动作和 generation rejection 均有失败前后测试。
- [x] 新旧数据语义：成功后失败保留 stale value；从未成功才显示 error empty。
- [x] `swift test`、source verifier 和 `git diff --check` 通过。

### 3. Unified native domain/session rebuild

**Ownership: MicaCore typed contracts + MainActor AppModel + generation-owned ControllerSession**

- [x] 用完整 typed domain models 替换窄化的 proxy/rule/connection/provider/log models；不丢字段。
- [x] 引入 granular `ControllerCapabilities`、endpoint resource state 和 runtime variant。
- [x] `ControllerSession` 集中拥有 generation、REST lanes、retry、pending presentation 和 bounded buffers；AppModel 只保留明确的 generation-owned task slots。
- [x] Mihomo/Surge/sing-box 各自通过纯 projection/apply helpers 写入统一 Dashboard/Workbench state；不引入第二套 session actor 或双写 compatibility layer。
- [x] 保留 controller source order、GLOBAL-last presentation rule 和 bounded memory/log/connection budgets。
- [x] 为 policy, traffic, memory, connections, logs, rules, providers, configuration, Tailscale 编写 deterministic state/presentation tests。

**Gate 3**

- [x] 任一 endpoint 只有一个生产者；没有并行 session engine 或兼容层双写。
- [x] controller switch、pause/resume、sleep/wake 和 profile transaction 测试覆盖。
- [x] 所有 domain projection 均有 deterministic fixture/state tests。

### 4. Mihomo and Surge parity surfaces

**Ownership: existing backend UI and presentation projections**

- [x] Overview 使用真实 traffic/memory/connection samples 绘制 charts；无 sample 时使用正确 ContentUnavailableView。
- [x] Policy groups 支持多展开、组内过滤、节点选择/固定/取消固定、单点和组测速；源顺序不可变。
- [x] Connections 支持完整字段、活动/已关闭、过滤、排序 projection、来源/进程分组、单条/全部关闭和 inspector。
- [x] Logs 分离 controller log/app event log，支持 upstream level、内容过滤、局部暂停、清空和回到底部。
- [x] Rules 保留 index/disabled/hit/miss/timestamps；只在真实能力存在时显示 toggle。
- [x] Sources 保留 format/updatable/health/count；更新按钮按记录能力门控。
- [x] Configuration/Actions 按能力提供模式、日志级别、TUN/LAN/IPv6/TCP concurrent/端口、reload/Geo/DNS/FakeIP 等远程动作。
- [x] 所有业务数据保持全量可见；长 endpoint/URL/ID 使用换行或 selectable，不 middle-truncate。

**Gate 4**

- [x] 每个工作区有 loaded/stale/empty/no-match/unsupported/error 测试。
- [x] 视图文件不直接创建网络任务、不调用协议 decoder、不修改源数组顺序。
- [x] `WorkbenchRootView`、menu、toolbar、help/accessibility 继续消费统一 capability。

### 5. CMFA and Stash remote adapters

- [x] 将 `stashCmfaCompatible` runtime split 为 CMFA 与 Stash variant，但保留用户 profile migration 语义。
- [x] 复用独立实现的 Clash-compatible transport，同时按 variant 探测配置、provider、connection-log、cache/action 能力。
- [x] 对齐 Sparxie 中 CMFA/Stash 的真实能力，不把 unsupported action 伪装为按钮。
- [x] 增加 variant fixtures、capability matrix tests、session switching tests。

### 6. Native sing-box gRPC and Tailscale

- [x] 在 `Package.swift` 加入 gRPC Swift 2、NIO HTTP/2 和 SwiftProtobuf 的精确兼容版本；记录 licenses。
- [x] 添加 `Sources/MicaCore/Protocols/SingBox/started_service.proto` 与可复现生成脚本/生成 Swift 输出。
- [x] 先完成 unary/stream/cancellation in-process fixture spike；不能连接真实核心。
- [x] 接入 version/status/groups/mode/URLTest/select/connections/logs。
- [x] 接入 Tailscale status、exit node 和 logout；在 Configuration 同窗 section 展示。
- [x] 按 sing-box capabilities 隐藏不支持的 Clash/Mihomo controls。

**Gate 5**

- [x] Swift 6.2/macOS 27 clean build。
- [x] gRPC stream cancellation 在 generation invalidation 后无残留 task/channel。
- [x] Tailscale 和 sing-box fixtures 覆盖 empty/error/partial state。

### 7. Native UI and Liquid Glass acceptance

- [x] 载入 `macos-app-design` + `apple-hig-expert` + `swiftui-liquid-glass`；用 `design-taste-frontend` 做反模板化 pre-flight。
- [x] Liquid Glass 仅用于 sidebar/toolbar/interactive policy selector；tables/logs/long content 保持高可读内容层。
- [x] 修正所有空状态 title/description 重复与非居中问题；剩余内容区水平/垂直居中。
- [x] Controller table 的 edit/delete/use/test 固定在最右侧，间距紧凑但 hit region 至少 44pt。
- [x] 保持 Rose Pine semantic palette、light/dark/system、四档 font scale、中文/英文和 accessibility labels。
- [x] 通过原生 skill/source contract 检查 reduced transparency/motion、VoiceOver labels、keyboard navigation 和 long business text；HIG batch 验证 semantic contrast 与 44pt targets。

### 8. Verification, docs, and cleanup

- [x] 更新 `scripts/verify-real-controller-source.mjs`，让它检查新能力/session/data contracts 而不是旧抽象名称。
- [x] 运行 `node --check scripts/verify-real-controller-source.mjs` 与 verifier。
- [x] 运行 `swift build --scratch-path tmp/codex/sparxie-parity-build` 和 `swift test --scratch-path tmp/codex/sparxie-parity-build`。
- [x] 运行 Xcode build/test，DerivedData 放 `tmp/codex/`。
- [x] 生成 `tmp/codex/hig-audit.json`，运行 `python3 /Volumes/T7 Shield/code/mica-mac/.agents/skills/apple-hig-expert/scripts/hig_checker.py batch tmp/codex/hig-audit.json`。
- [x] 不运行 runtime smoke；记录该用户约束和未做的真实控制器验证。
- [x] 运行 `git diff --check`，检查无敏感值进入 fixtures、logs、exports 或 diagnostics。
- [x] 用 `trellis-update-spec` 把新发现的 protocol/session/empty-state 规则写入 `.trellis/spec/`。
- [x] 删除 `tmp/codex/` 下不再需要的 checkout、build、DerivedData、fixture logs；保留必要研究资料和可复现 proto/fixtures。
- [x] 通过 Trellis finish-work；本任务提交到本地主分支，不推送远端。

## Convergence Notes

- 没有引入设计稿中的第二个 `ControllerSessionEngine` actor。现有 `@MainActor AppModel` + generation-owned `ControllerSession` 已能提供单生产者、结构化 sing-box task tree、统一 retry/pause/stale/buffer 语义；再增加 actor 会形成任务明确禁止的双写架构。
- CMFA 和 Stash 复用独立 Swift Clash-compatible transport，但快照必须携带解析后的 variant capability matrix，不能因 DTO 共用而退化为完整 Mihomo 能力。
- 远端写入成功、随后刷新失败按 partial success 处理；只有写入本身失败才回滚 optimistic state。
- Runtime smoke、真实控制器和真实核心均未运行；协议正确性由 request-level fixtures、in-process gRPC、state/presentation tests 和静态 contract 验证。

## Suggested Agent Slices

只在任务进入 `in_progress` 后派发，且每个 agent 明确 ownership：

1. `protocol-correctness`: MicaCore HTTP/WebSocket clients + request/response fixtures；不改 UI。
2. `session-engine`: generation actor, lanes, streams, buffers and reducer tests；不改 protocol decoder。
3. `workbench-parity`: Overview/Policies/Connections/Logs/Rules/Sources projections and UI；只消费 session API。
4. `singbox-native`: Package/proto/gRPC client/Tailscale fixtures；不改 shared UI until Gate 3。
5. `trellis-check`: each gate after integration; may self-fix spec drift and tests, never reintroduce old wrappers.

Agents must read `prd.md`, `design.md`, `implement.md`, relevant JSONL entries and spec files before editing, and must not revert unrelated worktree changes.

## Validation Commands

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
swift build --scratch-path tmp/codex/sparxie-parity-build
swift test --scratch-path tmp/codex/sparxie-parity-build
xcodebuild -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme Mica -destination platform=macOS \
  -derivedDataPath tmp/codex/xcode-derived build
xcodebuild -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme Mica -destination platform=macOS \
  -derivedDataPath tmp/codex/xcode-derived test
python3 .agents/skills/apple-hig-expert/scripts/hig_checker.py batch tmp/codex/hig-audit.json
git diff --check
```

## Risk Files And Rollback Points

- High risk: `Package.swift`, `Sources/MicaCore/Models/*`, `Sources/MicaCore/API/*`, `Sources/Mica/App/AppModel*.swift`, `Sources/Mica/App/OperationSessionModels.swift`.
- UI risk: `Sources/Mica/Features/Workbench/*`, `Sources/Mica/App/MicaStyle.swift`, `Sources/Mica/App/MicaSurfaces.swift`, `Localizable.xcstrings`.
- Rollback after Gate 2: revert only new session/domain changes while retaining fixture harness and protocol endpoint fixes.
- Rollback after Gate 5: remove gRPC package/proto/client changes; preserve all prior HTTP backend work.
- Never use destructive git reset/checkout to roll back user or unrelated changes.
