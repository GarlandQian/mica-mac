# Spec 更新草稿 — Phase TD(科技感·强制深底设计语言)

> **状态:待落地。** 真机终检全绿后,把下面的编辑机械应用到两份正式文档,再进 Phase 3.4 收尾。若真机发现问题(如 grouped Form 透出浅色矩形需补 `neutralFill`),先按反馈调整实现,再据最终实现措辞落地本草稿。
>
> 落地目标:
> 1. `docs/UI_GUIDELINES.md`
> 2. `.trellis/spec/frontend/workbench-ui-contract.md`
>
> **verifier 无关**:`verify-real-controller-source.mjs` 只断言源码,不读这两份文档;更新它们是让契约描述与 TD 后的实现一致,供人与 agent 阅读。

---

## 背景:TD 阶段改变了什么

Round 6 "数据仪表盘·科技感" 给工作台**内容区**引入了一套独立于 `MicaStyle`(跟随系统外观)的**强制深底**视觉语言,落在新文件 `Sources/Mica/App/MicaDashboardStyle.swift`:

- **`MicaDashboard`**:固定 sRGB 令牌(**非** `dynamicProvider`),内容区专用。含强制深底色板(`pageBackdrop`/card 填充/`hairline`/`topHighlight`)+ 固定亮色信号令牌(`accent`/`signalViolet`/`signalCyan`/`signalMint`/`signalAmber`/`signalRed`,语义同 `MicaStyle` 但恒为亮变体,深底上不会被解析成看不见的暗变体)。
- **`micaDashboardSurface()`**:给可滚动内容区套 `pageBackdrop` 背景 + `\.environment(\.colorScheme, .dark)`,使系统 `.primary`/`.secondary` 与嵌入控件在深底上正确解析,不受用户系统外观影响。
- **`MicaGlowCard`**:自发光卡片 —— 渐变填充 + 顶部内高光 hairline + 边缘发光渐变描边,**全静态绘制,零 `.blur`/`.shadow`**,滚动开销等同平面矩形。
- **原生 `Table`/`List`/`Form` 用 `.scrollContentBackground(.hidden)`** 让深底透出系统 chrome。
- **侧栏例外**:侧栏是 `NavigationSplitView` 导航层,**保持原生跟随系统外观**,不套强制深底(浅色系统下浅、深色系统下深),与深色内容区形成"导航外壳 + 数据舞台"的分工。这是 macOS 专业工具(Xcode/Instruments/系统设置)的标准范式。

覆盖页:概览(TD2)、策略组折叠列表(TD3)、连接/规则/来源/日志表格(TD4)、设置/诊断/编辑器表单(TD5)。侧栏(TD5)刻意不动。

---

## 文档 1:`docs/UI_GUIDELINES.md`

### 编辑 1-A —— `## Visual System` 段,第 33 行

**替换前:**

```
Native Liquid Glass/material belongs to windows, sidebars, toolbars, compact actions, and a small number of interactive selectors. Business-data tables, policy members, logs, long text, and inspectors use semantic system backgrounds/separators; do not nest cards, use decorative gradients/orbs, or apply glass per row.
```

**替换后:**

```
Native Liquid Glass/material belongs to windows, sidebars, toolbars, compact actions, and a small number of interactive selectors. The sidebar stays native and follows the system light/dark appearance — it is the navigation shell, not a dashboard content region, so it never takes the forced-dark surface. Business-data tables, policy members, logs, long text, and inspectors remain high-readability content; do not nest cards or apply glass per row.

The workbench **content region** (Overview, Proxies, Connections, Logs, Rules, Sources, Configuration, Actions, Diagnostics, Settings, and the controller editor) renders on a forced-dark tech-dashboard surface via `micaDashboardSurface()`, regardless of the system appearance. Its tokens come from `MicaDashboard` (fixed sRGB values, not the appearance-adaptive `MicaStyle` `dynamicProvider` colors): a deep near-black backdrop plus fixed bright signal tokens (`accent`/`signalViolet`/`signalCyan`/`signalMint`/`signalAmber`/`signalRed`) that stay legible on dark. Semantic meaning is unchanged from `MicaStyle`. On the forced-dark surface, use `MicaDashboard.*` for any explicit color; never `MicaStyle.signal*` (which resolves to the invisible dark variant under a light system appearance). Native `Table`/`List`/`Form` in the content region use `.scrollContentBackground(.hidden)` so the backdrop shows through system chrome.

The card "glow" is **painted, never blurred**: every dashboard surface is a static gradient fill + gradient stroke + hairline top highlight. There is no `.blur` and no `.shadow` anywhere in `MicaDashboardStyle.swift` or its call sites, so a screen full of glow cards composites as cheaply as flat rectangles and scrolls without per-frame GPU cost. These gradients are a deliberate, structural part of the design system — not the decorative gradients/orbs that landing-page slop uses.
```

### 编辑 1-B —— `## Visual System` 段,第 35 行(dashboardCard 描述)

**替换前:**

```
The overview dashboard is the one place that groups content into cards: KPI tiles, the throughput chart, insight modules, inventory, and endpoint health each sit in a flat `dashboardCard` (system `.regularMaterial` fill + soft separator border). These cards are **material, not glass** — they never use `.glassEffect`/`MicaGlassSelectionSurface`, and they do not nest (a card holds a chart or text rows, never another card). Reduce Transparency falls the material back to an opaque control background. Card titles pair a semantic-color SF Symbol with the localized label; metric values use one shared numeric scale (no per-block font drift).
```

**替换后:**

```
The overview dashboard groups content into cards: KPI tiles, the throughput chart, insight modules, inventory, and endpoint health each sit in a `MicaGlowCard` (a painted gradient fill + top inner-highlight hairline + edge-glow gradient stroke). A tint plus higher `glowIntensity` marks the focused/expanded element for hierarchy. These cards are **painted gradient, not glass** — they never use `.glassEffect`/`MicaGlassSelectionSurface`, carry no `.blur`/`.shadow`, and do not nest (a card holds a chart or text rows, never another card). Card titles pair a fixed-bright semantic-color SF Symbol with the localized label; metric values use one shared numeric scale (no per-block font drift). Full-width command strips and inspector/empty panes use the flat `MicaDashboard.neutralFill` dark gradient instead of a glow card, so their dividers stay full-bleed.
```

### 编辑 1-C —— `## Charts And Accessibility` 段末尾追加一条(第 53 行后)

**追加:**

```
- The content-region surface is pinned to a dark color scheme, so any embedded native control (Picker, Toggle, SecureField, table sort headers, grouped Form rows) resolves as its dark-mode variant; the sidebar and window chrome continue to follow the system appearance. Do not hardcode light-only colors into content-region cells — let the pinned scheme and `MicaDashboard` tokens drive legibility.
```

---

## 文档 2:`.trellis/spec/frontend/workbench-ui-contract.md`

### 编辑 2-A —— `## Visual Hierarchy` 段,第 17 行

**替换前:**

```
- Native windows, sidebars, toolbars, and standard controls provide the base Liquid Glass/material hierarchy. Do not add an opaque navigation background, custom top operation strip, gradients, or repeated card borders over them.
```

**替换后:**

```
- Native windows, the sidebar, toolbars, and standard controls provide the base Liquid Glass/material hierarchy and follow the system light/dark appearance. The sidebar is the navigation shell (a `NavigationSplitView` nav layer), not a dashboard content region, so it never takes the forced-dark surface. Do not add a custom top operation strip or a bespoke navigation background over the native chrome.
- The workbench content region renders on a forced-dark tech-dashboard surface via `micaDashboardSurface()`, independent of the system appearance. Its fixed-value tokens live in `MicaDashboard` (deep backdrop + fixed bright signal tokens), never the appearance-adaptive `MicaStyle` `dynamicProvider` colors. Explicit colors on this surface use `MicaDashboard.*`; `MicaStyle.signal*` is prohibited there because it resolves to an invisible dark variant under a light system appearance. Native `Table`/`List`/`Form` use `.scrollContentBackground(.hidden)` so the backdrop shows through.
- Card glow is painted, never blurred: `MicaGlowCard` and every surface in `MicaDashboardStyle.swift` are static gradient fill + gradient stroke + hairline highlight, with no `.blur`/`.shadow` anywhere (a performance invariant — glow cards must composite as cheaply as flat rectangles). Reintroducing `.blur`/`.shadow` to these primitives is prohibited.
```

### 编辑 2-B —— `## Visual Hierarchy` 段,第 20 行(dashboardCard 描述)

**替换前:**

```
- The Overview destination is the one dashboard that groups content into flat `dashboardCard` blocks (system `.regularMaterial` + soft separator border): a KPI tile row, the throughput chart, the three insight modules, inventory, and endpoint health. These cards are material, not glass — never `.glassEffect`/`MicaGlassSelectionSurface` — and never nest. Card titles use semantic-color SF Symbols; metric values share one numeric scale.
```

**替换后:**

```
- The Overview destination groups content into `MicaGlowCard` blocks (painted gradient fill + top inner-highlight hairline + edge-glow stroke): a KPI tile row, the throughput chart, the three insight modules, inventory, and endpoint health. A tint plus higher `glowIntensity` marks the focused/expanded element. These cards are painted gradient, not glass — never `.glassEffect`/`MicaGlassSelectionSurface`, no `.blur`/`.shadow` — and never nest. Full-width command strips and inspector/empty panes use the flat `MicaDashboard.neutralFill` gradient instead of a glow card so their dividers stay full-bleed. Card titles use fixed-bright semantic-color SF Symbols; metric values share one numeric scale.
```

### 编辑 2-C —— `## Visual Hierarchy` 段,第 21 行(调色板)

**替换前:**

```
- Rose Pine Dawn/Main remains the semantic tint and opaque-fallback palette: purple for selection/focus, blue/green for healthy state, cyan for information/live state, yellow for warnings, and red for failures/danger. Window and content bases use system semantic colors/materials.
```

**替换后:**

```
- Rose Pine Dawn/Main remains the semantic tint palette with unchanged meaning across both token sets: purple for selection/focus, blue/green for healthy state, cyan for information/live state, yellow for warnings, and red for failures/danger. `MicaStyle` holds the appearance-adaptive variants used by the native sidebar/window chrome; `MicaDashboard` holds the fixed bright variants used on the forced-dark content surface. Do not invent a third palette.
```

### 编辑 2-D —— `## Validation` 段,视觉检查条(第 40 行)补充

**替换前:**

```
- Visual checks cover normal/reduced transparency, reduced motion, VoiceOver, keyboard navigation, long business text, English/Chinese, light/dark/system appearance, and all font scales.
```

**替换后:**

```
- Visual checks cover normal/reduced transparency, reduced motion, VoiceOver, keyboard navigation, long business text, English/Chinese, light/dark/system appearance, and all font scales. Because the content region is forced-dark while the sidebar/chrome follow the system, both light and dark system appearances must be walked to confirm the two surfaces sit together without clashing, and scrolling must stay smooth (the painted-glow, no-blur/shadow invariant exists to protect this — a real-device scroll pass is the only confirmation).
```

---

## 落地后

- 两份文档改完 → 进 Phase 3.4 收尾提交(docs commit)。
- 更新 journal(Session 记录 TD 阶段)。
- `task.py archive`(status→completed 并归档)。
