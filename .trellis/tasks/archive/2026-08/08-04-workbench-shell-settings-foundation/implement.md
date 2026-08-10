# Workbench 壳层、设置与视觉基础实施计划

## Implementation

- [x] 机械提取 `MicaSettingsSceneView` 及其私有 preference helpers 到 `WorkbenchSettings.swift`，更新 Workbench 精确文件合同和 verifier。
- [x] 统一 chrome separator/page fill 使用，移除本阶段范围内重复或失效的背景路径。
- [x] 完善侧边栏整行按钮语义、选中态、方向键导航、help 和 accessibility。
- [x] 调整 Settings 的响应式说明/控件布局、尾随对齐、单一滚动和四项设置展示。
- [x] 审核 `MicaApp` scene/toolbar/commands，确认即时偏好传播、10 个目的地和无 Command Palette 路径。
- [x] 为新增合同补充 source verifier 与必要的 navigation/preference tests。

## Validation

- [x] `node --check scripts/verify-real-controller-source.mjs`
- [x] `node scripts/verify-real-controller-source.mjs`
- [x] `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`
- [x] `swift test --filter WorkbenchPreferencesTests --scratch-path tmp/codex/swift-build`
- [x] `swift test --filter WorkbenchNavigationTests --scratch-path tmp/codex/swift-build`
- [x] `swift build --scratch-path tmp/codex/swift-build`
- [x] `swift test --scratch-path tmp/codex/swift-build`
- [x] `git diff --check`
- [x] `python3 ./.trellis/scripts/task.py validate 08-04-workbench-shell-settings-foundation`
- [x] 清理 `tmp/codex/swift-build`

## Review Gate

- [x] 父任务和 Phase 1 范围已获用户批准。
- [x] 子任务通过 Trellis validate 并激活后才修改应用源码。
- [x] 任何涉及 controller/session 行为的意外需求停止并移交后续独立任务。

## Rollback Points

- Settings 机械提取后先依靠编译器/source verifier确认所有权正确。
- Shared chrome/sidebar/settings 作为一个完整 UI 切片集中验证；若失败，只回退本任务新增代码，不触碰父任务或已归档 Phase 0 工作。
