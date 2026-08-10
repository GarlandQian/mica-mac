# Mica Workbench 全局原生 UI 重构实施计划

## Execution Rules

- 这是父任务计划。页面实现进入子任务，不在父任务中一次性修改全部源码。
- 每个子任务遵循 `trellis-before-dev -> edit -> trellis-check -> validation -> trellis-update-spec -> commit -> trellis-finish-work`。
- 当前为 Codex inline 模式，不派发 implement/check 子代理。
- 每个子任务先完成完整相关修改，再集中验证；避免每个小补丁都 build/test。
- 不启动 Mica、不访问真实控制器、不运行 runtime smoke。临时文件只写入 `tmp/codex/`，完成后清理。
- 不使用破坏性 Git 命令，不覆盖无关用户修改。父任务最终只在所有子任务已提交后做集成提交或文档收尾。

## Phase 0. Reconcile Existing Child

- [x] 完成并验收 `08-03-connections-native-visual-rebuild` 的剩余 Connections/Proxies 工作。
- [x] 运行该子任务自己的定向投影、排序、关闭安全、本地化和 build/test 质量门。
- [x] 更新相关 Trellis spec、提交并归档子任务。
- [x] 在父任务记录实际完成范围和任何共享视觉原语变化。

回退点：该阶段只使用现有子任务边界；父任务不能再次重写 Connections/Proxies。

## Phase 1. Shared Shell, Settings, and Visual Foundation

创建子任务 `workbench-shell-settings-foundation`，范围为 `WorkbenchVisualSystem.swift`、`WorkbenchChrome.swift`、`MicaApp.swift` 和从 `WorkbenchManagement.swift` 拆出的 Settings。

- [x] 盘点全部共享 token/primitive 消费者，删除重复或失效视觉路径，但不创建平行 design system。
- [x] 统一 Window/Toolbar/Command Bar/Content/Status 的 page fill 和 separator。
- [x] 保持 10 个目的地，修复侧边栏整行点击、选中态、字号和键盘导航。
- [x] 保持原生 Settings Scene；只渲染语言、外观、四档字号和 GLOBAL 可见性。
- [x] 验证设置在主窗口与 Settings 窗口即时生效，且字号不改变页面断点。
- [x] 确认 Command Palette/Deck/Cmd+K 路径不存在，toolbar 不重复 controller identity。

定向验证：App preference/store tests、localization resolver tests、sidebar/navigation tests、source verifier、Swift build。

## Phase 2. Overview Native Monitoring Workspace

创建子任务 `overview-native-monitoring-workspace`，范围为 `WorkbenchDashboard.swift` 和现有 `WorkbenchOverview*.swift`。

- [x] 审核现有 personalization/runtime/projection，保留真实模块和每窗口事务草稿。
- [x] 重构 telemetry 为上传、下载、连接三块同权图表；内存作为连接上下文，不恢复第四张图。
- [x] 完整保留 Chart hover、pin、step、pause、return-live 和时间窗口交互。
- [x] 保留完整 Sankey 拓扑、网络信息、无横向滚动和同窗口展开/连接页导航。
- [x] 缺失能力或无数据时隐藏模块或显示准确状态，不制造样本。
- [x] 窄/中/宽布局只按可用宽度变化，个性化顺序和可见性保持稳定。

定向验证：overview projection/layout/store/topology tests、chart sample bounds、generation ownership、Swift build。

## Phase 3. Logs, Rules, and Sources Data Browsers

创建子任务 `logs-rules-sources-native-browsers`，范围为 `WorkbenchLogs.swift`、`WorkbenchRules.swift`、`WorkbenchSources.swift` 和必要的共享 data browser 原语。

### Logs

- [x] 保持 `BoundedLogBuffer.maximumEntryCount == 2_000` 和 `maximumUTF8Bytes == 8 MiB`。
- [x] 高密度展示时间、级别、类型和完整日志；Trace 只在 sing-box 能力中出现。
- [x] Follow Newest 对持续流不饥饿，用户上滚后可明确恢复。

### Rules

- [x] 保持报告顺序和一个原生 Table；序号、类型、载荷、目标、活动与状态可扫描。
- [x] 精确可见策略组目标才可跳转；DIRECT/REJECT/节点名/未知目标保持只读。
- [x] 页面不出现 API endpoint 或诊断说明。

### Sources

- [x] 保持一个原生 Table 和完整来源字段，不改为 card grid。
- [x] Update All 过滤可更新项但不重排，串行执行，通过共享 task slot 发布进度并最终刷新一次。
- [x] 单项 update/health/reload 不与 batch 互相取消或竞态。

定向验证：buffer tests、log projection/follow tests、rule projection/navigation tests、source batch ordering/refresh-count tests、2,000+ row projection benchmark、Swift build。

## Phase 4. Controller Management Workspace

创建子任务 `controller-management-native-workspace`。先机械拆分 `WorkbenchManagement.swift`，再分别重构。

### Mechanical split

- [x] 提取 Settings、Controllers、Configuration、Actions、Diagnostics 到职责文件，保留现有类型和访问级别。
- [x] 机械移动后先运行一次 Swift build，确认没有行为变化，再进入 UI 修改。

### Controllers and RouterEditor

- [x] Controllers 使用稳定 master-detail，编辑/删除在右侧上下文，只有 Use 切换活动控制器。
- [x] 保持用户配置顺序和显式移动操作；不按健康、名称或延迟自动重排。
- [x] RouterEditor 保持同窗口覆盖、原生 Form、一次性提交和现有 FileSecretStore 路径。

### Configuration and Actions

- [x] Configuration 只显示 controller metadata/config 中真实报告且支持修改的字段。
- [x] Actions 只显示现有 supported operation；不支持项不形成噪音列表，破坏性操作行内确认。
- [x] 所有 mutation 和 confirmation 校验 controller ID、generation 和目标。

### Diagnostics

- [x] 顶部改为人类可读的紧凑结论带；详情使用一个同窗口 outline。
- [x] 一级/二级 disclosure 整行可点、动画一致；展开后滚动不因嵌套 lazy 容器卡顿。
- [x] 隐藏 unavailable capability 行和空 section；页面不显示 API 路径、机器 assignment 或 raw payload。
- [x] Copy Report 保留凭据安全的技术详情。

定向验证：controller selection/order/tests、editor draft/store/tests、config/action generation tests、diagnostic projection/redaction/disclosure tests、Swift build。

## Phase 5. Cross-Surface Acceptance

创建子任务 `workbench-cross-surface-acceptance`，只处理跨页面一致性缺陷和最终验证，不重新设计已验收页面。

- [ ] 审查全部 14 模块在浅色/深色和 4 档字号下的颜色、标题、command bar、状态、空状态、scroll ownership 和控件对齐。
- [ ] 审查窄/中/宽窗口，无文本重叠、不必要横向滚动、断点跳变或大面积失衡空白。
- [ ] 审查中文/英文、菜单、help、tooltips、accessibility 和格式占位符。
- [ ] 审查 controller switch、generation end、stale reconnect、pause/resume 和 destination visibility 生命周期。
- [ ] 审查 2,000 连接、2,000 日志、大规则集、多策略组展开和诊断展开后的投影/滚动性能。
- [ ] 用户使用真实控制器逐页验收；只根据用户截图修复可重现视觉问题。
- [ ] 更新 `docs/` 和 `.trellis/spec/` 中真正长期有效的新合同，删除已被新合同取代的临时说明。

### Completed User-Feedback Follow-Up

- [x] 2026-08-06：Proxies 滚动期间保留最新可延迟目录结果至 idle，避免 200ms 到期时重建整页；节点 hover 进入事件在滚动期间被抑制，保留关键操作即时提交。

验证结果：`WorkbenchProxyWorkspaceTests` 17 tests、`WorkbenchTimelineAndProxyTests` 27 tests、`WorkbenchDataProjectionTests` 36 tests 通过；完整 Swift Testing 为 299 tests / 27 suites，Swift build、source verifier、JSON、diff 和 Trellis validation 均通过。

## Validation Matrix

每个子任务先运行最小相关检查，父任务最终只运行一次完整套件：

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings
swift build
swift test
git diff --check
python3 ./.trellis/scripts/task.py validate 08-04-workbench-native-ui-system
```

按子任务补充对应 `swift test --filter ...`。只有源文件变化涉及 Xcode 工程或发布边界时才运行额外 `xcodebuild`；本父任务不运行 runtime smoke、不启动应用、不访问控制器。

## Final Review Gate

实施前必须满足：

- [x] 用户审核并明确批准本 PRD、设计和分阶段计划。
- [x] 父任务通过 `task.py validate`。
- [x] 当前 Connections/Proxies 子任务的实际状态已确认，不重复安排已完成工作。
- [x] Phase 1 子任务创建后才运行 `task.py start`；本次规划消息不修改应用源码。

完成条件：所有子任务已通过各自质量门并归档，父任务 AC1-AC12 全部满足，最终集成验证通过，文档与 Trellis spec 已同步。
