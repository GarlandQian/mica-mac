import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function absolute(relativePath) {
  return path.join(root, relativePath);
}

function exists(relativePath) {
  return existsSync(absolute(relativePath));
}

function read(relativePath) {
  return readFileSync(absolute(relativePath), "utf8");
}

function listFiles(relativeDirectory) {
  const directory = absolute(relativeDirectory);
  if (!existsSync(directory)) return [];

  return readdirSync(directory).flatMap((entry) => {
    const entryPath = path.join(directory, entry);
    const relativeEntry = path.relative(root, entryPath);
    return statSync(entryPath).isDirectory()
      ? listFiles(relativeEntry)
      : [relativeEntry];
  });
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertIncludes(source, needle, message) {
  assert(source.includes(needle), message ?? `Expected source to include: ${needle}`);
}

function assertExcludes(source, needle, message) {
  assert(!source.includes(needle), message ?? `Expected source to exclude: ${needle}`);
}

function assertOrdered(source, needles, message) {
  let previous = -1;
  for (const needle of needles) {
    const index = source.indexOf(needle);
    assert(index >= 0, `${message}: missing ${needle}`);
    assert(index > previous, `${message}: ${needle} is out of order`);
    previous = index;
  }
}

function sourceSection(source, startNeedle, endNeedle = null) {
  const start = source.indexOf(startNeedle);
  assert(start >= 0, `Unable to find source section start: ${startNeedle}`);
  if (endNeedle === null) return source.slice(start);

  const end = source.indexOf(endNeedle, start + startNeedle.length);
  assert(end >= 0, `Unable to find source section end: ${endNeedle}`);
  return source.slice(start, end);
}

function code(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^[ \t]*\/\/.*$/gm, "");
}

function count(source, needle) {
  return source.split(needle).length - 1;
}

function assertLocalized(strings, key) {
  const english = strings[key]?.localizations?.en?.stringUnit?.value;
  const chinese = strings[key]?.localizations?.["zh-Hans"]?.stringUnit?.value;
  assert(english, `${key} must have an English localization`);
  assert(chinese, `${key} must have a Simplified Chinese localization`);
}

function formatArgumentSignature(template) {
  const argumentsByPosition = new Map();
  let nextImplicitPosition = 1;

  for (let cursor = 0; cursor < template.length; cursor += 1) {
    if (template[cursor] !== "%") continue;
    if (template[cursor + 1] === "%") {
      cursor += 1;
      continue;
    }

    const match = template.slice(cursor).match(
      /^%(?:(\d+)\$)?[-+#0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|L|j|z|t|q)?([@dDuUxXoifFeEgGaAcCsSp])/,
    );
    if (!match) continue;

    const position = match[1]
      ? Number.parseInt(match[1], 10)
      : nextImplicitPosition++;
    const conversion = match[2];
    const argumentType = conversion === "@" || /[sScC]/.test(conversion)
      ? "text"
      : /[dDuUxXoi]/.test(conversion)
        ? "integer"
        : /[fFeEgGaA]/.test(conversion)
          ? "floating"
          : "pointer";
    const existingType = argumentsByPosition.get(position);

    assert(
      existingType === undefined || existingType === argumentType,
      `Format argument ${position} changes type inside template: ${template}`,
    );
    argumentsByPosition.set(position, argumentType);
    cursor += match[0].length - 1;
  }

  return [...argumentsByPosition.entries()]
    .sort(([lhs], [rhs]) => lhs - rhs)
    .map(([position, argumentType]) => `${position}:${argumentType}`)
    .join(",");
}

function assertLocalizationFormatSignatures(strings) {
  for (const [key, entry] of Object.entries(strings)) {
    const keySignature = formatArgumentSignature(key);

    for (const languageCode of ["en", "zh-Hans"]) {
      const value = entry.localizations?.[languageCode]?.stringUnit?.value;
      assert(value, `${key} must have a ${languageCode} localization`);

      const valueSignature = formatArgumentSignature(value);
      assert(
        valueSignature === keySignature,
        `${key} has incompatible ${languageCode} format arguments: key=${keySignature || "none"}, value=${valueSignature || "none"}`,
      );
    }
  }
}

assert(
  formatArgumentSignature("100% complete") === "",
  "Ordinary percentage text must not be treated as a format argument",
);
assert(
  formatArgumentSignature("Progress %% %@") === "1:text",
  "Escaped percentages must not consume a format argument",
);
assert(
  formatArgumentSignature("%2$@ %1$lld") === "1:integer,2:text",
  "Explicitly positioned localization arguments must be normalized by position",
);

function assertDirectLocalizationKeys(files, strings) {
  const keys = new Set();
  const patterns = [
    /MicaStrings\.localizedKey\(\s*"([^"]+)"/g,
    /\blocalized\(\s*"([^"]+)"\)/g,
    /Workbench(?:Section|FormRow|DataInspectorSection|MetricLabel)\(\s*"([^"]+)"/g,
    /(?:titleKey|detailKey|actionTitleKey):\s*"([^"]+)"/g,
  ];

  for (const file of files) {
    const source = read(file);
    for (const pattern of patterns) {
      for (const match of source.matchAll(pattern)) {
        if (!match[1].includes("\\(")) keys.add(match[1]);
      }
    }
  }

  for (const key of keys) {
    assertLocalized(strings, key);
  }
}

const expectedWorkbenchFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchActions.swift",
  "Sources/Mica/Features/Workbench/WorkbenchActionsPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchChrome.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConfiguration.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionCache.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionDetails.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionPulseView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnections.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchControllerPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchControllerSelector.swift",
  "Sources/Mica/Features/Workbench/WorkbenchControllers.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDashboard.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDataInteraction.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDataPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDataShared.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDiagnostics.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDiagnosticsComponents.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDiagnosticsPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchLogPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchLogs.swift",
  "Sources/Mica/Features/Workbench/WorkbenchManagement.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewEditor.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewPolicyInspection.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewPreferences.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewProjection.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewTelemetry.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewWindowRuntime.swift",
  "Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift",
  "Sources/Mica/Features/Workbench/WorkbenchProxyInteraction.swift",
  "Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchProxies.swift",
  "Sources/Mica/Features/Workbench/WorkbenchRuleDetails.swift",
  "Sources/Mica/Features/Workbench/WorkbenchRulePresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchRules.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSettings.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSidebar.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSourceDetails.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSourcePresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSources.swift",
  "Sources/Mica/Features/Workbench/WorkbenchStatusBar.swift",
  "Sources/Mica/Features/Workbench/WorkbenchTailscale.swift",
  "Sources/Mica/Features/Workbench/WorkbenchWindow.swift",
  "Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift",
  "Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift",
].sort();

const designFiles = [
  "Sources/Mica/Design/MicaTheme.swift",
  "Sources/Mica/Design/MicaThemeComponents.swift",
].sort();

const connectionPageFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchConnections.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionCache.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionPulseView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionDetails.swift",
];

const logPageFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchLogPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchLogs.swift",
];

const rulePageFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchRulePresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchRules.swift",
  "Sources/Mica/Features/Workbench/WorkbenchRuleDetails.swift",
];

const sourcePageFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchSourcePresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSources.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSourceDetails.swift",
];

const dataPageFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchDataInteraction.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDataPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDataShared.swift",
  ...connectionPageFiles,
  ...logPageFiles,
  ...rulePageFiles,
  ...sourcePageFiles,
];

const dataBrowserTableFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchRules.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSources.swift",
  "Sources/Mica/Features/Workbench/WorkbenchLogs.swift",
];

const controllerPageFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchControllerPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchControllers.swift",
];

const actionPageFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchActionsPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchActions.swift",
  "Sources/Mica/Features/Workbench/WorkbenchTailscale.swift",
];

const diagnosticsPageFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchDiagnosticsPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDiagnostics.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDiagnosticsComponents.swift",
];

const managementPageFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchManagement.swift",
  ...controllerPageFiles,
  "Sources/Mica/Features/Workbench/WorkbenchConfiguration.swift",
  ...actionPageFiles,
  ...diagnosticsPageFiles,
];

const requiredPresentationTests = [
  "Tests/MicaTests/AppModelEndpointChecksTests.swift",
  "Tests/MicaTests/ConnectionMutationSafetyTests.swift",
  "Tests/MicaTests/GeoIPResolverTests.swift",
  "Tests/MicaTests/LiveSessionPublicationTests.swift",
  "Tests/MicaTests/LiveSessionRuntimeTests.swift",
  "Tests/MicaTests/MicaPerformanceBenchmarkTests.swift",
  "Tests/MicaTests/PerformanceObservationTests.swift",
  "Tests/MicaTests/ProviderUpdateAllTests.swift",
  "Tests/MicaTests/SessionRefreshCoordinatorTests.swift",
  "Tests/MicaTests/WorkbenchDataProjectionTests.swift",
  "Tests/MicaTests/WorkbenchManagementProjectionTests.swift",
  "Tests/MicaTests/WorkbenchNavigationTests.swift",
  "Tests/MicaTests/WorkbenchOperationOutcomePresentationTests.swift",
  "Tests/MicaTests/WorkbenchOverviewPerformanceTests.swift",
  "Tests/MicaTests/WorkbenchOverviewPreferencesTests.swift",
  "Tests/MicaTests/WorkbenchPreferencesTests.swift",
  "Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift",
  "Tests/MicaTests/WorkbenchTimelineAndProxyTests.swift",
  "Tests/MicaTests/ConnectionTopologyTests.swift",
];

const requiredFiles = [
  "Package.swift",
  "AGENTS.md",
  ".trellis/spec/frontend/workbench-ui-contract.md",
  ".trellis/spec/frontend/live-session-controller-contract.md",
  ".trellis/spec/backend/controller-data-contract.md",
  "Sources/Mica/App/AppAppearance.swift",
  "Sources/Mica/App/AppFontScale.swift",
  "Sources/Mica/App/AppLanguage.swift",
  "Sources/Mica/App/AppPreferenceEnvironment.swift",
  "Sources/Mica/App/AppPreferencesStore.swift",
  "Sources/Mica/App/AppModel.swift",
  "Sources/Mica/App/AppModelEndpointChecks.swift",
  "Sources/Mica/App/AppModelLiveSession.swift",
  "Sources/Mica/App/AppModelLiveSessionRuntime.swift",
  "Sources/Mica/App/AppModelSessionRefreshCoordinator.swift",
  "Sources/Mica/App/AppModelRouterProfiles.swift",
  "Sources/Mica/App/AppModelSelectionState.swift",
  "Sources/Mica/App/AppModelSurgeOperations.swift",
  "Sources/Mica/App/DashboardSurgeProjectionModels.swift",
  "Sources/Mica/App/DashboardSessionControls.swift",
  "Sources/Mica/App/DashboardSessionModels.swift",
  "Sources/Mica/App/Info.plist",
  "Sources/Mica/App/SessionBuffers.swift",
  "Sources/Mica/App/LiveSessionRefreshModels.swift",
  "Sources/Mica/App/LiveSessionRuntime.swift",
  "Sources/Mica/App/PerformanceObservation.swift",
  "Sources/Mica/App/SessionRefreshCoordinator.swift",
  "Sources/Mica/App/ConnectionTopologyModel.swift",
  "Sources/Mica/App/GeoIPResolver.swift",
  "Sources/Mica/App/OperationSessionModels.swift",
  "Sources/Mica/App/SessionTimelineModels.swift",
  "Sources/Mica/App/MicaApp.swift",
  "Sources/Mica/App/MicaCommandFocus.swift",
  "Sources/Mica/App/MainWindowCloseGuard.swift",
  "Sources/Mica/App/XCStringsResolver.swift",
  "Sources/Mica/Resources/Localizable.xcstrings",
  "Sources/Mica/Features/Routers/Views/RouterEditorAuditRows.swift",
  "Sources/Mica/Features/Routers/Views/RouterEditorDiagnosisSections.swift",
  "Sources/Mica/Features/Routers/Views/RouterEditorSections.swift",
  "Sources/Mica/Features/Routers/Views/RouterEditorView.swift",
  "Sources/MicaCore/API/ControllerHTTPProbeResolver.swift",
  "Sources/MicaCore/API/ControllerProbeResolver.swift",
  "Sources/MicaCore/API/MihomoClient.swift",
  "Sources/MicaCore/API/MihomoEndpoint.swift",
  "Sources/MicaCore/API/SurgeHttpAPIClient.swift",
  "Sources/MicaCore/API/UnifiedControllerAdapters.swift",
  "Sources/MicaCore/Models/MihomoModels.swift",
  "Sources/MicaCore/Models/SingBoxModels.swift",
  "Sources/MicaCore/Models/UnifiedControllerModels.swift",
  "Tests/MicaCoreTests/MihomoClientContractTests.swift",
  "Tests/MicaCoreTests/MihomoModelsTests.swift",
  "Tests/MicaTests/ControllerVariantCapabilityTests.swift",
  "Tests/MicaTests/SessionStreamStateTests.swift",
  "scripts/verify-runtime-smoke.mjs",
  ...expectedWorkbenchFiles,
  ...designFiles,
  ...requiredPresentationTests,
];

for (const file of requiredFiles) {
  assert(exists(file), `Required source-contract file is missing: ${file}`);
}

const actualWorkbenchFiles = listFiles("Sources/Mica/Features/Workbench")
  .filter((file) => file.endsWith(".swift"))
  .sort();
assert(
  JSON.stringify(actualWorkbenchFiles) === JSON.stringify(expectedWorkbenchFiles),
  `Workbench file ownership must match the replacement architecture. Found: ${actualWorkbenchFiles.join(", ")}`,
);

const removedPresentationTests = [
  "Tests/MicaTests/ControllerManagementPresentationTests.swift",
  "Tests/MicaTests/OverviewProjectorTests.swift",
  "Tests/MicaTests/PolicyGroupLayoutTests.swift",
  "Tests/MicaTests/PolicyGroupRebuildTests.swift",
  "Tests/MicaTests/WorkbenchChromeTests.swift",
  "Tests/MicaTests/WorkbenchDataSurfacesTests.swift",
  "Tests/MicaTests/WorkbenchPresentationTests.swift",
];
for (const file of removedPresentationTests) {
  assert(!exists(file), `Deleted old Workbench test must not return: ${file}`);
}

for (const removedPath of [
  "Sources/Mica/App/AppModelWorkbenchAliases.swift",
  "Sources/Mica/App/AppWorkspace.swift",
  "Sources/Mica/App/MicaFont.swift",
  "Sources/Mica/App/MicaStyle.swift",
  "Sources/Mica/App/PreviewData.swift",
  "Sources/Mica/Features/Dashboard/Views/DashboardCommandBar.swift",
  "Sources/Mica/Features/Dashboard/Views/DashboardCommandPalette.swift",
  "scripts/mock-mihomo-controller.mjs",
  "scripts/verify-mock-controller.mjs",
]) {
  assert(!exists(removedPath), `Removed compatibility or mock source must stay deleted: ${removedPath}`);
}

const packageManifest = read("Package.swift");
const agentsRules = read("AGENTS.md");
const appInfoPlist = read("Sources/Mica/App/Info.plist");
const workbenchContract = read(".trellis/spec/frontend/workbench-ui-contract.md");
const controllerContract = read(".trellis/spec/backend/controller-data-contract.md");
const liveSessionContract = read(".trellis/spec/frontend/live-session-controller-contract.md");
// Mica Ops design system (task 08-17 Phase 7.3): the consolidated theme namespace.
const designSystem = read("Sources/Mica/Design/MicaTheme.swift");
const themeComponents = read("Sources/Mica/Design/MicaThemeComponents.swift");
const chrome = read("Sources/Mica/Features/Workbench/WorkbenchChrome.swift");
const window = read("Sources/Mica/Features/Workbench/WorkbenchWindow.swift");
const sidebar = read("Sources/Mica/Features/Workbench/WorkbenchSidebar.swift");
const statusBar = read("Sources/Mica/Features/Workbench/WorkbenchStatusBar.swift");
const chromeSource = [chrome, window, sidebar, statusBar].join("\n");
const controllerSelector = read("Sources/Mica/Features/Workbench/WorkbenchControllerSelector.swift");
const workspaceView = read("Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift");
const dashboard = read("Sources/Mica/Features/Workbench/WorkbenchDashboard.swift");
const overviewEditor = read("Sources/Mica/Features/Workbench/WorkbenchOverviewEditor.swift");
const overviewPolicyInspection = read("Sources/Mica/Features/Workbench/WorkbenchOverviewPolicyInspection.swift");
const overviewPreferences = read("Sources/Mica/Features/Workbench/WorkbenchOverviewPreferences.swift");
const overviewProjection = read("Sources/Mica/Features/Workbench/WorkbenchOverviewProjection.swift");
const overviewTelemetry = read("Sources/Mica/Features/Workbench/WorkbenchOverviewTelemetry.swift");
const overviewTopology = read("Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift");
const overviewTopologyView = read("Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift");
const overviewWindowRuntime = read("Sources/Mica/Features/Workbench/WorkbenchOverviewWindowRuntime.swift");
const overviewSource = [
  dashboard,
  overviewEditor,
  overviewPolicyInspection,
  overviewPreferences,
  overviewProjection,
  overviewTelemetry,
  overviewTopology,
  overviewTopologyView,
  overviewWindowRuntime,
].join("\n");
const proxyRoot = read("Sources/Mica/Features/Workbench/WorkbenchProxies.swift");
const proxyPanels = read("Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift");
const proxyInteraction = read("Sources/Mica/Features/Workbench/WorkbenchProxyInteraction.swift");
const proxyPresentation = read("Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift");
const proxies = [proxyRoot, proxyPanels, proxyInteraction, proxyPresentation].join("\n");
const dataInteraction = read("Sources/Mica/Features/Workbench/WorkbenchDataInteraction.swift");
const dataPresentation = read("Sources/Mica/Features/Workbench/WorkbenchDataPresentation.swift");
const dataShared = read("Sources/Mica/Features/Workbench/WorkbenchDataShared.swift");
const dataPages = dataPageFiles.map(read).join("\n");
const connectionsPresentation = read("Sources/Mica/Features/Workbench/WorkbenchConnections.swift");
const connectionCache = read("Sources/Mica/Features/Workbench/WorkbenchConnectionCache.swift");
const connectionsRoot = read("Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift");
const connectionPulseView = read("Sources/Mica/Features/Workbench/WorkbenchConnectionPulseView.swift");
const connectionDetails = read("Sources/Mica/Features/Workbench/WorkbenchConnectionDetails.swift");
const connectionsPage = connectionPageFiles.map(read).join("\n");
const logPresentation = read("Sources/Mica/Features/Workbench/WorkbenchLogPresentation.swift");
const logsRoot = read("Sources/Mica/Features/Workbench/WorkbenchLogs.swift");
const logsPage = logPageFiles.map(read).join("\n");
const rulePresentation = read("Sources/Mica/Features/Workbench/WorkbenchRulePresentation.swift");
const rulesRoot = read("Sources/Mica/Features/Workbench/WorkbenchRules.swift");
const ruleDetails = read("Sources/Mica/Features/Workbench/WorkbenchRuleDetails.swift");
const rulesPage = rulePageFiles.map(read).join("\n");
const sourcePresentation = read("Sources/Mica/Features/Workbench/WorkbenchSourcePresentation.swift");
const sourcesRoot = read("Sources/Mica/Features/Workbench/WorkbenchSources.swift");
const sourceDetails = read("Sources/Mica/Features/Workbench/WorkbenchSourceDetails.swift");
const sourcesPage = sourcePageFiles.map(read).join("\n");
const managementShared = read("Sources/Mica/Features/Workbench/WorkbenchManagement.swift");
const controllerPresentation = read("Sources/Mica/Features/Workbench/WorkbenchControllerPresentation.swift");
const controllersRoot = read("Sources/Mica/Features/Workbench/WorkbenchControllers.swift");
const controllersPage = controllerPageFiles.map(read).join("\n");
const configurationPage = read("Sources/Mica/Features/Workbench/WorkbenchConfiguration.swift");
const actionsRoot = read("Sources/Mica/Features/Workbench/WorkbenchActions.swift");
const actionsPresentation = read("Sources/Mica/Features/Workbench/WorkbenchActionsPresentation.swift");
const tailscale = read("Sources/Mica/Features/Workbench/WorkbenchTailscale.swift");
const actionsPage = actionPageFiles.map(read).join("\n");
const diagnosticsPresentation = read("Sources/Mica/Features/Workbench/WorkbenchDiagnosticsPresentation.swift");
const diagnosticsRoot = read("Sources/Mica/Features/Workbench/WorkbenchDiagnostics.swift");
const diagnosticsComponents = read("Sources/Mica/Features/Workbench/WorkbenchDiagnosticsComponents.swift");
const diagnosticsPage = diagnosticsPageFiles.map(read).join("\n");
const management = [
  managementShared,
  controllersPage,
  configurationPage,
  actionsPage,
  diagnosticsPage,
].join("\n");
const settings = read("Sources/Mica/Features/Workbench/WorkbenchSettings.swift");
const workspaceStore = read("Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift");
const workbenchSource = expectedWorkbenchFiles.map(read).join("\n");
const workbenchCode = code(workbenchSource);
const presentationTests = requiredPresentationTests.map(read).join("\n");
const sessionStreamTests = read("Tests/MicaTests/SessionStreamStateTests.swift");
const liveSessionPublicationTests = read("Tests/MicaTests/LiveSessionPublicationTests.swift");
const liveSessionRuntimeTests = read("Tests/MicaTests/LiveSessionRuntimeTests.swift");
const overviewPreferencesTests = read(
  "Tests/MicaTests/WorkbenchOverviewPreferencesTests.swift",
);
const appAppearance = read("Sources/Mica/App/AppAppearance.swift");
const appFontScale = read("Sources/Mica/App/AppFontScale.swift");
const appLanguage = read("Sources/Mica/App/AppLanguage.swift");
const preferenceEnvironment = read("Sources/Mica/App/AppPreferenceEnvironment.swift");
const appPreferencesStore = read("Sources/Mica/App/AppPreferencesStore.swift");
const micaApp = read("Sources/Mica/App/MicaApp.swift");
const micaCommandFocus = read("Sources/Mica/App/MicaCommandFocus.swift");
const mainWindowCloseGuard = read("Sources/Mica/App/MainWindowCloseGuard.swift");
const xcstringsResolver = read("Sources/Mica/App/XCStringsResolver.swift");
const routerEditorView = read("Sources/Mica/Features/Routers/Views/RouterEditorView.swift");
const routerEditorSections = read("Sources/Mica/Features/Routers/Views/RouterEditorSections.swift");
const routerEditorDiagnosis = read(
  "Sources/Mica/Features/Routers/Views/RouterEditorDiagnosisSections.swift",
);
const appModel = read("Sources/Mica/App/AppModel.swift");
const appModelEndpointChecks = read("Sources/Mica/App/AppModelEndpointChecks.swift");
const liveSession = read("Sources/Mica/App/AppModelLiveSession.swift");
const liveSessionRuntime = read("Sources/Mica/App/LiveSessionRuntime.swift");
const liveSessionRuntimeBridge = read("Sources/Mica/App/AppModelLiveSessionRuntime.swift");
const refreshCoordinator = read("Sources/Mica/App/SessionRefreshCoordinator.swift");
const performanceObservation = read("Sources/Mica/App/PerformanceObservation.swift");
const routerProfiles = read("Sources/Mica/App/AppModelRouterProfiles.swift");
const selectionState = read("Sources/Mica/App/AppModelSelectionState.swift");
const surgeOperations = read("Sources/Mica/App/AppModelSurgeOperations.swift");
const surgeProjection = read("Sources/Mica/App/DashboardSurgeProjectionModels.swift");
const sessionControls = read("Sources/Mica/App/DashboardSessionControls.swift");
const dashboardSessionModels = read("Sources/Mica/App/DashboardSessionModels.swift");
const sessionBuffers = read("Sources/Mica/App/SessionBuffers.swift");
const liveSessionRefreshModels = read("Sources/Mica/App/LiveSessionRefreshModels.swift");
const connectionTopology = read("Sources/Mica/App/ConnectionTopologyModel.swift");
const geoIPResolver = read("Sources/Mica/App/GeoIPResolver.swift");
const operationSessionModels = read("Sources/Mica/App/OperationSessionModels.swift");
const sessionTimelines = read("Sources/Mica/App/SessionTimelineModels.swift");
const mihomoClient = read("Sources/MicaCore/API/MihomoClient.swift");
const mihomoEndpoint = read("Sources/MicaCore/API/MihomoEndpoint.swift");
const mihomoModels = read("Sources/MicaCore/Models/MihomoModels.swift");
const surgeClient = read("Sources/MicaCore/API/SurgeHttpAPIClient.swift");
const unifiedAdapters = read("Sources/MicaCore/API/UnifiedControllerAdapters.swift");
const unifiedModels = read("Sources/MicaCore/Models/UnifiedControllerModels.swift");
const controllerVariantTests = read("Tests/MicaTests/ControllerVariantCapabilityTests.swift");
const runtimeSmoke = read("Sources/Mica/App/AppRuntimeSmokeProbe.swift");
const executableSource = listFiles("Sources/Mica")
  .filter((file) => file.endsWith(".swift"))
  .map(read)
  .join("\n");
const stringCatalog = JSON.parse(read("Sources/Mica/Resources/Localizable.xcstrings"));
const strings = stringCatalog.strings ?? {};

assertLocalizationFormatSignatures(strings);

assertIncludes(packageManifest, '.macOS("27.0")', "Mica must retain the macOS 27 deployment target");
assertIncludes(packageManifest, '.executable(name: "Mica"', "Package must expose the native Mica executable");
assertExcludes(packageManifest, "WebKit", "The native frontend must not add WebKit");
const appTransportSecurity = sourceSection(
  appInfoPlist,
  "<key>NSAppTransportSecurity</key>",
  "<key>NSHumanReadableCopyright</key>",
);
assertIncludes(
  appTransportSecurity,
  "<key>NSAllowsLocalNetworking</key>",
  "Mica must declare local-network ATS access for user-configured controller IP addresses",
);
assertIncludes(
  appTransportSecurity,
  "<true/>",
  "Mica local-network ATS access must remain enabled",
);
assertIncludes(
  appInfoPlist,
  "<key>NSLocalNetworkUsageDescription</key>",
  "Mica must explain direct local-network controller access in its embedded Info.plist",
);
assertIncludes(
  appInfoPlist,
  "Mica uses the local network",
  "The local-network usage description must retain English copy",
);
assertIncludes(
  appInfoPlist,
  "Mica 使用本地网络",
  "The local-network usage description must retain Simplified Chinese copy",
);
assertIncludes(agentsRules, "Keep controller-reported business data visible and selectable in active UI", "Repository rules must keep active data fully visible");
assertIncludes(agentsRules, "tmp/codex/", "Repository rules must keep scratch output in the repository");
assertIncludes(agentsRules, "Add a Swift package only for a verified material benefit", "Repository rules must retain the evidence-based dependency policy");
assertIncludes(workbenchContract, "The directory contains exactly:", "Workbench contract must define the exact owned-file architecture");
assertIncludes(workbenchContract, "Logs retain", "Workbench contract must preserve incoming log order");
assertIncludes(workbenchContract, "incoming order and explicit Follow Newest behavior", "Workbench contract must preserve explicit Follow Newest behavior");
assertIncludes(workbenchContract, "one source-ordered vertical workspace", "Workbench contract must preserve the expandable proxy workspace architecture");
assertIncludes(workbenchContract, "admits every active connection", "Workbench contract must preserve complete topology admission");
assertIncludes(workbenchContract, "logs 5 Hz, traffic 4 Hz", "Workbench contract must preserve visible-domain budgets");
assertIncludes(controllerContract, "proxyOrder", "Controller contract must preserve controller proxy order");
assertIncludes(liveSessionContract, "generation", "Live-session contract must retain generation ownership");
assertIncludes(liveSessionContract, "LiveSessionRuntime", "Live-session contract must retain actor-owned high-frequency ingestion");
assertIncludes(liveSessionContract, "SessionRefreshCoordinator", "Live-session contract must retain actor-owned lane coordination");
assertIncludes(liveSessionContract, "200 records and 30 minutes", "Live-session contract must preserve current-session closed-history limits");
assertIncludes(liveSessionContract, "DashboardSnapshot` does not own logs", "Live-session contract must keep logs out of the broad dashboard snapshot");

assertIncludes(
  routerEditorView,
  "WorkbenchManagementFormCanvas",
  "Controller editing must use the native grouped management form canvas",
);
assertExcludes(
  routerEditorView,
  "editorCanvas(availableWidth:",
  "Controller editing must not restore the fixed manual split canvas",
);
assertExcludes(
  routerEditorSections,
  "WorkbenchSection(",
  "Controller form rows must not restore raised content strips inside the grouped form",
);
assertOrdered(
  management,
  [
    "private var controlColumn: some View {",
    ".labelsHidden()",
    "struct WorkbenchFormValue: View",
  ],
  "Shared management form rows must hide embedded native control labels",
);
const controllerDetailSection = sourceSection(
  management,
  "struct WorkbenchControllerInspector: View {",
  "private func controllerIdentity(_ profile: RouterProfile) -> some View {",
);
assertIncludes(
  controllerDetailSection,
  "WorkbenchManagementFormCanvas",
  "Controller detail must use the native grouped management form canvas",
);
assertIncludes(actionsPresentation, "struct WorkbenchActionsInput", "Actions must consume one pure typed input");
assertIncludes(actionsPresentation, "struct WorkbenchActionsSnapshot", "Actions must expose one pure typed snapshot");
const actionsInputSource = sourceSection(
  actionsPresentation,
  "struct WorkbenchActionsInput: Equatable {",
  "struct WorkbenchActionsSnapshot: Equatable {",
);
const diagnosticsInputSource = sourceSection(
  diagnosticsPresentation,
  "struct WorkbenchDiagnosticsInput: Equatable {",
  "struct WorkbenchDiagnosticsSnapshot: Equatable {",
);
for (const streamPayloadType of [
  "ConnectionSnapshot",
  "ControllerLogEntry",
  "TrafficTimeline",
  "ConnectionsCatalogSnapshot",
  "LogsCatalogSnapshot",
]) {
  assertExcludes(actionsInputSource, streamPayloadType, `Actions input must not observe ${streamPayloadType}`);
  assertExcludes(diagnosticsInputSource, streamPayloadType, `Diagnostics input must not observe ${streamPayloadType}`);
}
assertIncludes(actionsPresentation, "supportsRuntimeDispatcher", "Actions must prove the adapter dispatcher before exposing runtime commands");
assertIncludes(actionsPresentation, "executableCount:", "Actions must derive an exact executable count");
assertIncludes(actionsPresentation, "let effectiveAvailability", "Actions must derive recovery and rendering from one effective state");
assertIncludes(actionsPresentation, "showsRelatedDestinations", "Actions must reserve related workspaces for compact command states");
assertIncludes(actionsRoot, "recoveryCanvas", "Actions must use a dedicated recovery composition");
assertIncludes(actionsRoot, "commandCanvas", "Actions must use a dedicated connected command composition");
assertIncludes(actionsRoot, "appModel.actionsRuntimeOperationRows", "Actions must consume evidence-free runtime command rows");
assertIncludes(actionsRoot, "let usesTwoColumns = availableWidth >= 900", "Actions must adapt connected commands by measured width");
assertExcludes(actionsRoot, "WorkbenchManagementFormCanvas", "Actions must not force recovery and commands into a grouped form");
assertExcludes(
  management,
  'WorkbenchSection("controllers.actions"',
  "Controller detail must not restore custom raised action strips",
);
assertExcludes(
  management,
  'WorkbenchSection("diagnostics.runtime_operations"',
  "Actions must not restore custom raised operation strips",
);
assertIncludes(
  management,
  'isTesting(profile) ? "editor.testing" : "action.test"',
  "Controller detail testing must retain a visible command title",
);
assertIncludes(
  routerEditorView,
  ".labelStyle(.titleAndIcon)",
  "Controller editor commands must keep their visible titles",
);
assertIncludes(
  routerEditorView,
  ".layoutPriority(1)",
  "Controller editor commands must resist horizontal compression",
);
assertExcludes(
  routerEditorDiagnosis,
  '"editor.controller_preview"',
  "Controller editing must not duplicate draft values in an idle preview column",
);

assertIncludes(liveSessionRuntime, "actor LiveSessionRuntime", "High-frequency live ingestion must remain actor-owned");
assertIncludes(liveSessionRuntime, "struct LiveSessionRuntimePublication", "Runtime must publish immutable typed envelopes");
assertIncludes(liveSessionRuntime, "LiveSessionConnectionRevisions", "Connection structure, metrics, and traffic revisions must remain separate");
assertIncludes(liveSessionRefreshModels, "struct LiveSessionWindowDemandID", "Each window must own a stable demand token");
assertIncludes(liveSessionRefreshModels, "private(set) var windowDestinations:", "The coordinator must retain token-scoped destinations");
assertIncludes(liveSessionRefreshModels, "struct LiveSessionPresentationDemand", "Runtime visibility must travel as one complete demand snapshot");
for (const demandField of [
  "let identity: LiveSessionRuntimeIdentity",
  "let revision: UInt64",
  "let observedDomains: Set<LiveSessionPublicationDomain>",
  "let presentationPaused: Bool",
  "let logsPresentationPaused: Bool",
  "let baselinePublicationRequired: Bool",
]) {
  assertIncludes(liveSessionRefreshModels, demandField, `Complete live demand must retain ${demandField}`);
}
assertIncludes(liveSessionRuntime, "initialPresentationDemand: LiveSessionPresentationDemand", "Runtime initialization must install demand before ingestion");
assertIncludes(liveSessionRuntime, "force: force && demandIsCurrent", "A stale immediate flush may publish only when the current demand still observes its domain");
assertIncludes(liveSessionRuntimeBridge, "flushStagedRuntimePresentationDomainIfVisible(", "Visibility re-entry must recover already-staged actor data");
assertIncludes(liveSessionRuntimeBridge, "lastRuntimePublicationRevisions", "AppModel must track applied runtime revisions by domain");
assertIncludes(liveSessionRuntimeBridge, "guard publication.revision > lastRevision", "Older actor publications must not overwrite newer visible state");
for (const liveDemandRegression of [
  "staleImmediateFlushUsesCurrentDemandWhenDomainRemainsVisible",
  "actorVisibilityReentryFlushesPreviouslyStagedLogs",
  "dualWindowUnionUsesOneGenerationAndOneRuntime",
  "runtimeInstallationUsesCurrentCompleteDemandBeforeIngestion",
]) {
  assertIncludes(
    `${liveSessionRuntimeTests}\n${liveSessionPublicationTests}`,
    liveDemandRegression,
    `Live demand needs regression coverage for ${liveDemandRegression}`,
  );
}
assertIncludes(refreshCoordinator, "actor SessionRefreshCoordinator", "REST refresh ownership must remain actor-isolated");
assertIncludes(refreshCoordinator, "pendingFollowUp", "Refresh lanes must retain one coalesced follow-up");
assertIncludes(performanceObservation, "OSSignposter", "Performance hot paths must retain signpost instrumentation");
assertIncludes(performanceObservation, "MicaPerformanceMetadata", "Performance metadata must remain typed and business-data-free");
for (const performanceContract of [
  "case fullPresentationProjection",
  "case incrementalPresentationProjection",
  "case topologyBasePresentation",
  "case topologyHighlightPresentation",
  "case topologyAccessibilityPresentation",
  "case scrollPhase",
  "case dataTableEvaluation",
  "case workspaceEncoding",
  "static func recordDebug(",
]) {
  assertIncludes(performanceObservation, performanceContract, `Vertical-scroll observability must retain ${performanceContract}`);
}

for (const legacyType of [
  "ControllerManagementPresentation",
  "ControllerSwitcherPresentation",
  "SessionChromePresentation",
  "PolicyGroupPresentation",
  "PolicyGroupCatalogProjection",
  "PolicyGroupInteractionStore",
  "WorkbenchConnectionsProjector",
  "WorkbenchRulesProjector",
  "WorkbenchSourcesProjector",
  "WorkbenchLogsProjector",
  "WorkbenchDataSurfaceResolution",
  "WorkbenchChromeMetrics",
  "WorkbenchMetrics",
  "WorkbenchCoreConfigView",
  "WorkbenchCoreActionsView",
  "WorkbenchArea",
  "ActivitySection",
  "ResourcesSection",
  "SystemSection",
]) {
  assertExcludes(workbenchCode, legacyType, `Replacement frontend must not retain old UI type ${legacyType}`);
  assertExcludes(presentationTests, legacyType, `Replacement tests must not expect old UI type ${legacyType}`);
}

for (const forbiddenPattern of [
  ".glassEffect(",
  "GlassEffectContainer",
  ".sheet(",
  ".popover(",
  ".confirmationDialog(",
  "NSViewRepresentable",
  "NSViewControllerRepresentable",
  "NSTableView",
  "NSOutlineView",
  "try!",
  " as! ",
  "fatalError(",
  "TODO",
  "FIXME",
]) {
  assertExcludes(workbenchCode, forbiddenPattern, `Workbench replacement contains forbidden pattern ${forbiddenPattern}`);
}
const directSystemFontCalls = [...workbenchCode.matchAll(/\.font\(\s*\.system\(/g)].length;
assert(
  directSystemFontCalls === 0,
  "Workbench text must route through micaThemeFont; only MicaTheme constructs system fonts (task 08-17 Phase 7.3)",
);
assertIncludes(
  designSystem,
  "content.font(MicaTheme.font(for: role, scale: fontScale, weight: weight))",
  "The MicaTheme font modifier must own ordinary interface font construction",
);
// Task 08-20: topology text moved to the system-pipeline label band, which
// reads the font scale from the environment via micaThemeFont.
assertIncludes(
  workbenchSource,
  "@Environment(\\.micaAppFontScale) private var fontScale",
  "Topology label band must read the active font scale from the environment",
);
assertIncludes(
  workbenchSource,
  ".micaThemeFont(.label, weight: .semibold)",
  "Topology column titles must use the scaled semibold label role",
);
assertIncludes(
  workbenchSource,
  ".micaThemeFont(.label)",
  "Topology node labels must use the scaled label role",
);
const appearanceRows = sourceSection(
  workbenchSource,
  "private var appearanceRows: some View {",
  "private var routingRows: some View {",
);
assertExcludes(
  appearanceRows,
  "Divider()",
  "Native Settings Form rows must not insert dividers as empty form rows",
);
assertExcludes(workbenchCode, "MicaFont", "Removed manual font factory must not return");
assertExcludes(workbenchCode, ".truncationMode(.middle)", "Active business values must not be middle-truncated");
for (const privacyEraCopy of ["redacted", "masked", "safe summary", "privacy boundary"]) {
  assertExcludes(workbenchSource.toLowerCase(), privacyEraCopy, `Active UI must not restore privacy-era copy: ${privacyEraCopy}`);
}

for (const token of [
  "static let canvas = Color(micaLight: rgb(0xFFFFFF), dark: rgb(0x0D0E10))",
  "static let surface = Color(micaLight: rgb(0xF5F6F7), dark: rgb(0x15171A))",
  "static let surfaceRaised = Color(micaLight: rgb(0xFFFFFF), dark: rgb(0x1C1F23))",
  "static let separator = Color(micaLight: rgb(0xD9DBDF), dark: rgb(0x2A2D32))",
  "static let accent = Color(micaLight: rgb(0x0B8F66), dark: rgb(0x34D1A3))",
  "static let statusOK",
  "static let statusWarning",
  "static let statusError",
]) {
  assertIncludes(designSystem, token, `Mica Ops design system must retain the token ${token} (task 08-17)`);
}
assertIncludes(designSystem, "enum TextRole", "Mica Ops typography must expose semantic text roles");
assertIncludes(designSystem, "struct MicaThemeFontModifier", "Mica Ops typography must visibly apply the selected font scale");
assertIncludes(designSystem, "scale.pointSize(for: role.basePointSize)", "Mica Ops typography must calculate an explicit macOS point size");
const scalableTypographyCalls =
  count(workbenchSource, ".micaFont(") + count(workbenchSource, ".micaThemeFont(");
assert(
  scalableTypographyCalls >= 150,
  "Workbench interface text must use the scalable typography API",
);
assertIncludes(designSystem, "enum Motion", "Mica Ops state-change motion tokens must exist");
assertIncludes(designSystem, "accessibilityReduceMotion", "Motion must honor Reduce Motion");
for (const metric of [
  "static let controlMinHeight: CGFloat = 28",
  "static let iconControlSize: CGFloat = 28",
  "static let commandBarHeight: CGFloat = 40",
  "static let statusBarHeight: CGFloat = 34",
  "static let moduleRadius: CGFloat = 8",
  "static let badgeRadius: CGFloat = 5",
  "static let sidebarMin: CGFloat = 176",
  "static let sidebarMax: CGFloat = 232",
  "static let inspectorMin: CGFloat = 300",
  "static let inspectorMax: CGFloat = 480",
  "static let wideThreshold: CGFloat = 720",
]) {
  assertIncludes(designSystem, metric, `Design system must retain bounded metric ${metric}`);
}
assertExcludes(designSystem, "hitTarget", "Workbench must not restore a universal touch-target metric");
for (const primitive of [
  "struct WorkbenchSymbol",
  "struct WorkbenchPageScaffold",
  "struct WorkbenchCommandBar",
  "struct WorkbenchSection",
  "struct WorkbenchMetricTile",
  "struct WorkbenchStateView",
  "struct WorkbenchStatusBadge",
  "struct WorkbenchStaleNotice",
  "struct WorkbenchIconCommand",
]) {
  assertIncludes(themeComponents, primitive, `Mica Ops theme components must expose ${primitive}`);
}
assertIncludes(themeComponents, ".symbolRenderingMode(.monochrome)", "Shared workbench symbols must retain deterministic native rendering");
assertIncludes(themeComponents, "ContentUnavailableView", "Shared states must use native centered unavailable content");
assertIncludes(themeComponents, ".frame(maxWidth: .infinity, maxHeight: .infinity)", "Full-page states must center in the remaining region");

const destinationSource = sourceSection(chrome, "enum WorkbenchDestination", "// MARK: - Workbench Shell");
assertOrdered(destinationSource, [
  "case overview", "case proxies", "case connections", "case logs", "case rules", "case sources",
  "case controllers", "case configuration", "case actions", "case diagnostics",
], "Workbench destinations must keep the fixed product order");
assertIncludes(destinationSource, ".overview, .proxies, .connections, .logs, .rules, .sources,", "Keyboard destinations must keep the fixed six-tab order");
assertIncludes(destinationSource, ".overview, .proxies, .connections, .rules,", "Operate group must keep its fixed order");
    assertIncludes(destinationSource, ".logs, .sources, .diagnostics,", "Observe group must keep its fixed order");
    assertIncludes(destinationSource, ".controllers, .configuration, .actions,", "Manage group must keep its fixed order");
assertIncludes(destinationSource, "static let sidebarCases = operateCases + observeCases + manageCases", "Sidebar keyboard navigation must use the visible destination order");
assertExcludes(destinationSource, "case settings", "Application Settings must remain a native Settings scene, not a Workbench destination");
assertIncludes(window, "NavigationSplitView", "Main window must use native split navigation");
assertIncludes(sidebar, "List {", "Sidebar must retain a native virtualized list");
assertIncludes(chrome, ".toolbarTitleDisplayMode(.inline)", "Native navigation title must retain toolbar space without duplicate identity chrome");
assertIncludes(chrome, ".sharedBackgroundVisibility(.hidden)", "Session commands must not be wrapped in a second shared glass capsule");
assertExcludes(chromeSource, "WorkbenchToolbarControllerButton", "Controller identity must not be duplicated in the toolbar");
assertExcludes(workbenchSource, "CommandPalette", "Workbench must not restore a command palette");
assertExcludes(workbenchSource, "CommandDeck", "Workbench must not restore a command deck");
assertExcludes(micaApp, '.keyboardShortcut("k", modifiers: [.command])', "Mica must not reserve Command-K for a custom command surface");
assertExcludes(chromeSource, "workbenchArea", "Replacement navigation must not migrate the old area model");
assertExcludes(chromeSource, "workbenchActivitySection", "Replacement navigation must not migrate the old activity model");
const sidebarSource = sourceSection(sidebar, "struct WorkbenchSidebarView");
assertExcludes(sidebarSource, "@Environment(AppModel.self)", "Destination list shell must not observe controller or stream state");
assertIncludes(sidebarSource, "@Environment(\\.micaAppLanguage)", "Sidebar must observe language changes directly");
assertIncludes(sidebarSource, "language: language", "Sidebar localization must resolve from its observed language");
assertExcludes(sidebarSource, "List(selection:", "Sidebar must not restore the saturated system selection block");
assertExcludes(sidebarSource, ".accentColor(", "Sidebar must not restore the soft-deprecated accent override");
assertIncludes(sidebarSource, "Button(action: action)", "Every custom navigation row must retain native button semantics");
assertIncludes(sidebarSource, ".listRowInsets(\n                    EdgeInsets()", "Sidebar navigation buttons must occupy the full list-row width");
assert(count(sidebarSource, ".frame(maxWidth: .infinity, alignment: .leading)") >= 2, "Sidebar navigation labels and buttons must both occupy the complete row width");
assertIncludes(sidebarSource, ".contentShape(.interaction, Rectangle())", "Sidebar navigation must make trailing row whitespace clickable");
assertIncludes(sidebarSource, ".focused(focusedDestination, equals: destination)", "Sidebar rows must expose native keyboard focus");
assertIncludes(sidebarSource, ".onMoveCommand(perform: onMove)", "Sidebar rows must support directional keyboard navigation");
assertExcludes(sidebarSource, "defaultMinListRowHeight", "Sidebar height must remain content-driven rather than globally fixed");
assertIncludes(sidebarSource, ".fill(MicaTheme.accent.opacity(0.14))", "Selected navigation must use the MicaTheme accent-tinted surface");
assertIncludes(sidebarSource, ".accessibilityAddTraits(isSelected ? .isSelected : [])", "Custom navigation must expose selection to accessibility");
assertExcludes(sidebarSource, ".appSettings", "The Workbench sidebar must not duplicate the native Settings scene");
assertIncludes(controllerSelector, "ForEach(snapshot.items)", "Inline sidebar controller switching must preserve persisted controller order");
assertIncludes(controllerSelector, "onSelectController(item.profile)", "Controller switching must route through the window replacement guard");
assertOrdered(window, ["await Task.yield()", "appModel.selectRouter(router)"], "Guarded controller switching must settle before replacing the live generation");
for (const route of [
  "WorkbenchOverviewView(destination: $destination)",
  "WorkbenchPolicyGroupsView(searchText: searchText)",
  "WorkbenchConnectionsView(",
  "WorkbenchLogsView(searchText: searchText)",
  "WorkbenchRulesView(",
  "WorkbenchSourcesView(searchText: searchText)",
  "WorkbenchControllersView(",
  "WorkbenchConfigurationView()",
  "WorkbenchActionsView(",
  "WorkbenchDiagnosticsView(",
]) {
  assertIncludes(workspaceView, route, `Workspace must route the replacement destination ${route}`);
}
assertExcludes(workspaceView, "WorkbenchSettingsView()", "Workspace routing must not duplicate application Settings");
assertIncludes(
  workspaceView,
  "destination: $destination,\n                    searchText: searchText",
  "Rules and Connections must receive destination navigation and the shared search binding",
);
assertIncludes(workspaceView, ".searchable(", "Searchable destinations must share the native toolbar search field");
assertIncludes(chrome, ".safeAreaInset(edge: .bottom", "Workbench must keep a fixed bottom status bar");
assertIncludes(statusBar, "struct WorkbenchStatusBar", "Workbench must expose the replacement status bar");
assert(count(workbenchCode, "MicaHairlineSeparator()") >= 2, "Workbench command and status chrome must share the Mica Ops hairline separator");
assertIncludes(statusBar, "struct WorkbenchOperationOutcomePresentation", "Completed operations must retain a durable presentation projection");
assertIncludes(statusBar, "activityIdentity(status:", "Completed operations must share the stable bottom status surface");
assertExcludes(statusBar, "WorkbenchOperationOutcomeBar", "Operation outcomes must not add a second stacked bottom bar");
assertIncludes(statusBar, ".textSelection(.enabled)", "Status chrome business values must remain selectable");
assertExcludes(dataPages, "setVisibleSessionDestination", "Only the window root may own live-domain visibility");
assertIncludes(chrome, "registerLiveSessionWindowDemand(", "Each window must register a stable live-domain demand");
assertIncludes(chrome, "updateLiveSessionWindowDemand(", "Each window must update only its own live-domain demand");
assertIncludes(chrome, "unregisterLiveSessionWindowDemand(", "A closing window must unregister only its own live-domain demand");
assertIncludes(window, "MainWindowCloseGuardAttachment(closeGuard:", "Dirty-close protection must bind to the owning SwiftUI window");
assertIncludes(mainWindowCloseGuard, "func attach(to candidate: NSWindow)", "The close guard must attach to an explicit owning window");
assertExcludes(mainWindowCloseGuard, "NSApplication.shared.mainWindow", "A window-local close guard must not select a process-global main window");
assertIncludes(window, ".environment(overviewPreferencesStore)", "Every window must observe the one app-owned Overview preference store");
assertIncludes(window, ".environment(overviewRuntime)", "Every window must own one stable Overview runtime");
assertIncludes(micaApp, "wrappedValue: OverviewPreferencesStore()", "The application must create one global Overview preference authority");
assertIncludes(chrome, "overviewRuntime.liveSessionWindowDemandID", "Live-session demand must remain window-owned after layout removal");
assertExcludes(window, "overviewCoordinator", "Overview preferences must not participate in window draft or dirty-close coordination");
assertIncludes(chrome, "struct WorkbenchRootView", "WorkbenchChrome must own root destination composition");
assertExcludes(chrome, "struct ContentView", "WorkbenchChrome must not absorb window editing coordination");
assertIncludes(window, "struct ContentView", "WorkbenchWindow must own window and editor coordination");
assertIncludes(sidebar, "struct WorkbenchSidebarView", "WorkbenchSidebar must own navigation rendering");
assertIncludes(statusBar, "struct WorkbenchBottomChrome", "WorkbenchStatusBar must own bottom status composition");
assertIncludes(micaCommandFocus, "Binding<WorkbenchDestination>", "App menus must target the focused replacement destination");
assertIncludes(micaApp, "WorkbenchDestination.workbenchTabCases", "View menu must use the replacement destination order");

for (const realTimeline of [
  "OverviewTimelineProjection.trafficSamples(",
  "OverviewTimelineProjection.memorySamples(",
  "OverviewTimelineProjection.connectionSamples(",
  "OverviewProjection.latencyAnomalies(",
  "OverviewProjection.ruleHitSummary(",
  "OverviewProjection.topActiveConnections(",
  "OverviewProjection.networkFactGroups(",
  "ConnectionTopologyBuilder.buildCancellable(",
]) {
  assertIncludes(overviewSource, realTimeline, `Overview must render real projected data through ${realTimeline}`);
}
assertIncludes(dashboard, "OverviewTelemetrySection(", "Overview root must compose the extracted telemetry surface");
assertIncludes(dashboard, "OverviewTopologySection(", "Overview root must compose the extracted topology surface");
assertIncludes(dashboard, "ForEach(visibleOptionalModules)", "Overview must construct only globally enabled optional modules");
assertOrdered(
  dashboard,
  ["OverviewTelemetrySection(", "OverviewTopologySection(", "ForEach(visibleOptionalModules)"],
  "Overview must keep the fixed telemetry, topology, optional-module hierarchy",
);
assertExcludes(dashboard, "struct OverviewTelemetrySection", "Dashboard root must not retain telemetry implementation ownership");
assertExcludes(dashboard, "struct OverviewTopologySection", "Dashboard root must not retain topology view implementation ownership");
assertExcludes(dashboard, "struct OverviewInstrumentRailSection", "Dashboard root must not retain instrument implementation ownership");
assertIncludes(overviewTelemetry, "struct OverviewTelemetrySection", "Telemetry source must own the chart surface");
assertIncludes(overviewTelemetry, "struct OverviewInstrumentRailSection", "Telemetry source must own the instrument rail");
assertIncludes(overviewTopologyView, "struct OverviewTopologySection", "Topology view source must own SwiftUI and Canvas composition");
assert(
  (overviewTelemetry.match(/\bChart(?:\s*\{|\()/g) ?? []).length === 2,
  "Overview must use one reusable traffic chart primitive plus one connection chart primitive",
);
assert(/trafficChart\(\s*\.upload/.test(overviewTelemetry), "Overview must render a dedicated upload chart");
assert(/trafficChart\(\s*\.download/.test(overviewTelemetry), "Overview must render a dedicated download chart");
assert(count(overviewTelemetry, "AreaPlot(") === 3, "Overview live charts must keep upload, download, and connection areas");
assert(count(overviewTelemetry, "LinePlot(") === 3, "Overview live charts must keep upload, download, and connection lines");
assert(count(overviewTelemetry, "PointMark(") === 2, "Overview live chart primitives must expose finite latest-sample marks");
assertIncludes(overviewTelemetry, "OverviewLatestDataMark(", "Latest real samples must use the finite latest-sample mark");
assertIncludes(overviewProjection, "struct OverviewTimelineChartScale", "Overview charts must retain a real-data visible scale");
assertIncludes(overviewTelemetry, ".chartYScale(domain: scale.domain)", "Overview charts must apply their visible real-data scale");
assertIncludes(dashboard, "LazyVStack(alignment: .leading", "Overview below-fold analytics must construct lazily");
assertExcludes(dashboard, "OverviewDashboardRowPacker", "Fixed Overview composition must not retain dashboard row packing");
assertExcludes(dashboard, "min(availableWidth, 1_180)", "Overview charts and topology must use the full padded content width");
assertIncludes(dashboard, ".frame(maxWidth: .infinity, alignment: .topLeading)", "Overview monitoring content must fill the available canvas");
const overviewFlatSection = sourceSection(
  dashboard,
  "struct OverviewFlatSection",
  "private struct OverviewHighlightsSection",
);
const overviewSymbolMark = sourceSection(
  dashboard,
  "struct OverviewSymbolMark",
  "struct OverviewFlatSection",
);
const overviewHighlightsSection = sourceSection(
  dashboard,
  "private struct OverviewHighlightsSection",
  "private struct OverviewSummaryColumn",
);
const overviewNetworkSection = sourceSection(
  dashboard,
  "private struct OverviewNetworkFactsSection",
  "private struct OverviewNetworkFactGroupHeader",
);
const overviewTopologySection = sourceSection(
  overviewTopologyView,
  "struct OverviewTopologySection",
  "private struct OverviewTopologyWorkspace",
);
const overviewTelemetryControls = sourceSection(
  overviewTelemetry,
  "private struct OverviewTelemetryControls",
  "private struct OverviewSessionStateReadout",
);
assertIncludes(overviewSymbolMark, ".symbolRenderingMode(.hierarchical)", "Overview marks must retain refined native symbol layering");
assertIncludes(overviewSymbolMark, "case .section: 34", "Overview section marks must retain prominent geometry");
assertIncludes(overviewSymbolMark, "case .metric: 28", "Overview metric marks must retain legible geometry");
assertIncludes(overviewFlatSection, "OverviewSymbolMark(", "Overview sections must use the dedicated native symbol mark");
assertIncludes(overviewFlatSection, "size: .section", "Overview section marks must remain visually prominent");
assertIncludes(overviewFlatSection, ".micaThemeFont(.title3)", "Overview section titles must anchor the monitoring hierarchy");
assertIncludes(overviewFlatSection, "tint: Color = MicaTheme.textSecondary", "Overview category marks must default to the neutral monochrome tint");
assertExcludes(overviewHighlightsSection, "tint: MicaStyle.signalViolet", "Overview category marks must not borrow the debug tint");
assertExcludes(overviewNetworkSection, "tint: MicaStyle.signalMint", "Overview category marks must not borrow the healthy-state tint");
assertExcludes(overviewTopologySection, "tint: MicaStyle.signalViolet", "Topology category chrome must not borrow the debug tint");
assertIncludes(overviewTopologySection, "OverviewTopologyHeaderControls(", "Topology commands must share the section heading row");
assertIncludes(overviewTelemetryControls, "} else if snapshot.isPinned {", "Only a pinned chart sample may change the global chart state to selected");
assertExcludes(overviewTelemetryControls, "snapshot.selectedDate != nil", "Transient chart hover must not change header chrome state");
assertIncludes(overviewTelemetry, "struct OverviewInstrumentRailSection", "Overview must use one unified instrument rail");
assertIncludes(overviewTelemetry, "appModel.trafficTimeline.samples.last", "Overview current-rate readouts must consume received live samples");
assertExcludes(overviewTelemetry, "connectionsCatalog.traffic.upload", "Overview must not label cumulative connection upload totals as a live rate");
assertExcludes(overviewTelemetry, "connectionsCatalog.traffic.download", "Overview must not label cumulative connection download totals as a live rate");
assertIncludes(overviewTelemetry, "struct OverviewTelemetryPanel", "Overview must use one repeated metric-panel primitive for its three primary charts");
assertIncludes(overviewTelemetry, ".micaPanel(", "Overview telemetry must use flat Mica Ops instrument panels");
assertIncludes(dashboard, ".micaPanel(", "Optional Overview modules must use flat Mica Ops panels");
assertExcludes(overviewSource, "TimelineView", "Overview must not keep an idle animation clock alive");
assertExcludes(overviewSource, ".glassEffect", "Overview content surfaces must not apply Liquid Glass");
assertExcludes(overviewSource, "GlassEffectContainer", "Overview content surfaces must not create glass containers");
assertIncludes(overviewTelemetry, "availableWidth >= 960", "Overview charts must use a three-column wide layout");
assertIncludes(overviewTelemetry, "availableWidth >= 700", "Overview charts must use a two-column medium layout");
assertIncludes(overviewTelemetry, "private var plotHeight: CGFloat", "Overview plot height must follow the effective panel width");
assertIncludes(overviewTelemetry, "return min(max(panelWidth * 0.60, 240), 300)", "Overview plots must retain the primary 240-300 point visual range");
assertIncludes(overviewTelemetry, "systemName: \"chart.line.uptrend.xyaxis\"", "Overview telemetry must retain its native chart symbol");
assertIncludes(overviewTelemetry, ".micaThemeFont(.title3)", "Overview telemetry title must use the Mica Ops title role");
assertIncludes(overviewTelemetry, ".micaThemeFont(.dataHero", "Overview metric values must render as SF Mono data-role readouts");
assertIncludes(overviewTelemetry, ".frame(height: plotHeight)", "Every primary Overview plot must use the responsive height");
assertExcludes(overviewSource, "OverviewMemoryBaseChart", "Memory must remain context on the connection chart instead of a fourth plot");
assertIncludes(overviewPreferences, "visibleOptionalModules: Set<OverviewOptionalModuleID> = []", "The default Overview must hide every optional module");
assertIncludes(overviewPreferences, "visibleMetrics: Set<OverviewMetricID> = Set(OverviewMetricID.allCases)", "The default Overview must keep all primary telemetry visible");
assertExcludes(overviewSource, "OverviewSessionHeader", "Overview must not duplicate selected-controller session chrome");
assertExcludes(overviewSource, "OverviewMetricModule", "Overview must not restore four independent KPI cards");
for (const removedSparkline of [
  "OverviewTrafficSparkline",
  "OverviewMemorySparkline",
  "OverviewCategorySparkline",
]) {
  assertExcludes(overviewSource, removedSparkline, `Overview KPI sparklines must stay removed: ${removedSparkline}`);
}
const overviewRoot = sourceSection(
  dashboard,
  "struct WorkbenchOverviewView",
  "private struct OverviewAvailabilityRegion",
);
assertExcludes(overviewRoot, "WorkbenchCommandBar", "Overview must not repeat controller identity in a command bar");
assertIncludes(dashboard, 'guard value > 0 else { return "0 B" }', "Overview zero-byte formatting must be locale independent");
assertIncludes(dashboard, "struct OverviewNetworkFactsSection", "Overview must keep complete network information");
assertIncludes(dashboard, "OverviewProjection.networkFactGroups(", "Network information must use grouped definition lists");
assertIncludes(dashboard, "GridItem(.adaptive(minimum: 320)", "Network groups must adapt without becoming a full-width field wall");
assertIncludes(dashboard, "OverviewOptionalModuleID.allCases.filter(", "Optional modules must stay in one fixed declaration order");
assertIncludes(overviewPreferences, "struct OverviewPreferences", "Overview must expose one compact global preference value");
assertIncludes(overviewPreferences, "final class OverviewPreferencesStore", "Overview must expose one app-owned preference authority");
assertIncludes(overviewPreferences, 'static let schema = "mica.overview.fixed-core.v1"', "Overview persistence must reject superseded layout payloads by schema");
assertIncludes(overviewPreferences, 'static let defaultPersistenceKey = "overview.dashboard.layout.v1"', "Overview must reset the old v1 payload in place");
assertIncludes(overviewPreferences, "guard normalized != preferences else { return }", "Overview preference writes must be deduplicated");
assertExcludes(overviewPreferences, "controllerID", "Overview preferences must be global rather than controller-specific");
for (const removedLayoutModel of [
  "OverviewDashboardLayout",
  "OverviewDashboardPreset",
  "OverviewDashboardWindowCoordinator",
  "OverviewDashboardLayoutStore",
  "OverviewDashboardRowPacker",
  "OverviewDashboardSpanLayout",
  "OverviewDashboardModuleRuntimeRegistry",
]) {
  assertExcludes(overviewSource, removedLayoutModel, `Superseded Overview layout compatibility must stay deleted: ${removedLayoutModel}`);
}
assertIncludes(overviewEditor, "struct OverviewPreferencesBar", "Overview preferences must use the inline immediate control bar");
assertIncludes(overviewEditor, "ForEach(OverviewMetricID.allCases)", "Overview preferences must control visible primary metrics");
assertIncludes(overviewEditor, "ForEach(OverviewOptionalModuleID.allCases)", "Overview preferences must control optional visibility");
assertIncludes(overviewEditor, "store.setTimelineWindow", "Overview preferences must own one global timeline choice");
assertIncludes(overviewEditor, "store.reset()", "Overview preferences must expose one clean reset");
for (const removedEditorBehavior of [
  "UndoManager",
  "DropDelegate",
  ".dropDestination",
  "coordinator.commit",
  "coordinator.cancel",
]) {
  assertExcludes(overviewEditor, removedEditorBehavior, `Overview preferences must not retain layout editing behavior: ${removedEditorBehavior}`);
}
assertIncludes(overviewWindowRuntime, "final class OverviewRuntimeRegistry", "Overview must preserve expensive telemetry and topology runtimes per live generation");
assertIncludes(overviewWindowRuntime, "let liveSessionWindowDemandID", "Each Overview window must retain stable live-session demand identity");
assertIncludes(overviewWindowRuntime, "let registry = OverviewRuntimeRegistry()", "Each Overview window must retain one runtime registry");
assertIncludes(overviewTelemetry, "state.label(language: language)", "Telemetry must expose live or stale session state");
for (const preferenceRegression of [
  "fixedPreferencesDefaultAndNormalizationAreMinimal",
  "globalPreferencesRoundTripResetAndDeduplicateWrites",
  "supersededLayoutAndWrongSchemaResetWithoutMigration",
  "oneStoreIsSharedWhileEachWindowKeepsStableRuntimeIdentity",
  "policyInspectionResolvesOnlyUniqueExactNames",
  "policyInspectionCacheAndInspectionProjectionExposesCompleteFields",
  "motionProjectionIsStaticForPauseInactiveAndReduceMotion",
]) {
  assertIncludes(
    overviewPreferencesTests,
    preferenceRegression,
    `Overview replacement needs regression coverage for ${preferenceRegression}`,
  );
}
assertExcludes(overviewSource, "selectedConnectionFields", "Overview must not restore the removed raw connection inspector");
assertExcludes(overviewSource, "geoIPCoordinator.lookup", "Overview facts must not start per-connection GeoIP work");
assertExcludes(overviewSource, "NetworkInfoProjector", "Removed overview network abstractions must not return");
for (const interaction of [
  "enum OverviewTimelineWindow",
  "enum OverviewTimelineProjection",
  "struct OverviewTrafficChart",
  "struct OverviewTelemetryPanel",
  "case upload",
  "case download",
  "struct OverviewDateSelectionOverlay",
  "struct OverviewTopologyViewport",
  "enum OverviewTopologyLayoutBuilder",
  ".accessibilityRepresentation",
  "pinnedSelection",
  "SpatialTapGesture()",
]) {
  assertIncludes(overviewSource, interaction, `Overview must retain operational chart interaction through ${interaction}`);
}
assertExcludes(overviewSource, "DragGesture(minimumDistance: 0)", "Overview overlays must not steal vertical scrolling with zero-distance drags");
assertIncludes(overviewTelemetry, "layout: .regular", "Telemetry controls must retain the regular header composition");
assertIncludes(overviewTelemetry, "layout: .compact", "Telemetry controls must retain the compact wrapped composition");
assertIncludes(overviewTelemetry, ".pickerStyle(.segmented)", "Telemetry must retain the explicit 1/3/5 minute mode control");
assertExcludes(overviewTelemetry, "overview.real_samples_count", "Telemetry footers must prioritize user-facing time and memory context over projection counts");
const overviewTrafficChart = sourceSection(
  overviewTelemetry,
  "private struct OverviewTrafficChart",
  "private struct OverviewTrafficBaseChart",
);
const overviewConnectionChart = sourceSection(
  overviewTelemetry,
  "private struct OverviewConnectionChart",
  "private struct OverviewConnectionBaseChart",
);
for (const chart of [overviewTrafficChart, overviewConnectionChart]) {
  assertIncludes(chart, ".accessibilityLabel(", "Every Overview chart must expose a localized purpose");
  assertIncludes(chart, ".accessibilityValue(", "Every Overview chart must expose its current or selected value");
  assertExcludes(chart, ".accessibilityElement(children: .ignore)", "Overview chart summaries must not flatten Swift Charts data accessibility");
}
const overviewTrafficBase = sourceSection(
  overviewTelemetry,
  "private struct OverviewTrafficBaseChart",
  "private struct OverviewConnectionChart",
);
const overviewConnectionBase = sourceSection(
  overviewTelemetry,
  "private struct OverviewConnectionBaseChart",
  "private struct OverviewTrafficSelectionIndicator",
);
for (const baseChart of [overviewTrafficBase, overviewConnectionBase]) {
  assertExcludes(baseChart, ".animation(", "Live chart samples must update without animating the complete plot geometry");
}
for (const topologyContract of [
  "case policyHop(Int)",
  "let paths: [PathRecord]",
  "for (sourceIndex, connection) in connections.enumerated()",
  "let policyHops = reportedChains.dropFirst().reversed()",
  "pathIDs: [ConnectionOccurrenceID]",
  "@concurrent",
]) {
  assertIncludes(connectionTopology, topologyContract, `Complete topology must retain ${topologyContract}`);
}
assertExcludes(connectionTopology, ".prefix(", "Complete topology must not cap active connection paths");
assertExcludes(connectionTopology, "maximumConnection", "Complete topology must not introduce a Top-N admission limit");
// Task 08-20 R6: exactly one opaque linear Canvas per band (base+highlight
// merged); the label layer carries all text.
assertIncludes(overviewTopologyView, "Canvas(\n            opaque: true,", "Topology must render through one opaque Canvas pass");
assert(overviewTopologyView.split("Canvas(").length - 1 === 1, "Topology must render through exactly one Canvas per band (task 08-20 R6)");
const overviewTopologyViewport = sourceSection(
  overviewTopologyView,
  "private struct OverviewTopologyViewport",
  "private struct OverviewTopologyIdleSummary",
);
assertExcludes(overviewTopologyViewport, "ScrollView(.horizontal)", "Complete topology must fit its available width without a nested horizontal viewport");
assertIncludes(overviewTopologyViewport, ".frame(maxWidth: .infinity, alignment: .center)", "Complete topology must center its width-fitted canvas");
assertIncludes(overviewTopologyViewport, ".help(hoverTooltip", "Topology hover must revert to a standard tooltip carrying the truthful route label");
assertExcludes(overviewTopologyViewport, "OverviewTopologyHUDOverlay(", "The node-anchored floating HUD overlay must stay deleted");
assertIncludes(overviewTopologyViewport, "MicaTheme.surface", "Topology must use the flat Mica Ops panel surface");
assertIncludes(overviewTopologyViewport, ".focusable()", "Topology must expose one native keyboard focus surface");
assertIncludes(overviewTopologyViewport, ".onMoveCommand(perform: movePathSelection)", "Topology must support keyboard path stepping");
assertIncludes(overviewTopologyViewport, ".onExitCommand", "Topology must clear local selection with the native exit command");
assertIncludes(overviewTopologyViewport, ".contextMenu", "Topology must mirror selection commands in a native context menu");
assert(
  [...workbenchCode.matchAll(/\.contextMenu/g)].length === 1,
  "Workbench context menus are limited to the topology canvas command mirror",
);
assertExcludes(overviewTopologyView, "OverviewTopologyHUDOverlay", "The node-anchored HUD overlay must stay deleted");
assertExcludes(overviewTopologyView, "OverviewHolographicHUD", "The floating policy HUD surface must stay deleted");
assertExcludes(overviewTopologyView, "OverviewPolicyHUDPlacementResolver", "HUD placement scoring must stay deleted");
assertIncludes(overviewTopologyView, "workspaceStore.selectInspector(", "Topology policy-node selection must open the workspace inspector");
assertIncludes(overviewTopologyView, "revision: appModel.policyGroupCatalogRevision", "Policy inspector selection must resolve against the live catalog revision");
assertIncludes(overviewTopologyView, "catalog: appModel.policyGroupCatalog", "Policy inspector selection must resolve against the real controller catalog");
assertIncludes(overviewTopologyView, "interaction.clearSelection", "Topology must keep its explicit local clear command");
assertIncludes(workspaceView, "WorkbenchPolicyInspectorView(", "The workspace inspector must render the policy detail content");
assertIncludes(overviewPolicyInspection, "stageConnectionNavigation(", "Policy inspector must provide same-window connection navigation");
assertIncludes(overviewPolicyInspection, "destination = .proxies", "Policy inspector must provide same-window proxies navigation");
const overviewTopologyIdleSummary = sourceSection(
  overviewTopologyView,
  "private struct OverviewTopologyIdleSummary",
  "private struct OverviewTopologyPathRows",
);
assertIncludes(overviewPolicyInspection, "snapshot.sections", "Policy inspector must expose the complete organized field composition");
assertIncludes(overviewPolicyInspection, "MicaHairlineSeparator()", "Policy inspector sections must separate with hairlines only");
assertIncludes(overviewPolicyInspection, "field.monospaced ? .dataCaption : .caption", "Policy inspector data values must keep the mono treatment (Mica Ops data role, task 08-17 Phase 7)");
assertIncludes(overviewPolicyInspection, "runtime.interaction.snapshot.highlight.paths", "Policy inspector Open Connections must keep the single-live-path eligibility rule");
assertExcludes(overviewTopologyView, "OverviewTopologySelectionDetail", "The removed fixed selection-detail band must stay deleted");
assertIncludes(overviewTopologyIdleSummary, "overview.connection_count", "Idle topology summary must retain the real connection count");
assertIncludes(overviewTopologyIdleSummary, "overview.topology_unavailable_paths", "Idle topology summary must expose unavailable real paths");
assertExcludes(overviewTopologyIdleSummary, "WorkbenchSymbol(", "Idle topology summary must not repeat the section icon");
assertExcludes(overviewTopologyView, "WorkbenchCommandSummary(", "Topology must not repeat its section identity in a second command summary");
assertIncludes(overviewTopology, "let graphWidth = max(availableWidth.rounded(.down), 1)", "Topology layout must be bounded by the measured module width");
assertIncludes(overviewTopology, "static let columnHeaderHeight: CGFloat = 40", "Topology columns must reserve a legible header geometry");
assertIncludes(overviewTopology, "let topInset = OverviewTopologyLayout.columnHeaderHeight + 12", "Topology must reserve only its column-header inset");
assertIncludes(overviewTopology, "private let nodeGeometryByID", "Topology HUD anchoring must use an O(1) node geometry index");
assertIncludes(overviewTopology, "func nodeGeometry(id: String)", "Topology layout must expose indexed node geometry lookup");
assertExcludes(overviewTopology, "hudObstacles", "Topology layout must not retain HUD obstacle geometry");
assertExcludes(overviewTopology, "selectionDetailHeight", "Topology geometry must not retain a fixed selection-detail band");
for (const policyInspectionContract of [
  "struct OverviewPolicyInspectionIndex",
  "groups.count == 1 ? .group(groups[0]) : .ambiguous",
  "members.count == 1 ? .member(members[0]) : .ambiguous",
  "final class OverviewPolicyInspectionCache",
  "if self.revision == revision",
  "enum OverviewPolicyInspectionProjection",
  "struct WorkbenchPolicyInspectorView",
  "transportCapabilities.map",
  "detailProjection.reportedFields.map",
]) {
  assertIncludes(overviewPolicyInspection, policyInspectionContract, `Policy inspection must retain ${policyInspectionContract}`);
}
const overviewTopologyBandLayers = sourceSection(
  overviewTopologyView,
  "private struct OverviewTopologyBandLayers",
  "private struct OverviewTopologyBaseBand",
);
assertIncludes(overviewTopologyBandLayers, "OverviewTopologyBaseBand(", "Topology bands must retain an isolated base drawing layer");
assertIncludes(overviewTopologyBandLayers, "OverviewTopologyLabelBand(", "Topology bands must retain a dedicated system-text label layer (task 08-20)");
assertIncludes(overviewTopologyBandLayers, "policyStatusRevision == rhs.policyStatusRevision", "Topology band equality must gate on the policy-status revision, never per-tick values (task 08-20 R5)");
assertIncludes(overviewTopologyBandLayers, "OverviewTopologyHitBand(", "Topology bands must retain an isolated hit-testing layer");
assertIncludes(overviewTopologyBandLayers, "allowsMotion: allowsMotion", "Topology bands must gate all motion through the resolved motion state");
assertIncludes(overviewTopologyView, "revision: catalog.structureRevision", "Topology must react to a new real topology revision");
const overviewTopologyBaseBandSection = sourceSection(
  overviewTopologyView,
  "private struct OverviewTopologyBaseBand",
  "private struct OverviewTopologyLabelBand",
);
assertIncludes(overviewTopologyBaseBandSection, "opaque: true", "Topology base canvas must composite opaquely (task 08-20 R6)");
assertIncludes(overviewTopologyBaseBandSection, "colorMode: .linear", "Topology base canvas must composite in linear space (task 08-20 R6)");
assertIncludes(overviewTopologyBaseBandSection, "allowsMotion ? MicaTheme.Motion.stateChange : nil", "Topology highlight motion must be finite and gated on the resolved motion state");
assertIncludes(overviewTopologyBaseBandSection, "value: snapshot.activeSelection", "Topology highlight must react to explicit interaction");
assertExcludes(overviewTopologyView, "OverviewTopologyHighlightBand", "Topology selection highlight must render inside the single base canvas (task 08-20 R6)");
assertExcludes(overviewTopologyView, "TimelineView", "Topology must not keep an idle clock alive");
assertIncludes(overviewTopologyView, "private func minimumFlowHeight(for availableWidth: Int)", "Topology must scale its sparse-flow viewport with the available width");
assertIncludes(overviewTopologyView, "return Int(min(max(scaledHeight, 680), 920).rounded())", "Topology must remain a primary 680-920 point surface when sparse");
for (const sankeyScaleContract of [
  "log10(Double(connectionCount) + 1) * 10",
  "private static func sankeyRibbonPath(",
]) {
  assertIncludes(overviewTopology, sankeyScaleContract, `Topology must retain count-faithful Sankey behavior through ${sankeyScaleContract}`);
}
for (const sankeyGeometryContract of [
  "private static let sankeyNodeWidth: CGFloat = 20",
  "private static let sankeyNodeGap: CGFloat = 8",
  "private static let nodeLabelGap: CGFloat = 8",
  "private static let minimumReadableNodeHeight: CGFloat = 20",
]) {
  assertIncludes(overviewTopology, sankeyGeometryContract, `Topology must retain large-format geometry through ${sankeyGeometryContract}`);
}
assertExcludes(overviewTopologyView, "ScrollView([.horizontal, .vertical])", "Topology must not compete with Overview for vertical scrolling");
assertIncludes(overviewTopologyView, "ForEach(layout.renderBands)", "Complete topology must render through stable vertical bands");
assertIncludes(overviewTopologyView, "struct OverviewTopologyBaseBand", "Topology base drawing must have an isolated invalidation boundary");
assertIncludes(overviewTopologyView, "struct OverviewTopologyLabelBand", "Topology labels must render in a dedicated system-text layer (task 08-20 R3/R7)");
assertExcludes(overviewTopologyView, "snapshot.activeSelection == nil ? 0 : 0.34", "Topology must not dim the graph through a full-size overlay (task 08-20 R6)");
assertIncludes(overviewTopologyView, "struct OverviewTopologyHitBand", "Topology hit testing must have an isolated invalidation boundary");
assertIncludes(overviewTopologyView, "stageConnectionNavigation(", "Topology paths must open the matching connection in the same window");
assertIncludes(overviewTopologyView, "runtime.interaction.snapshot.isHovering", "Topology hover must freeze only the presented snapshot");
assertIncludes(overviewTopologyView, "runtime.isPaused", "Topology must provide explicit presentation pause");
assertIncludes(overviewTopologyView, "runtime.isExpanded", "Topology must provide same-window expansion");
assertIncludes(overviewTopology, "let isPinned: Bool", "Topology interaction snapshots must distinguish hover from pinned selection");
assertIncludes(overviewTopology, "func clearSelection()", "Topology interaction must expose an explicit local clear command");
assertIncludes(overviewTopology, "func movePathSelection(", "Topology interaction must support bounded path stepping");
assertIncludes(overviewTopologyView, ".accessibilityAddTraits(isPinned ? .isSelected : [])", "Topology paths must expose pinned state to accessibility");
assertIncludes(overviewTopologyView, "Text(verbatim: node.node.name)", "Topology labels must consume the complete reported node name");
assertIncludes(overviewTopologyView, "OverviewTopologyHeaderGeometry.clampedCenter(", "Topology column titles must clamp inside the band at any width (task 08-20 R4)");
assertIncludes(overviewTopologyView, "OverviewTopologyHeaderGeometry.sliceWidth(", "Topology column titles must not overlap neighbor titles (task 08-20 R4)");
assertIncludes(overviewTopologyView, "node.labelRect.midY - band.bounds.minY", "Topology labels must keep the geometry engine's fitted positions");
assertIncludes(overviewTopologyView, "OverviewTopologyRuntime", "Topology node statuses must come from the memoized runtime cache (task 08-20 R5)");
assertExcludes(overviewTopologyView, "displayLabel(", "Topology must not rewrite reported names using fixed character counts");
for (const stateKind of ["kind: .noController", "kind: .loading", "kind: .unsupported", "kind: .empty", "kind: .failed"]) {
  assertIncludes(overviewSource, stateKind, `Overview must distinguish ${stateKind}`);
  assertIncludes(proxies, stateKind, `Proxies must distinguish ${stateKind}`);
}
for (const syntheticSource of ["Timer", "Double.random", "Int.random", "PreviewData", "mockData", "placeholderSamples"]) {
  assertExcludes(code(overviewSource), syntheticSource, `Overview must not synthesize controller data with ${syntheticSource}`);
}
for (const timelineContract of [
  "static let maximumSampleCount = 300",
  "static let retentionDuration: TimeInterval = 5 * 60",
  "mutating func append",
  "mutating func reset",
  "struct ConnectionCountTimeline",
]) {
  assertIncludes(sessionTimelines, timelineContract, `Session timelines must retain ${timelineContract}`);
}
assertIncludes(liveSessionRuntime, "trafficTimeline.append", "Live traffic must feed the actor-owned generation timeline");
assertIncludes(liveSessionRuntime, "memoryTimeline.append", "Live memory must feed the actor-owned generation timeline");
assertIncludes(liveSessionRuntime, "connectionCountTimeline.append", "Real connection frames must feed the actor-owned connection-count timeline");
for (const chartContract of [
  "struct OverviewConnectionBaseChart",
  "AreaPlot(",
  ".chartXScale(domain: dateDomain)",
  "connections: appModel.connectionCountTimeline.samples",
]) {
  assertIncludes(overviewTelemetry, chartContract, `Overview charts must retain Zashboard-aligned real-data interaction through ${chartContract}`);
}
assertIncludes(operationSessionModels, "final class ControllerSessionPresentationState", "SwiftUI session state must use a field-granular observable reference");
assertIncludes(operationSessionModels, "if state != session.state", "Session presentation must guard state publication");
assertIncludes(operationSessionModels, "if runtime != session.runtime", "Session presentation must guard runtime publication independently");
assertIncludes(appModel, "synchronizeControllerSessionPresentation()", "Controller session mutations must synchronize the narrow presentation state");
assertIncludes(appModel, "resetSessionPublicationCoordinator(for: controllerSession)", "New generations must reset publication ownership");
assertExcludes(workbenchCode, "appModel.controllerSession.", "Workbench views must not observe the high-frequency controller session aggregate directly");
assertIncludes(liveSessionPublicationTests, "sessionPresentationIgnoresTimelineOnlyChanges", "Timeline-only updates need a presentation-isolation regression test");
assertIncludes(dashboardSessionModels, "struct ControllerMetadataSnapshot", "Low-frequency controller metadata must be published separately from live dashboard frames");
assertIncludes(appModel, "func synchronizeControllerMetadata()", "Dashboard publication must synchronize controller metadata independently");
assertExcludes(workbenchCode, "appModel.dashboard.", "Workbench views must consume per-domain snapshots instead of the broad dashboard aggregate");
assertIncludes(appModel, "guard next != liveStreamState else { return }", "Live stream state publication must ignore equivalent frames");
assertIncludes(liveSessionRuntime, "timelineSource: .connectionsFrame", "Mihomo connection frames must publish their reported memory samples");
assertIncludes(sessionTimelines, "case memoryEndpoint", "Memory samples must retain endpoint provenance");
assertIncludes(sessionTimelines, "case connectionsFrame", "Memory samples must retain connection-frame provenance");
assertIncludes(sessionTimelines, "case runtimeStatus", "Memory samples must retain runtime-status provenance");
assertIncludes(selectionState, "trafficTimeline.reset()", "Controller changes must reset the traffic timeline");
assertIncludes(selectionState, "memoryTimeline.reset()", "Controller changes must reset the memory timeline");
const geoIPLookup = sourceSection(
  geoIPResolver,
  "    func lookup(\n        ip:",
  "    private func cancelInFlightLookups",
);
assertIncludes(geoIPLookup, "guard cache.generation == generation else {", "Offline GeoIP must reject stale generations before lookup and publication");
assertExcludes(geoIPLookup, "bind(generation:", "A stale GeoIP lookup must never rebind the session cache");

for (const bufferContract of [
  "static let maximumEntryCount = 2_000",
  "static let maximumUTF8Bytes = 8 * 1_024 * 1_024",
  "private var storage: [Slot?]",
  "private var headIndex = 0",
  "private(set) var rawRevision: UInt64 = 0",
  "static let maximumEntryCount = 200",
  "static let maximumAge: TimeInterval = 30 * 60",
]) {
  assertIncludes(sessionBuffers, bufferContract, `Session buffers must retain ${bufferContract}`);
}
assertExcludes(sessionBuffers, ".removeFirst(", "Session buffers must not use front-removing arrays");
assertExcludes(dashboardSessionModels, "controllerLogs", "Observable DashboardSnapshot must not own high-frequency logs");
assertIncludes(liveSession, "ControllerLogEntry(receivedAt: receivedAt, message: log)", "Log ingestion must preserve the transport receipt timestamp");

for (const cadence of [
  "case .logs: .milliseconds(200)",
  "case .traffic: .milliseconds(250)",
  "case .connections: .milliseconds(500)",
  "case .memory: .seconds(1)",
]) {
  assertIncludes(liveSessionRefreshModels, cadence, `Live publication must retain cadence ${cadence}`);
}
for (const visibility of [
  "case (.overview, .traffic), (.overview, .connections), (.overview, .memory):",
  "case (.connections, .connections), (.logs, .logs):",
  "scheduledTokens[domain] == nil",
]) {
  assertIncludes(liveSessionRefreshModels, visibility, `Live publication must retain visibility contract ${visibility}`);
}
assertIncludes(liveSession, "func leaveLiveSession(reason: LiveSessionEndReason = .sessionEnd)", "Session ending must record an explicit reason");
assertIncludes(liveSession, "clearOperationalSessionPresentation(endedControllerID:", "Explicit session end must clear all operational presentation");
assertIncludes(operationSessionModels, "state = .staleReconnecting(message)", "Reconnect must retain the committed snapshot as read-only stale data");
assertIncludes(operationSessionModels, "mutating func commitBaseline(at date: Date)", "A replacement snapshot must commit through one baseline boundary");
assertIncludes(liveSessionRefreshModels, "case .staleReconnecting", "Stale reconnecting sessions must reject live commands");

for (const proxyContract of [
  "struct ProxyLatencyScale",
  "struct ProxyGroupCatalogIndex",
  "struct ProxyActiveGroupIndex",
  "enum ProxyWorkspaceProjection",
  "enum ProxyProjection",
  "static func arrangedGroups(",
  "static func activeGroupIndex(",
  "static func memberMutationTarget(",
  "peers + globalGroups",
  "next.openGroupIDs = groups.map(\\.id).filter(requested.contains)",
  "next.groupFilters = workspace.groupFilters.filter",
  "next.selectedGroupMemberIDs = selectedGroupMemberIDs",
  "static func closingInspector(",
]) {
  assertIncludes(proxies, proxyContract, `Proxy replacement must retain ${proxyContract}`);
}
for (const rootContract of [
  "struct WorkbenchPolicyGroupsView",
  "ProxyPolicyGroupPanel(",
  "@State private var projectionCache",
  "@State private var expandedProjections",
]) {
  assertIncludes(proxyRoot, rootContract, `Proxy root must own ${rootContract}`);
}
for (const displacedRootContract of [
  "struct ProxyPolicyGroupPanel",
  "final class ProxyCatalogPresentationCoordinator",
  "struct ProxyCatalogProjectionCache",
  "enum ProxyProjection",
]) {
  assertExcludes(proxyRoot, displacedRootContract, `Proxy root must not own ${displacedRootContract}`);
}
for (const panelContract of [
  "struct ProxyPolicyGroupPanel",
  "ProxyLatencyDistributionView",
  "private extension ProxyLatencyDistributionBucket",
]) {
  assertIncludes(proxyPanels, panelContract, `Proxy panels must own ${panelContract}`);
}
for (const displacedPanelContract of [
  "struct WorkbenchPolicyGroupsView",
  "final class ProxyCatalogPresentationCoordinator",
  "enum ProxyProjection",
]) {
  assertExcludes(proxyPanels, displacedPanelContract, `Proxy panels must not own ${displacedPanelContract}`);
}
for (const interactionContract of [
  "struct ProxyCatalogRevision",
  "final class ProxyCatalogPresentationCoordinator",
  "final class ProxyScrollInteractionTracker",
  "func proxyScrollInteraction(",
  "struct ProxyCatalogPresentationScheduler",
]) {
  assertIncludes(proxyInteraction, interactionContract, `Proxy interaction must own ${interactionContract}`);
}
for (const displacedInteractionContract of [
  "struct WorkbenchPolicyGroupsView",
  "struct ProxyCatalogProjectionCache",
  "enum ProxyProjection",
]) {
  assertExcludes(proxyInteraction, displacedInteractionContract, `Proxy interaction must not own ${displacedInteractionContract}`);
}
for (const presentationContract of [
  "struct ProxySessionPresentation",
  "struct ProxyOperationActivity",
  "struct ProxyCatalogProjectionCache",
  "enum ProxyWorkspaceProjection",
  "enum ProxyProjection",
]) {
  assertIncludes(proxyPresentation, presentationContract, `Proxy presentation must own ${presentationContract}`);
}
for (const displacedPresentationContract of [
  "struct WorkbenchPolicyGroupsView",
  "final class ProxyCatalogPresentationCoordinator",
  "import SwiftUI",
  "MicaDesignTokens",
  "ViewModifier",
]) {
  assertExcludes(proxyPresentation, displacedPresentationContract, `Proxy presentation must not own ${displacedPresentationContract}`);
}
for (const supersededProxyType of [
  "private struct ProxyCompactGroupDirectoryHeader: View",
  "private struct ProxyGroupDirectory: View",
  "private struct ProxyGroupDirectoryRow: View",
  "private struct ProxyNodeWorkspace: View",
  "private struct ProxyOpenPathRibbon: View",
  "private struct ProxyOpenPathRibbonItem: View",
  "private struct ProxyActiveGroupFocusRail: View",
  "private struct ProxyNodeList: View",
  "private struct ProxyNodeRow: View",
  "private struct ProxyNodeInspector: View",
  "private struct ProxyNodeDetailSections: View",
  "private struct ProxyNodeVerbatimDetailField: View",
  "enum ProxyWorkspaceLayoutMode",
  "struct ProxyMasterDetailMetrics",
  "struct ProxyOpenPathRibbonProjection",
]) {
  assertExcludes(proxies, supersededProxyType, `Proxy source must remove superseded ${supersededProxyType}`);
}
assertExcludes(sourceSection(proxyPresentation, "enum ProxyProjection"), ".sorted", "Proxy presentation must preserve controller-reported order");
assertExcludes(sourceSection(proxyPresentation, "enum ProxyProjection"), "ranked", "GLOBAL options must not rank or reorder peer groups");
assertExcludes(sourceSection(proxyPresentation, "enum ProxyProjection"), "globalGroups.first?.group.options", "GLOBAL options must not drive presentation order");
assertExcludes(dashboardSessionModels, "stabilizedPolicyGroups", "Policy refreshes must adopt the controller's latest reported order instead of merging an earlier order");
for (const mihomoConfigurationOrderContract of [
  "mihomoPolicyGroupsInConfigurationOrder(",
  'groups.filter { $0.name == "GLOBAL" }',
  "for name in global.all where consumedNames.insert(name).inserted",
  "return orderedPeers + globalGroups",
]) {
  assertIncludes(dashboardSessionModels, mihomoConfigurationOrderContract, `Mihomo policy groups must retain ${mihomoConfigurationOrderContract}`);
}
const proxyRootContent = sourceSection(proxyRoot, "private var content:", "private var emptyState:");
assertIncludes(proxyRootContent, "LazyVStack", "Policy groups must render as one source-ordered vertical workspace");
assertExcludes(proxyRootContent, "ScrollView(.horizontal)", "Policy groups must not force a horizontal canvas");
assertIncludes(proxyPanels, "struct ProxyPolicyGroupPanel", "Policy groups must use the redesigned expandable panel");
assertIncludes(proxyPanels, "ProxyLatencyDistributionView", "Collapsed groups must retain a real latency distribution preview");
assertIncludes(proxyPanels, ".adaptive(minimum: 340, maximum: 460)", "Expanded groups must keep node cells readable in a three/two/one-column grid");
assertIncludes(proxyPanels, "Button(action: onSelect)", "The full node tile body must switch or inspect the selected node");
assertIncludes(proxyPanels, "workspaceStore.selectInspector(", "Node inspection must route to the workspace inspector");
assertIncludes(proxyPanels, ".proxyNode(", "Node tiles must select the proxy-node inspector destination");
assertExcludes(proxyPanels, "ProxyPolicyNodeInlineDetails", "Node details must render in the workspace inspector, not an inline shelf");
assertIncludes(proxyPanels, "@State private var isHovered", "Node cells must provide a restrained pointer-hover treatment");
assertExcludes(proxyPanels, "ProxyNodeFactGrid", "Selected node details must not regress to the old field grid");
assertIncludes(proxyPresentation, "updateExpandedGroups(groupIDs:", "Only expanded policy groups may materialize node indexes");
assertIncludes(proxyPresentation, "expandedGroupIndexes", "Expanded policy groups must retain independent cached indexes");
assertIncludes(proxyRoot, "currentWorkspace.groupFilters[groupID]", "Each expanded group must retain an independent node filter");
assertIncludes(proxyPresentation, "group.usageRank(for: member.name)", "SMART labels must come from controller-reported ranks");
assertIncludes(proxyPresentation, "ProxyProjection.groupSearchText(", "Group search must include reported member names and metadata");
assertIncludes(proxyPresentation, "canSelect: selectionActionAvailable && group.selectable", "Read-only policy groups must disable node switching without hiding members");
assertIncludes(proxyPresentation, "struct ProxyMemberDetailProjection", "Proxy details must use a typed presentation projection");
for (const proxyDetail of ["let alive: Bool?", "let fixed: String?", "let latestHistoryDelay: Int?", "let latestHistoryTime: String?"]) {
  assertIncludes(proxyPresentation, proxyDetail, `Proxy details must retain ${proxyDetail}`);
}
assertIncludes(dashboardSessionModels, "let transportCapabilities: [ProxyTransportCapabilityState]", "Proxy node projection must retain reported transport states");
assertIncludes(dashboardSessionModels, "let reportedMetadata: [String: MihomoJSONValue]", "Proxy node projection must separate additional controller fields from known fields");
assertIncludes(dashboardSessionModels, '"name", "type", "now", "all", "alive"', "Proxy search metadata must exclude duplicated group selection and member arrays");
for (const reportedFieldContract of [
  "struct ProxyReportedMetadataField",
  "let reportedFields: [ProxyReportedMetadataField]",
  ".sorted { $0.key < $1.key }",
  "reportedFields = ProxyReportedMetadataField.fields(",
]) {
  assertIncludes(proxyPresentation, reportedFieldContract, `Selected proxy detail projection must retain ${reportedFieldContract}`);
}
assertExcludes(proxyPanels, "additionalMetadataText", "Proxy details must not collapse controller fields into one JSON value");
assertExcludes(sourceSection(proxyPresentation, "enum ProxyWorkspaceProjection", "enum ProxyProjection"), "PolicyGroupUsageRank", "Local interaction state must not infer SMART rank");
assertExcludes(proxies, "revealLimit", "Proxy nodes must not return to manual reveal pagination");

for (const stateCase of [
  "case noController", "case loading", "case unsupported", "case empty",
  "case filterEmpty", "case failed(String)", "case content(staleMessage: String?)",
]) {
  assertIncludes(dataPages, stateCase, `Data pages must distinguish ${stateCase}`);
}
for (const projection of [
  "enum WorkbenchConnectionProjection",
  "enum WorkbenchRuleProjection",
  "enum WorkbenchSourceProjection",
  "enum WorkbenchLogProjection",
]) {
  assertIncludes(dataPages, projection, `Data pages must expose pure replacement ${projection}`);
}
for (const browserContract of [
  "struct WorkbenchDataBrowserScaffold",
  "struct WorkbenchDataResponsive",
  "func micaWorkbenchTable(",
  "static let height: CGFloat = 40",
  "Table(rows, selection:",
  "WorkbenchDataSelection.reconciled(",
]) {
  assertIncludes(dataPages, browserContract, `Data browsers must retain ${browserContract}`);
}
assertIncludes(dataInteraction, "final class WorkbenchDataInteractionCoordinator", "Data interaction must own scroll and evaluation coordination");
assertIncludes(dataPresentation, "enum WorkbenchDataState", "Data presentation must own controller-neutral state projection");
assertIncludes(dataShared, "struct WorkbenchDataBrowserScaffold", "Data shared UI must own browser composition");
for (const purePresentationSource of [
  dataPresentation,
  connectionsPresentation,
  connectionCache,
  logPresentation,
  rulePresentation,
  sourcePresentation,
]) {
  assertExcludes(purePresentationSource, "import SwiftUI", "Pure data presentation and cache sources must not depend on SwiftUI");
}
for (const file of dataBrowserTableFiles) {
  assert(
    (code(read(file)).match(/\bTable\(/g) ?? []).length === 1,
    `${file} must construct exactly one native Table`,
  );
}
assertIncludes(dataPages, ".dataTableEvaluation", "Data Table evaluation must remain observable in DEBUG builds");
assertIncludes(dataPages, ".scrollPhase", "Data scroll begin/end must remain observable in DEBUG builds");
assertIncludes(dashboardSessionModels, "struct ConnectionsCatalogChange", "Connections must publish typed structural and metric changes");
assertIncludes(dashboardSessionModels, "var changedMetricIndices: [Int]?", "Connections must carry keyed metric positions");
assertIncludes(liveSessionRuntime, "pendingConnectionMetricIndices", "Runtime must coalesce keyed metric changes");
assertIncludes(dashboardSessionModels, "enum LogsCatalogChange", "Logs must publish replacement versus delta changes");
assertIncludes(dashboardSessionModels, "case delta(", "Logs must carry append/drop deltas to presentation");
assert(count(dataPages, "filtered.sorted(using: sortOrder)") === 3, "Only Connections, Rules, and Sources may apply native presentation sorting");
const logProjection = sourceSection(logPresentation, "enum WorkbenchLogProjection", "struct WorkbenchLogProjectionCache");
assertExcludes(logProjection, ".sorted", "Logs must preserve incoming order");
assertIncludes(logProjection, "return entries.map", "Log rows must retain incoming controller order");
const logTableSource = sourceSection(logsRoot, "private var logStream", "private func rebuildRows");
for (const logColumnContract of [
  '"traffic.log_received_time"',
  '"traffic.log_level"',
  '"traffic.log_type"',
  '"traffic.log_payload"',
]) {
  assertIncludes(logTableSource, logColumnContract, `Logs must retain the explicit event column ${logColumnContract}`);
}
const ruleTableSource = sourceSection(rulesRoot, "private var ruleTable", "private func rebuildRows");
assertIncludes(ruleTableSource, "ruleStateCell(row)", "Rules must combine status and mutation into one scan column");
assertIncludes(ruleTableSource, "ruleCompactSummary(row)", "Rules must retain a compact composite summary");
assertIncludes(ruleTableSource, "ruleStackedRow(row)", "Rules must collapse to one complete stacked column");
assertIncludes(ruleTableSource, "private func ruleStateLabel", "Rules must use a quiet dot-and-text state treatment");
for (const ruleColumnContract of [
  '"dashboard.col_index"',
  '"dashboard.col_type"',
  '"dashboard.col_payload"',
  '"dashboard.col_proxy"',
  '"traffic.rule_section_statistics"',
  '"dashboard.col_status"',
]) {
  assertIncludes(ruleTableSource, ruleColumnContract, `Rules must retain the explicit decision column ${ruleColumnContract}`);
}
assertExcludes(ruleTableSource, 'TableColumn(MicaStrings.localizedKey("traffic.action"', "Rules must not restore an isolated action-button column");
assertExcludes(ruleTableSource, "WorkbenchStatusBadge(", "Rule scan rows must not render type or state as boxed badges");
for (const rulePathContract of [
  "enum WorkbenchRulePolicyTargetResolver",
  "struct WorkbenchRuleDecisionPathProjection",
  "struct WorkbenchRuleDecisionPathRail",
  "ProxyWorkspaceProjection.opening(",
  "destination = .proxies",
]) {
  assertIncludes(rulesPage, rulePathContract, `Rule decision paths must retain ${rulePathContract}`);
}
for (const connectionNavigationContract of [
  "struct WorkbenchConnectionNavigationDirectory",
  "struct WorkbenchConnectionDecisionPathProjection",
  "struct WorkbenchConnectionDecisionPathRail",
  "func stageRuleNavigation(",
  "func consumeRuleNavigation(",
  "enum WorkbenchRuleNavigationResolver",
  "openMatchingRule(for:",
  "ProxyWorkspaceProjection.opening(",
]) {
  assertIncludes(
    `${workspaceStore}\n${rulesPage}\n${connectionsPage}`,
    connectionNavigationContract,
    `Connection-to-rule and policy navigation must retain ${connectionNavigationContract}`,
  );
}
const sourceTableSource = sourceSection(sourcesRoot, "private var sourceTable", "private func rebuildRows");
assertIncludes(sourceTableSource, "sourceStatus(row)", "Sources must retain a quiet lifecycle state column");
assertExcludes(sourceTableSource, "WorkbenchStatusBadge(", "Source scan rows must not render lifecycle state as a boxed badge");
assertIncludes(sourceDetails, "private var lifecycleReadouts", "Selected sources must expose a compact lifecycle summary");
assertExcludes(connectionsPage, "closeCommand(for:", "Connections must not restore a per-row close command");
assertExcludes(connectionsPage, 'TableColumn(MicaStrings.localizedKey("traffic.action"', "Connections must not restore an isolated action column");
assertIncludes(connectionsPage, "WorkbenchConnectionDecisionPathRail", "Selected connections must expose a focus rail");
for (const pulseContract of [
  "struct WorkbenchConnectionPulseProjection",
  "pulseProjection.applyMetricDeltas",
  "pulseMetricCandidateCount",
  "remainingOwnerCount",
]) {
  assertIncludes(connectionsPage, pulseContract, `Connection pulse projection must retain ${pulseContract}`);
}
for (const decisionPathField of [
  "let origin: String",
  "let inbound: String",
  "let rule: String",
  "let destination: String",
]) {
  assertIncludes(connectionsPage, decisionPathField, `Connection decision paths must retain ${decisionPathField}`);
}
assertIncludes(connectionsPage, "struct WorkbenchConnectionAdditionalField", "Connection details must retain typed additional fields");
assertIncludes(connectionsPage, "WorkbenchConnectionAdditionalFieldList", "Connection details must render additional fields structurally");
assertExcludes(connectionsPage, "WorkbenchDataFormat.json(row.connection", "Connection details must not collapse additional fields into machine JSON");
assertExcludes(connectionsPage, '"/connections"', "Connections UI must not expose controller API paths");
assertExcludes(sourcesRoot, "sourceActions(_", "Sources must not restore per-row action commands");
assertExcludes(sourcesRoot, 'TableColumn(MicaStrings.localizedKey("traffic.action"', "Sources must not restore an isolated action column");
assertIncludes(sourceDetails, "struct WorkbenchSourceFocusRail", "Selected sources must expose a lifecycle focus rail");
assertExcludes(sourceDetails, "traffic.source_section_actions", "Source inspectors must not duplicate focus-rail actions");
assertIncludes(connectionsPresentation, "enum WorkbenchConnectionProjection", "Connections presentation must own stable row projection");
assertIncludes(connectionCache, "struct WorkbenchConnectionPulseProjection", "Connection cache must own high-frequency pulse projection");
assertIncludes(connectionsRoot, "struct WorkbenchConnectionsView", "Connections root must own the native Table workspace");
assertIncludes(connectionPulseView, "struct WorkbenchConnectionPulseStrip", "Connection pulse view must own pulse rendering");
assertIncludes(connectionDetails, "struct WorkbenchConnectionInspector", "Connection details must own selection-driven inspection");
assertIncludes(logPresentation, "struct WorkbenchLogProjectionCache", "Log presentation must own its stable row cache");
assertIncludes(logsRoot, "struct WorkbenchLogsView", "Logs root must own Table rendering and follow interaction");
assertIncludes(rulePresentation, "struct WorkbenchRuleProjectionCache", "Rule presentation must own its stable row cache");
assertIncludes(ruleDetails, "struct WorkbenchRuleInspector", "Rule details must own selection-driven inspection");
assertIncludes(sourcePresentation, "struct WorkbenchSourceProjectionCache", "Source presentation must own its stable row cache");
assertIncludes(sourceDetails, "struct WorkbenchSourceInspector", "Source details must own selection-driven inspection");
assertIncludes(dataPages, "struct WorkbenchLogProjectionCache", "Logs must cache source and filtered row projections");
assertIncludes(dataPages, "replaceRowsByStableID", "Log updates must reuse stable-ID row projections when possible");
assertIncludes(dataPages, "static let minimumInterval: TimeInterval = 0.2", "Follow Newest must be capped at five hertz");
assertIncludes(dataPages, "followNewest", "Logs must expose explicit Follow Newest state");
assertIncludes(dataPages, ".onScrollPhaseChange", "Follow Newest must react to real user scrolling");
assertIncludes(dataPages, "struct WorkbenchRuleConnectionIndexCache", "Rules must cache connection matching by revision");
assertIncludes(dataPages, "dashboardSessionControls.closedConnectionRecords", "Connections must keep retained closed history separate from active rows");
assertIncludes(dataPages, "appModel.clearClosedConnections()", "Closed history must expose an explicit clear command");
assertIncludes(chrome, ".inspector(isPresented:", "Data-page details must remain in-window inspectors");
assertIncludes(dataPages, ".textSelection(.enabled)", "Business values must remain selectable");
assertIncludes(dataPages, "metadata?.remoteDestination", "Connection projection must preserve complete remote destinations");
assertIncludes(dataPages, "connection.id", "Connection projection must preserve complete connection IDs");
assertIncludes(dataPages, "rule.payload", "Rule projection must preserve complete payloads");
assertIncludes(dataPages, "source.name", "Source projection must preserve provider names");
assertIncludes(dataPages, "entry.message.payload", "Log projection must preserve controller payloads");
for (const workspaceContract of [
  "func activateSession(",
  "func updateScrollAnchor(",
  "func scrollAnchorID(",
  "scrollAnchorGenerations",
  "private actor WorkbenchWorkspacePersistenceSink",
  "case encoded(data: Data?, encodingDuration: Duration)",
]) {
  assertIncludes(workspaceStore, workspaceContract, `Workspace scrolling must retain ${workspaceContract}`);
}
assertIncludes(dataPages, "static func closeGroups(", "Connections must expose deterministic real-data close groups");
assertIncludes(dataPages, "for row in rows where row.connection.id.dataNonEmpty != nil", "Connection close groups must reject rows without controller IDs");
assertIncludes(dataPages, "case group(String)", "Connection destructive intent must support same-window group termination");
assertIncludes(dataPages, "appModel.closeConnectionGroup", "Grouped termination must use the typed AppModel operation");
const connectionCloseIntent = sourceSection(
  dataPages,
  "struct WorkbenchConnectionCloseIntent",
  "struct WorkbenchConnectionsView",
);
for (const identityField of ["let routerID: RouterProfile.ID", "let generation: UUID", "func isCurrent(", "func reconciled("]) {
  assertIncludes(connectionCloseIntent, identityField, `Connection close confirmation must retain ${identityField}`);
}

for (const providerContract of [
  "source.testURL",
  "source.subscriptionInfoText",
  "appModel.updateAllProviders()",
  "struct WorkbenchProviderUpdateAllProgressView",
]) {
  assertIncludes(dataPages, providerContract, `Sources must retain ${providerContract}`);
}
assertIncludes(dashboardSessionModels, "var testURL: String?", "Provider projection must retain the reported test URL");
assertIncludes(dashboardSessionModels, "var subscriptionInfo: MihomoJSONValue?", "Provider projection must retain subscription metadata");
assertIncludes(dashboardSessionModels, "struct ProviderUpdateAllProgress", "Provider update-all progress must be typed");
assertIncludes(operationSessionModels, "case providerUpdateAll", "Provider update-all must be retained in command history");
const providerUpdateAll = sourceSection(appModel, "    func updateAllProviders()", "    func updateProxyProvider");
for (const providerOperation of [
  "routingCatalog.providers.filter(\\.updatable)",
  "for (index, provider) in providers.enumerated()",
  "try await providerUpdateOperation(router, secret, provider)",
  "let providerSnapshots = await providerSnapshotOperation(router, secret)",
  "isCurrentSession(routerID: router.id, generation: generation)",
]) {
  assertIncludes(providerUpdateAll, providerOperation, `Provider update-all must retain ${providerOperation}`);
}
assert(count(providerUpdateAll, "providerSnapshotOperation(router, secret)") === 1, "Provider update-all must refresh snapshots exactly once");
assertIncludes(appModelEndpointChecks, "entry.action == .providerUpdate || entry.action == .providerUpdateAll", "Diagnostics must include individual and batch provider updates");
assertIncludes(appModelEndpointChecks, "if entry.timestamp > currentLatest.timestamp", "Diagnostics must choose the newest provider command record");

const selectNodeOperation = sourceSection(appModel, "    func selectNode(", "    func clearFixedSelection");
assertIncludes(selectNodeOperation, "guard group.selectable else {", "AppModel must reject writes to read-only policy groups");
assertIncludes(selectNodeOperation, 'localized("operation.policy_group_not_selectable")', "Read-only policy groups need an explicit operation outcome");
assertIncludes(selectNodeOperation, "guard group.options.contains(node) else {", "AppModel must reject stale policy members before starting a write");
const closeConnectionOperation = sourceSection(appModel, "    func closeConnection(", "    func closeConnectionGroup(");
assertIncludes(closeConnectionOperation, "connection.id.trimmingCharacters", "Single connection close must reject blank controller IDs");
assertIncludes(closeConnectionOperation, "var didCloseConnection = false", "Single close must distinguish a confirmed write from refresh failure");
assertIncludes(closeConnectionOperation, 'status: .partial', "A confirmed single close with refresh failure must remain partial");
assertIncludes(closeConnectionOperation, 'localized("operation.connection_closed_refresh_failed")', "Single close refresh failures need an explicit partial outcome");
const closeAllConnectionsOperation = sourceSection(appModel, "    func closeAllConnections()", "    func updateAllProviders()");
assertIncludes(closeAllConnectionsOperation, "var didCloseAllConnections = false", "Close-all must distinguish a confirmed write from refresh failure");
assertIncludes(closeAllConnectionsOperation, 'localized("operation.connections_closed_refresh_failed")', "Close-all refresh failures need an explicit partial outcome");
const mihomoCloseConnection = sourceSection(mihomoClient, "    public func closeConnection(id:", "    public func closeAllConnections()");
assertIncludes(mihomoCloseConnection, "id.trimmingCharacters(in: .whitespacesAndNewlines)", "The Mihomo API boundary must reject blank connection IDs");

assertIncludes(sessionControls, "case trace", "Log filtering must retain sing-box trace as a distinct level");
assertIncludes(sessionControls, "controllerType == .singBoxCompatible", "Trace filtering must only be offered for sing-box sessions");
const singBoxLogProjection = sourceSection(
  dashboardSessionModels,
  "extension LogMessage {",
  "struct RuleViewState",
);
assertIncludes(singBoxLogProjection, "case SingBoxLogLevel.trace.rawValue:", "sing-box trace must be projected explicitly");
assertIncludes(singBoxLogProjection, '"trace"', "sing-box trace must not be downgraded to debug");
assertIncludes(dataPages, "ForEach(availableLogLevels)", "Logs must use backend-specific level choices");
assertIncludes(logPresentation, "enum WorkbenchLogSeverity", "Logs must project a stable semantic severity");
assertIncludes(logPresentation, "let severity: WorkbenchLogSeverity", "Log rows must carry projected severity");
assertIncludes(logsRoot, "private func severityRail", "Logs must render a fixed semantic severity rail");
assertExcludes(logsRoot, "WorkbenchStatusBadge(", "Logs must not restore colored severity badges");
assertIncludes(appLanguage, 'case "trace":', "Trace logs must localize through the shared language boundary");

for (const managementSurface of [
  "struct WorkbenchControllersView",
  "struct WorkbenchConfigurationView",
  "struct WorkbenchActionsView",
  "struct WorkbenchDiagnosticsView",
]) {
  assertIncludes(management, managementSurface, `Management replacement must expose ${managementSurface}`);
}
assertExcludes(management, "struct WorkbenchSettingsView", "Settings must only exist in the native Settings scene");
assertExcludes(management, "struct MicaSettingsSceneView", "Native Settings must remain isolated from Workbench management pages");
assertIncludes(settings, "struct MicaSettingsSceneView", "The dedicated Settings source must expose the native Settings scene");
const controllersSource = controllersRoot;
assertIncludes(controllersSource, "List(filteredProfiles, selection: managementSelectionBinding)", "Controllers must use a native virtualized selectable list");
assertIncludes(controllersSource, "selectInspector(.controller(id: id))", "Controller selection must route detail to the workspace inspector (task 08-17 Phase 6A)");
assertIncludes(controllersSource, "struct WorkbenchControllerInspector", "Controller detail must render in the shared workspace inspector");
const controllerRowSource = sourceSection(controllersSource, "private func controllerRow", "private var filteredProfiles");
assertIncludes(controllerRowSource, ".contentShape(Rectangle())", "Controller list rows must expose a full-row selection target");
for (const detailOnlyAction of [
  "appModel.selectRouter(profile)",
  "onEditController(profile)",
  "moveSelection(",
  "requestDelete(profile)",
]) {
  assertExcludes(controllerRowSource, detailOnlyAction, `Controller list rows must stay scan-only and exclude ${detailOnlyAction}`);
}
const controllerActionsSource = sourceSection(
  controllersSource,
  "private func controllerDetailActionButtons(_ profile: RouterProfile) -> some View {",
  "private func lastSuccess(_ profile: RouterProfile) -> some View {",
);
for (const detailAction of [
  "appModel.selectRouter(profile)",
  "onEditController(profile)",
  "moveSelection(.up)",
  "moveSelection(.down)",
  "requestDelete(profile)",
]) {
  assertIncludes(controllerActionsSource, detailAction, `Controller detail must own ${detailAction}`);
}
assert(
  count(controllersSource, "appModel.selectRouter(profile)") === 1,
  "Only the explicit Use command may switch the active controller",
);
assertIncludes(controllerDetailSection, "deleteConfirmation(profile, confirmation: pendingDelete)", "Controller deletion confirmation must stay inline with the selected detail");
assertExcludes(controllersSource, ".safeAreaInset(", "Controller deletion confirmation must not become a detached bottom bar");
const controllerListProjection = sourceSection(controllerPresentation, "enum WorkbenchControllerListProjection", "struct WorkbenchConnectionTestProjection");
assertIncludes(controllerListProjection, "guard !normalizedQuery.isEmpty else { return profiles }", "Empty controller search must preserve persisted order");
assertExcludes(controllerListProjection, ".sorted", "Controllers must never reorder profiles automatically");
assertIncludes(controllersSource, "appModel.selectRouter(profile)", "Only explicit Use may switch the active controller");
assertIncludes(controllersSource, "appModel.moveRouter", "Controller order changes must use the persisted move operation");
assertIncludes(controllersSource, "pendingDelete", "Controller deletion must confirm inline");
assertIncludes(controllersSource, "profile.endpointURL", "Controllers must show the complete endpoint");
assertIncludes(controllerPresentation, "struct WorkbenchControllerDeleteConfirmation", "Controller presentation must own session-bound delete intent");
assertExcludes(controllerPresentation, "import SwiftUI", "Controller presentation must remain independent from SwiftUI");
assertIncludes(controllersRoot, "struct WorkbenchControllersView", "Controllers root must own native management composition");
for (const canvasMetric of [
  "static let formCanvasWidth: CGFloat = 1_040",
  "static let maximumCanvasWidth: CGFloat = 1_180",
]) {
  assertIncludes(management, canvasMetric, `Management pages must retain constrained canvas metric ${canvasMetric}`);
}
assertIncludes(settings, "static let readingWidth: CGFloat = 820", "Native Settings must retain its approved reading width");
assertIncludes(managementShared, "alignment: .topLeading", "Management canvases must remain bounded and leading-anchored in wide windows");
assertIncludes(diagnosticsComponents, "struct WorkbenchDiagnosticsCanvas", "Diagnostics must own one full-width scroll canvas");
assertExcludes(management, "Spacer(minLength: 0)\n\n                Form {", "Management forms must not return to centered spacer framing");
assertIncludes(management, "appModel.updateControllerConfig", "Configuration must use typed AppModel writes");
const configurationSource = configurationPage;
for (const stateKind of ["kind: .noController", "kind: .loading", "kind: .unsupported", "kind: .empty", "kind: .failed"]) {
  assertIncludes(configurationSource, stateKind, `Configuration must distinguish ${stateKind}`);
}
assertExcludes(configurationSource, '"overview.config_mode_options"', "Configuration must not repeat the mode picker as a read-only options row");
assertIncludes(configurationSource, "appModel.capabilityMatrixRows.first", "Tailscale presentation must use the reported capability matrix");
assertIncludes(configurationSource, '$0.id == "tailscale"', "Tailscale presentation must resolve the dedicated capability row");
assertIncludes(configurationSource, "return status != .unavailable", "Unsupported Tailscale controls must remain absent");
assertIncludes(configurationSource, "appModel.singBoxTailscaleStatus != nil", "Reported Tailscale status must remain visible before capability refresh completes");
assertIncludes(configurationSource, "appModel.singBoxTailscaleError != nil", "Reported Tailscale failure must remain visible before capability refresh completes");
assertIncludes(management, "appModel.performDiagnosticsRuntimeOperation", "Actions must use capability-gated AppModel operations");
assertIncludes(actionsPresentation, "input.capabilities.supports(action)", "Actions must honor runtime capabilities");
assertIncludes(actionsRoot, "snapshot?.visibleOperationIDs", "Actions must invalidate confirmations when executable operations disappear");
assertIncludes(actionsRoot, "inlineConfirmation(command)", "Dangerous actions must confirm beside the originating operation");
assertExcludes(actionsRoot, ".safeAreaInset(", "Action confirmation must not become a detached bottom bar");
assertIncludes(actionsPresentation, 'case "memory":', "Actions must classify the memory dispatcher explicitly");
assertIncludes(actionsPresentation, "controllerType == .cmfaCompatible", "CMFA commands must retain their verified subset");
assertExcludes(sourceSection(actionsPresentation, 'case "memory":', 'case "dns-flush":'), ".singBoxCompatible", "sing-box observation memory must not become a Mihomo command");
assertIncludes(actionsPresentation, "WorkbenchControllerTargetScope", "Actions and diagnosis must share factual target scope");
assertIncludes(actionsPresentation, "var hasWorkbenchRuntimeOperations", "Actions must keep runtime-row observation aligned with verified dispatcher families");
const runtimeOperationRowsSource = read("Sources/Mica/App/AppModelDiagnosticsRuntimeOperations.swift");
const actionsRuntimeRowsSource = sourceSection(
  runtimeOperationRowsSource,
  "var actionsRuntimeOperationRows: [DiagnosticsRuntimeOperationRow] {",
  "private var runtimeOperationRows: [DiagnosticsRuntimeOperationRow] {",
);
assertIncludes(actionsRuntimeRowsSource, "hasWorkbenchRuntimeOperations", "Actions runtime rows must be gated by verified dispatcher family");
assertExcludes(actionsRuntimeRowsSource, "diagnosticsRuntimeOperationEvidence", "Actions runtime rows must not observe diagnostic evidence or session runtime");
assertIncludes(runtimeOperationRowsSource, "evidence: \"\"", "Shared runtime command rows must remain evidence-free until Diagnostics enriches them");
assertIncludes(tailscale, "struct WorkbenchSingBoxTailscaleSection", "Tailscale source must own sing-box Tailscale rendering");
assertIncludes(diagnosticsRoot, "appModel.copyDiagnosticsReport", "Diagnostics must retain one credential-safe report command");
assertExcludes(diagnosticsRoot, "appModel.copyEndpointResults", "Diagnostics must not restore a second endpoint-copy command");
assertExcludes(diagnosticsRoot, "appModel.copyCheckResults", "Diagnostics must not restore a second check-result-copy command");
assertIncludes(diagnosticsPresentation, "struct WorkbenchDiagnosticsInput", "Diagnostics must consume one pure typed input");
assertIncludes(diagnosticsPresentation, "struct WorkbenchDiagnosticsSnapshot", "Diagnostics must expose one pure typed snapshot");
assertIncludes(diagnosticsPresentation, "controllerAccessIssue", "Diagnostics must project controller-wide access failures");
assertIncludes(diagnosticsPresentation, "endpointIsExpected", "Diagnostics must suppress unsupported endpoint failures by capability");
assertIncludes(diagnosticsPresentation, "deduplicatedAndSorted", "Diagnostics must deduplicate and prioritize stable issue IDs");
assertIncludes(diagnosticsPresentation, "reconciledSelection", "Diagnostics must reconcile issue selection by stable ID");
assertIncludes(diagnosticsPresentation, "if !isChecking", "Diagnostics checking state must gate provisional failures");
assertIncludes(diagnosticsPresentation, "guard input.lastSuccessAt != nil else { return [] }", "Diagnostics must not claim available areas before the first baseline");
assertIncludes(diagnosticsPresentation, '"diagnostics.evidence_unavailable"', "Diagnostics must replace unsafe evidence with localized fallback copy");
assertIncludes(diagnosticsRoot, "usesSplitLayout: contentWidth >= 900", "Diagnostics must choose master-detail from measured width");
assertIncludes(diagnosticsComponents, "struct WorkbenchDiagnosticsIssueWorkspace", "Diagnostics must own one adaptive issue workspace");
const diagnosticsIssueRowSource = sourceSection(
  diagnosticsComponents,
  "private struct WorkbenchDiagnosticsIssueRow: View {",
  "private struct WorkbenchDiagnosticsIssueDetail: View {",
);
assertIncludes(diagnosticsIssueRowSource, ".accessibilityLabel(", "Diagnostics issue rows must expose an explicit accessible label");
assertIncludes(diagnosticsIssueRowSource, "issue.severity.label", "Diagnostics issue rows must announce severity without relying on color or symbols");
assertIncludes(diagnosticsComponents, "struct WorkbenchDiagnosticsAvailableAreas", "Diagnostics must expose current product areas without a success wall");
assertIncludes(diagnosticsComponents, "struct WorkbenchDiagnosticsTechnicalDetails", "Diagnostics must retain one secondary technical disclosure");
assert(count(diagnosticsPage, "ScrollView {") === 1, "Diagnostics must retain exactly one scroll owner");
assert(count(diagnosticsPage, "DisclosureGroup") === 1, "Diagnostics must retain one native technical disclosure");
assertExcludes(diagnosticsPage, "WorkbenchManagementCanvas", "Diagnostics must not inherit the bounded management reading canvas");
assertExcludes(diagnosticsPage, ".glassEffect", "Diagnostics content must not add custom Liquid Glass");
assertExcludes(diagnosticsPage, "MicaDesignTokens.contentFill", "Diagnostics must remain a flat unframed workspace");
assertExcludes(diagnosticsRoot, "endpointCheckSteps", "Diagnostics must not mirror the endpoint workflow checklist");
assertExcludes(diagnosticsRoot, "checkResultRows", "Diagnostics must not mirror historical check-result tables");
assertExcludes(diagnosticsRoot, "capabilityMatrixRows", "Diagnostics must not mirror the capability matrix");
assertExcludes(diagnosticsRoot, "performDiagnosticsRuntimeOperation", "Diagnostics must not execute remote maintenance commands");
assertIncludes(chrome, "if destination != .diagnostics", "Diagnostics must hide the duplicate toolbar Test command");
assertIncludes(routerEditorDiagnosis, "WorkbenchControllerTargetScope", "Router editor diagnosis must reuse factual target scope");
assertIncludes(routerEditorDiagnosis, "target.loopback_recovery_detail", "Router editor diagnosis must explain loopback targets");
const diagnosticsSource = diagnosticsPage;
assertExcludes(diagnosticsSource, "diagnostics.operation_source_backend_boundary", "Visible diagnosis must not expose backend-boundary terminology");
assertExcludes(diagnosticsPresentation, "import SwiftUI", "Diagnostics presentation must remain independent from SwiftUI");
assertIncludes(diagnosticsRoot, "struct WorkbenchDiagnosticsView", "Diagnostics root must own page composition");
assertIncludes(controllerPresentation, "struct WorkbenchConnectionTestProjection", "Controller connection tests must retain complete typed reports");
assertIncludes(management, "report.steps", "Controller connection reports must expose every reported step");
assertIncludes(management, "Link(destination: authenticationLinkURL)", "Tailscale authentication URLs must be actionable with a native Link");
assertIncludes(management, "WorkbenchSingBoxTailscaleSection", "Configuration must retain in-window sing-box Tailscale state");
assertIncludes(management, "DisclosureGroup", "Tailscale detail must expand in the same window");
assertIncludes(actionsPresentation, ".reloadProfile", "Supported operations must include Surge profile reload");

assertIncludes(surgeProjection, "static func surgeEventLogEntries", "Surge events must project into typed controller log entries");
assertIncludes(surgeProjection, "static func surgeRecentRequestConnections", "Surge recent requests must project into retained closed connections");
assertIncludes(liveSession, "DashboardSnapshot.surgeEventLogEntries", "Surge snapshots must stage event logs in the generation-owned log buffer");
assertIncludes(surgeOperations, "DashboardSnapshot.surgeRecentRequestConnections", "Surge snapshots must publish recent requests");

const settingsSource = settings;
assertIncludes(settingsSource, "@EnvironmentObject private var preferences: AppPreferencesStore", "Settings must use the single persisted preference authority");
assertIncludes(settingsSource, "set: { preferences.language = $0 }", "Language changes must persist immediately");
assertIncludes(settingsSource, "preferences.appearance = $0", "Appearance changes must persist immediately");
assertIncludes(settingsSource, "preferences.fontScale = $0", "Font changes must persist immediately");
assertIncludes(settingsSource, "preferences.globalGroupVisibility = $0", "GLOBAL visibility must share the preference store");
assertIncludes(settingsSource, "WorkbenchPreferenceForm()", "Native Settings must own the preference form");
assertExcludes(settingsSource, "WorkbenchPreferenceHost", "A single Settings scene must not retain obsolete host branching");
assertIncludes(settingsSource, "Form {", "Native Settings must use a native Form");
assertIncludes(settingsSource, ".formStyle(.grouped)", "Native Settings must use grouped form styling");
assertIncludes(settingsSource, ".scrollContentBackground(.hidden)", "Native Settings must share the workbench page background instead of drawing a mismatched form wall");
assertExcludes(settingsSource, ".scrollIndicators(.hidden)", "Native Settings must retain the system on-demand scroll indicator");
assertIncludes(settingsSource, "MicaSettingsMetrics.readingWidth", "Native Settings must retain a centered reading width");
assertExcludes(settingsSource, "preferenceCanvasWidth", "Settings must not return to the old fixed leading-width canvas");
assertExcludes(settingsSource, "preferenceColumnMinimumWidth", "Settings must not return to an unbalanced two-column composition");
assertIncludes(settingsSource, "min(\n                    geometry.size.width,\n                    MicaSettingsMetrics.readingWidth", "Native Settings must cap the form at the approved reading width");
assertIncludes(settingsSource, "availableWidth: availableContentWidth", "Native Settings must resolve field layout from its actual form content width");
assertIncludes(settingsSource, "struct WorkbenchPreferenceRow", "Settings must use a dedicated responsive preference row");
assertIncludes(settingsSource, "WorkbenchPreferenceRow(titleKey, detailKey: detailKey)", "Settings controls must keep visible help while using the preference layout");
assertIncludes(settingsSource, ".frame(alignment: .trailing)", "Regular-width preference controls must align to the trailing edge");
assertIncludes(settingsSource, '"settings.appearance_section"', "Native Settings must use the flat management section hierarchy");
assertIncludes(settingsSource, 'detailKey: "settings.help_language"', "Preference rows must expose their help text in the visible hierarchy");
assertIncludes(settingsSource, "struct WorkbenchPreferenceMenu", "Settings choices must share one compact native menu treatment");
assertIncludes(settingsSource, ".menuStyle(.borderlessButton)", "Settings menus must avoid boxed button chrome");
assertIncludes(settingsSource, ".menuIndicator(.hidden)", "Settings menus must use one restrained disclosure indicator");
assertExcludes(settingsSource, ".pickerStyle(.segmented)", "Settings must not restore rows of boxed segmented choices");
assertExcludes(settingsSource, "LaunchAtLogin", "Native Settings must not add an unsupported launch-at-login preference");
assertExcludes(settingsSource, "Shortcut", "Native Settings must not add a shortcut editor");
assertExcludes(settingsSource, "About", "Native Settings must not add an About pane");
assertExcludes(management, "LabeledContent", "Management fields must not restore the centered system value column");
assertExcludes(management, "formControlMax, alignment: .trailing", "Management form controls must not be pushed to the trailing edge");
assertExcludes(management, "@Environment(\\.dynamicTypeSize)", "Font preference must not select management page layout variants");
const formRowSource = sourceSection(management, "struct WorkbenchFormRow", "struct WorkbenchFormValue");
assertExcludes(formRowSource, "controlAlignment", "The canonical management field row must always lead-align controls");
assertExcludes(formRowSource, "dynamicTypeSize", "Font preference must not rearrange management form rows");
assertIncludes(formRowSource, "widthMode == .compact", "Management form rows must stack only from measured width");
assertIncludes(formRowSource, "alignment: .leading", "The canonical management field row must lead-align its control column");
assertIncludes(formRowSource, "var detailKey: String?", "Management fields must support concise visible descriptions");
assertIncludes(appPreferencesStore, "appearance.applyToApplication()", "Appearance preference must repaint immediately");
assertIncludes(micaApp, "Settings {", "Mica must expose the standard native Settings scene");
assertIncludes(micaApp, "MicaSettingsSceneView()", "The native Settings scene must host Mica preferences");
assert(count(micaApp, ".micaWindowChrome()") >= 2, "Main and native Settings windows must share window chrome styling");
assertIncludes(micaApp, "containerBackground(MicaTheme.canvas, for: .window)", "Window containers must use the shared page fill (Mica Ops canvas, task 08-17 Phase 7)");
assertIncludes(micaApp, ".toolbarBackground(MicaTheme.canvas, for: .windowToolbar)", "Native toolbars must use the shared page fill (Mica Ops canvas, task 08-17 Phase 7)");
assertIncludes(micaApp, ".toolbarBackgroundVisibility(.visible, for: .windowToolbar)", "Native toolbar fill must remain visible in every appearance");
assertIncludes(micaApp, 'CommandMenu(menuLocalized("controller.command_menu"))', "The custom top-level menu must follow the macOS menu language");
assertIncludes(appLanguage, "static var menuBarLanguage: AppLanguage", "Custom menu commands must resolve from the same bundle language as AppKit menus");
assertIncludes(micaApp, ".defaultSize(width: 880, height: 700)", "Native Settings must open at a practical size for larger interface text");
assertIncludes(themeComponents, "content\n                .frame(maxWidth: .infinity, maxHeight: .infinity)\n                .background(MicaTheme.canvas)", "Every page content root must paint the shared page fill");
assertIncludes(dataPages, ".background(MicaTheme.canvas)", "Data browser loading and empty states must use the shared page fill (Mica Ops canvas token, task 08-17 Phase 4C)");
assertExcludes(diagnosticsSource, ".animation(", "Diagnostics must not attach persistent animation to the live issue subtree");
assertIncludes(designSystem, "static let canvas", "Management surfaces must share the Mica Ops canvas token (task 08-17 Phase 7.3)");
assertIncludes(appAppearance, "application.appearance = nsAppearance", "Appearance must update the application");
assertIncludes(appAppearance, "window.appearance = nsAppearance", "Appearance must update existing windows");
assertIncludes(preferenceEnvironment, ".dynamicTypeSize(fontScale.dynamicTypeSize)", "Font scale must use Dynamic Type");
assertExcludes(preferenceEnvironment, ".controlSize(", "Font scale must not change native control geometry");
for (const multiplier of ["0.92", "1.16", "1.32", "func pointSize(for basePointSize: CGFloat)"]) {
  assertIncludes(appFontScale, multiplier, `Font preference must retain visible scale contract ${multiplier}`);
}
for (const size of [".small", ".large", ".xxLarge", ".xxxLarge"]) {
  assertIncludes(appFontScale, size, `Font preference must expose Dynamic Type size ${size}`);
}
for (const languageCase of ["case system", 'case english = "en"', 'case simplifiedChinese = "zh-Hans"']) {
  assertIncludes(appLanguage, languageCase, `Language preference must retain ${languageCase}`);
}
assert(count(micaApp, ".micaScenePreferences(") >= 2, "Main and native Settings scenes must share preference injection");
assertIncludes(micaApp, "appModel.applyPresentationLanguage(language)", "Language changes must relocalize cached AppModel presentation immediately");
assertIncludes(xcstringsResolver, "removingUnresolvedFormatSpecifiers", "Dynamic localization lookup must never expose raw format placeholders");

for (const testContract of [
  "destinationsKeepTheFixedProductOrder",
  "editorPresentationsUseUniqueViewIdentityForTheSameDraft",
  "publicationCadencesMatchTheVisibleDomainBudgets",
  "destinationsObserveOnlyTheirExpensiveLiveDomains",
  "visibleLogBurstsUseOneNonRestartingFiveHertzPublisher",
  "hiddenLogsRetainRawDataAndEnteringLogsFlushesImmediately",
  "explicitSessionEndClearsEveryPublishedOperationalDomain",
  "reconnectRetainsTheCommittedSnapshotAsReadOnlyStaleData",
  "logReceiptPreservesTheTransportTimestamp",
  "trafficTimelineUsesOnlyReceivedSamplesAndEnforcesCapacity",
  "proxyGroupsPreserveControllerOrderAndAppendVisibleGlobalLast",
  "policyRefreshUsesLatestMihomoConfigurationAndMemberOrder",
  "proxyOpenPathsStayInControllerOrderAndOnlyActiveMembersProject",
  "latencyDistributionUsesReportedOrderAndHealthBuckets",
  "nodeDetailSeparatesKnownFieldsFromAdditionalControllerFields",
  "latencyScaleUsesOnlyPositiveReportedValuesWithoutReordering",
  "closingInspectorPreservesGroupStateAndDoesNotAutoReopen",
  "activeGroupIndexBuildsOnlyTheActiveMembersAndFiltersCachedRows",
  "proxyWorkspaceKeepsIndependentFilterAndSelectionPerGroup",
  "reportedSmartRanksNeverReorderOrInferNodeRows",
  "catalogRevisionBuildsRowsOnlyForExpandedGroups",
  "connectionProjectionKeepsCompleteValuesAndSortsOnlyTheCopy",
  "connectionProjectionSeparatesActiveAndClosedRowsWithReceiptTime",
  "connectionPulseProjectionTracksVisibleResultsAndStableOwners",
  "connectionPulseCacheSkipsSortRebuildAndAppliesKeyedMetricDeltas",
  "closedConnectionPulseNeverPresentsHistoricalRatesAsLive",
  "connectionPulseDistinguishesReportedZeroFromMissingMetrics",
  "logProjectionNeverSortsAndFilteringRetainsIncomingOrder",
  "logProjectionCacheReusesSourceRowsAcrossFiltersAtTwoThousandEntries",
  "followNewestCadenceCoalescesSteadyRequestsWithoutRestartingDeadline",
  "ruleConnectionIndexBuildsOncePerControllerGenerationAndRevision",
  "ruleDecisionPathResolvesOnlyExactPolicyGroupTargets",
  "sourceProjectionPreservesControllerOrderAndFiltersByKind",
  "inspectorProjectionsExposeCompleteReportedValuesWithoutMasking",
  "connectionCloseGroupsPreserveFirstSeenOwnerOrder",
  "connectionCloseGroupsExcludeRowsWithoutControllerIDs",
  "connectionCloseIntentsRejectReconnectedSessionWithUnchangedTargets",
  "connectionCloseIntentReconciliationDropsMissingTargets",
  "overviewSummaryProjectionsUseOnlyRealReportedValues",
  "overviewDownsamplingRetainsOnlyReceivedSamplesAndEndpoints",
  "overviewNetworkFactsKeepCompleteReportedValuesAndOmitMissingFields",
  "overviewTopActiveConnectionsKeepOccurrenceIdentityAndMissingCountersUnavailable",
  "overviewTopologyHitIndexUsesPointerSizedTargets",
  "completePathUsesDynamicDepthAndPreservesChainSemantics",
  "everyConnectionAndCompletePathIsAdmittedWithoutCaps",
  "sharedVerticesAndEdgesRetainEveryPathMembership",
  "missingSourceOrChainCreatesUnavailableRecordsWithoutGraphEdges",
  "duplicateAndBlankConnectionIDsReceiveStableOccurrenceIdentities",
  "columnsNodesAndEdgesFollowDeterministicFirstAppearanceOrder",
  "globalGroupSearchMatchesMembersAndMetadataWithoutReordering",
  "proxyCatalogProjectionCachesOrderedGroupsForCurrentQuery",
  "proxyNodeSearchTextIsPrecomputedAndNormalized",
  "nonSelectableSingBoxGroupKeepsMembersAndTestsAvailable",
  "proxyMemberDetailsPreserveReportedStatusFixedAndHistory",
  "retainsCompleteLatestReportForEachProfile",
  "actionsRecoveryDoesNotCountDisabledRefresh",
  "actionsProjectionUsesVerifiedControllerDispatchers",
  "actionsExecutableCountTracksTransientReadinessWithoutLosingInventory",
  "targetScopeDistinguishesThisMacNetworkAndExplicitMacLocal",
  "diagnosticsControllerFailureSuppressesDuplicateEndpointFailures",
  "diagnosticsProjectionOmitsMachineFacingEvidence",
  "diagnosticsUsesCapabilitiesToSuppressUnsupportedFailures",
  "diagnosticsMapsExpectedEndpointFailuresToProductAreas",
  "diagnosticsSelectionReconcilesByStableIssueID",
  "updateAllPreservesSourceOrderSkipsReadOnlyProvidersAndRefreshesOnce",
  "controllerChangeCancelsAndResetsBatchWithoutStalePublication",
  "providerProjectionPreservesTestURLAndSubscriptionInformation",
  "newerProviderUpdateAllRecordDrivesEndpointAndCheckResults",
  "newerIndividualProviderUpdateRecordWinsOlderBatchRecord",
  "blankConnectionIDNeverReachesTheCloseTransport",
  "confirmedSingleCloseRemainsPartialWhenAuthoritativeRefreshFails",
  "confirmedCloseAllRemainsPartialWhenAuthoritativeRefreshFails",
  "readOnlyPolicyGroupCannotStartASelectionMutation",
  "stalePolicyMemberCannotStartASelectionMutation",
  "staleGenerationLookupCannotRebindTheCoordinator",
  "successOutcomeKeepsCommandContext",
  "preferenceStoreLoadsAndPersistsTheSingleSettingsAuthority",
]) {
  assertIncludes(presentationTests, testContract, `Replacement pure-presentation tests must cover ${testContract}`);
}
assertIncludes(
  sessionStreamTests,
  "memoryTimelineRetainsConnectionsFrameSamplesAndDeduplicatesConcurrentSources",
  "Session tests must cover memory provenance and cross-source deduplication",
);
for (const sessionContract of [
  "surgeEventProjectionPreservesReportedOrderPayloadAndStableIDs",
  "surgeSnapshotPublishesEventsAndRecentRequestsWithoutDuplication",
  "singBoxTraceLogsKeepTheirReportedLevel",
  "traceLogFilterIsOfferedOnlyForSingBoxSessions",
]) {
  assertIncludes(sessionStreamTests, sessionContract, `Session tests must retain ${sessionContract}`);
}

assertDirectLocalizationKeys(expectedWorkbenchFiles, strings);
for (const key of [
  "navigation.overview",
  "navigation.proxies",
  "dashboard.tab_connections",
  "dashboard.tab_logs",
  "dashboard.tab_rules",
  "dashboard.tab_providers",
  "sidebar.controllers",
  "workbench.configuration",
  "workbench.actions",
  "workspace.diagnostics",
  "workbench.settings",
  "settings.language",
  "settings.appearance",
  "settings.font_scale",
  "settings.global_group_visibility",
  "action.provider_update_all",
  "log_type.trace",
  "traffic.provider_subscription_info",
  "editor.api_version",
  "editor.sing_box_started_service",
  "live.pause",
  "live.resume",
  "operation.connection_id_unavailable",
  "operation.connection_closed_refresh_failed",
  "operation.connections_closed_refresh_failed",
  "operation.policy_group_not_selectable",
  "actions.executable_count %lld",
  "diagnostics.verdict_ready",
  "diagnostics.needs_attention",
  "diagnostics.technical_details",
  "target.scope_this_mac",
  "target.loopback_recovery_detail",
  "routing.activate_group",
  "routing.choose_group",
  "routing.close_group",
  "routing.collapse_group_directory",
  "routing.current_latency",
  "routing.expand_group_directory",
  "routing.more_open_groups",
  "routing.open_group",
  "routing.open_group_paths",
  "routing.path_candidates",
  "routing.path_group",
  "traffic.open_target_policy",
]) {
  assertLocalized(strings, key);
}
for (const key of [
  "operation.provider_update_all_started %lld",
  "operation.provider_update_all_progress %lld %lld %@",
  "operation.provider_update_all_succeeded %lld",
  "operation.provider_update_all_partial %lld %lld",
  "operation.provider_update_all_failed %lld",
  "traffic.no_updatable_providers",
  "traffic.provider_update_all_progress",
  "traffic.provider_update_current %@",
  "traffic.provider_update_refreshing",
  "traffic.provider_update_complete",
  "traffic.provider_update_completed_count %lld %lld",
  "traffic.provider_update_succeeded_count %lld",
  "traffic.provider_update_failed_count %lld",
]) {
  assertLocalized(strings, key);
}
for (const [key, entry] of Object.entries(strings)) {
  const english = entry.localizations?.en?.stringUnit?.value ?? "";
  const chinese = entry.localizations?.["zh-Hans"]?.stringUnit?.value ?? "";
  assert(!/(?:Session Sync|Start Sync|Stop Sync|Start Live|Stop Live)/i.test(english), `Legacy live/sync copy must stay removed: ${key}`);
  assert(!/(?:会话同步|开始同步|停止同步|开启实时|停止实时)/.test(chinese), `Legacy live/sync Chinese copy must stay removed: ${key}`);
}

for (const clientMethod of [
  "version", "configs", "proxies", "connections", "connectionsStream", "rules",
  "proxyProviders", "ruleProviders", "memory", "logsStream", "updateConfigs",
  "reloadConfigs", "updateGeoData", "clearFixedProxy", "healthCheckProxyProvider",
  "setRuleDisabled",
]) {
  assertIncludes(mihomoClient, `func ${clientMethod}(`, `Mihomo client must retain real API method ${clientMethod}`);
}
assertIncludes(mihomoClient, "decodePreservingProxyOrder", "Mihomo proxy decoding must preserve object-key order");
assertIncludes(mihomoModels, "public var proxyOrder: [String]", "Mihomo models must retain proxy order");
assertIncludes(mihomoModels, "proxyOrder.compactMap", "Policy groups must project from controller order");
assertExcludes(mihomoModels, "orderedGroups.sort", "Decoded policy groups must never be sorted locally");
assertIncludes(mihomoModels, "public var providerOrder: [String]", "Provider responses must retain controller order");
assertExcludes(mihomoModels, "providers.values.sorted", "Providers must not be alphabetically reordered");
assertIncludes(mihomoEndpoint, "public static func clearFixedProxy", "Fixed-selection clear must use the real endpoint");
assertIncludes(mihomoEndpoint, "public static func setRuleDisabled", "Rule writes must use the real endpoint");
assertIncludes(surgeClient, '"X-Key"', "Surge API must retain X-Key authentication");
assertIncludes(surgeClient, 'pathComponents: ["v1", "policy_groups", "select"]', "Surge policy selection must use the official endpoint");
assertIncludes(surgeClient, 'pathComponents: ["v1", "requests", "kill"]', "Surge connection termination must use the official endpoint");
assertIncludes(unifiedModels, "public struct ControllerCapabilities", "All UI actions must remain capability-gated");
assertIncludes(unifiedAdapters, "ControllerAdapterProtocol", "Controller implementations must remain behind the unified adapter boundary");
assertIncludes(routerProfiles, "func moveRouter", "Manual controller reordering must remain persisted");
assertExcludes(routerProfiles, ".sort", "Controller profile persistence must not reorder names automatically");
assertIncludes(appModel, "SingBoxGRPCClient.withConnectedClient", "sing-box connection tests must use StartedService gRPC");
assertIncludes(routerProfiles, "case .singBox(let version)", "Connection-test reports must handle sing-box results explicitly");
assertIncludes(routerProfiles, "resolvedKind: resolvedKind", "Connection-test failures must retain the resolved controller kind");
assertIncludes(controllerVariantTests, "autoDetectedSingBoxConnectionTestUsesStartedServiceTransport", "Auto-detected sing-box connection testing needs regression coverage");
assertIncludes(controllerVariantTests, "singBoxConnectionFailureUsesRPCReportInsteadOfJSONReport", "sing-box failures must not be presented as JSON failures");
assertIncludes(controllerVariantTests, "autoDetectSingBoxProbeFailureUsesRPCReportInsteadOfJSONReport", "Auto Detect probe failures from sing-box must retain the RPC report boundary");
assertIncludes(liveSession, "isCurrentSession", "Async live-session publication must validate the current generation");
assertIncludes(appModel, "canRefreshSelectedRouter", "Shared refresh capability must remain the command authority");

for (const forbiddenRuntimePrimitive of [
  "Process()",
  'ProcessInfo.processInfo.environment["http_proxy"]',
  "networksetup",
  "pfctl",
  "iptables",
  "ubus ",
  "ssh ",
]) {
  assertExcludes(executableSource, forbiddenRuntimePrimitive, `Mica must not launch or modify forbidden local primitive ${forbiddenRuntimePrimitive}`);
}
for (const boundary of [
  "activeUIFullControllerData: true",
  "credentialsExcludedFromExports: true",
  "rawResponseBodiesExcludedFromExports: true",
  "networkAccess: false",
  "controllerProfilesLoaded: false",
  "coreLaunched: false",
  "systemEnvironmentModified: false",
]) {
  assertIncludes(runtimeSmoke, boundary, `Runtime smoke source must retain non-network boundary ${boundary}`);
}
assertExcludes(runtimeSmoke, "AppModel(", "Runtime smoke source must not instantiate the controller model");
assertExcludes(runtimeSmoke, "MihomoClient", "Runtime smoke source must not contact Mihomo");
assertExcludes(runtimeSmoke, "SurgeHttpAPIClient", "Runtime smoke source must not contact Surge");

console.log("Mica native workbench source contract passed");
