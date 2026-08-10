# Workbench 壳层、设置与视觉基础重构

## Goal

统一 Mica 主窗口壳层、侧边栏、原生工具栏、命令栏、底部状态栏和独立 Settings 的视觉与交互基础。在不改变控制器协议、AppModel/session 生命周期或页面业务行为的前提下，消除颜色断层、重复视觉路径、狭小点击区域和字号/布局耦合，为后续页面重构提供稳定基础。

## Requirements

- 直接修改现有 `ContentView`、`WorkbenchRootView`、`WorkbenchSidebarView`、`MicaApp`、`MicaSettingsSceneView` 和 `WorkbenchVisualSystem`，不创建平行壳层或第二套设计系统。
- 主窗口、窗口工具栏、页面命令栏、内容区、加载/空状态和底部状态栏共享 `MicaDesignTokens.pageFill` 与一致的 separator 语义。
- 侧边栏保留 10 个固定目的地和顶部内联控制器切换器。导航行整行可点击，选中态使用现有 soft accent、3pt leading indicator 和单色 SF Symbol；支持完整键盘导航。
- 侧边栏和工具栏不重复控制器身份；不得恢复 Command Palette、Command Deck 或 Cmd+K。
- 保持原生 `Settings { MicaSettingsSceneView() }`，仅显示语言、外观、四档界面字号和 GLOBAL 策略组可见性。
- Settings 使用单一原生 grouped form、明确的说明/控件两列关系和响应式窄布局；控件在常规宽度下尾随对齐，不形成大面积失衡空白。
- 语言、外观和字号继续通过现有 `AppPreferencesStore` 与 scene environment 同步到所有已打开窗口，无需重启。
- 字号仅影响 `micaFont` 文本角色，不缩放侧边栏、toolbar、status bar、表格或页面断点几何。
- 内容圆角不超过 8pt；内容区不使用 `.thinMaterial`、`.ultraThinMaterial`、自定义 glass、装饰渐变或阴影卡片墙。
- 不启动 Mica、不访问控制器、不运行 runtime smoke；临时产物只写入 `tmp/codex/` 并在验证后清理。

## Acceptance Criteria

- [x] AC1：主窗口只保留一个 `NavigationSplitView` 和 10 个既有目的地，Settings 不出现在 Workbench 导航中。
- [x] AC2：侧边栏目的地按钮的 label 与 button 本身都占满行宽，点击区域为整行；选中态、字体和图标符合共享视觉合同。
- [x] AC3：侧边栏可用上下方向键按显示顺序切换目的地，焦点与 VoiceOver 语义清晰，不干扰控制器切换器。
- [x] AC4：Window、Toolbar、Command Bar、Content、State View 和 Status Bar 使用同一 page fill 与共享 separator，无独立色带或额外浮动胶囊。
- [x] AC5：Settings 只包含语言、外观、四档字号和 GLOBAL 可见性，且只存在于原生 Settings scene。
- [x] AC6：Settings 在常规宽度使用说明在左、控件尾随对齐的两列布局；窄宽度自然堆叠，布局断点只由可用宽度决定。
- [x] AC7：语言、外观和字号修改继续即时传播；四档字号分别为 0.92、1.0、1.16、1.32，几何 token 不参与缩放。
- [x] AC8：源码中不存在 Command Palette、Command Deck、Cmd+K、自定义内容 glass、全局 44pt 导航高度或重复 controller identity toolbar。
- [x] AC9：相关 preference/navigation/localization 测试、source verifier、XCStrings JSON、Swift build、Swift test 和 `git diff --check` 通过。

## Out of Scope

- 不重构 Overview、Logs、Rules、Sources 或管理页面的业务内容。
- 不更改控制器选择、连接、认证、刷新、重连、generation 或持久化语义。
- 不新增第三方依赖，不修改发布配置，不创建或推送 Git 提交。

## Notes

- 父任务：`08-04-workbench-native-ui-system`，本任务负责其 Phase 1。
- 运行时视觉验收由用户完成；自动验证只做纯本地源码、构建和测试检查。
