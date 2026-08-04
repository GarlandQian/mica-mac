# 连接页面原生视觉重构实施计划

## 执行原则

- 保持原生 SwiftUI/macOS 27，不新增第三方包，不新增 AppKit 内容层。
- 只重构 Connections 的 presentation 与视觉层；不改控制器 API、认证、采集、重连、已关闭保留策略或 AppModel 操作语义。
- 先完成全部相关修改，再集中验证；除编译阻断或高风险缓存边界外，不在每个小补丁后 build/test。
- 不启动 Mica、不运行 runtime smoke、不访问真实控制器。临时产物只写入 `tmp/codex/`，结束时清理。
- 保留用户未提交修改，不使用破坏性 Git 命令，不在本任务创建提交。

## Phase 0：基线与合同

- [x] 读取活动 PRD、设计、Connections 源码、数据浏览器契约、当前 `git status --short` 和相关 dirty diff。
- [x] 记录连接投影、关闭安全、工作区状态、状态解析、本地化和性能测试的现有引用，确认不覆盖用户修改。
- [x] 确认 `Package.swift` 依赖不变，本任务不添加 Swift package。

## Phase 1：概览投影与增量缓存

- [x] 新增 `WorkbenchConnectionPulseProjection` 及来源桶值类型，明确活动与已关闭指标语义。
- [x] 扩展 `WorkbenchConnectionProjectionCache`，在结构/筛选变化时重建聚合，在 changed metric indices 上增量修正数值。
- [x] 确保排序变化不重建聚合，语言变化只更新格式化展示，隐藏页面不执行聚合。
- [x] 为可见/总数、上传/下载/合计、未报告值、来源排名、稳定同值顺序、搜索范围和 scope 切换增加定向测试。
- [x] 增加缓存计数或等价断言，证明单行指标更新不全量重投影，排序不重建来源桶。

风险与回退点：`WorkbenchConnections.swift` 的 projection/cache。先证明数值和 revision 合同，再接 UI。

## Phase 2：文件职责拆分

- [x] 将页面状态、Table 和工作区协调机械移动到 `WorkbenchConnectionsView.swift`，保持现有 internal API 与行为。
- [x] 将决策链和 inspector 机械移动到 `WorkbenchConnectionDetails.swift`，保持关闭与导航闭包边界。
- [x] 保留连接行、聚合缓存、排序 cadence、owner identity 和 close intent 在 `WorkbenchConnections.swift`。
- [x] 检查移动后没有重复类型、循环依赖、扩大可见性或改变 SwiftPM target。

风险与回退点：只做机械拆分，不在同一步改视觉；若拆分引入高风险冲突，保留原文件并继续局部重构。

## Phase 3：命令栏与紧凑连接概览

- [x] 精简命令栏为结果摘要、活动/已关闭切换和当前合法破坏性命令，保持搜索入口和稳定高度。
- [x] 实现无嵌套卡片的 pulse strip：连接、上传、下载、总流量和前 3 个来源分布。
- [x] 活动范围显示真实速率与累计量；已关闭范围只显示历史累计值，不使用“实时”语义。
- [x] 使用 `ViewThatFits` 适配常规/紧凑宽度，不按字体倍数切换布局，不引入横向滚动。
- [x] 为浅色/深色、四档字号、英文/中文、Reduce Motion、VoiceOver 和键盘焦点补齐语义。

风险与回退点：pulse strip 是独立 supplementary 区，可在不影响 Table 的情况下回退。

## Phase 4：表格、路径带与检查器

- [x] 保持单一原生 `Table`，审计 full / compact / stacked 列顺序、稳定行几何、文本截断和完整字段入口。
- [x] 将选中连接决策链收敛为紧凑、完整、可换行但无横向滚动的交互路径带。
- [x] 保持精确 Rules / Proxies 跳转，链路顺序与控制器报告一致，不显示 API 路径或技术键名。
- [x] 将单项和同来源组关闭动作 trailing 对齐并复用 inline confirmation；已关闭范围隐藏关闭操作。
- [x] 重组 inspector 的身份、路由、传输和附加信息；已知字段去重，额外对象/数组使用可读结构化呈现。
- [x] 检查 selection、sort、scroll restoration、scope 和 inspector 状态继续按控制器工作区持久化。

风险与回退点：不修改 AppModel 操作；关闭安全和 navigation directory 继续由既有测试保护。

## Phase 5：状态、本地化与合同同步

- [x] 统一 loading、empty、filtered-empty、unsupported、failed、disconnected 和 stale 的底色、居中与实时语义。
- [x] 补齐新增文案的 English / Simplified Chinese、help、tooltip 和 accessibility label/value。
- [x] 审计格式化本地化，确保 `%@`、`%d` 和位置占位符不会作为可见文字泄漏。
- [x] 更新 `verify-real-controller-source.mjs` 中与 Connections 唯一 Table、无 API 路径、无假数据和增量投影相关的 durable assertions。
- [x] 仅在行为合同确实改变时更新 `.trellis/spec/frontend/workbench-ui-contract.md` 与 `docs/`；不写实现流水账。

## Phase 6：集中验证

按顺序执行；失败后只重跑受影响检查：

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
```

- [x] 确认连接投影、增量缓存、关闭安全、工作区恢复和性能 benchmark 全部通过。
- [x] 确认未新增 package、未启动 Mica、未运行 runtime smoke、未访问控制器、未生成仓库外临时文件。
- [x] 清理 `tmp/codex/` 中不再需要的构建和研究产物。
- [x] 汇总用户视觉验收清单：活动/已关闭、无搜索/有搜索、宽/中/窄窗口、浅/深色、四档字号、英文/中文、loading/empty/failed/stale、选中详情与关闭确认。

## Phase 7：策略组视觉验收修正

- [x] 将组标题改为无永久描边的扁平分区，并保留真实延迟分布、完整展开点击范围和现有操作。
- [x] 将节点矩阵改为宽屏三列、中屏两列、窄屏一列；保留单一 `LazyVGrid`、源顺序、多组展开和独立过滤。
- [x] 重做节点单元的状态轨、hover、检查、当前节点和延迟测试层级，减少重复边框与图标噪音。
- [x] 将节点详情改为概况、传输、测试三栏信息架，附加字段仍默认折叠且逐项可选择。
- [x] Mihomo 每次刷新采用最新 `GLOBAL.all` 配置组顺序，未列出组保持 `/proxies` 相对顺序，节点保持各组 `all` 顺序，`GLOBAL` 置尾；其他控制器保持报告顺序。
- [x] 同步 Workbench UI 合同、长期 UI 文档与源码验证断言。
- [x] 修改完成后集中运行源码验证、Swift build/test 和 `git diff --check`，不运行 runtime smoke。

## Phase 8：控制器编辑器视觉验收修正

- [x] 移除旧的固定双栏编辑画布和未测试时的重复预览栏，统一为单一原生 grouped Form 与一个滚动所有者。
- [x] 将控制器身份、端点和安全配置组织为可自适应的原生 Section；长输入使用可用宽度，端口保持紧凑。
- [x] 连接诊断只在用户执行测试后出现，测试状态与步骤继续复用既有连接、认证和本地化边界。
- [x] 取消与测试降为轻量命令，仅保存保留主操作层级；保存、放弃、验证和密钥语义保持不变。
- [x] 隐藏输入控件的第二套原生 Form 标签，保持单一字段名、统一控制列和不会退化为纯图标的取消/测试/保存命令。
- [x] 完成后集中运行源码验证、Swift build/test 和 `git diff --check`，不运行 runtime smoke。

## Phase 9：管理页面视觉同步

- [x] 将原生控件标签隐藏下沉到 `WorkbenchFormRow`，统一控制器编辑、配置、端口与 Tailscale 字段，避免重复字段名。
- [x] 将控制器详情迁移为有界原生 grouped Form，保留持久化顺序列表、同窗口详情、使用、测试与诊断语义。
- [x] 将操作页迁移为原生 grouped Form/Section，保持能力门控、同窗口确认和原有 AppModel 命令边界。
- [x] 统一管理页文字命令的右侧对齐与抗压缩行为；不把诊断层级或数据表强行改成管理表单。
- [x] 同步 UI 合同、长期文档与源码断言并集中验证，不运行 runtime smoke。

## 启动前检查

- [x] 用户已审阅 `prd.md`、`design.md`、`implement.md` 并明确批准实施。
- [x] 使用 `trellis-before-dev` 读取本任务和相关 spec。
- [x] 运行 `task.py start` 将任务从 planning 切换为 active。
