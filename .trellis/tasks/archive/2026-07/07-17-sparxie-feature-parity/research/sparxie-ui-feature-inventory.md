# Research: Sparxie UI feature inventory

- Query: 审计本地参考仓库 `tmp/codex/sparxie` 的 Flutter/Dart 前端功能，形成覆盖导航、页面数据、筛选/排序/分页、策略组与节点、连接/日志/规则/流量、配置、provider、缓存/内存/状态、控制器管理、错误/加载/空状态及平台差异的源码级清单；标记 Clash/Mihomo、Surge、sing-box 的 UI 能力差异。
- Scope: internal
- Date: 2026-07-17

## Findings

### 1. 审计边界与总体结论

- 本清单以 Flutter 视图、Dart 会话/偏好/控制器状态和 Rust 后端分派三层交叉取证，不以 README 作为功能事实来源。应用入口先加载同一个 `config.json`、窗口状态、Rust bridge、偏好、磁盘缓存和控制器列表，然后立即为当前控制器创建共享 `MihomoSession`；没有用户触发的“开始同步”步骤。锚点：`tmp/codex/sparxie/lib/main.dart:35-75`、`tmp/codex/sparxie/lib/session.dart:26-30`。
- 顶层可达功能族共十类：概览、代理组、连接、核心配置、日志、外部资源、核心操作、分流规则、Tailscale、其他；“其他”再进入后端设置与应用设置。具体是否直接出现在导航中由布局、窗口宽度、窗口高度和运行时能力探测共同决定。锚点：`tmp/codex/sparxie/lib/main.dart:322-382`、`tmp/codex/sparxie/lib/screens/settings_screen.dart:48-136`。
- 三类后端共享代理组、流量、连接、日志的统一 UI 模型，但后端实现并不等价：Mihomo/Clash 主要使用 WebSocket/REST；Surge 流量按 1 秒轮询、日志按 5 秒轮询；sing-box 通过 gRPC 状态/连接/日志流。锚点：`tmp/codex/sparxie/core/src/backend/streams.rs:11-45`、`tmp/codex/sparxie/core/src/backend/streams.rs:82-133`、`tmp/codex/sparxie/core/src/surge/state/logs.rs:85-106`。
- `BackendType.clash` 不是单一能力集：运行时还会探测普通 Mihomo、CMFA、Stash 或 Unknown，并据此决定核心配置、核心管理、缓存清理、内存和连接日志等 UI。锚点：`tmp/codex/sparxie/core/src/clash/api/backend.rs:6-18`、`tmp/codex/sparxie/core/src/clash/api/version.rs:36-50`。

### 1.1 最高优先级结论（供后续 Mica 对齐）

| 优先级 | 结论 | 真实用户影响与源码证据 |
|---|---|---|
| P0 | 必须分别建模“导航入口可见”“控件可操作”“后端动作真实支持”，不能把存在 API 或共用页面等同于功能齐平。 | Surge 用户在标准核心配置页只能读取配置，但在概览卡片可切换出站模式；Surge 重载 API 没有对应 UI。sing-box 用户能看到按组/按链关闭入口，但后端返回 unsupported。锚点：`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:132-143`、`tmp/codex/sparxie/lib/widgets/outbound_mode_card.dart:78-97`、`tmp/codex/sparxie/core/src/surge/api.rs:102-108`、`tmp/codex/sparxie/lib/widgets/connection_group_header.dart:132-137`、`tmp/codex/sparxie/core/src/sing_box/api.rs:98-104`。 |
| P0 | Sparxie 的会话生命周期和暂停语义只能作为参考行为，不能直接复制为 Mica 的状态契约。 | 用户切换控制器时，当前流量、内存、连接、日志、代理等可见数据会整体重置并复用单一错误状态；连接/日志暂停时，新帧或新条目直接丢弃，而不是保留为待发布数据；部分流错误路径还可能保留 `isStreaming=true`。锚点：`tmp/codex/sparxie/lib/session.dart:359-414`、`tmp/codex/sparxie/lib/session.dart:564-579`、`tmp/codex/sparxie/lib/session.dart:607-633`、`tmp/codex/sparxie/lib/session.dart:715-729`、`tmp/codex/sparxie/lib/session/logs.dart:17-28`。 |
| P0 | 功能对齐必须以业务字段完整可达为准，不能只复刻 Sparxie 的主列表呈现。 | 用户在多个主列表中会看到省略后的控制器地址、策略/节点、provider 或 Tailscale 文本；连接模型虽保留 `specialProxy`、`specialRules`、`remoteDestination`，详情页也没有呈现这些字段。因此“后端已返回/模型已保存”仍不等于用户可查看。锚点：`tmp/codex/sparxie/lib/session/connections.dart:142-145`、`tmp/codex/sparxie/lib/widgets/connection_detail_sheet.dart:25-46`。 |
| P1 | 筛选后的结果集和空状态存在可复现的 UI 语义缺口，应按用户操作单独验收。 | 用户搜索不存在的代理时，“没有匹配的项”分支不可达；用户在非分组连接列表筛选时，未命中行变成占位块，列表不压缩且没有无匹配状态。锚点：`tmp/codex/sparxie/lib/screens/proxies_screen.dart:436-445`、`tmp/codex/sparxie/lib/screens/connections_screen.dart:605-655`。 |
| P1 | 控制器管理不能照搬 Sparxie 的持久化与切换事务。 | 用户不能测试连通性或手动排序；删除当前控制器后会直接选中第一项；secret 虽在编辑框遮蔽，却明文写入 `config.json`，且存储异常被吞掉、无可见失败反馈。锚点：`tmp/codex/sparxie/lib/controller.dart:60-67`、`tmp/codex/sparxie/lib/controller.dart:190-204`、`tmp/codex/sparxie/lib/config_store.dart:62-73`。 |

收敛后的首要验收顺序应为：先按后端类型与运行时 probe 建立能力矩阵，再验证控制器切换/暂停/错误状态，随后验证业务字段完整可见，最后补齐筛选空状态与控制器管理事务；视觉布局和组件形态不构成 parity 依据。

### 2. Files found

| 文件 | 一行说明 |
|---|---|
| `tmp/codex/sparxie/lib/main.dart` | 应用启动、主题/语言、响应式导航、卡片/侧栏/底栏入口和页面装配。 |
| `tmp/codex/sparxie/lib/controller.dart` | 后端类型、控制器模型、默认控制器、增删改与当前控制器持久化。 |
| `tmp/codex/sparxie/lib/session.dart` | 当前控制器的统一流量/内存/连接/日志/代理会话、能力探测与重试。 |
| `tmp/codex/sparxie/lib/session/proxies.dart` | 策略组稳定对象、当前/固定节点、成员窗口和延迟状态。 |
| `tmp/codex/sparxie/lib/session/connections.dart` | 活动/已关闭连接窗口、进程分组、计数、排序和乐观删除。 |
| `tmp/codex/sparxie/lib/session/logs.dart` | Dart 侧 500 条日志镜像与暂停/清空。 |
| `tmp/codex/sparxie/lib/session/process_icons.dart` | 本机进程图标/应用名内存缓存及 Android/桌面解析路径。 |
| `tmp/codex/sparxie/lib/screens/dashboard_screen.dart` | 概览页流量、内存、连接指标和 60 点迷你图。 |
| `tmp/codex/sparxie/lib/screens/proxies_screen.dart` | 策略组浏览、搜索、展开、节点选择/取消固定、单点/组测速。 |
| `tmp/codex/sparxie/lib/screens/connections_screen.dart` | 活动/已关闭连接、筛选、排序、分组、暂停、关闭和窗口化列表。 |
| `tmp/codex/sparxie/lib/screens/logs_screen.dart` | 日志等级、内容过滤、暂停、清空、自动跟随。 |
| `tmp/codex/sparxie/lib/screens/rules_screen.dart` | 后端缓存规则集、过滤、虚拟窗口、可选规则禁用。 |
| `tmp/codex/sparxie/lib/screens/resources_screen.dart` | 代理 provider 与规则 provider 目录、刷新及更新。 |
| `tmp/codex/sparxie/lib/screens/core_config_screen.dart` | 核心配置页容器。 |
| `tmp/codex/sparxie/lib/widgets/basic_config_panel.dart` | 出站模式、日志级别、TUN、LAN、IPv6、TCP 并发和端口配置。 |
| `tmp/codex/sparxie/lib/screens/core_actions_screen.dart` | 重载、GeoData、重启、升级、DNS/FakeIP 清理。 |
| `tmp/codex/sparxie/lib/screens/tailscale_screen.dart` | sing-box Tailscale 状态、认证、设备、出口节点和退出登录。 |
| `tmp/codex/sparxie/lib/screens/settings_screen.dart` | “其他”、应用设置、磁盘缓存、字体和控制器管理/编辑。 |
| `tmp/codex/sparxie/lib/widgets/backend_switcher.dart` | 概览页当前控制器快速切换。 |
| `tmp/codex/sparxie/lib/widgets/proxy_group_header.dart` | 策略组名称、类型、当前节点、数量、测速、展开。 |
| `tmp/codex/sparxie/lib/widgets/proxy_node_tile.dart` | 节点名称、类型、选中/固定状态和延迟入口。 |
| `tmp/codex/sparxie/lib/widgets/proxies_settings_menu.dart` | 代理列数、排序、隐藏组、切换断连和测速偏好。 |
| `tmp/codex/sparxie/lib/widgets/connection_tile.dart` | 连接行摘要。 |
| `tmp/codex/sparxie/lib/widgets/connection_detail_sheet.dart` | 连接完整详情与 Stash 连接日志。 |
| `tmp/codex/sparxie/lib/widgets/connections_settings_menu.dart` | 连接刷新间隔、进程信息、分组及分组排序。 |
| `tmp/codex/sparxie/lib/app_prefs.dart` | 全局 UI 偏好、默认值和持久化键。 |
| `tmp/codex/sparxie/lib/config_store.dart` | `config.json` 读写与 `controllers`/`prefs`/`window` 分区。 |
| `tmp/codex/sparxie/lib/app_paths.dart` | 标准目录与桌面便携模式路径。 |
| `tmp/codex/sparxie/lib/window_state.dart` | 桌面窗口尺寸、位置、最大化/全屏恢复。 |
| `tmp/codex/sparxie/core/src/backend/*.rs` | 三类后端的统一 API 分派、类型和能力边界。 |
| `tmp/codex/sparxie/core/src/clash/api/version.rs` | Mihomo/CMFA/Stash 运行时能力探测。 |
| `tmp/codex/sparxie/core/src/surge/api.rs` | Surge 配置、模式、流量及不支持能力。 |
| `tmp/codex/sparxie/core/src/sing_box/api.rs` | sing-box 模式、连接操作与 Tailscale 能力。 |
| `tmp/codex/sparxie/core/src/cache/db.rs` | 图标、进程图标和进程名的共享 redb 磁盘缓存。 |
| `tmp/codex/sparxie/pubspec.yaml` | 本地应用版本、Dart SDK 与 Flutter/Rust bridge 依赖声明。 |

### 3. 导航、布局与页面可达性

#### 3.1 响应式导航

| 布局/尺寸 | 用户实际操作 | 页面组织与能力门控 | 证据 |
|---|---|---|---|
| 卡片布局，宽度 `>= 800` | 点击左侧 300pt 卡片栏；核心配置、连接、规则使用 hero card 切换同窗主区；点击 “Sparxie” 进入后端设置。 | 卡片目的地包含代理组、日志、可用时的外部资源/Tailscale、其他；规则单独插入卡片，连接与核心配置不在普通目的地数组。 | `tmp/codex/sparxie/lib/main.dart:430-446`、`tmp/codex/sparxie/lib/main.dart:534-581`、`tmp/codex/sparxie/lib/main.dart:842-962` |
| 卡片布局，宽度 `< 800` | 首页是入口网格；点击任一卡片 push 新路由，用系统返回、Esc 或鼠标后退返回。 | 同样按能力隐藏核心配置、规则、外部资源、Tailscale。 | `tmp/codex/sparxie/lib/main.dart:676-727`、`tmp/codex/sparxie/lib/main.dart:310-319`、`tmp/codex/sparxie/lib/main.dart:408-413` |
| 标准布局，宽度 `>= 800` | 点击左侧固定高度侧栏，在 `IndexedStack` 中切页。 | 侧栏按窗口高度计算可容纳项；放不下的功能移入“其他”，从“其他”再 push 路由。 | `tmp/codex/sparxie/lib/main.dart:458-531` |
| 标准布局，宽度 `< 800` | 点击底部 Material `NavigationBar`。 | 直接只保留概览、代理组、连接、日志、其他；核心配置/操作/规则/资源/Tailscale 从“其他”进入。 | `tmp/codex/sparxie/lib/main.dart:322-355`、`tmp/codex/sparxie/lib/main.dart:584-637`、`tmp/codex/sparxie/lib/screens/settings_screen.dart:60-135` |
| 悬浮布局，宽度 `< 800` | 点击圆角悬浮底栏。 | 目的地集合与紧凑标准布局相同，并为底栏额外增加内容下边距。 | `tmp/codex/sparxie/lib/main.dart:639-674` |
| 悬浮布局，宽度 `>= 800` | 实际使用与标准宽屏相同的侧栏，而不是悬浮底栏。 | `wide && !cards` 统一进入 `_buildWideStandard`。 | `tmp/codex/sparxie/lib/main.dart:443-452` |

- 默认导航布局是“卡片”；用户可在应用设置中切换卡片/标准/悬浮，偏好持久化。锚点：`tmp/codex/sparxie/lib/app_prefs.dart:18-20`、`tmp/codex/sparxie/lib/app_prefs.dart:140-150`、`tmp/codex/sparxie/lib/screens/settings_screen.dart:300-327`。
- 页面实例按当前布局和目的地标签缓存于 `IndexedStack`，切页不重建已订阅页面；改变布局或能力导致目的地集合变化时才重建页面缓存。锚点：`tmp/codex/sparxie/lib/main.dart:385-403`。
- 键盘 `Esc` 和鼠标后退键仅在当前 Navigator 可 pop 时返回。移动端从后台恢复会调用会话重连，桌面最小化/恢复不会。锚点：`tmp/codex/sparxie/lib/main.dart:275-319`。

#### 3.2 页面与入口清单

| 页面/入口 | 直接出现条件 | 真实用户路径 | 证据 |
|---|---|---|---|
| 概览 | 仅标准/悬浮布局；卡片布局以 hero cards 取代。 | 导航点击“概览”。 | `tmp/codex/sparxie/lib/main.dart:331-338`、`tmp/codex/sparxie/lib/main.dart:358-381` |
| 代理组 | 始终出现。 | 导航/卡片点击“代理组”。 | `tmp/codex/sparxie/lib/main.dart:337` |
| 连接 | 标准/悬浮为普通目的地；卡片布局为流量/连接 hero card。 | 导航点击或 hero card 点击。 | `tmp/codex/sparxie/lib/main.dart:338`、`tmp/codex/sparxie/lib/main.dart:539-550`、`tmp/codex/sparxie/lib/main.dart:931-935` |
| 核心配置 | `supportsCoreConfig` 为真；卡片布局为状态 hero card。 | 导航、其他页或 hero card。 | `tmp/codex/sparxie/lib/main.dart:339-340`、`tmp/codex/sparxie/lib/main.dart:543-545`、`tmp/codex/sparxie/lib/main.dart:907-929` |
| 日志 | 始终出现。 | 导航/卡片点击“日志”。 | `tmp/codex/sparxie/lib/main.dart:341` |
| 外部资源 | 会话仅对 `BackendType.clash` 置真。 | 宽屏导航、卡片入口，或紧凑“其他”。 | `tmp/codex/sparxie/lib/session.dart:390-394`、`tmp/codex/sparxie/lib/main.dart:342-343` |
| 核心操作 | `supportsCoreActions` 为真。 | 宽屏导航或“其他”。 | `tmp/codex/sparxie/lib/main.dart:344-345`、`tmp/codex/sparxie/lib/screens/settings_screen.dart:105-114` |
| 分流规则 | 所有非 sing-box 后端；卡片布局单独规则卡。 | 宽屏导航、规则卡，或紧凑“其他”。 | `tmp/codex/sparxie/lib/session.dart:393-395`、`tmp/codex/sparxie/lib/main.dart:346-347`、`tmp/codex/sparxie/lib/main.dart:955-962` |
| Tailscale | 版本探测报告支持；当前实现仅 sing-box 返回真。 | 宽屏导航、卡片入口，或紧凑“其他”。 | `tmp/codex/sparxie/lib/session.dart:480-499`、`tmp/codex/sparxie/core/src/sing_box/api.rs:27-42` |
| 其他 | 始终出现。 | 导航/卡片点击“其他”。 | `tmp/codex/sparxie/lib/main.dart:354` |
| 后端设置 | 始终在“其他”；卡片布局标题也可直达。 | 点击“后端设置”或卡片栏“Sparxie”。 | `tmp/codex/sparxie/lib/screens/settings_screen.dart:82-87`、`tmp/codex/sparxie/lib/main.dart:885-904` |
| 应用设置 | 始终在“其他”。 | 点击“应用设置”。 | `tmp/codex/sparxie/lib/screens/settings_screen.dart:88-95` |

### 4. 逐页源码级功能清单

#### 4.1 概览

- 可见数据：当前控制器名称、后端类型、流状态圆点；除 Surge 外显示探测到的版本字符串。控制器超过一个时，点击标题弹出带后端类型和完整 `baseUrl` 的快速切换菜单。锚点：`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:98-140`、`tmp/codex/sparxie/lib/widgets/backend_switcher.dart:21-53`、`tmp/codex/sparxie/lib/widgets/backend_switcher.dart:117-139`。
- 流量：上传/下载当前速率、启动后累计上传/下载，以及各自最近 60 次通知的内存迷你图和峰值；切换控制器会清空历史。用户只读，无缩放或时间范围操作。锚点：`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:23-28`、`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:64-67`、`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:192-217`、`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:642-680`。
- 连接：显示当前连接总数；如果后端提供 `connectionsIn/connectionsOut`，改为显示“入站 / 出站”。锚点：`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:220-235`。
- 内存：仅 `supportsMemory` 时显示当前使用、可选 OS 上限和可选 goroutine 数，并维护 60 点迷你图。Mihomo 转换层不提供 goroutine，sing-box 状态流会提供。锚点：`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:69-76`、`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:177-181`、`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:238-256`、`tmp/codex/sparxie/core/src/backend/convert.rs:20-27`、`tmp/codex/sparxie/core/src/sing_box/state/status.rs:62-73`。
- 状态：共享会话错误以内联错误条显示；指标初始值为零，没有独立首次加载骨架或手动刷新。锚点：`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:83-95`、`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:141-188`、`tmp/codex/sparxie/lib/session.dart:65-76`。

#### 4.2 代理组与节点选择

- 可见数据：每组显示可选图标、组名、组类型、当前节点、成员数；`LoadBalance` 当前节点显示 `*`。每节点显示名称、类型、延迟，以及选中/固定状态。锚点：`tmp/codex/sparxie/lib/widgets/proxy_group_header.dart:52-109`、`tmp/codex/sparxie/lib/widgets/proxy_node_tile.dart:37-125`。
- 组展开：点击组头展开/收起；收起即释放该组 Dart 成员窗口，展开先请求第 0 项附近窗口。节点网格按宽度自动 1/2/3/4 列，或使用用户强制列数。锚点：`tmp/codex/sparxie/lib/screens/proxies_screen.dart:67-78`、`tmp/codex/sparxie/lib/screens/proxies_screen.dart:446-529`。
- 节点分页/窗口：后端保留完整成员列表，Dart 每组最小窗口 96 条、两侧 overscan 32；可见空位先画占位块，再按可见索引合并请求。这里不是页码式分页。锚点：`tmp/codex/sparxie/lib/session/proxies.dart:223-225`、`tmp/codex/sparxie/lib/session/proxies.dart:299-320`、`tmp/codex/sparxie/lib/screens/proxies_screen.dart:396-425`、`tmp/codex/sparxie/lib/screens/proxies_screen.dart:468-505`。
- 节点选择：点击可选节点先乐观更新 `now`，再调用后端；失败回滚并显示 SnackBar。若后端报告该节点为 `fixed`，再次点击会调用取消固定。锚点：`tmp/codex/sparxie/lib/screens/proxies_screen.dart:96-145`。
- 选点后断连：默认开启；用户可选择关闭全部连接或仅关闭代理链包含当前组的连接。调用为 fire-and-forget，不阻塞选点完成。锚点：`tmp/codex/sparxie/lib/screens/proxies_screen.dart:109-121`、`tmp/codex/sparxie/lib/app_prefs.dart:70-75`、`tmp/codex/sparxie/lib/app_prefs.dart:140-150`。
- 单节点测速：点击延迟文本触发；未测试显示“测试”、0 显示“超时”、1–499ms 为绿色、500ms 以上为橙色。失败时该节点延迟被写为 0。锚点：`tmp/codex/sparxie/lib/screens/proxies_screen.dart:192-215`、`tmp/codex/sparxie/lib/widgets/delay_badge.dart:5-37`、`tmp/codex/sparxie/lib/utils.dart:33-46`。
- 组测速：点击组头速度图标。可选择一次性组 API 或并发逐节点流式测速；Stash 强制走逐节点路径。测速中仅禁用该组按钮并显示 spinner。锚点：`tmp/codex/sparxie/lib/screens/proxies_screen.dart:147-190`、`tmp/codex/sparxie/lib/widgets/proxy_group_header.dart:100-109`。
- 搜索：点击 AppBar 搜索打开对话框，输入“组名或节点”；筛选值传给 Rust 重新生成目录，页面显示筛选条和清除按钮。三种后端都按组名或任一成员名匹配。锚点：`tmp/codex/sparxie/lib/screens/proxies_screen.dart:238-293`、`tmp/codex/sparxie/lib/screens/proxies_screen.dart:560-606`、`tmp/codex/sparxie/core/src/clash/api/proxies/catalog.rs:39-64`、`tmp/codex/sparxie/core/src/surge/api/policies.rs:35-59`、`tmp/codex/sparxie/core/src/sing_box/api/proxies.rs:171-196`。
- 排序：仅成员排序，选项为控制器原顺序、名称、延迟；不会由 Flutter 重新排序组。Clash 组顺序按 `GLOBAL.all` 优先映射，Surge 按 profile 组顺序后名称，sing-box 保持 gRPC groups 顺序。锚点：`tmp/codex/sparxie/lib/screens/proxies_screen.dart:53-65`、`tmp/codex/sparxie/core/src/clash/api/proxies/catalog.rs:45-95`、`tmp/codex/sparxie/core/src/surge/api/policies.rs:80-86`、`tmp/codex/sparxie/core/src/sing_box/api/proxies.rs:171-215`。
- 显示/测速设置：列数自适应或 1–4、节点排序、组图标、隐藏组、切换断连及模式、测试 URL、组/全局 URL 来源、组 API 开关、并发数、2/3/5/8/10 秒超时。锚点：`tmp/codex/sparxie/lib/widgets/proxies_settings_menu.dart:73-127`、`tmp/codex/sparxie/lib/widgets/proxies_settings_menu.dart:195-283`、`tmp/codex/sparxie/lib/widgets/proxies_settings_menu.dart:287-475`。
- 刷新/状态：AppBar 可手动刷新；目录默认每 3 秒轮询。共享错误条可与旧目录共存；首次加载没有 spinner。无组时显示空文本。锚点：`tmp/codex/sparxie/lib/screens/proxies_screen.dart:259-264`、`tmp/codex/sparxie/lib/screens/proxies_screen.dart:294-333`、`tmp/codex/sparxie/lib/screens/proxies_screen.dart:436-445`、`tmp/codex/sparxie/lib/session.dart:58-63`、`tmp/codex/sparxie/lib/session.dart:469-475`。

#### 4.3 连接

- 顶部数据：实时状态圆点、总上传/下载、活动/已关闭数量；用户可暂停/继续连接帧应用。活动页有“关闭所有”，已关闭页有“清空已关闭”。锚点：`tmp/codex/sparxie/lib/screens/connections_screen.dart:192-270`。
- 行可见数据：`进程或来源 → 主机`、相对建立时间、协议/网络、当前代理、累计上传/下载、非零时的上传/下载速度；每行有立即关闭按钮，点击行打开详情。锚点：`tmp/codex/sparxie/lib/widgets/connection_tile.dart:11-14`、`tmp/codex/sparxie/lib/widgets/connection_tile.dart:49-68`、`tmp/codex/sparxie/lib/widgets/connection_tile.dart:119-222`。
- 详情可见数据：主机、连接 ID、网络、连接类型、来源地址、目标地址、入站 IP/端口/名称、DNS 模式、嗅探主机、进程/路径、UID、规则类型/内容、反向显示的代理链、上传/下载、建立时间；Stash 额外显示逐连接日志。用户可在详情中关闭连接。锚点：`tmp/codex/sparxie/lib/widgets/connection_detail_sheet.dart:18-46`、`tmp/codex/sparxie/lib/widgets/connection_detail_sheet.dart:48-115`、`tmp/codex/sparxie/lib/widgets/connection_detail_sheet.dart:118-174`、`tmp/codex/sparxie/lib/screens/connections_screen.dart:179-189`。
- 后端模型还携带 `specialProxy`、`specialRules`、`remoteDestination`，但当前详情表没有渲染这些字段。锚点：`tmp/codex/sparxie/lib/session/connections.dart:142-145` 对比 `tmp/codex/sparxie/lib/widgets/connection_detail_sheet.dart:25-46`。
- 关闭操作：单条关闭先从当前窗口乐观移除；关闭全部和关闭来源组都要求确认；清空已关闭先清本地缓存。失败均用 SnackBar。锚点：`tmp/codex/sparxie/lib/screens/connections_screen.dart:109-174`、`tmp/codex/sparxie/lib/screens/connections_screen.dart:796-830`、`tmp/codex/sparxie/lib/session/connections.dart:771-822`。
- 活动/已关闭窗口：完整排序结果保留在 Rust，Dart 只缓存可视范围上下各 5 行；滚动自动拉取新窗口。Rust 各后端保留最多 500 条已关闭连接。锚点：`tmp/codex/sparxie/lib/session/connections.dart:287-310`、`tmp/codex/sparxie/lib/session/connections.dart:406-480`、`tmp/codex/sparxie/core/src/backend/types.rs:3`。
- 筛选：输入即时匹配 host、代理链、规则类型、规则内容、网络、进程名和进程路径。非分组列表不重建紧凑结果集，而是在原索引位置把不匹配行变成占位槽，顶部数量仍是总数。锚点：`tmp/codex/sparxie/lib/session/connections.dart:164-174`、`tmp/codex/sparxie/lib/screens/connections_screen.dart:313-325`、`tmp/codex/sparxie/lib/screens/connections_screen.dart:605-655`。
- 排序：时间、上传量、下载量、上传速度、下载速度、进程名，支持升/降序；选择会推送到 Rust，对完整列表排序。默认时间降序。锚点：`tmp/codex/sparxie/lib/screens/connections_screen.dart:80-107`、`tmp/codex/sparxie/lib/screens/connections_screen.dart:326-381`、`tmp/codex/sparxie/lib/app_prefs.dart:132-155`。
- 来源归类：用户可把活动连接按进程/来源分组，组头显示应用/进程、真实总数、聚合流量和速度；可按名称、数量、流量或速度排序。展开组只显示当前排序下最多 100 条成员。锚点：`tmp/codex/sparxie/lib/widgets/connections_settings_menu.dart:83-121`、`tmp/codex/sparxie/lib/widgets/connections_settings_menu.dart:228-277`、`tmp/codex/sparxie/lib/session/connections.dart:301-304`、`tmp/codex/sparxie/lib/screens/connections_screen.dart:736-911`。
- 进程图标/应用名：只对本机控制器启用；远端控制器不解析。iOS 和 Web 不支持，Android 用包名/PackageManager，桌面用进程路径。锚点：`tmp/codex/sparxie/lib/session.dart:175-190`、`tmp/codex/sparxie/lib/platform_capabilities.dart:1-5`、`tmp/codex/sparxie/lib/session/process_icons.dart:11-35`。
- 暂停语义：暂停时连接流仍工作，但 Dart 丢弃收到的帧，画面和 totals 保持旧值；继续后等待下一帧自然更新，没有待发布快照。锚点：`tmp/codex/sparxie/lib/session.dart:164-167`、`tmp/codex/sparxie/lib/session.dart:607-633`。
- 状态：零条时区分“暂无连接/暂无已关闭连接”；窗口未命中的行画骨架占位；共享会话错误在工具栏下显示。没有单独首次加载 spinner。锚点：`tmp/codex/sparxie/lib/screens/connections_screen.dart:417-469`、`tmp/codex/sparxie/lib/screens/connections_screen.dart:595-613`、`tmp/codex/sparxie/lib/screens/connections_screen.dart:720-733`。

#### 4.4 日志

- 可见数据：等级徽标、可选时间字符串、完整可选择消息文本；等级按 error/warning/debug/trace/info 使用不同语义色。锚点：`tmp/codex/sparxie/lib/screens/logs_screen.dart:258-336`。
- 等级：Clash/Surge 提供 `info/debug/warning/error/silent`，sing-box 额外提供 `trace`；切换等级会重启订阅并清空当前 Dart 镜像。切离 sing-box 时若当前为 trace，会自动降为 debug。锚点：`tmp/codex/sparxie/lib/screens/logs_screen.dart:24-25`、`tmp/codex/sparxie/lib/screens/logs_screen.dart:90-94`、`tmp/codex/sparxie/lib/screens/logs_screen.dart:121-127`、`tmp/codex/sparxie/lib/session.dart:242-249`、`tmp/codex/sparxie/lib/session.dart:396-398`、`tmp/codex/sparxie/lib/session.dart:452-460`。
- 过滤：本地按消息或等级大小写不敏感过滤，结果是紧凑列表；无源日志与无匹配日志有不同文案。锚点：`tmp/codex/sparxie/lib/screens/logs_screen.dart:58-64`、`tmp/codex/sparxie/lib/screens/logs_screen.dart:105-119`、`tmp/codex/sparxie/lib/screens/logs_screen.dart:212-237`。
- 暂停/继续：暂停只让 Dart `LogBuffer.addAll` 丢弃新批次；不会积累一个可在继续时发布的 pending 列表。锚点：`tmp/codex/sparxie/lib/screens/logs_screen.dart:96-103`、`tmp/codex/sparxie/lib/session/logs.dart:17-28`。
- 清空：清本地列表并调用 Rust 清该目标/等级缓存，流保持运行。锚点：`tmp/codex/sparxie/lib/session.dart:663-670`。
- 缓冲：Dart 最多 500 条；Clash 和 Surge Rust 环形缓存也是 500 条。用户滚离底部会停止自动跟随，并出现“回到底部”浮动按钮。锚点：`tmp/codex/sparxie/lib/session/logs.dart:7-28`、`tmp/codex/sparxie/core/src/clash/state/logs.rs:17-30`、`tmp/codex/sparxie/core/src/surge/state/logs.rs:119-124`、`tmp/codex/sparxie/lib/screens/logs_screen.dart:66-87`、`tmp/codex/sparxie/lib/screens/logs_screen.dart:244-253`。
- 状态：共享错误条、暂无日志、没有匹配日志；没有加载 spinner。锚点：`tmp/codex/sparxie/lib/screens/logs_screen.dart:183-223`。

#### 4.5 分流规则

- 可见数据：规则 payload（空时显示 `Match`）、规则类型、出站、额外参数；若 hit/miss 总数大于零，仅显示命中率百分比，不显示原始 hit/miss 数和规则 index。锚点：`tmp/codex/sparxie/lib/screens/rules_screen.dart:385-467`、`tmp/codex/sparxie/core/src/backend/types.rs:202-213`。
- 筛选：输入“规则 / 类型 / 出站”，200ms 防抖后让 Rust 在已缓存完整规则集上重算过滤索引；显示 `filtered/total`。锚点：`tmp/codex/sparxie/lib/screens/rules_screen.dart:24-43`、`tmp/codex/sparxie/lib/screens/rules_screen.dart:118-143`、`tmp/codex/sparxie/lib/screens/rules_screen.dart:293-304`。
- 分页/窗口：首次 `rulesLoad` 把完整规则集留在 Rust；Flutter 仅持有可视窗口，滚动按上下 5 行 overscan 换窗。无页码、无用户排序。锚点：`tmp/codex/sparxie/lib/screens/rules_screen.dart:9-14`、`tmp/codex/sparxie/lib/screens/rules_screen.dart:91-116`、`tmp/codex/sparxie/lib/screens/rules_screen.dart:145-230`。
- 规则开关：只有 `hasExtra` 的条目显示开关；操作先乐观切换，失败回滚并提示。Surge 解析器固定 `has_extra=false`，因此其规则页实际只读。锚点：`tmp/codex/sparxie/lib/screens/rules_screen.dart:233-273`、`tmp/codex/sparxie/lib/screens/rules_screen.dart:426-431`、`tmp/codex/sparxie/core/src/surge/state/rules.rs:109-163`。
- 刷新：AppBar 刷新和下拉刷新都重新抓取完整规则集。状态区分首次 loading、暂无规则、没有匹配规则和错误条。过滤失败及滚动窗口失败被静默忽略，保留当前画面。锚点：`tmp/codex/sparxie/lib/screens/rules_screen.dart:93-116`、`tmp/codex/sparxie/lib/screens/rules_screen.dart:199-224`、`tmp/codex/sparxie/lib/screens/rules_screen.dart:275-359`。

#### 4.6 外部资源 / provider

- 页面有两个区块：代理订阅与规则集。会话只对 Clash 类型显示入口；Surge/sing-box 后端分派虽有空目录实现，但 UI 不可达。锚点：`tmp/codex/sparxie/lib/screens/resources_screen.dart:39-69`、`tmp/codex/sparxie/lib/session.dart:390-394`、`tmp/codex/sparxie/core/src/backend/providers.rs:13-24`、`tmp/codex/sparxie/core/src/backend/providers.rs:56-67`。
- 代理 provider 可见数据：名称、vehicle type、节点数、相对更新时间、是否可更新；用户可单项更新、更新全部、刷新目录。锚点：`tmp/codex/sparxie/lib/screens/resources_screen.dart:92-116`、`tmp/codex/sparxie/lib/screens/resources_screen.dart:177-269`、`tmp/codex/sparxie/lib/screens/resources_screen.dart:473-531`。
- 规则 provider 可见数据：名称、vehicle type、behavior、format、规则数、相对更新时间、是否可更新；同样支持单项/全部更新和刷新。锚点：`tmp/codex/sparxie/lib/screens/resources_screen.dart:118-148`、`tmp/codex/sparxie/lib/screens/resources_screen.dart:299-394`、`tmp/codex/sparxie/lib/screens/resources_screen.dart:534-594`。
- “更新全部”逐项串行执行；每个单项更新后都会重新刷新整个对应目录。没有搜索、排序或分页。锚点：`tmp/codex/sparxie/lib/screens/resources_screen.dart:203-225`、`tmp/codex/sparxie/lib/screens/resources_screen.dart:325-347`。
- 状态：首次空目录加载显示 spinner；错误替换整个区块内容；成功空目录显示“暂无代理订阅/暂无规则集”。锚点：`tmp/codex/sparxie/lib/screens/resources_screen.dart:397-463`。

#### 4.7 核心配置

- 可见配置按后端返回字段动态出现：出站模式；日志级别；TUN；允许局域网；IPv6；TCP 并发；HTTP/SOCKS5/Mixed 端口。用户选择/开关/输入后单项保存，成功后重新抓取配置。锚点：`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:71-127`、`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:134-224`、`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:228-348`、`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:351-462`。
- 出站模式默认候选为 `rule/global/direct`；如果后端给出 `mode-options` 则使用后端列表，当前模式即使不在列表也插入。sing-box 不使用默认候选，只显示 gRPC 返回的 mode list。锚点：`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:515-553`。
- 卡片布局把出站模式抽为可直接点击的独立卡片；核心配置页本体会隐藏重复的模式区块。锚点：`tmp/codex/sparxie/lib/screens/core_config_screen.dart:12-37`、`tmp/codex/sparxie/lib/widgets/outbound_mode_card.dart:7-9`、`tmp/codex/sparxie/lib/widgets/outbound_mode_card.dart:103-165`。
- Surge 的核心配置页被 `_readOnly` 整页禁用，但卡片布局的独立出站模式卡没有该只读判断，仍可调用 Surge 模式 API。因此同一后端的可写能力取决于导航布局。锚点：`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:132-143`、`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:178-220`、`tmp/codex/sparxie/lib/widgets/outbound_mode_card.dart:78-97`、`tmp/codex/sparxie/core/src/surge/api.rs:62-75`。
- sing-box `configs` 只返回 clash mode 当前值和候选，其他通用开关/端口不出现；如果 mode list 为空，核心配置入口也不会通过能力探测显示。锚点：`tmp/codex/sparxie/core/src/sing_box/api.rs:27-58`。
- 状态：首次加载 spinner、内联错误；若请求结束后既无配置也无错误，页面主体为空白，没有专用空状态或手动刷新按钮。锚点：`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:59-88`、`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:147-223`。

#### 4.8 核心操作

- 普通 Mihomo（非 CMFA）可见：重载当前配置、更新 GeoData、重启核心、升级核心、清 DNS、清 FakeIP；重启和升级需要确认。锚点：`tmp/codex/sparxie/lib/screens/core_actions_screen.dart:118-191`、`tmp/codex/sparxie/core/src/clash/api/version.rs:36-50`。
- CMFA 被判定为无核心管理但有 Mihomo 缓存清理，因此只显示 DNS/FakeIP；Stash 不显示核心操作；Surge 只显示 DNS 清理；sing-box 不显示。能力组合来源：`tmp/codex/sparxie/lib/session.dart:383-399`、`tmp/codex/sparxie/lib/session.dart:480-499`。
- 每次只允许一个操作；运行时锁定所有行，行尾 spinner，完成后 SnackBar 显示成功或格式化错误。锚点：`tmp/codex/sparxie/lib/screens/core_actions_screen.dart:36-65`、`tmp/codex/sparxie/lib/screens/core_actions_screen.dart:212-237`。
- Surge Rust 适配器实际支持“重载当前配置”，但 `VersionInfo.supports_core_management=false`，所以 UI 不提供该操作；这是“API 存在但 UI 不可用”的明确差异。锚点：`tmp/codex/sparxie/core/src/surge/api.rs:31-41`、`tmp/codex/sparxie/core/src/surge/api.rs:102-108` 对比 `tmp/codex/sparxie/lib/screens/core_actions_screen.dart:101-119`。
- 无可用操作时页面显示“当前后端不支持核心操作”。锚点：`tmp/codex/sparxie/lib/screens/core_actions_screen.dart:192-200`。

#### 4.9 Tailscale

- 仅 sing-box：页面拒绝其他后端，订阅 Tailscale 状态流。可见 endpoint 状态、网络名、MagicDNS、认证状态、当前设备和当前出口节点。锚点：`tmp/codex/sparxie/lib/screens/tailscale_screen.dart:54-108`、`tmp/codex/sparxie/lib/screens/tailscale_screen.dart:284-362`。
- 认证操作：有 auth URL 时可显示二维码、调用外部应用打开、复制链接；打开失败会自动回退复制。二维码 sheet 同时显示最多两行截断 URL。锚点：`tmp/codex/sparxie/lib/screens/tailscale_screen.dart:140-158`、`tmp/codex/sparxie/lib/screens/tailscale_screen.dart:365-439`、`tmp/codex/sparxie/lib/screens/tailscale_screen.dart:441-489`。
- 设备列表按用户组展示：显示用户 display/login 名；peer 显示在线/离线、OS、DNS 名、Tailscale IP、是否出口/共享/过期、最后在线时间和收发流量。支持把具备资格的 peer 设为出口节点、清除出口节点、退出登录。锚点：`tmp/codex/sparxie/lib/screens/tailscale_screen.dart:492-637`、`tmp/codex/sparxie/lib/screens/tailscale_screen.dart:762-800`。
- 后端模型中的 `profilePicUrl`、`sshHostKeys`、原始 `keyExpiry` 和 `active` 当前没有直接可见字段；仅使用了 `expired` 等派生状态。锚点：`tmp/codex/sparxie/core/src/backend/tailscale.rs:24-50` 对比 `tmp/codex/sparxie/lib/screens/tailscale_screen.dart:492-637`。
- 状态：区分首次 loading、错误、无 endpoint；操作级失败用 SnackBar，各 endpoint/action 有独立 busy key。锚点：`tmp/codex/sparxie/lib/screens/tailscale_screen.dart:119-138`、`tmp/codex/sparxie/lib/screens/tailscale_screen.dart:237-280`。

#### 4.10 应用设置、缓存与字体

- 导航布局：卡片、标准、悬浮三选一，立即重建顶层导航并持久化。没有语言或外观选择；应用固定 `zh_CN`，同时提供 light/dark theme 让系统主题自动选择。锚点：`tmp/codex/sparxie/lib/screens/settings_screen.dart:288-339`、`tmp/codex/sparxie/lib/main.dart:224-253`。
- 字体：非 Web 平台可读取系统字体列表、搜索添加、按顺序设置主/备用字体、拖动重排、移除/清空，并导入 `ttf/otf/ttc/otc` 文件。修改即时写入偏好并重绘主题。锚点：`tmp/codex/sparxie/lib/screens/settings_screen.dart:293-336`、`tmp/codex/sparxie/lib/screens/settings_screen.dart:395-551`、`tmp/codex/sparxie/lib/screens/settings_screen.dart:586-705`。
- 在线资源 TLS：用户可允许代理组图标等在线资源跳过证书验证；明确不影响控制器连接本身。修改后同步通知 Rust。锚点：`tmp/codex/sparxie/lib/screens/settings_screen.dart:774-787`、`tmp/codex/sparxie/lib/main.dart:62-73`。
- 磁盘缓存：显示图标与进程信息总大小，用户点击“清空缓存”会清 Rust redb 三张表并清 Dart 进程图标/名称内存缓存。锚点：`tmp/codex/sparxie/lib/screens/settings_screen.dart:790-870`、`tmp/codex/sparxie/core/src/cache/db.rs:1-10`、`tmp/codex/sparxie/core/src/cache/db.rs:142-195`。
- 进程图标内存缓存上限：160 张解码图、512 个名称、512 个 miss；桌面磁盘图标 TTL 为 24 小时，并限制 5 个并发解析。锚点：`tmp/codex/sparxie/lib/session/process_icons.dart:16-21`、`tmp/codex/sparxie/lib/session/process_icons.dart:165-185`、`tmp/codex/sparxie/core/src/cache/process_icons.rs:18-25`。

### 5. 控制器管理

- 数据模型：控制器字段为 ID、名称、后端类型、base URL、secret、跳过 TLS 验证。首次无配置时自动创建 `本地内核 / http://127.0.0.1:9090 / Clash` 并设为当前。锚点：`tmp/codex/sparxie/lib/controller.dart:24-76`、`tmp/codex/sparxie/lib/controller.dart:88-101`。
- 列表可见数据：名称、后端类型、完整 `baseUrl`，secret 只显示“已设置密钥”；当前项有 check 图标。点击非当前项即可激活，菜单另有设为当前/编辑/删除。锚点：`tmp/codex/sparxie/lib/screens/settings_screen.dart:994-1049`。
- 用户操作：新增、编辑、激活、删除；不能删除唯一控制器。没有控制器连通性测试、复制、拖动排序或批量操作。删除当前控制器后固定回退列表第一项。锚点：`tmp/codex/sparxie/lib/screens/settings_screen.dart:898-990`、`tmp/codex/sparxie/lib/controller.dart:143-205`。
- 编辑字段：名称、Clash/Surge/sing-box 类型、连接方式、地址/路径、可选密钥、HTTPS/gRPC TLS 跳过验证。secret 输入为 `obscureText`。锚点：`tmp/codex/sparxie/lib/screens/settings_screen.dart:1287-1418`。
- 连接方式差异：Clash 可用 HTTP/HTTPS；Unix-like 主机可用 Unix IPC，Windows 可用 named pipe；Linux/macOS/Windows 还可用 Sparkle service auth 文件。Surge 只有 HTTP/HTTPS。sing-box 标签为 gRPC/gRPC TLS，只有 TCP/TLS。锚点：`tmp/codex/sparxie/lib/screens/settings_screen.dart:1075-1144`、`tmp/codex/sparxie/lib/screens/settings_screen.dart:1176-1184`、`tmp/codex/sparxie/lib/screens/settings_screen.dart:1254-1265`。
- 持久化：所有控制器、偏好和窗口状态写入同一个可读 `config.json`；控制器 `toJson` 把 secret 原文写入 `controllers.list`。UI 遮蔽输入不等于存储加密。锚点：`tmp/codex/sparxie/lib/config_store.dart:9-14`、`tmp/codex/sparxie/lib/config_store.dart:30-45`、`tmp/codex/sparxie/lib/controller.dart:60-67`、`tmp/codex/sparxie/lib/controller.dart:132-140`。
- 保存失败没有用户级事务错误：`JsonStore.flush` 捕获文件错误后仅 debugPrint，调用方仍继续通知 UI。锚点：`tmp/codex/sparxie/lib/config_store.dart:62-73`、`tmp/codex/sparxie/lib/controller.dart:143-204`。
- 激活/编辑当前控制器会触发共享会话完全重订阅：清零指标、清连接/日志/代理、重置能力，再启动流和探测；旧 Clash 目标会显式停止 Rust 流。锚点：`tmp/codex/sparxie/lib/session.dart:344-414`。
- 快速切换只存在于“概览”标题；卡片布局没有概览页，需从后端设置列表激活。锚点：`tmp/codex/sparxie/lib/screens/dashboard_screen.dart:109-116`、`tmp/codex/sparxie/lib/widgets/backend_switcher.dart:21-53`。

### 6. 筛选、排序、分页/窗口总表

| 数据面 | 筛选 | 排序 | 分页/缓存窗口 | 真实用户效果 | 证据 |
|---|---|---|---|---|---|
| 代理组 | Rust 侧匹配组名或节点名 | 成员：原序/名称/延迟；组序由后端适配器决定 | 每展开组动态窗口，最小 96、overscan 32 | 搜索会重新抓目录；无页码 | `tmp/codex/sparxie/lib/screens/proxies_screen.dart:53-65`、`tmp/codex/sparxie/lib/session/proxies.dart:223-225` |
| 连接 | Dart 行匹配；分组模式匹配组名/进程/路径/source IP | Rust 完整列表 6 个键升降序；分组另有 6 个键 | 可视上下 5 行；组成员最多 100；已关闭最多 500 | 非分组筛选留下空占位，计数不变 | `tmp/codex/sparxie/lib/screens/connections_screen.dart:313-381`、`tmp/codex/sparxie/lib/session/connections.dart:301-307` |
| 日志 | Dart 匹配消息/等级 | 保持到达顺序 | Dart 500，Clash/Surge Rust 500 | 紧凑过滤列表，支持跟随底部 | `tmp/codex/sparxie/lib/screens/logs_screen.dart:105-119`、`tmp/codex/sparxie/lib/session/logs.dart:10-28` |
| 规则 | Rust 缓存上 200ms 防抖过滤 | 无 UI 排序 | 可视窗口 overscan 5 | 显示过滤/总数，无页码 | `tmp/codex/sparxie/lib/screens/rules_screen.dart:24-43`、`tmp/codex/sparxie/lib/screens/rules_screen.dart:118-230` |
| Provider | 无 | 后端返回顺序 | 无 | 仅刷新/逐项更新 | `tmp/codex/sparxie/lib/screens/resources_screen.dart:177-225`、`tmp/codex/sparxie/lib/screens/resources_screen.dart:299-347` |
| Tailscale | 无 | 状态流返回顺序 | 无 | endpoint/user/peer 全部顺序渲染 | `tmp/codex/sparxie/lib/screens/tailscale_screen.dart:256-279`、`tmp/codex/sparxie/lib/screens/tailscale_screen.dart:346-357` |

### 7. 后端类型 UI 能力差异

#### 7.1 能力矩阵

| UI 能力 | 普通 Mihomo | CMFA（Clash 类型） | Stash（Clash 类型） | Surge | sing-box | 证据 |
|---|---|---|---|---|---|---|
| 流量 | WebSocket/状态流，当前+累计 | 同 Mihomo | Clash 兼容流 | 1 秒 REST 轮询 | gRPC status 流 | `tmp/codex/sparxie/core/src/backend/streams.rs:11-45` |
| 内存 | 显示 | 显示 | 不显示 | 不显示 | 显示，含 goroutine/入出连接统计 | `tmp/codex/sparxie/core/src/clash/api/version.rs:36-50`、`tmp/codex/sparxie/core/src/sing_box/api.rs:33-41` |
| 代理组浏览/选择 | 支持；LoadBalance 不可选 | 同 | 支持 | 支持 | 支持 | `tmp/codex/sparxie/core/src/backend/proxies.rs:71-112`、`tmp/codex/sparxie/core/src/backend/convert.rs:125-138` |
| 固定节点 UI | 后端 `fixed` 字段可显示/取消 | 同 | 取决兼容响应 | catalog 固定为空，UI 不会进入取消固定分支 | catalog 默认 fixed 为空 | `tmp/codex/sparxie/core/src/clash/api/proxies/catalog.rs:73-82`、`tmp/codex/sparxie/core/src/surge/api/policies.rs:67-77`、`tmp/codex/sparxie/core/src/sing_box/api/proxies.rs:202-214` |
| 隐藏组开关 | 生效 | 生效 | 取决兼容响应 | 生效 | 参数被忽略 | `tmp/codex/sparxie/core/src/clash/api/proxies/catalog.rs:53-64`、`tmp/codex/sparxie/core/src/surge/api/policies.rs:48-50`、`tmp/codex/sparxie/core/src/sing_box/api/proxies.rs:22-28` |
| 测速参数 | URL/timeout/concurrency 均参与 | 同 | UI 禁止组 API、走逐节点 | 原生组/批量 API，不完全使用 timeout/concurrency | 原生 URL-test，基本忽略 UI URL/timeout/concurrency | `tmp/codex/sparxie/core/src/backend/proxy_delay.rs:11-34`、`tmp/codex/sparxie/core/src/backend/proxy_delay.rs:77-104`、`tmp/codex/sparxie/lib/screens/proxies_screen.dart:156-180` |
| 连接列表/关闭单条/全部 | 支持 | 支持 | 支持 | 支持 | 支持 | `tmp/codex/sparxie/core/src/backend/connections.rs:21-37`、`tmp/codex/sparxie/core/src/backend/connections.rs:73-157` |
| 按链/按来源组关闭 | 支持 | 支持 | 取决兼容响应 | 支持 | 后端明确不支持，但 UI 仍显示入口 | `tmp/codex/sparxie/core/src/backend/connections.rs:39-70`、`tmp/codex/sparxie/core/src/sing_box/api.rs:98-104` |
| 连接详情日志 | 不显示 | 不显示 | 显示 | 不显示 | 不显示 | `tmp/codex/sparxie/lib/screens/connections_screen.dart:179-188` |
| 日志 trace 等级 | 无 | 无 | 无 | 无 | 有 | `tmp/codex/sparxie/lib/screens/logs_screen.dart:121-127` |
| 规则页 | 有；有 extra 时可禁用 | 有 | 有 | 有但只读 | 入口隐藏 | `tmp/codex/sparxie/lib/session.dart:393-395`、`tmp/codex/sparxie/core/src/backend/rules.rs:5-59` |
| 核心配置 | 完整动态字段 | 入口隐藏 | 可显示兼容配置 | 页面只读；卡片模式可改出站模式 | 有 mode list 时仅出站模式 | `tmp/codex/sparxie/core/src/clash/api/version.rs:39-49`、`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:132-143`、`tmp/codex/sparxie/core/src/sing_box/api.rs:27-58` |
| 核心管理操作 | 重载/Geo/重启/升级 | 无管理，仅 DNS/FakeIP | 无 | 仅 DNS | 无 | `tmp/codex/sparxie/lib/screens/core_actions_screen.dart:101-191`、`tmp/codex/sparxie/lib/session.dart:487-499` |
| 外部资源/provider | UI 显示 | UI 显示 | UI 显示，端点不兼容时会报错 | UI 隐藏 | UI 隐藏 | `tmp/codex/sparxie/lib/session.dart:390-394` |
| Tailscale | 无 | 无 | 无 | 无 | 状态、认证、出口节点、登出 | `tmp/codex/sparxie/core/src/backend/tailscale.rs:53-92` |
| 概览版本文字 | 显示 | 显示 | 显示 | 明确隐藏 | 显示 | `tmp/codex/sparxie/lib/screens/dashboard_screen.dart:101-137` |

#### 7.2 连接字段差异

- Clash/Mihomo 解析的详情字段最完整，包括 inbound IP/端口/名称、DNS mode、UID、process/path、special fields、sniff host、rule/payload、chains 和可选 connection log。锚点：`tmp/codex/sparxie/core/src/clash/state/connections/parse.rs:5-45`。
- Surge 将 URL/remoteAddress、policy、规则、进程、notes、累计与当前速度映射到统一模型；未提供的字段保持默认空值，因此详情表按条件省略。锚点：`tmp/codex/sparxie/core/src/surge/state/connections/parse.rs:20-87`。
- sing-box 提供 source/destination、domain、network/protocol、inbound、process、rule、chain、流量/速度和时间，但没有 Clash 的 inbound IP、DNS mode、逐连接日志等字段。锚点：`tmp/codex/sparxie/core/src/sing_box/state/connections/parse.rs:6-59`。

#### 7.3 明确的 UI/后端不对称

- sing-box 分组连接头仍显示“关闭该来源全部连接”，但调用会返回“不支持按分组关闭连接”。锚点：`tmp/codex/sparxie/lib/widgets/connection_group_header.dart:132-137`、`tmp/codex/sparxie/core/src/sing_box/api.rs:102-104`。
- sing-box 若用户把“切换节点时断开连接”设为“当前组”，选点后 fire-and-forget 的按链关闭同样不支持，且该 Future 没有附加错误 UI。锚点：`tmp/codex/sparxie/lib/screens/proxies_screen.dart:109-119`、`tmp/codex/sparxie/core/src/sing_box/api.rs:98-100`。
- Surge 核心配置的读取数据包含 mode、LAN、IPv6、日志级别和端口，但标准核心配置页全部只读；只有卡片布局的出站模式卡可写 mode。锚点：`tmp/codex/sparxie/core/src/surge/api/config.rs:5-29`、`tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:132-143`。
- Clash 外部资源入口按“类型”而非实际 provider 能力显示；Stash/CMFA 若接口不兼容，会进入页面后显示请求错误，而不是提前隐藏。锚点：`tmp/codex/sparxie/lib/session.dart:390-394`、`tmp/codex/sparxie/lib/screens/resources_screen.dart:177-200`。

### 8. 会话、状态、缓存与刷新机制

- 当前控制器唯一拥有一组 Dart 会话状态：traffic、memory、connections、logs、process icons、proxies、version、rule count、后端 flavor/capability、共享 error 和 `isStreaming`。锚点：`tmp/codex/sparxie/lib/session.dart:65-170`。
- 控制器切换会取消订阅、清零/清空所有可见数据和 capability，再并行启动 traffic、connections、logs、3 秒 proxy poll、version probe 和 rule count probe。不存在保留旧控制器内容的 stale 标记。锚点：`tmp/codex/sparxie/lib/session.dart:359-414`。
- 流错误采用 5/10/20/30 秒封顶的 Dart 重试；任何健康流事件会清除共享 stream error。代理目录/成员错误和流错误共用一个 `error` 值与单一 source 标记。锚点：`tmp/codex/sparxie/lib/session.dart:19-24`、`tmp/codex/sparxie/lib/session.dart:672-737`。
- `isStreaming` 只在 traffic 或 connections 收到数据时设为真，单个流后续失败不会显式把它改回假；只有完整重订阅时重置。锚点：`tmp/codex/sparxie/lib/session.dart:359-362`、`tmp/codex/sparxie/lib/session.dart:564-579`、`tmp/codex/sparxie/lib/session.dart:607-633`。
- 连接刷新间隔默认 1 秒，用户可选 500ms/1s/2s/5s/10s；变更会重启连接订阅。代理目录固定默认 3 秒轮询。锚点：`tmp/codex/sparxie/lib/app_prefs.dart:132-155`、`tmp/codex/sparxie/lib/widgets/connections_settings_menu.dart:195-219`、`tmp/codex/sparxie/lib/session.dart:192-202`。
- Surge 特殊节奏：traffic 每 1 秒轮询，logs 每 5 秒轮询；连接使用用户配置间隔。锚点：`tmp/codex/sparxie/core/src/backend/streams.rs:27-33`、`tmp/codex/sparxie/core/src/surge/state/logs.rs:85-100`。
- 规则完整集合留在 Rust 缓存；代理完整成员留在 Rust per-target catalog；Flutter 只持窗口。锚点：`tmp/codex/sparxie/lib/screens/rules_screen.dart:9-14`、`tmp/codex/sparxie/lib/session/proxies.dart:6-10`。
- 磁盘配置与缓存分离：`config.json` 保存控制器/偏好/窗口；`cache.redb` 保存远程图标、进程图标和进程名。便携桌面模式把两者放到可执行文件旁 `userdata`，否则使用平台标准 support/cache 目录。锚点：`tmp/codex/sparxie/lib/config_store.dart:9-14`、`tmp/codex/sparxie/lib/app_paths.dart:6-50`、`tmp/codex/sparxie/core/src/cache/db.rs:1-10`。

### 9. 错误、加载与空状态矩阵

| 页面 | Loading | Error | Empty / 无匹配 | 用户恢复路径 | 证据 |
|---|---|---|---|---|---|
| 概览 | 无，先显示零值 | 共享错误条 | 无专用空状态 | 自动重试/切控制器 | `tmp/codex/sparxie/lib/screens/dashboard_screen.dart:141-188` |
| 代理组 | 成员窗口有占位；目录无 spinner | 共享错误条 | 无组显示“暂无代理组”；源码中的“没有匹配的项”分支实际不可达，因为判断的仍是同一空 groups 列表 | 刷新、清过滤、自动 3s poll | `tmp/codex/sparxie/lib/screens/proxies_screen.dart:436-445` |
| 连接 | 行窗口占位，无首次 spinner | 共享错误条 | 活动/已关闭空文案；非分组筛选无明确“无匹配”，只留下空占位 | 自动重试、改筛选 | `tmp/codex/sparxie/lib/screens/connections_screen.dart:417-469`、`tmp/codex/sparxie/lib/screens/connections_screen.dart:605-655` |
| 日志 | 无 | 共享错误条 | 区分暂无日志/无匹配 | 自动重试、改等级/过滤 | `tmp/codex/sparxie/lib/screens/logs_screen.dart:183-223` |
| 规则 | 首次 spinner，窗口 miss 占位 | 本地错误条 | 区分暂无规则/无匹配 | AppBar/下拉刷新 | `tmp/codex/sparxie/lib/screens/rules_screen.dart:275-359` |
| Provider | 区块首次 spinner | 错误替换区块 | 暂无代理订阅/规则集 | 刷新 | `tmp/codex/sparxie/lib/screens/resources_screen.dart:397-463` |
| 核心配置 | 首次 spinner | 本地错误条 | 无配置时可能空白 | 切控制器；无刷新按钮 | `tmp/codex/sparxie/lib/widgets/basic_config_panel.dart:147-223` |
| 核心操作 | 行级 spinner | SnackBar | “当前后端不支持” | 再次点击 | `tmp/codex/sparxie/lib/screens/core_actions_screen.dart:192-237` |
| Tailscale | 首次 spinner | 状态错误盒/操作 SnackBar | 暂无 endpoint | 状态流重连依赖后端；无刷新按钮 | `tmp/codex/sparxie/lib/screens/tailscale_screen.dart:237-280` |
| 控制器设置 | 无 | 持久化错误不呈现 | 有空列表文案，但正常启动会自动建默认项 | 新增 | `tmp/codex/sparxie/lib/screens/settings_screen.dart:898-940`、`tmp/codex/sparxie/lib/controller.dart:88-101` |

- 通用 FFI 错误会转换成中文：无效 URL、正则、HTTP status/body、网络、JSON、其他；带当前后端名称。锚点：`tmp/codex/sparxie/lib/error_format.dart:6-30`。
- 流式页面共享单一错误值，因此一个流恢复可能清掉另一个仍有问题的 stream error；页面没有 endpoint 级 stale/partial 状态。锚点：`tmp/codex/sparxie/lib/session.dart:715-729`。

### 10. 平台差异

- Android/iOS 使用 edge-to-edge 系统栏；桌面/Web 不应用。锚点：`tmp/codex/sparxie/lib/main.dart:101-136`。
- 仅 Android/iOS 在 app resume 时强制重连 socket；桌面和 Web 不做。锚点：`tmp/codex/sparxie/lib/main.dart:275-307`。
- 桌面 Linux/macOS/Windows 保存窗口尺寸、位置、最大化和全屏；移动/Web 为 no-op。最小窗口 `380x600`，默认 `1100x720`。锚点：`tmp/codex/sparxie/lib/window_state.dart:10-45`、`tmp/codex/sparxie/lib/window_state.dart:55-87`。
- Web 隐藏字体设置；所有非 Web 平台可导入字体文件。锚点：`tmp/codex/sparxie/lib/screens/settings_screen.dart:288-336`。
- 进程身份：iOS/Web 完全禁用；Android 通过 Kotlin PackageManager；macOS/Linux/Windows 用桌面文件图标/进程路径。且只有本机控制器显示。锚点：`tmp/codex/sparxie/lib/platform_capabilities.dart:1-5`、`tmp/codex/sparxie/core/src/cache/process_icons.rs:1-5`。
- 控制器 IPC：Clash 在 Linux/macOS/Android 可用 Unix socket，在 Windows 可用 named pipe；Sparkle service 只在 Linux/macOS/Windows；iOS/Web 仅 TCP。锚点：`tmp/codex/sparxie/lib/screens/settings_screen.dart:1086-1122`。
- 桌面支持 `.portable` 标记的便携数据目录；移动/Web 使用平台目录。锚点：`tmp/codex/sparxie/lib/app_paths.dart:6-50`。
- Rust 库加载：iOS 使用进程内静态链接；Linux 优先加载可执行文件旁 `lib/libsparxie.so`；其他平台使用 FRB 默认加载。锚点：`tmp/codex/sparxie/lib/main.dart:78-99`。
- UI 语言固定简体中文，无语言切换；主题跟随系统 light/dark。锚点：`tmp/codex/sparxie/lib/main.dart:230-250`。

### 11. External references

- 按用户要求未联网、未读取远程文档或 GitHub 页面。
- 本地声明的应用版本为 `1.0.0+1`，Dart SDK 约束为 `^3.12.0`；关键 UI/bridge 依赖包括 `flutter_rust_bridge ^2.12.0`、`super_sliver_list ^0.4.1`、`sliver_tools ^0.2.12`、`window_manager ^0.5.1`、`url_launcher ^6.3.2`、`qr_flutter ^4.1.0`、`file_selector ^1.1.0`。锚点：`tmp/codex/sparxie/pubspec.yaml:19-47`。

### 12. Related specs

- `.trellis/tasks/07-17-sparxie-feature-parity/prd.md:3-34`：要求以真实数据源、状态转换、用户操作、筛选/排序/分页、错误/空状态建立 Sparxie → Mica 对齐证据。
- `.trellis/spec/frontend/workbench-ui-contract.md:7-45`：Mica 的固定 11 目的地、同窗交互、数据全可见、排序/暂停/最后数据保留和控制器事务目标；本清单应作为差距对照输入，而不是要求复制 Flutter 布局。
- `.trellis/spec/frontend/live-session-controller-contract.md:28-40`：Mica 的 generation、分 lane 刷新、暂停 pending、stale 数据和控制器事务契约；Sparxie 当前实现明显采用另一套“共享流 + 页面本地状态”语义。
- `.trellis/spec/backend/controller-data-contract.md:20-28`：Mica 要求按控制器原始顺序保留代理组；Sparxie Clash 适配器则明确用 `GLOBAL.all` 重排组，属于需要在后续对齐阶段区分的产品/数据语义差异。
- `.trellis/spec/guides/cross-layer-thinking-guide.md:21-50`：本研究按 Source → Rust adapter/cache → Dart session → Flutter view 追踪边界。

## Caveats / Not Found

- 上述 P0/P1 是后续 Mica 功能对齐与验收的排序建议，不是对 Mica 当前源码已经存在相同缺陷的判断；本文件只审计 Sparxie 参考仓库，并用现有 Mica specs 限定不可照搬的语义。
- 所有 `file:line` 锚点基于 2026-07-17 工作区内的本地快照。由于按要求未执行 git 操作，无法提供稳定 commit permalink；参考仓库后续改动可能使行号漂移。
- “未发现 UI”仅表示在已审计的 Flutter/Dart 可达页面、会话状态与 Rust 后端分派中没有找到用户入口，不证明上游 controller/core 不存在相应协议能力，也不证明隐藏或未装配代码绝对不存在。
- 能力矩阵描述的是源码门控和已实现动作的上限。实际用户可见字段、按钮成功率和错误文案仍可能随 controller 版本、version probe、权限及响应内容变化；静态审计不能替代逐后端运行时验收。
- 本次是静态源码审计；未构建 Flutter、未运行 widget test、未启动真实 core/controller，也未验证任何端点的运行时响应。
- 未执行任何 git 操作，因此没有记录 `tmp/codex/sparxie` 快照对应的 commit/hash；本地 `pubspec.yaml` 只能证明声明版本，不能证明上游发布时间或最新状态。
- 运行时能力依赖 version probe。探测失败时核心配置、核心操作、内存、Tailscale 等入口会保持隐藏，即使后端理论上支持；源码注释明确把失败视为非关键并等待未来 reconnect。锚点：`tmp/codex/sparxie/lib/session.dart:478-502`。
- `BackendType.clash` 包含 Mihomo、CMFA、Stash 和 Unknown，不能把“Clash”列当作单一能力。外部资源和规则的门控又部分只看枚举类型，不完全看 probe，故“入口显示”与“端点可用”可能分离。
- 代理无匹配空状态实现有逻辑缺口：`_groups.isEmpty` 时再次检查同一 `session.proxies.groups.isEmpty`，所以“没有匹配的项”文案不可达。锚点：`tmp/codex/sparxie/lib/screens/proxies_screen.dart:436-445`。
- 非分组连接筛选并不压缩结果，也不显示“无匹配”；它保留总 itemCount 并把未命中行变成占位块。锚点：`tmp/codex/sparxie/lib/screens/connections_screen.dart:605-655`。
- sing-box UI 暴露按组/按链关闭入口，但后端明确返回 unsupported；选点后的 fire-and-forget 按链关闭没有错误处理。锚点：`tmp/codex/sparxie/core/src/sing_box/api.rs:98-104`、`tmp/codex/sparxie/lib/screens/proxies_screen.dart:109-119`。
- Surge 的“核心配置”写能力随布局不同：标准页面只读，卡片模式出站模式可写；Surge 重载当前配置的后端 API 没有对应 UI 操作。
- 多处业务文本使用 `TextOverflow.ellipsis`（控制器地址、策略/节点名、provider、Tailscale URL/设备等）；详情页只有连接字段使用 `SelectableText`。因此“字段存在于模型”不等于“主列表完整可见”。
- 控制器 secret 在编辑 UI 中遮蔽，但明文保存在 `config.json`；存储失败被吞掉且无用户错误状态。这是后续 Mica 安全/事务对照时的关键差异，不应照搬。
- 未发现以下 UI：控制器连通性测试、控制器手动排序、全局手动刷新、全局业务数据暂停、导出/诊断、主题/语言选择、provider 搜索/排序、规则排序、显式页码、连接模型中 `specialProxy/specialRules/remoteDestination` 的显示、Tailscale profile picture/SSH keys 的显示。
