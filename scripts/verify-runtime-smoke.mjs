import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const executable = process.argv[2] ?? path.join(root, ".build", "debug", "Mica");
const bundleID = "dev.mica.mica";
const preferenceKeys = ["appLanguage", "appAppearance", "appFontScale"];

const requiredWorkbenchSurfaces = {
  settings: ["workbench.settings", "settings.language", "settings.controller_endpoint"],
  sidebar: ["sidebar.controllers", "sidebar.add_controller", "navigation.overview", "sidebar.group_controller_management"],
  toolbar: ["action.test", "action.refresh", "live.pause", "live.resume", "sidebar.edit"],
  overview: ["workspace.overview", "overview.traffic_summary", "overview.current_data", "overview.endpoint_status", "overview.connecting_title"],
  controllers: ["sidebar.controllers", "controllers.controller", "dashboard.col_status", "controllers.actions", "controllers.use", "controllers.search_prompt"],
  policyGroups: ["dashboard.routing_modules_header", "routing.group_catalog", "routing.no_inspector", "routing.test_group", "routing.filter_nodes", "routing.members_filtered_empty"],
  connections: ["dashboard.tab_connections", "traffic.connection_host", "traffic.connection_process_path", "traffic.inbound_address", "traffic.connection_uid", "dashboard.col_id", "dashboard.no_matching_connections"],
  rules: ["dashboard.tab_rules", "dashboard.col_payload", "dashboard.col_proxy"],
  sources: ["dashboard.tab_providers", "traffic.provider_kind", "dashboard.col_vehicle", "dashboard.no_matching_sources", "traffic.sources_empty_message"],
  logs: ["dashboard.tab_logs", "traffic.log_payload", "traffic.follow_bottom", "traffic.jump_to_newest", "dashboard.no_logs_yet", "dashboard.no_logs_yet_message", "dashboard.no_matching_logs", "traffic.empty_filtered"],
  coreConfig: ["workbench.configuration", "dashboard.mode", "overview.config_tun"],
  coreActions: ["workbench.actions", "diagnostics.operation_dns_flush", "diagnostics.operation_core_restart"],
  diagnostics: ["workspace.diagnostics", "diagnostics.endpoint_checks", "command.show_data_availability"],
};

const languageExpectations = {
  en: {
    resolvedLanguageCode: "en",
    localeIdentifier: "en",
    localizedSamples: {
      "settings.language": "Language",
      "settings.appearance_system": "Follow System",
      "settings.font_scale_extra_large": "Extra Large",
      "navigation.overview": "Overview",
      "navigation.proxies": "Proxies",
      "navigation.activity": "Activity",
      "navigation.resources": "Rules & Sources",
      "navigation.system": "System",
    },
    menuSamples: {
      "navigation.view_menu": "View",
      "controller.command_menu": "Controller",
      "command.menu_new_controller": "New Controller...",
      "command.menu_test_connection": "Test Connection",
      "command.menu_refresh_data": "Refresh Data",
      "command.menu_copy_diagnostics_report": "Copy Diagnostics Report",
    },
    helpSamples: {
      "settings.help_language": "Choose the language used by Mica windows and exported reports.",
      "settings.help_global_group_visibility": "Show the GLOBAL policy group only in Global mode, or always. When shown it appears at the end.",
      "sidebar.help_create_profile": "Create a local controller profile",
      "dashboard.help_test_controller": "Probe the selected controller without exposing its secret.",
    },
    accessibilitySamples: {
      "settings.acc_font_scale": "Interface text size",
      "sidebar.acc_add_router": "Add controller",
      "action.test": "Test",
    },
    workspaceSamples: {
      overview: "Overview",
      proxies: "Proxies",
      connections: "Connections",
      logs: "Logs",
      rules: "Rules",
      sources: "Sources",
      controllers: "Controllers",
      configuration: "Configuration",
      actions: "Actions",
      diagnostics: "Diagnostics",
      settings: "Settings",
    },
    surfaceSamples: {
      settings: { "settings.language": "Language" },
      sidebar: { "sidebar.group_controller_management": "Controller Management" },
      toolbar: { "action.test": "Test", "live.pause": "Pause Presentation" },
      overview: { "overview.traffic_summary": "Traffic overview", "overview.current_data": "Controller data", "overview.connecting_title": "Connecting to Controller" },
      controllers: { "controllers.controller": "Controller", "controllers.use": "Use" },
      policyGroups: {
        "routing.group_catalog": "Policy Groups",
        "routing.no_inspector": "No policy group selected",
        "routing.filter_nodes": "Filter Nodes",
        "routing.members_filtered_empty": "No nodes match the current filter.",
      },
      connections: {
        "traffic.connection_host": "Host",
        "traffic.connection_process_path": "Process path",
        "traffic.inbound_address": "Inbound address",
        "traffic.connection_uid": "UID",
        "dashboard.no_matching_connections": "No Matching Connections",
      },
      rules: { "dashboard.col_payload": "PAYLOAD" },
      sources: {
        "traffic.provider_kind": "Kind",
        "dashboard.no_matching_sources": "No Matching Sources",
        "traffic.sources_empty_message": "The controller did not report sources for this category.",
      },
      logs: {
        "traffic.log_payload": "Log message",
        "traffic.jump_to_newest": "Jump to Newest",
        "dashboard.no_logs_yet": "No Logs Yet",
        "dashboard.no_logs_yet_message": "Log events will appear here when the controller reports them.",
        "dashboard.no_matching_logs": "No Matching Logs",
        "traffic.empty_filtered": "No items match the current filters.",
      },
      coreConfig: { "dashboard.mode": "Mode" },
      coreActions: { "diagnostics.operation_dns_flush": "DNS Flush" },
      diagnostics: { "diagnostics.endpoint_checks": "Endpoint checks" },
    },
  },
  "zh-Hans": {
    resolvedLanguageCode: "zh-Hans",
    localeIdentifier: "zh-Hans",
    localizedSamples: {
      "settings.language": "语言",
      "settings.appearance_system": "跟随系统",
      "settings.font_scale_extra_large": "超大",
      "navigation.overview": "概览",
      "navigation.proxies": "代理",
      "navigation.activity": "活动",
      "navigation.resources": "规则与来源",
      "navigation.system": "系统",
    },
    menuSamples: {
      "navigation.view_menu": "视图",
      "controller.command_menu": "控制器",
      "command.menu_new_controller": "新增控制器...",
      "command.menu_test_connection": "测试连接",
      "command.menu_refresh_data": "刷新数据",
      "command.menu_copy_diagnostics_report": "复制诊断报告",
    },
    helpSamples: {
      "settings.help_language": "选择 Mica 窗口和导出报告的显示语言。",
      "settings.help_global_group_visibility": "仅在 Global 模式显示 GLOBAL 策略组，或始终显示。显示时置于末尾。",
      "sidebar.help_create_profile": "创建本地控制器配置",
      "dashboard.help_test_controller": "探测所选控制器，不暴露密钥。",
    },
    accessibilitySamples: {
      "settings.acc_font_scale": "界面文字大小",
      "sidebar.acc_add_router": "添加控制器",
      "action.test": "测试",
    },
    workspaceSamples: {
      overview: "概览",
      proxies: "代理",
      connections: "连接",
      logs: "日志",
      rules: "规则",
      sources: "来源",
      controllers: "控制器",
      configuration: "配置",
      actions: "操作",
      diagnostics: "诊断",
      settings: "设置",
    },
    surfaceSamples: {
      settings: { "settings.language": "语言" },
      sidebar: { "sidebar.group_controller_management": "控制器管理" },
      toolbar: { "action.test": "测试", "live.pause": "暂停呈现" },
      overview: { "overview.traffic_summary": "流量概览", "overview.current_data": "控制器数据", "overview.connecting_title": "正在连接控制器" },
      controllers: { "controllers.controller": "控制器", "controllers.use": "使用" },
      policyGroups: {
        "routing.group_catalog": "策略组",
        "routing.no_inspector": "未选择策略组",
        "routing.filter_nodes": "过滤节点",
        "routing.members_filtered_empty": "没有符合当前过滤条件的节点。",
      },
      connections: {
        "traffic.connection_host": "主机",
        "traffic.connection_process_path": "进程路径",
        "traffic.inbound_address": "入站地址",
        "traffic.connection_uid": "用户 ID",
        "dashboard.no_matching_connections": "无匹配连接",
      },
      rules: { "dashboard.col_payload": "载荷" },
      sources: {
        "traffic.provider_kind": "类别",
        "dashboard.no_matching_sources": "没有匹配的来源",
        "traffic.sources_empty_message": "控制器未上报当前类别的来源。",
      },
      logs: {
        "traffic.log_payload": "日志内容",
        "traffic.jump_to_newest": "跳到最新日志",
        "dashboard.no_logs_yet": "暂无日志",
        "dashboard.no_logs_yet_message": "控制器上报日志后会显示在这里。",
        "dashboard.no_matching_logs": "没有匹配的日志",
        "traffic.empty_filtered": "没有符合当前筛选条件的内容。",
      },
      coreConfig: { "dashboard.mode": "模式" },
      coreActions: { "diagnostics.operation_dns_flush": "DNS 刷新" },
      diagnostics: { "diagnostics.endpoint_checks": "端点检测" },
    },
  },
};

const appearanceExpectations = {
  system: ["system", "system", "system", true],
  light: ["light", "NSAppearanceNameAqua", "NSAppearanceNameAqua", false],
  dark: ["dark", "NSAppearanceNameDarkAqua", "NSAppearanceNameDarkAqua", false],
};

const fontScaleExpectations = {
  standard: ["small", "small", 0.92],
  comfortable: ["large", "regular", 1],
  large: ["xLarge", "large", 1.16],
  extraLarge: ["xxLarge", "large", 1.32],
};

const testCases = [
  { name: "zh-dark-extra-large", language: "zh-Hans", appearance: "dark", fontScale: "extraLarge" },
  { name: "en-light-standard", language: "en", appearance: "light", fontScale: "standard" },
  { name: "en-dark-large", language: "en", appearance: "dark", fontScale: "large" },
  { name: "zh-system-comfortable", language: "zh-Hans", appearance: "system", fontScale: "comfortable" },
];

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function readDefault(key) {
  const result = spawnSync("defaults", ["read", bundleID, key], { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : null;
}

function readPreferenceSnapshot() {
  return Object.fromEntries(preferenceKeys.map((key) => [key, readDefault(key)]));
}

function runSmokeCase(testCase) {
  const result = spawnSync(executable, [
    "-appLanguage", testCase.language,
    "-appAppearance", testCase.appearance,
    "-appFontScale", testCase.fontScale,
    "-micaRuntimeSmokeStdout",
  ], { encoding: "utf8" });

  assert(
    result.status === 0,
    `${testCase.name} smoke failed with status ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`
  );
  return JSON.parse(result.stdout);
}

function assertFields(actual, expected, context) {
  for (const [key, value] of Object.entries(expected)) {
    assert(actual?.[key] === value, `${context}: ${key} resolved as ${actual?.[key]}`);
  }
}

function assertWorkbenchSurfaceContract(surfaceSamples, context) {
  const actualNames = Object.keys(surfaceSamples ?? {}).sort();
  const expectedNames = Object.keys(requiredWorkbenchSurfaces).sort();
  assert(
    JSON.stringify(actualNames) === JSON.stringify(expectedNames),
    `${context}: missing or legacy surfaces: ${actualNames.join(", ")}`
  );

  for (const [surfaceName, keys] of Object.entries(requiredWorkbenchSurfaces)) {
    const surface = surfaceSamples?.[surfaceName];
    assert(surface, `${context}: missing ${surfaceName} surface`);
    for (const key of keys) {
      const value = surface[key];
      assert(typeof value === "string" && value.length > 0, `${context}: missing ${surfaceName}.${key}`);
      assert(value !== key, `${context}: ${surfaceName}.${key} did not localize`);
    }
  }
}

function assertLanguageProjection(actual, expected, context) {
  assert(actual.resolvedLanguageCode === expected.resolvedLanguageCode, `${context}: language did not resolve`);
  if (actual.localeIdentifier !== undefined) {
    assert(actual.localeIdentifier === expected.localeIdentifier, `${context}: locale did not resolve`);
  }

  for (const section of ["localizedSamples", "menuSamples", "helpSamples", "accessibilitySamples", "workspaceSamples"]) {
    assertFields(actual[section], expected[section], `${context} ${section}`);
  }
  for (const [surface, samples] of Object.entries(expected.surfaceSamples)) {
    assertFields(actual.surfaceSamples?.[surface], samples, `${context} ${surface}`);
  }
  assertWorkbenchSurfaceContract(actual.surfaceSamples, context);
}

function assertAppearance(actual, rawValue, context) {
  const [colorScheme, nsAppearanceName, appliedNSAppAppearanceName, followsSystem] = appearanceExpectations[rawValue];
  assertFields(actual, { rawValue, colorScheme, nsAppearanceName, appliedNSAppAppearanceName, followsSystem }, context);
}

function assertFontScale(actual, rawValue, context) {
  const [dynamicTypeSize, controlSize, multiplier] = fontScaleExpectations[rawValue];
  assertFields(actual, { rawValue, dynamicTypeSize, controlSize, multiplier }, context);
}

function assertPreferenceTransitions(transitions, context) {
  for (const [language, expected] of Object.entries(languageExpectations)) {
    assertLanguageProjection(transitions.languages?.[language], expected, `${context} ${language} transition`);
  }
  for (const appearance of Object.keys(appearanceExpectations)) {
    assertAppearance(transitions.appearances?.[appearance], appearance, `${context} ${appearance} transition`);
  }
  for (const fontScale of Object.keys(fontScaleExpectations)) {
    assertFontScale(transitions.fontScales?.[fontScale], fontScale, `${context} ${fontScale} transition`);
  }
}

function assertSmokePayload(payload, testCase) {
  const context = testCase.name;
  assert(payload.probe === "mica-runtime-smoke", `${context}: unexpected probe id`);
  assert(payload.language.rawValue === testCase.language, `${context}: language override did not apply`);

  assertLanguageProjection({
    resolvedLanguageCode: payload.language.resolvedLanguageCode,
    localizedSamples: payload.localizedSamples,
    menuSamples: payload.menuSamples,
    helpSamples: payload.helpSamples,
    accessibilitySamples: payload.accessibilitySamples,
    workspaceSamples: payload.workspaceSamples,
    surfaceSamples: payload.surfaceSamples,
  }, languageExpectations[testCase.language], context);
  assertAppearance(payload.appearance, testCase.appearance, `${context} appearance`);
  assertFontScale(payload.fontScale, testCase.fontScale, `${context} font scale`);
  assertPreferenceTransitions(payload.preferenceTransitions, context);

  assert(payload.privacy.activeUIFullControllerData === true, `${context}: active UI must stay full-visible`);
  assert(payload.privacy.credentialsExcludedFromExports === true, `${context}: exports must exclude credentials`);
  assert(payload.privacy.rawResponseBodiesExcludedFromExports === true, `${context}: exports must exclude raw response bodies`);
  assert(payload.privacy.aggregateOnly === true, `${context}: smoke should not load controller rows`);
  assert(payload.privacy.networkAccess === false, `${context}: smoke accessed the network`);
  assert(payload.privacy.realControllerData === false, `${context}: smoke read real controller data`);
  assert(payload.privacy.controllerProfilesLoaded === false, `${context}: smoke loaded controller profiles`);
  assert(payload.privacy.coreLaunched === false, `${context}: smoke launched a core`);
  assert(payload.privacy.systemEnvironmentModified === false, `${context}: smoke modified system state`);
}

const before = readPreferenceSnapshot();
for (const testCase of testCases) {
  assertSmokePayload(runSmokeCase(testCase), testCase);
}
const after = readPreferenceSnapshot();
assert(
  JSON.stringify(after) === JSON.stringify(before),
  `runtime smoke persisted launch overrides\nbefore: ${JSON.stringify(before)}\nafter: ${JSON.stringify(after)}`
);

console.log("runtime smoke probe contract passed");
