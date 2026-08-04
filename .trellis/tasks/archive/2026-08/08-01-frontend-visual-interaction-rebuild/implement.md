# Implementation Plan: 前端全局视觉与交互重构

## Gate Before Code

- [ ] 用户审核并批准 `prd.md`、`design.md` 和本计划。
- [ ] Phase 0 完成（4 个既有任务收口并提交）后才可开始 Phase 1。
- [ ] 批准后 `python3 .trellis/scripts/task.py validate 08-01-frontend-visual-interaction-rebuild`，再 `task.py start`。
- [ ] 记录 `git status --short`；只处理本任务文件，不回退无关改动。
- [ ] Phase 2 前加载 `mica-controller-development`、`macos-app-design`、
  `apple-hig-expert`、`swiftui-expert-skill`、`swiftui-liquid-glass`。

本任务不连接真实控制器/9090/核心，不改系统网络，不运行旧 runtime smoke。
临时构建与检查输出放 `tmp/codex/frontend-visual-interaction-rebuild/`，完成后
清理。所有页面改完后集中执行完整验证。

## Phase 0: 既有任务收口（前置，阻塞 Phase 1）

- [ ] 收口并提交 `08-01-connection-source-log-workspaces`。
- [ ] 收口并提交 `07-31-rules-policy-workspace-innovation`。
- [ ] 收口并提交 `07-30-localization-placeholder-settings-alignment`。
- [ ] 收口并提交 `07-30-vertical-scroll-jank`（滚动性能地基必须先稳）。
- [ ] 确认 `git status` 干净后开始视觉重塑。

**Rollback point:** 本阶段不改视觉；功能/性能成果保留。

## Phase 1: 设计系统与外壳（全局换肤）

**Primary files**

- `Sources/Mica/Features/Workbench/WorkbenchVisualSystem.swift`
- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift`
- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift`
- `Sources/Mica/App/MicaSurfaces.swift`
- `Sources/Mica/Resources/Localizable.xcstrings`

**Work**

- [x] 重写 `MicaStyle`/`MicaDesignTokens` 为 1.1 色彩 token 表（双外观）。
- [x] 收敛 `MicaSpacing` 为 4pt 基线网格（space1-6，语义名保留以护固定行几何）。
- [x] 重写字阶（`micaDisplay/Headline/Instrument/Data/DataSmall/Label/Caption`）。
- [x] 新增 `WorkbenchMotion` 动效原语（含 Reduce Motion 降级）。
- [ ] 统一 `WorkbenchSymbol` 尺寸/权重/variants 规约（侧边栏激活态已用 .fill；size 枚举待做）。
- [ ] 按组件重塑清单重绘所有共享组件（见 design.md §2）（已做 MetricValue 数值滚动 / Section 字阶；其余随各页 phase 推进）。
- [ ] W2 外壳精修：侧边栏选中态辉光轨（已做 2pt 轨 + .fill）、底部三段式会话条（已做等宽时间戳，三段式待做）、工具栏分区（待做）、检查器大标题区（待做）。
- [ ] 补充/更新中英文案。

**Focused checks**

- [x] 所有 token 组合对比度 ≥ 阈值；命中区域 ≥ 44pt。（新 token HIG 审计 100 分无违规）
- [x] 全局换肤后各页无未替换的 Rose Pine 旧值（grep 旧 hex 无残留）。

**Rollback point:** 本阶段不改任何页面内部布局/数据流，可整阶段回退。

## Phase 2: Overview 仪表重构

- [x] 卡片 `pageIn` stagger 入场；KPI `numeric` 数值滚动。
- [x] 流量/内存/连接曲线 `liveDraw` 实时推移（读现有 timeline，不动投影；147 Overview 测试通过）。
- [x] 图表图例、readout、拓扑区按新 token/字阶重绘（readout 数值滚动；token 全局生效）。

**Rollback point:** Overview 可独立回退；图表基图 `.equatable()` 边界不破。

## Phase 3: Proxies 重构

- [x] 目录行/节点行/延迟条重绘；测速 `latencyShift` + 进行中脉冲（44 Proxy 测试通过）。
- [x] 选中节点 `expand`；路径 ribbon 与检查器按新组件重绘（共享组件 token/字阶全局生效）。

**Rollback point:** 节点/延迟数据流不变，仅渲染层。

## Phase 4: 数据页（Connections/Logs/Rules/Sources）— 含并入的 08-01 功能

- [ ] 列头/单元格/选中行/焦点区按新组件重绘；保持单 Table 与固定行几何。
- [x] 仅选中行与聚合数字 `numeric`；无逐行动画（数据平面固定行几何，无逐行动画）。
- [x] 检查器大标题区 + 字段分节重绘（共享 InspectorShell/Section token 生效）。
- [x] Connections：连接焦点区（链路 + readout）、策略组精确匹配跨页激活、
  规则唯一精确匹配跨页选择（navigationDirectory + consumeConnectionNavigation），
  单项/同组关闭进焦点区，表格无独立操作列（既有实现，token 换肤生效）。
- [x] Sources：选中焦点区（WorkbenchSourceFocusRail）+ 单项更新/健康检查，
  Update All/重载留命令栏，表格无独立操作列，缺失值不合成（既有实现）。
- [x] Logs：severity 枚举预计算 + 3pt severityRail 色轨 + 级别文字双重编码
  （error红/warning琥珀/debug紫/info青），Follow Newest 状态保留（既有实现）。

**Rollback point:** 数据平面与增量投影不动，可逐页回退。

## Phase 5: 管理页（Controllers/Configuration/Actions/Diagnostics/Settings）

- [x] 表单行/偏好菜单/控制器列表/操作区按新组件与字阶重绘（30 处共享组件，无独立硬编码色）。
- [x] 保持既有行为契约（编辑、保存、测试、确认）。

**Rollback point:** 仅视觉，行为不变，可逐页回退。

## Phase 6: 集中验证与文档

- [x] 更新 `scripts/verify-real-controller-source.mjs` 新结构（暗夜仪器 token/字阶/动效断言）。
- [x] `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`。
- [x] `node --check` + 运行验证脚本（通过）。
- [x] HIG 对比度与 44pt 命中区域检查（双色外观，100 分无违规）。
- [ ] Reduce Motion 路径走查；滚动/高频刷新掉帧回归检查。
- [x] `swift build` + `swift test`（288 测试通过）。
- [x] `git diff --check` + `task.py validate`（通过）。
- [ ] 对照 AC 汇总证据；确认未连真实控制器/9090。
- [x] 同步新约束到 `.trellis/spec/frontend/workbench-ui-contract.md` 与 `docs/UI_GUIDELINES.md`（暗夜仪器调色板 + 等宽数字 + 动效边界）。

## Risk Review Before Start

- 259 个未提交改动与 4 个进行中任务同区施工——Phase 0 必须先收口。
- 数据页固定行几何/单 Table 是滚动性能底线，任何视觉改动不得恢复卡片墙或
  逐行动画。
- 动效 state 不得进入共享 observable 或 projection 缓存热路径。
- 双外观必须同交，不允许只做深色。
- 验证失败按页面/组件回退，不回退既有功能与性能边界。
