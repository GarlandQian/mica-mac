# 全面性能优化与必要重写

## Goal

以可重复测量为依据，全面降低 Mica 在实时数据更新、页面滚动、筛选与
排序、策略组切换、图表交互、控制器切换和后台网络会话中的延迟、卡顿、
CPU 与内存消耗。允许重写现有实现；只有成熟三方库能够显著改善性能、
正确性或长期维护成本时才引入。

## Background And Evidence

- Mica 是原生 Swift 6.2 / SwiftUI macOS 27 应用，不使用 WebView 或网页
  前端。
- 当前 Workbench 已收敛为 6 个 Swift 文件和 11 个固定目的地；旧 UI
  架构不是兼容目标。
- `AppModel` 是 `@MainActor @Observable`，实时会话按领域发布，并已有日志
  5 Hz、流量 4 Hz、连接 2 Hz、内存 1 Hz 的可见发布预算。
- 日志使用 2,000 条 / 8 MiB 的 O(1) 环形缓冲；已关闭连接保留 200 条 /
  30 分钟；活动会话具有 generation 校验和单飞刷新通道。
- 当前直接三方依赖只有 sing-box gRPC/Protobuf 链：`grpc-swift-2`、
  `grpc-swift-nio-transport`、`grpc-swift-protobuf`、`swift-protobuf`。
  SwiftUI 列表、Canvas 和 Swift Charts 目前均使用系统实现。
- 自动化验证不得连接真实控制器、启动核心、访问 9090 或修改系统网络
  环境。真实数据 Instruments 验收需要单独获得用户运行授权。
- 用户决定本轮暂不启动真实控制器或采集真实会话 Instruments trace；后续
  由用户另行明确授权。当前任务必须以 Release 离线基准、合成负载、请求
  记录、任务生命周期测试和源码 signpost 作为性能证据。
- 合成数据仅用于测试和基准目标，不得编译成用户可见的产品数据源，不得
  在正式 Workbench 中替代控制器真实数据。
- 四项源码审计已完成。当前最高优先级热点候选是：高频原始流逐条进入
  `@MainActor AppModel`、连接和日志在发布边界重复全量比较/物化、拓扑
  共享链路与高亮路径存在近似 O(n²) 工作、连接修订同时驱动 Connections/
  Rules/Topology 全量投影，以及递归刷新重试和重复 HTTP 客户端/请求。
- 依赖审计建议默认不新增三方包。现有四个直接包组成 sing-box gRPC/
  Protobuf 必需链路；SwiftUI、Swift Charts、Canvas、URLSession 和
  OSSignposter 足以覆盖当前 UI、图表、网络与性能观测需求。
- 追加候选库研究与本地 Release 对比后，当前没有新运行时包通过采用门槛：
  Mica 专用有序数组/索引和固定环形缓冲在对应代理基准中优于
  `OrderedDictionary`/`Deque`；AsyncAlgorithms、Atomics、Alamofire、
  AsyncHTTPClient 和 DGCharts 不匹配已确认热点；Benchmark 工具功能成熟，
  但其插件/传递依赖和可测目标边界成本暂高于小型原生基准入口。

## Technical Notes

- P0. 将日志、流量、内存和连接的高频原始摄取移出主 Actor，建立按
  generation 所有的摄取/运行时边界，只按既有领域预算向 UI 发布不可变
  快照或增量。证据：`Sources/Mica/App/AppModel.swift:69,129`、
  `Sources/Mica/App/AppModelLiveSession.swift:1656,1783,1801,1818,2293-2361`。
- P0. 将连接“成员/链路结构变化”和“流量计数变化”拆成不同 revision，
  避免仅字节计数变化时重建 Rules 索引、完整连接行和拓扑。
  证据：`Sources/Mica/App/AppModel.swift:396-405`、
  `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:919-1030,2633-2969`、
  `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:969-1099`。
- P0. 让日志所有者直接发布 append/drop delta 与单调序列，避免 5 Hz
  路径反复复制 2,000 条环形缓冲、全量比较并在视图层重新发现重叠区间。
  证据：`Sources/Mica/App/AppModel.swift:408-417`、
  `Sources/Mica/App/SessionBuffers.swift:19`、
  `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1383-1562`。
- P0. 重写拓扑累积、高亮路径和命中索引热点，完整保留所有链路，但使
  构建与交互成本随总路径阶段数近线性增长。
  证据：`Sources/Mica/App/ConnectionTopologyModel.swift:295,315`、
  `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:1134,1248,1984,2053,2072`。
- P0. 将手动刷新、周期 lane、重试和 follow-up 收敛到 generation-scoped
  迭代协调器；消除递归重试、丢失任务句柄、启动基线与稳态轮询重叠。
  证据：`Sources/Mica/App/AppModelLiveSession.swift:319-340,652,694,2235-2247`。
- P1. 每个 generation 复用类型化 HTTP/gRPC 客户端与连接池，明确每个
  端点唯一刷新所有者；必需长连接流正常结束也必须触发整体重连。
  证据：`Sources/Mica/App/AppModelLiveSession.swift:715,833,1873-1982`、
  `Sources/MicaCore/API/MihomoClient.swift:77`、
  `Sources/MicaCore/API/SurgeHttpAPIClient.swift:42`。
- P1. 缓存 Overview 时间线/Top-K、规则静态字段、来源日期/元数据、代理
  搜索索引和本地化反向索引，只让真正变化的动态字段进入高频路径。
- P1. 非当前目的地或窗口不可见时暂停该页面的高频投影、图表重算和布局，
  但继续维护控制器连接、generation、原始会话状态和必要后台更新；重新
  激活时一次发布最新一致快照。
- P1. 用户滚动、拖动图表或输入筛选时，合并非关键遥测、排行、拓扑和
  表格计数更新；交互结束后直接发布最新快照，不逐帧回放积压状态。断线、
  错误、节点切换结果和用户操作反馈不参与延迟合并。
- P1. 将离线合成负载、投影/物化计数器和低开销 signpost 作为长期性能
  回归基础保留；重型性能基准使用专用命令运行，不拖慢普通测试。
- P2. 在主要实时/UI 热点稳定后，再处理配置密钥文件重复读取、本地化
  反向匹配、格式化器/编码器重复创建，以及 `swift-protobuf traits: []`
  的独立构建体积实验；测量无收益则不保留改动。
- P1. 优先使用 `OSSignposter`、Instruments 和离线合成数据建立证据；仅在
  聚焦基准证明系统/本地实现不足时重新评估新依赖。

## Requirements

- R1. 先建立可重复的性能基线，再决定优化或重写；不得只凭代码风格或
  主观感觉宣称性能改善。
- R2. 审计 UI 渲染、Observation 失效范围、列表和表格投影、图表绘制、
  拓扑布局、日志跟随、策略组筛选、控制器切换、网络轮询/流、持久化和
  并发任务生命周期。
- R3. 优先消除算法复杂度、重复物化、主线程工作、宽域状态发布、非稳定
  identity、无界缓存、重复请求和无效视图更新，而不是仅调低刷新频率。
- R4. 保持完整业务数据可见、控制器报告顺序、GLOBAL-last、generation
  安全、原子重连、能力门控和现有 controller/API 语义。
- R5. 允许删除和重写热点实现，不要求兼容已经废弃的 UI、投影器或状态
  抽象。
- R6. 三方依赖必须逐项证明：系统框架或小型本地实现无法同等解决；项目
  活跃维护；许可证可再分发；兼容 macOS 27 与 Swift 6.2；二进制、启动
  时间和构建成本可接受；并在任务和长期文档记录理由。
- R7. 不为装饰、普通集合操作、简单缓存或可以由 SwiftUI/Swift Charts/
  Canvas/OSLog/URLSession 完成的功能引入依赖。
- R8. 优化后必须保持原生 SwiftUI 内容架构；AppKit 仅用于 SwiftUI 无法
  提供的系统服务，不建立第二套内容 UI 或状态系统。
- R9. 新增性能观测应使用可移除或低开销的 signpost/测试钩子，不得在
  发布构建留下高频调试日志。
- R10. 允许拆分当前超大 Swift 文件，但拆分必须对应真实所有权或性能
  边界，例如高频可观察状态、纯投影/索引、拓扑布局、数据浏览器、会话
  协调器和控制器传输。不得只按行数拆分，也不得恢复旧 Workbench 的
  一文件一小组件和兼容包装层。
- R11. `WorkbenchDataPages.swift` 可按 Connections、Rules、Sources、Logs
  四个产品页面及共享纯投影边界拆分；`WorkbenchDashboard.swift` 可按
  Overview 遥测与 Topology 数据/布局/Canvas 交互边界拆分；最终边界由
  测量和单向依赖决定，不预设机械文件数量。
- R12. `AppModelLiveSession.swift` 的重写应把摄取、刷新协调和 UI 发布拆成
  可独立测试的所有权单元，同时保留一个明确的 session/generation 生命周期
  入口，禁止产生第二套互相同步的会话真相。
- R13. 可见性门控只能暂停展示层派生工作，不得暂停协议必须的读取、破坏
  重连/退避、漏记日志和已关闭连接，或让返回页面时短暂显示旧 generation
  数据。
- R14. 交互优先调度必须有明确的关键/非关键领域分类、最长延迟和取消边界；
  不得通过无限 debounce、降低数据真实性或积压后连续补帧来伪造流畅度。
- R15. 性能测试基础设施必须确定性、无真实网络依赖且适合长期维护。普通
  `swift test` 保留快速正确性与计数器合同；大规模 Release 基准和 Instruments
  采集通过显式命令或方案执行。
- R16. “当前不引入”不是永久禁令。实施中发现新的明确热点时，必须在同一
  输入、Release 配置和正确性合同下比较本地/系统实现与候选包；只有性能、
  正确性或维护收益显著且依赖成本通过 R6 时，才允许修改 `Package.swift`。

## Initial Acceptance Criteria

- [ ] AC1. 建立覆盖启动、控制器会话、11 个目的地、滚动、筛选、策略组
      切换、日志跟随、Overview 图表和完整拓扑的基线与优化后对比。
- [ ] AC2. 自动化测试证明领域发布互不干扰，高频样本不会使无关页面、
      侧边栏、工具栏或控制器列表失效。
- [ ] AC3. 大数据集下的筛选、排序、稳定 identity、缓存和增量投影具有
      可重复的单元/性能测试，不出现 O(n²) 或前端数组头删热点。
- [ ] AC4. 离线 SwiftUI/Time Profiler 或等价的可重复 Release 基准证据
      显示主要主线程工作、重复投影、布局和滚动热点已消除或显著下降；
      真实控制器 trace 在用户后续授权前不作为本轮阻塞条件。
- [ ] AC5. 断开、重连、切换和结束会话后不继续发布旧数据，也不保留泄漏
      的任务、流、计时器或大缓存。
- [ ] AC6. 网络请求保持单飞、取消和退避语义；不会通过额外轮询掩盖 UI
      卡顿。
- [ ] AC7. 依赖审计列出所有直接和传递包的用途、必要性、许可证、维护
      状态和性能影响；新增/删除依赖均有测量依据。
- [ ] AC8. `swift build`、完整测试、源码契约、本地化 JSON、HIG 检查和
      `git diff --check` 全部通过。
- [ ] AC9. 不运行真实控制器或运行时 profiling 时，任务必须明确区分
      “源码/自动化改善”与“用户实机性能已验收”，不得伪造后者。
- [ ] AC10. 被拆分的模块拥有单向、可测试的依赖边界；高频变化不会因为
      环境注入或共享模型重新扩大到整个页面，源码验证器和项目文档同步
      反映最终文件架构。
- [ ] AC11. 1k/5k/10k 连接、满载 2,000 条日志和大规模共享链路拓扑的
      Release 离线基准记录中，连接/日志增量工作与实际 delta 成比例；
      拓扑构建、命中索引和选择高亮不出现可复现的二次增长。
- [ ] AC12. 自动化请求记录证明每个 generation 复用传输客户端、每个端点
      只有一个 cadence 所有者，重复手动刷新会合并或等待同一 flight，
      长时间瞬时失败不会累积递归 async frame。
- [ ] AC13. 文件拆分完成后，页面入口只组合窄域状态和功能模块；纯投影、
      索引、布局与传输代码不依赖 SwiftUI Environment 或整个 `AppModel`。
- [ ] AC14. 自动化可见性测试证明未激活目的地不会持续执行其高频投影、
      Chart/Canvas 或布局任务；重新激活后只发布最新 generation 的一致快照，
      且控制器连接和原始数据连续性不受影响。
- [ ] AC15. 自动化交互测试证明持续滚动、图表拖动和筛选输入期间，非关键
      展示工作被有界合并；关键状态保持即时，交互结束后一次追到最新值，
      不发生陈旧帧回放、选择跳动或滚动位置重置。
- [ ] AC16. 仓库保留可重复的合成夹具、性能计数器、signpost 分类和专用
      Release 基准入口；普通测试不运行重型基准，且性能观测不会泄露凭据
      或原始响应体。
- [ ] AC17. 任何新增三方包都附带精确版本、官方维护/许可证/兼容性证据、
      采用前后基准、生产与开发构建图影响、二进制/构建成本及回退结果；
      无显著收益的候选不得保留。

## Out Of Scope

- 下载、捆绑、启动或管理本地代理核心。
- 修改系统代理、环境变量、防火墙、OpenWrt、SSH 或 `ubus`。
- 为性能重写 controller 协议语义，或复制 SparkXie、Zashboard、
  OpenSurge 等项目的前端/运行时代码。
- 在没有测量依据时更换 SwiftUI、Swift Charts、URLSession 或现有 gRPC
  协议栈。
