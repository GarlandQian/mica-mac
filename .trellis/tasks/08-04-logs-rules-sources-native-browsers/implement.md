# Logs、Rules 与 Sources 实施计划

## 1. Pre-development gate

- [x] 经用户审查 `prd.md`、`design.md` 和本计划后运行 `task.py start`。
- [x] 加载 `trellis-before-dev`、`mica-controller-development`、`macos-app-design`、`apple-hig-expert`、`swiftui-expert-skill`；本任务未引入玻璃 API。
- [x] 记录实施前 `git status --short`，保留当前工作树中父阶段和其他页面的未提交修改。
- [x] 再次确认不启动 Mica、不访问真实控制器、不运行 runtime smoke。

## 2. Durable contract tests first

- [x] 更新相关源码 verifier，只断言一个原生 `Table`、共享数据浏览器、无内容 Material / 卡片网格、Rules 精确导航与 Sources 串行批次等长期合同。
- [x] 复核 Logs 投影、过滤、Trace 门控、Follow Newest 和 buffer 边界测试。
- [x] 补齐 Rules 列投影，并复核源顺序、展示副本排序、连接索引和策略组跳转测试。
- [x] 补齐 Sources 状态投影，并复核报告顺序、Update All 单次最终刷新和竞态拒绝测试。

Review gate：测试应描述目标行为，不绑定无意义的具体 padding、颜色数值或私有 View 层级。

## 3. Logs implementation

- [x] 在 `WorkbenchLogs.swift` 内调整 full / compact / stacked 单元格层级，保留一个 Table 和现有 inspector。
- [x] 使用窄 severity cue、时间、级别 / 类型和消息主体建立连续事件流；移除不必要的盒状状态表达。
- [x] 保留增量投影、2,000 条 / 8 MiB buffer、到达顺序、0.2 秒 Follow Newest 合并和用户滚动暂停语义。
- [x] 检查英文、简体中文、四档字号合同与 VoiceOver 组合文本。

Rollback point：若滚动或增量更新回归，只回退 Logs 展示组合，不触碰 buffer 和 projection cache。

## 4. Rules implementation

- [x] 在 `WorkbenchRules.swift` 内为 full 模式实现明确的 `# / Type / Payload / Target / Activity / State` 列。
- [x] 调整 compact / stacked 组合，确保窄宽度不丢失目标、活动和状态信息。
- [x] 保留 `ruleStateCell(row)`、`ruleCompactSummary(row)`、`ruleStackedRow(row)` 等长期入口并同步 verifier。
- [x] 保留源顺序、presentation-only sort、预索引连接统计和精确策略组目标导航。
- [x] 检查 focus rail、Inspector、键盘选择、可选择文本和辅助功能。

Rollback point：若列预算导致横向滚动，先回退列宽和 compact 断点，不合并回不可扫描的单一文本块。

## 5. Sources implementation

- [x] 在 `WorkbenchSources.swift` 内将状态改为安静的 dot / symbol / text 组合，保持一个 Table 且不使用卡片网格。
- [x] 简化选中来源 focus rail，使生命周期、真实健康结果和 inline action 关系清楚。
- [x] 保留报告顺序、`updateTargets` 过滤、串行 Update All、共享任务槽、一次最终刷新和竞态保护。
- [x] 检查 individual update / health / reload、部分失败、只读来源和 generation 变化状态。
- [x] 检查英文、简体中文、四档字号合同和 VoiceOver 进度反馈。

Rollback point：状态视觉可以独立回退，批量更新和操作协调代码不得因 UI 回退改变。

## 6. Consolidated verification

完成三页全部修改后集中运行，不在每个小补丁后重复全套验证：

1. `node --check scripts/verify-real-controller-source.mjs`
2. `node scripts/verify-real-controller-source.mjs`
3. `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`
4. 与 Logs / Rules / Sources 直接相关的 `swift test --filter ...`
5. `swift build`
6. `swift test`
7. `git diff --check`
8. `python3 ./.trellis/scripts/task.py validate 08-04-logs-rules-sources-native-browsers`

完整 Swift 测试只在完成时运行一次；若失败，只重跑受影响检查。不得运行 runtime smoke、启动应用或访问控制器。

## 7. Finish

- [x] 运行 `trellis-check` 做需求、架构、数据流、性能和一致性复核。
- [x] 使用 `trellis-update-spec` 将 Rules 过时的合并列合同改为批准的六列扫描合同。
- [x] 更新本任务实施记录和父任务阶段状态。
- [ ] 按 Trellis finish 流程归档；归档会自动提交，等待用户明确要求提交后执行。

## 8. Implementation record

- Logs：full 模式分为接收时间、级别、类型和 payload；compact / stacked 保留相同事件层级。severity rail、投影缓存、Follow Newest 和 Inspector 未改变。
- Rules：full 模式分为 `# / Type / Payload / Target / Activity / State`；索引显示与排序使用同一控制器报告值，活动连接与命中数预计算后组合呈现。
- Sources：扫描行使用 dot / symbol / text 状态；compact / stacked 同时表达更新与健康能力；focus rail 显示选中来源身份、更新能力、数量、时间和真实健康结果。
- 未修改 Controller、Session、API、DTO、认证、批量更新协调或 generation 生命周期；未增加依赖。

## 9. Verification record

- `node --check scripts/verify-real-controller-source.mjs`：通过。
- `node scripts/verify-real-controller-source.mjs`：通过。
- `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`：通过。
- 定向 `swift test --filter 'WorkbenchDataProjectionTests|ProviderUpdateAllTests'`：41 个测试通过。
- `swift build`：通过。
- 完整 `swift test`：299 个测试、27 个套件通过。
- `git diff --check`：通过。
- 未运行 runtime smoke、未启动 Mica、未访问真实控制器。
