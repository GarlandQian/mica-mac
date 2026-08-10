# Overview 原生监控工作台重构

## Goal

在不改变控制器、Session、API、投影或持久化语义的前提下，就地打磨现有 Overview 监控工作台。默认页面保持三张真实实时图表、完整链路拓扑和分组网络信息，重点解决滚动动画叠加、卡片感过重、图表层级松散和拓扑纵向拥挤问题。

## Requirements

- 直接修改现有 `WorkbenchOverviewView` 及其 Overview 私有组件，不创建 `MicaDashboardView` 等平行页面。
- 保留上传、下载、活动连接三张真实 Swift Charts 图表；内存只作为连接图上下文，不新增第四张图。
- 保留 hover、点击固定、左右步进、暂停和返回实时等共享时间轴交互，所有图表继续使用同一交互状态。
- 三张图在宽窗口三列、中等窗口两列加一行、窄窗口单列；布局仅由实际可用宽度决定。
- 将三张图整合为一个连续监控表面，通过留白和分隔线建立层级，避免三个重复描边卡片。
- 去除滚动视口内逐模块入场动画和每个实时样本触发的整图动画；保留选择、状态等有意义的轻量反馈并遵循 Reduce Motion。
- 保留完整拓扑的全部连接路径、Sankey 布局、路径选择、暂停、同窗展开和跳转 Connections；不得增加 Top-N、横向滚动或单独弹窗。
- 拓扑画布宽度必须受模块实际宽度约束，纵向空间随真实路径复杂度稳定展开，避免挤压或裁切。
- 网络信息继续以真实控制器元数据分组呈现；调整为可扫描的定义列表/字段墙，不伪造缺失字段。
- 保留五模块个性化、预设、拖拽排序、全局默认与控制器覆盖、CAS 冲突处理和昂贵 runtime 复用。
- 继续使用 `MicaStyle`、`micaFont`、系统 Charts 和现有 Workbench primitive；内容圆角不超过 8pt，不使用自定义 glass、装饰渐变或阴影卡片墙。
- 不启动应用、不访问真实控制器、不运行 runtime smoke；临时产物只放在 `tmp/codex/` 并在完成时清理。

## Acceptance Criteria

- [ ] AC1：默认 Overview 仍只显示 telemetry、complete route topology、network information，instrument rail 和 operational summaries 保持可选且默认隐藏。
- [ ] AC2：三张图继续使用真实 projection、真实 Y 轴尺度和共享时间轴交互；无 fake samples、无静态占位曲线。
- [ ] AC3：三张图呈现为一个连续监控表面，宽/中/窄布局稳定，无重复外框卡片墙或水平滚动。
- [ ] AC4：Overview 模块不再在滚动进入视口时执行 opacity/offset 入场动画，实时样本更新不再触发整张 Chart 的隐式动画。
- [ ] AC5：完整拓扑不截断路径、不增加 Top-N，宽度适配模块，无水平滚动；暂停、hover、固定路径、展开和跳转 Connections 保持有效。
- [ ] AC6：网络信息保持全部真实分组字段，使用紧凑、可扫描且能随字号自然换行的布局。
- [ ] AC7：个性化布局、模块顺序、per-window runtime、全局默认和 controller override 行为不变。
- [ ] AC8：Overview 源码/性能/个性化/拓扑相关测试、source verifier、Swift build、全量 Swift test、JSON 校验和 `git diff --check` 通过。

## Out of Scope

- 不更改 AppModel、ControllerCapabilities、HTTP/WebSocket、Session generation、认证或重连逻辑。
- 不重构 Proxies、Connections、Logs、Rules、Sources、管理页或 Settings。
- 不修改全局配色 token，不引入第三方图表库，不创建或推送 Git 提交。

## Notes

- 父任务：`08-04-workbench-native-ui-system`，本任务负责 Phase 2。
- 运行时视觉验收由用户完成；自动验证只执行纯本地源码、构建和测试检查。
