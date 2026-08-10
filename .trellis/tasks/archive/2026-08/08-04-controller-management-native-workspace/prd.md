# 控制器管理原生工作区重构

## Goal

将 Controllers、同窗口 RouterEditor、Configuration、Actions 与 Diagnostics 重构为一致、清晰、响应式且高性能的原生 macOS 管理工作区，同时把过大的 `WorkbenchManagement.swift` 按职责机械拆分。用户应能在一个窗口内安全管理控制器、修改真实支持的配置、执行受能力约束的操作并读懂诊断结果，且不会因本地选择、旧异步结果或视觉重构改变控制器会话语义。

## Confirmed Facts

- 当前管理页面集中在约 4,500 行的 `WorkbenchManagement.swift`；Settings 已迁至 `WorkbenchSettings.swift`，不得回退或重复实现。
- `AppModel` 是 `@MainActor @Observable`，控制器会话由 controller ID 与 generation 共同拥有；UI 只能调用现有 AppModel intent。
- 控制器列表顺序来自持久化 profile 数组；`moveRouter` 是唯一显式重排入口。列表选择只改变工作区详情，只有明确的 `Use` 操作可以调用 `selectRouter`。
- 新增或编辑控制器由主窗口内的 `RouterEditorView` 完成。保存通过 `upsertRouter(from:)` 一次性提交 profile 与现有 `FileSecretStore` 事务；不得改为 Keychain 或视图直写持久层。
- 配置修改使用 `ControllerConfigMutation`，现有操作会进行 capability 检查、乐观更新、失败回滚，并在结果回收时校验 controller ID 与 generation。
- Actions 的真实端点和能力来自现有 runtime operation/capability 映射；不得依据外部生成稿新增或删除真实能力。
- Diagnostics 已有可见性与字段投影，可隐藏不支持项并排除机器字段；安全技术细节继续由现有 Copy Report 输出。
- SwiftPM 会自动纳入 target 目录下的新 Swift 文件，但源码 verifier 和 Workbench 精确文件清单必须同步更新。

## Requirements

### R1. Mechanical ownership split

- 先按完整职责块机械拆分现有类型，不改类型名、入口、状态所有权、业务行为或 AppModel API。
- `WorkbenchManagement.swift` 只保留真正跨管理页面共享的布局、表单和状态原语；页面分别归属 `WorkbenchControllers.swift`、`WorkbenchConfiguration.swift`、`WorkbenchActions.swift` 与 `WorkbenchDiagnostics.swift`。
- 页面私有 helper 随页面整体移动并保持 `private`；只有真实跨文件共享的原语允许保持 module-internal，禁止扩大为 `public`。
- 拆分后先执行一次 Swift build 作为高风险边界检查，通过后再进行 UI 修改。
- 同步更新 `.trellis/spec/frontend/workbench-ui-contract.md`、源码 verifier 的精确文件集合和依赖该文件映射的长期文档。

### R2. Controllers workspace

- 使用稳定的 master-detail 工作区：宽窗口左右分栏，窄窗口同页上下分栏；页面保持一个主滚动所有者，不制造不成比例的空白。
- 列表严格保持持久化顺序。搜索只过滤投影，不修改源数组；移动只通过显式上移/下移操作完成。
- 选择列表行只显示详情，不发起连接或测试。只有详情中的可见 `Use` 命令能切换活动控制器；当前活动控制器不再显示可执行的 `Use`。
- Edit、Delete、Test、Use 与重排命令集中在右侧详情上下文，列表行保持易扫描且整行可选择。
- 删除和其他危险操作使用同窗口行内确认，并绑定目标 controller ID 与当前 generation；切换会话、目标消失或 generation 改变时确认立即失效。
- 不自动轮询所有控制器，不抢占已有会话，不自动排序或故障转移，不显示明文 secret。

### R3. RouterEditor

- 保持主窗口内覆盖式编辑，不改成普通 Sheet、独立窗口或全屏弹窗。
- 使用现有管理表单原语形成紧凑、可读、响应式的分组表单；避免重复标签列、固定巨宽画布和字段卡片墙。
- 保留名称、控制器类型、协议、主机、端口、凭据与 TLS 等现有字段、校验和连接测试语义。
- Save、Test、Cancel 均有可见标题和键盘语义；未保存更改使用同窗口行内确认。
- 保存只调用 `upsertRouter(from:)`，保持单次 profile/secret 事务、失败恢复和 `FileSecretStore` 语义。

### R4. Configuration workspace

- 仅展示当前控制器实际报告且 capability 允许修改的字段；不显示猜测项、灰色占位项或原始 YAML/JSON 编辑器。
- 保持现有 typed mutation、乐观更新、失败回滚、刷新和 controller ID/generation 校验。
- 使用原生分组表单与紧凑行，不为每个字段创建卡片；字段值在稳定标签列后左对齐，只有操作命令靠尾部对齐，窄布局允许自然换行而不切换成另一套页面。
- 连接中、暂停、部分可用、失败和 unsupported 状态必须准确区分。

### R5. Actions workspace

- 只投影当前控制器真实支持且已有 AppModel intent 的操作，保持现有能力顺序；不支持项直接隐藏，空分组不渲染。
- 使用原生列表/表单行而非卡片网格。标题、影响范围、最近结果和执行命令应在单行或紧凑两行内清晰扫描。
- 破坏性操作采用 generation-safe 行内确认；确认、执行和结果都必须绑定同一 controller ID、generation 与 operation ID。
- 执行中阻止重复提交；成功、部分成功和失败使用结构化、可本地化状态，不弹普通模态窗口。

### R6. Diagnostics workspace

- 顶部先给出人类可读的诊断结论、连接状态、兼容状态、最近结果和建议操作，不输出内部赋值串。
- 主体为一个同窗口诊断 outline。一级与二级 disclosure 均整行可点击，使用一致的短动画，并在 Reduce Motion 下静态切换。
- 只显示当前控制器可检测且有用户价值的检查；不支持项和空 section 从两个层级同时隐藏。
- 展开内容按“现状/影响/建议”或等价结构展示，不显示 `/rules`、`/connections` 等 API 路径、机器键值墙、原始响应正文或凭据。
- Copy Report 保留安全技术细节，但继续排除凭据、授权、订阅 URL、密钥内容和原始响应/流正文。
- 展开后滚动必须保持顺畅：使用稳定 ID 和预计算投影，避免嵌套 lazy/scroll 容器、全集格式化和全树隐式动画。

### R7. Shared UI, localization, and accessibility

- 复用现有 `MicaStyle`、`WorkbenchVisualSystem`、`WorkbenchSymbol` 与 `micaFont`；内容区不使用自定义 glass/material、装饰渐变、阴影堆叠或超过 8pt 的圆角。
- 页面宽度断点只由可用宽度决定；四档字号必须即时生效，但不得因字号改变页面架构。
- 所有可见文案、help、状态和 accessibility 文案提供英文与简体中文，不泄漏 `%@` 等格式占位符。
- 列表、详情行、disclosure header 和命令具有完整点击区域、键盘焦点与可理解的 VoiceOver 标签。
- 不新增第三方依赖，不新增平行 View、平行数据源或页面级 timer。

## Acceptance Criteria

- [x] AC1：管理源码已按职责拆分，现有 View 类型与入口保持不变；`WorkbenchManagement.swift` 只保留共享原语，SwiftPM、UI 合同和源码 verifier 的文件清单一致。
- [x] AC2：机械拆分后的独立 Swift build 通过，证明拆分未改变可编译边界；任何必要的访问级别变化仅为 module-internal 且有明确共享消费者。
- [x] AC3：Controllers 在窄/宽窗口均为稳定 master-detail；过滤和选择不改源顺序、不连接，只有显式 `Use` 切换活动控制器，移动操作持久化用户顺序。
- [x] AC4：Edit、Delete、Test、Use 和重排位于详情上下文；危险确认在 controller ID 或 generation 改变后不可执行。
- [x] AC5：RouterEditor 保持同窗口、无重复标签或固定巨宽布局；Save/Test/Cancel、校验、未保存确认和现有 `FileSecretStore` 事务语义保持正确。
- [x] AC6：Configuration 仅渲染真实支持字段，所有写入继续使用 typed mutation，并在失败或旧 generation 结果时正确回滚/丢弃。
- [x] AC7：Actions 仅显示真实支持操作，保持能力顺序；不支持项和空分组隐藏，破坏性操作使用目标与 generation 绑定的行内确认。
- [x] AC8：Diagnostics 的结论和明细可直接理解；一级、二级展开均整行可点且动画一致，不支持项在两个层级隐藏，界面无 API 路径、机器赋值串、原始 payload 或凭据。
- [x] AC9：诊断展开多个 section 后仍只有一个主滚动所有者，无嵌套 lazy/scroll 容器导致的明显滚动卡顿。
- [x] AC10：五个页面在浅色/深色、四档字号和窄/中/宽窗口下无重叠、不必要横向滚动、色带断层或大面积失衡空白。
- [x] AC11：英文/简体中文可见文案、help 和 accessibility 无混杂或格式占位符泄漏；完整行点击和键盘导航可用。
- [x] AC12：相关现有 projection、profile transaction、FileSecretStore、config/action generation 与 diagnostics redaction 测试、源码 verifier、Swift build/test、XCStrings JSON 和 `git diff --check` 通过；自动验证不启动 Mica、不访问控制器、不运行 runtime smoke。

## Out of Scope

- 不改变控制器 HTTP/WebSocket/gRPC 协议、DTO/领域模型或会话重连策略。
- 不新增、下载、打包、启动或管理本地核心，不修改系统网络、OpenWrt、LuCI、SSH 或 `ubus`。
- 不新增控制器能力、后台控制器 Ping、自动故障转移、自动排序、Command Palette 或重复 Settings 页面。
- 不把 `FileSecretStore` 改为 Keychain，不在 UI 或导出中暴露 secret。
- 不引入第三方 UI/诊断库，不运行真实控制器 smoke。

## Key Decisions

- 本任务不继续拆成更小子任务：五个页面共享同一大文件、表单原语、能力投影与 generation 边界，先机械拆分再统一验收能减少重复迁移和访问级别漂移。
- 源码、测试和现有 AppModel API 优先于外部生成稿；真实已支持的 operation 不因生成稿中的端点清单而删除，也不新增未经仓库确认的 operation。
- 视觉重构不改变业务语义。现有可证明正确的顺序、持久化、回滚、确认和 redaction 逻辑优先复用。
- 没有阻塞规划的开放问题；运行时视觉和真实数据体验由用户在实现完成后手工验收。
