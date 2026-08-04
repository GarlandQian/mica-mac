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
  "Sources/Mica/Features/Workbench/WorkbenchChrome.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionDetails.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnections.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchControllerSelector.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDashboard.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDataShared.swift",
  "Sources/Mica/Features/Workbench/WorkbenchLogs.swift",
  "Sources/Mica/Features/Workbench/WorkbenchManagement.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewEditor.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewPersonalization.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewProjection.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewRuntimes.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift",
  "Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift",
  "Sources/Mica/Features/Workbench/WorkbenchProxies.swift",
  "Sources/Mica/Features/Workbench/WorkbenchRules.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSources.swift",
  "Sources/Mica/Features/Workbench/WorkbenchVisualSystem.swift",
  "Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift",
  "Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift",
].sort();

const connectionPageFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchConnections.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionDetails.swift",
];

const dataPageFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchDataShared.swift",
  ...connectionPageFiles,
  "Sources/Mica/Features/Workbench/WorkbenchRules.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSources.swift",
  "Sources/Mica/Features/Workbench/WorkbenchLogs.swift",
];

const dataBrowserTableFiles = [
  "Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchRules.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSources.swift",
  "Sources/Mica/Features/Workbench/WorkbenchLogs.swift",
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
  "Tests/MicaTests/WorkbenchOverviewPersonalizationTests.swift",
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
const workbenchContract = read(".trellis/spec/frontend/workbench-ui-contract.md");
const controllerContract = read(".trellis/spec/backend/controller-data-contract.md");
const liveSessionContract = read(".trellis/spec/frontend/live-session-controller-contract.md");
const visualSystem = read("Sources/Mica/Features/Workbench/WorkbenchVisualSystem.swift");
const chrome = read("Sources/Mica/Features/Workbench/WorkbenchChrome.swift");
const controllerSelector = read("Sources/Mica/Features/Workbench/WorkbenchControllerSelector.swift");
const workspaceView = read("Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift");
const dashboard = read("Sources/Mica/Features/Workbench/WorkbenchDashboard.swift");
const overviewEditor = read("Sources/Mica/Features/Workbench/WorkbenchOverviewEditor.swift");
const overviewPersonalization = read("Sources/Mica/Features/Workbench/WorkbenchOverviewPersonalization.swift");
const overviewProjection = read("Sources/Mica/Features/Workbench/WorkbenchOverviewProjection.swift");
const overviewRuntimes = read("Sources/Mica/Features/Workbench/WorkbenchOverviewRuntimes.swift");
const overviewTopology = read("Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift");
const overviewSource = [
  dashboard,
  overviewEditor,
  overviewPersonalization,
  overviewProjection,
  overviewRuntimes,
  overviewTopology,
].join("\n");
const proxyModel = read("Sources/Mica/Features/Workbench/WorkbenchProxies.swift");
const proxyPanels = read("Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift");
const proxies = [proxyModel, proxyPanels].join("\n");
const dataPages = dataPageFiles.map(read).join("\n");
const connectionsPage = connectionPageFiles.map(read).join("\n");
const logsPage = read("Sources/Mica/Features/Workbench/WorkbenchLogs.swift");
const rulesPage = read("Sources/Mica/Features/Workbench/WorkbenchRules.swift");
const management = read("Sources/Mica/Features/Workbench/WorkbenchManagement.swift");
const workspaceStore = read("Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift");
const workbenchSource = expectedWorkbenchFiles.map(read).join("\n");
const workbenchCode = code(workbenchSource);
const presentationTests = requiredPresentationTests.map(read).join("\n");
const sessionStreamTests = read("Tests/MicaTests/SessionStreamStateTests.swift");
const liveSessionPublicationTests = read("Tests/MicaTests/LiveSessionPublicationTests.swift");
const liveSessionRuntimeTests = read("Tests/MicaTests/LiveSessionRuntimeTests.swift");
const overviewPersonalizationTests = read(
  "Tests/MicaTests/WorkbenchOverviewPersonalizationTests.swift",
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
  "private func controllerDetail(_ profile: RouterProfile) -> some View {",
  "private func controllerIdentity(_ profile: RouterProfile) -> some View {",
);
assertIncludes(
  controllerDetailSection,
  "WorkbenchManagementFormCanvas",
  "Controller detail must use the native grouped management form canvas",
);
const actionsContentSection = sourceSection(
  management,
  "private func actionsContent(_ projection: WorkbenchActionsProjection) -> some View {",
  "private func commandBar(_ projection: WorkbenchActionsProjection) -> some View {",
);
assertIncludes(
  actionsContentSection,
  "WorkbenchManagementFormCanvas",
  "Actions must use the native grouped management form canvas",
);
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
  ".contextMenu",
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
  directSystemFontCalls === 3,
  "Workbench text must use micaFont except for the scaled-font modifier and two Canvas Text renderers",
);
assertIncludes(
  visualSystem,
  "content.font(\n            .system(",
  "The semantic font modifier must own ordinary interface font construction",
);
assertIncludes(
  workbenchSource,
  "size: fontScale.pointSize(for: MicaTextStyle.caption.basePointSize)",
  "Topology Canvas column labels must receive the active font scale",
);
assertIncludes(
  workbenchSource,
  ".font(.system(size: fontPointSize))",
  "Topology Canvas node labels must use the scaled point size passed by the view layer",
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
  "light: color(0xE7E9F2)", "dark: color(0x0E0F1A)",
  "light: color(0xFBFBFE)", "dark: color(0x161827)",
  "light: color(0xDEE1EE)", "dark: color(0x1E2133)",
  "light: color(0xD9DCE9)", "dark: color(0x2A2E45)",
  "light: color(0x4F5BD5)", "dark: color(0x8B93FF)",
  "light: color(0x1E7A93)", "dark: color(0x6FD3E7)",
  "light: color(0x2E7D54)", "dark: color(0x7FD4A8)",
  "light: color(0x9A6410)", "dark: color(0xF2BE6E)",
  "light: color(0xB23A52)", "dark: color(0xF28B9E)",
  "light: color(0x6C4FD1)", "dark: color(0xB79CFF)",
]) {
  assertIncludes(visualSystem, token, `Visual system must retain the Midnight Instrument token ${token}`);
}
assertIncludes(visualSystem, "static let accentSoft", "Midnight Instrument must expose a soft selection fill");
assertIncludes(visualSystem, "static let navigationSelectionFill = accentSoft", "Sidebar selection must remain a restrained semantic tint");
assertIncludes(visualSystem, "enum MicaTextStyle", "Typography ladder must expose semantic Mica text roles");
assertIncludes(visualSystem, "struct MicaScaledFontModifier", "Typography ladder must visibly apply the selected font scale");
assertIncludes(visualSystem, "fontScale.pointSize(for: style.basePointSize)", "Typography ladder must calculate an explicit macOS point size");
assert(count(workbenchSource, ".micaFont(") >= 150, "Workbench interface text must use the scalable typography API");
assertIncludes(visualSystem, "enum WorkbenchMotion", "Instrument motion primitives must exist");
assertIncludes(visualSystem, "accessibilityReduceMotion", "Motion must honor Reduce Motion");
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
  assertIncludes(visualSystem, metric, `Visual system must retain bounded metric ${metric}`);
}
assertExcludes(visualSystem, "hitTarget", "Workbench must not restore a universal touch-target metric");
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
  assertIncludes(visualSystem, primitive, `Visual system must expose ${primitive}`);
}
assertIncludes(visualSystem, ".symbolRenderingMode(.monochrome)", "Shared workbench symbols must retain deterministic native rendering");
assertIncludes(visualSystem, "ContentUnavailableView", "Shared states must use native centered unavailable content");
assertIncludes(visualSystem, ".frame(maxWidth: .infinity, maxHeight: .infinity)", "Full-page states must center in the remaining region");

const destinationSource = sourceSection(chrome, "enum WorkbenchDestination", "struct ContentView");
assertOrdered(destinationSource, [
  "case overview", "case proxies", "case connections", "case logs", "case rules", "case sources",
  "case controllers", "case configuration", "case actions", "case diagnostics",
], "Workbench destinations must keep the fixed product order");
assertIncludes(destinationSource, ".overview, .proxies, .connections, .logs, .rules, .sources,", "Keyboard destinations must keep the fixed six-tab order");
assertIncludes(destinationSource, ".controllers, .configuration, .actions, .diagnostics,", "Management destinations must keep their fixed order");
assertExcludes(destinationSource, "case settings", "Application Settings must remain a native Settings scene, not a Workbench destination");
assertIncludes(chrome, "NavigationSplitView", "Main window must use native split navigation");
assertIncludes(chrome, "List {", "Sidebar must retain a native virtualized list");
assertIncludes(chrome, ".toolbarTitleDisplayMode(.inline)", "Native navigation title must retain toolbar space without duplicate identity chrome");
assertIncludes(chrome, ".sharedBackgroundVisibility(.hidden)", "Session commands must not be wrapped in a second shared glass capsule");
assertExcludes(chrome, "WorkbenchToolbarControllerButton", "Controller identity must not be duplicated in the toolbar");
assertExcludes(chrome, "workbenchArea", "Replacement navigation must not migrate the old area model");
assertExcludes(chrome, "workbenchActivitySection", "Replacement navigation must not migrate the old activity model");
const sidebarSource = sourceSection(chrome, "struct WorkbenchSidebarView", "// MARK: - Toolbar");
assertExcludes(sidebarSource, "@Environment(AppModel.self)", "Destination list shell must not observe controller or stream state");
assertIncludes(sidebarSource, "@Environment(\\.micaAppLanguage)", "Sidebar must observe language changes directly");
assertIncludes(sidebarSource, "language: language", "Sidebar localization must resolve from its observed language");
assertExcludes(sidebarSource, "List(selection:", "Sidebar must not restore the saturated system selection block");
assertExcludes(sidebarSource, ".accentColor(", "Sidebar must not restore the soft-deprecated accent override");
assertIncludes(sidebarSource, "Button(action: action)", "Every custom navigation row must retain native button semantics");
assertIncludes(sidebarSource, ".listRowInsets(\n                    EdgeInsets()", "Sidebar navigation buttons must occupy the full list-row width");
assertIncludes(sidebarSource, ".contentShape(.interaction, Rectangle())", "Sidebar navigation must make trailing row whitespace clickable");
assertExcludes(sidebarSource, "defaultMinListRowHeight", "Sidebar height must remain content-driven rather than globally fixed");
assertIncludes(sidebarSource, ".fill(MicaStyle.navigationSelectionFill)", "Selected navigation must use the restrained shared fill");
assertIncludes(sidebarSource, ".accessibilityAddTraits(isSelected ? .isSelected : [])", "Custom navigation must expose selection to accessibility");
assertExcludes(sidebarSource, ".appSettings", "The Workbench sidebar must not duplicate the native Settings scene");
assertIncludes(controllerSelector, "ForEach(snapshot.items)", "Inline sidebar controller switching must preserve persisted controller order");
assertIncludes(controllerSelector, "onSelectController(item.profile)", "Controller switching must route through the window replacement guard");
assertOrdered(chrome, ["await Task.yield()", "appModel.selectRouter(router)"], "Guarded controller switching must settle before replacing the live generation");
for (const route of [
  "WorkbenchOverviewView(destination: $destination)",
  "WorkbenchPolicyGroupsView(searchText: searchText)",
  "WorkbenchConnectionsView(",
  "WorkbenchLogsView(searchText: searchText)",
  "WorkbenchRulesView(",
  "WorkbenchSourcesView(searchText: searchText)",
  "WorkbenchControllersView(",
  "WorkbenchConfigurationView()",
  "WorkbenchActionsView()",
  "WorkbenchDiagnosticsView()",
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
assertIncludes(chrome, "struct WorkbenchStatusBar", "Workbench must expose the replacement status bar");
assertIncludes(chrome, "struct WorkbenchOperationOutcomePresentation", "Completed operations must retain a durable presentation projection");
assertIncludes(chrome, "activityIdentity(status:", "Completed operations must share the stable bottom status surface");
assertExcludes(chrome, "WorkbenchOperationOutcomeBar", "Operation outcomes must not add a second stacked bottom bar");
assertIncludes(chrome, ".textSelection(.enabled)", "Status chrome business values must remain selectable");
assertExcludes(dataPages, "setVisibleSessionDestination", "Only the window root may own live-domain visibility");
assertIncludes(chrome, "registerLiveSessionWindowDemand(", "Each window must register a stable live-domain demand");
assertIncludes(chrome, "updateLiveSessionWindowDemand(", "Each window must update only its own live-domain demand");
assertIncludes(chrome, "unregisterLiveSessionWindowDemand(", "A closing window must unregister only its own live-domain demand");
assertIncludes(chrome, "MainWindowCloseGuardAttachment(closeGuard:", "Dirty-close protection must bind to the owning SwiftUI window");
assertIncludes(mainWindowCloseGuard, "func attach(to candidate: NSWindow)", "The close guard must attach to an explicit owning window");
assertExcludes(mainWindowCloseGuard, "NSApplication.shared.mainWindow", "A window-local close guard must not select a process-global main window");
assertIncludes(appModel, "var didFinishLoadingPersistedState = false", "Controller layout cleanup must wait for completed profile loading");
assertIncludes(chrome, "previous.subtracting(current)", "Layout cleanup must remove only controllers deleted after initial loading");
assertExcludes(chrome, "overviewLayoutStore.retainControllers(", "Cold launch must not prune overrides from a transient router snapshot");
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
assert(
  (dashboard.match(/\bChart(?:\s*\{|\()/g) ?? []).length === 2,
  "Overview must use one reusable traffic chart primitive plus one connection chart primitive",
);
assertIncludes(dashboard, "trafficChart(.upload", "Overview must render a dedicated upload chart");
assertIncludes(dashboard, "trafficChart(.download", "Overview must render a dedicated download chart");
assert(count(dashboard, "AreaPlot(") === 3, "Overview live charts must keep upload, download, and connection areas");
assert(count(dashboard, "LinePlot(") === 3, "Overview live charts must keep upload, download, and connection lines");
assert(count(dashboard, "PointPlot(") === 3, "Overview live charts must expose the latest real sample for each displayed timeline");
assertIncludes(overviewProjection, "struct OverviewTimelineChartScale", "Overview charts must retain a real-data visible scale");
assertIncludes(dashboard, ".chartYScale(domain: scale.domain)", "Overview charts must apply their visible real-data scale");
assertIncludes(dashboard, "LazyVStack(alignment: .leading", "Overview below-fold analytics must construct lazily");
assertIncludes(dashboard, "OverviewDashboardRowPacker.rows(", "Overview modules must use deterministic sequential row packing");
assertIncludes(dashboard, "struct OverviewInstrumentRailSection", "Overview must use one unified instrument rail");
assertIncludes(dashboard, "struct OverviewTelemetryPanel", "Overview must use one repeated metric-panel primitive for its three primary charts");
assertIncludes(dashboard, "if availableWidth >= 960", "Overview charts must use a three-column wide layout");
assertIncludes(dashboard, "else if availableWidth >= 700", "Overview charts must use a two-column medium layout");
assertIncludes(dashboard, ".frame(height: 144)", "Every primary Overview plot must remain large enough to inspect");
assertExcludes(dashboard, "OverviewMemoryBaseChart", "Memory must remain context on the connection chart instead of a fourth plot");
assertIncludes(overviewPersonalization, ".init(id: .instrumentRail, size: .full, isVisible: false)", "The default Overview must hide the duplicate instrument rail");
assertIncludes(overviewPersonalization, ".init(id: .operationalSummaries, size: .full, isVisible: false)", "The default Overview must hide secondary summaries");
assertExcludes(dashboard, "OverviewSessionHeader", "Overview must not duplicate selected-controller session chrome");
assertExcludes(dashboard, "OverviewMetricModule", "Overview must not restore four independent KPI cards");
for (const removedSparkline of [
  "OverviewTrafficSparkline",
  "OverviewMemorySparkline",
  "OverviewCategorySparkline",
]) {
  assertExcludes(dashboard, removedSparkline, `Overview KPI sparklines must stay removed: ${removedSparkline}`);
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
assertIncludes(overviewPersonalization, "modules.filter(\\.isVisible)", "Hidden modules must be filtered before subtree construction");
assertIncludes(overviewPersonalization, "enum OverviewDashboardPreset", "Overview must retain built-in native layout presets");
assertIncludes(overviewEditor, ".dropDestination(for: String.self)", "Overview editing must support one-shot native drag reordering");
assertIncludes(overviewRuntimes, "OverviewDashboardModuleRuntimeRegistry", "Overview must preserve expensive module runtimes across reordering");
assertIncludes(overviewPersonalization, "case resetController", "Reset must remove a controller override instead of copying the current default");
assertIncludes(overviewPersonalization, "guard current.token == expected", "Global-default commits must CAS both target and global revisions");
assertIncludes(overviewPersonalization, "resetsControllerOverride", "Window drafts must retain inherited-default intent");
assertIncludes(dashboard, ".disabled(coordinator.isEditing)", "Layout editing must disable keyboard and accessibility business actions");
assertExcludes(dashboard, ".onChange(of: preferredTimelineWindow, initial: true)", "Pure module reorder must not reset a temporary timeline selection");
assertIncludes(dashboard, "state.label(language: language)", "The instrument rail must expose live or stale session state");
assertIncludes(overviewEditor, "width: MicaBounds.iconControlSize", "Overview editor icon commands must use compact macOS control geometry");
for (const personalizationRegression of [
  "staleGlobalCommitCannotDeleteNewerControllerOverride",
  "resetKeepsInheritanceWhenGlobalDefaultChangesBeforeCommit",
  "selectedControllerConflictCannotBeClearedByReload",
  "undoReconcilesConflictAfterDefaultIntentIsRemoved",
]) {
  assertIncludes(
    overviewPersonalizationTests,
    personalizationRegression,
    `Overview personalization needs regression coverage for ${personalizationRegression}`,
  );
}
assertExcludes(dashboard, "selectedConnectionFields", "Overview must not restore the removed raw connection inspector");
assertExcludes(dashboard, "geoIPCoordinator.lookup", "Overview facts must not start per-connection GeoIP work");
assertExcludes(dashboard, "NetworkInfoProjector", "Removed overview network abstractions must not return");
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
assertExcludes(dashboard, "DragGesture(minimumDistance: 0)", "Overview overlays must not steal vertical scrolling with zero-distance drags");
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
assertIncludes(dashboard, "Canvas { context, _ in", "Topology must render through one Canvas pass");
const overviewTopologyViewport = sourceSection(
  dashboard,
  "private struct OverviewTopologyViewport",
  "private struct OverviewTopologySelectionDetail",
);
assertExcludes(overviewTopologyViewport, "ScrollView(.horizontal)", "Complete topology must fit its available width without a nested horizontal viewport");
assertIncludes(overviewTopologyViewport, ".frame(maxWidth: .infinity, alignment: .center)", "Complete topology must center its width-fitted canvas");
assertIncludes(overviewTopology, "let graphWidth = max(availableWidth.rounded(.down), 1)", "Topology layout must be bounded by the measured module width");
for (const sankeyContract of [
  "log10(Double(connectionCount) + 1) * 10",
  "private static let sankeyNodeWidth: CGFloat = 15",
  "private static let sankeyNodeGap: CGFloat = 4",
  "private static func sankeyRibbonPath(",
]) {
  assertIncludes(overviewTopology, sankeyContract, `Topology must retain Zashboard-aligned Sankey behavior through ${sankeyContract}`);
}
assertExcludes(dashboard, "ScrollView([.horizontal, .vertical])", "Topology must not compete with Overview for vertical scrolling");
assertIncludes(dashboard, "ForEach(layout.renderBands)", "Complete topology must render through stable vertical bands");
assertIncludes(dashboard, "struct OverviewTopologyBaseBand", "Topology base drawing must have an isolated invalidation boundary");
assertIncludes(dashboard, "struct OverviewTopologyHighlightBand", "Topology highlighting must have an isolated invalidation boundary");
assertIncludes(dashboard, "struct OverviewTopologyHitBand", "Topology hit testing must have an isolated invalidation boundary");
assertIncludes(dashboard, "stageConnectionNavigation(", "Topology paths must open the matching connection in the same window");
assertIncludes(dashboard, "runtime.interaction.snapshot.isHovering", "Topology hover must freeze only the presented snapshot");
assertIncludes(dashboard, "runtime.isPaused", "Topology must provide explicit presentation pause");
assertIncludes(dashboard, "runtime.isExpanded", "Topology must provide same-window expansion");
for (const stateKind of ["kind: .noController", "kind: .loading", "kind: .unsupported", "kind: .empty", "kind: .failed"]) {
  assertIncludes(dashboard, stateKind, `Overview must distinguish ${stateKind}`);
  assertIncludes(proxies, stateKind, `Proxies must distinguish ${stateKind}`);
}
for (const syntheticSource of ["Timer", "Double.random", "Int.random", "PreviewData", "mockData", "placeholderSamples"]) {
  assertExcludes(code(dashboard), syntheticSource, `Overview must not synthesize controller data with ${syntheticSource}`);
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
  assertIncludes(dashboard, chartContract, `Overview charts must retain Zashboard-aligned real-data interaction through ${chartContract}`);
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
  "struct ProxyMasterDetailMetrics",
  "struct ProxyOpenPathRibbonProjection",
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
assertExcludes(sourceSection(proxies, "enum ProxyProjection"), ".sorted", "Proxy presentation must preserve controller-reported order");
assertExcludes(sourceSection(proxies, "enum ProxyProjection"), "ranked", "GLOBAL options must not rank or reorder peer groups");
assertExcludes(sourceSection(proxies, "enum ProxyProjection"), "globalGroups.first?.group.options", "GLOBAL options must not drive presentation order");
assertExcludes(dashboardSessionModels, "stabilizedPolicyGroups", "Policy refreshes must adopt the controller's latest reported order instead of merging an earlier order");
for (const mihomoConfigurationOrderContract of [
  "mihomoPolicyGroupsInConfigurationOrder(",
  'groups.filter { $0.name == "GLOBAL" }',
  "for name in global.all where consumedNames.insert(name).inserted",
  "return orderedPeers + globalGroups",
]) {
  assertIncludes(dashboardSessionModels, mihomoConfigurationOrderContract, `Mihomo policy groups must retain ${mihomoConfigurationOrderContract}`);
}
const proxyRootContent = sourceSection(proxyModel, "private var content:", "private var emptyState:");
assertIncludes(proxyRootContent, "LazyVStack", "Policy groups must render as one source-ordered vertical workspace");
assertExcludes(proxyRootContent, "ScrollView(.horizontal)", "Policy groups must not force a horizontal canvas");
assertIncludes(proxyPanels, "struct ProxyPolicyGroupPanel", "Policy groups must use the redesigned expandable panel");
assertIncludes(proxyPanels, "ProxyLatencyDistributionView", "Collapsed groups must retain a real latency distribution preview");
assertIncludes(proxyPanels, ".adaptive(minimum: 340, maximum: 460)", "Expanded groups must keep node cells readable in a three/two/one-column grid");
assertIncludes(proxyPanels, "Button(action: onSelect)", "The full node tile body must switch or inspect the selected node");
assertIncludes(proxyPanels, "ProxyPolicyNodeInlineDetails", "Node details must remain inline with their policy group");
assertIncludes(proxyPanels, "@State private var isHovered", "Node cells must provide a restrained pointer-hover treatment");
assertIncludes(proxyPanels, "ProxyNodeFactSection", "Selected node details must group facts into readable sections");
assertIncludes(proxyPanels, "ProxyNodeFactList", "Selected node details must present labeled values instead of a field-card wall");
assertExcludes(proxyPanels, "ProxyNodeFactGrid", "Selected node details must not regress to the old field grid");
assertIncludes(proxyModel, "updateExpandedGroups(groupIDs:", "Only expanded policy groups may materialize node indexes");
assertIncludes(proxyModel, "expandedGroupIndexes", "Expanded policy groups must retain independent cached indexes");
assertIncludes(proxyModel, "currentWorkspace.groupFilters[groupID]", "Each expanded group must retain an independent node filter");
assertIncludes(proxies, "group.usageRank(for: member.name)", "SMART labels must come from controller-reported ranks");
assertIncludes(proxies, "ProxyProjection.groupSearchText(", "Group search must include reported member names and metadata");
assertIncludes(proxies, "@State private var projectionCache", "Proxy search must cache the current catalog index");
assertIncludes(proxies, "@State private var expandedProjections", "Only expanded groups may publish node projections");
assertIncludes(proxies, "canSelect: selectionActionAvailable && group.selectable", "Read-only policy groups must disable node switching without hiding members");
assertIncludes(proxies, "struct ProxyMemberDetailProjection", "Proxy details must use a typed presentation projection");
for (const proxyDetail of ["let alive: Bool?", "let fixed: String?", "let latestHistoryDelay: Int?", "let latestHistoryTime: String?"]) {
  assertIncludes(proxies, proxyDetail, `Proxy details must retain ${proxyDetail}`);
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
  assertIncludes(proxies, reportedFieldContract, `Selected proxy detail projection must retain ${reportedFieldContract}`);
}
assertIncludes(proxyPanels, "ProxyReportedMetadataField.fields(in: detail?.reportedMetadata", "Inline details must expose only uncategorized controller fields");
assertIncludes(proxyPanels, "showsAdditionalFields", "Additional controller fields must remain folded until requested");
assertExcludes(proxyPanels, "additionalMetadataText", "Proxy details must not collapse controller fields into one JSON value");
assertExcludes(sourceSection(proxies, "enum ProxyWorkspaceProjection", "enum ProxyProjection"), "PolicyGroupUsageRank", "Local interaction state must not infer SMART rank");
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
const logProjection = sourceSection(logsPage, "enum WorkbenchLogProjection", "struct WorkbenchLogProjectionCache");
assertExcludes(logProjection, ".sorted", "Logs must preserve incoming order");
assertIncludes(logProjection, "return entries.map", "Log rows must retain incoming controller order");
const ruleTableSource = sourceSection(rulesPage, "private var ruleTable", "private func rebuildRows");
assertIncludes(ruleTableSource, "ruleStateCell(row)", "Rules must combine status and mutation into one scan column");
assertIncludes(ruleTableSource, "ruleCompactSummary(row)", "Rules must retain a compact composite summary");
assertIncludes(ruleTableSource, "ruleStackedRow(row)", "Rules must collapse to one complete stacked column");
assertIncludes(ruleTableSource, "private func ruleStateLabel", "Rules must use a quiet dot-and-text state treatment");
assertExcludes(ruleTableSource, 'TableColumn(MicaStrings.localizedKey("traffic.action"', "Rules must not restore an isolated action-button column");
assertExcludes(ruleTableSource, "WorkbenchStatusBadge(", "Rule scan rows must not render type or state as boxed badges");
for (const rulePathContract of [
  "enum WorkbenchRulePolicyTargetResolver",
  "struct WorkbenchRuleDecisionPathProjection",
  "private struct WorkbenchRuleDecisionPathRail",
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
const sourcesPage = read("Sources/Mica/Features/Workbench/WorkbenchSources.swift");
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
assertExcludes(sourcesPage, "sourceActions(_", "Sources must not restore per-row action commands");
assertExcludes(sourcesPage, 'TableColumn(MicaStrings.localizedKey("traffic.action"', "Sources must not restore an isolated action column");
assertIncludes(sourcesPage, "private struct WorkbenchSourceFocusRail", "Selected sources must expose a lifecycle focus rail");
assertExcludes(sourcesPage, "traffic.source_section_actions", "Source inspectors must not duplicate focus-rail actions");
assertIncludes(dataPages, "struct WorkbenchLogProjectionCache", "Logs must cache source and filtered row projections");
assertIncludes(dataPages, "replaceRowsByStableID", "Log updates must reuse stable-ID row projections when possible");
assertIncludes(dataPages, "static let minimumInterval: TimeInterval = 0.2", "Follow Newest must be capped at five hertz");
assertIncludes(dataPages, "followNewest", "Logs must expose explicit Follow Newest state");
assertIncludes(dataPages, ".onScrollPhaseChange", "Follow Newest must react to real user scrolling");
assertIncludes(dataPages, "struct WorkbenchRuleConnectionIndexCache", "Rules must cache connection matching by revision");
assertIncludes(dataPages, "dashboardSessionControls.closedConnectionRecords", "Connections must keep retained closed history separate from active rows");
assertIncludes(dataPages, "appModel.clearClosedConnections()", "Closed history must expose an explicit clear command");
assertIncludes(dataPages, ".inspector(isPresented:", "Data-page details must remain in-window inspectors");
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
assertIncludes(logsPage, "enum WorkbenchLogSeverity", "Logs must project a stable semantic severity");
assertIncludes(logsPage, "let severity: WorkbenchLogSeverity", "Log rows must carry projected severity");
assertIncludes(logsPage, "private func severityRail", "Logs must render a fixed semantic severity rail");
assertExcludes(logsPage, "WorkbenchStatusBadge(", "Logs must not restore colored severity badges");
assertIncludes(appLanguage, 'case "trace":', "Trace logs must localize through the shared language boundary");

for (const managementSurface of [
  "struct WorkbenchControllersView",
  "struct WorkbenchConfigurationView",
  "struct WorkbenchActionsView",
  "struct WorkbenchDiagnosticsView",
  "struct MicaSettingsSceneView",
]) {
  assertIncludes(management, managementSurface, `Management replacement must expose ${managementSurface}`);
}
assertExcludes(management, "struct WorkbenchSettingsView", "Settings must only exist in the native Settings scene");
const controllersSource = sourceSection(management, "struct WorkbenchControllersView", "// MARK: - Configuration");
assertIncludes(controllersSource, "List(filteredProfiles, selection: managementSelectionBinding)", "Controllers must use a native virtualized selectable list");
assertIncludes(controllersSource, "HSplitView", "Wide controller management must use native master-detail layout");
assertIncludes(controllersSource, "VSplitView", "Compact controller management must keep list and detail in one window");
const controllerRowSource = sourceSection(controllersSource, "private func controllerRow", "private var filteredProfiles");
assertOrdered(
  controllerRowSource,
  [".frame(maxWidth: .infinity, alignment: .leading)", "HStack(spacing: 0)"],
  "Controller edit and delete actions must remain at the far trailing edge",
);
const controllerListProjection = sourceSection(management, "enum WorkbenchControllerListProjection", "struct WorkbenchConnectionTestProjection");
assertIncludes(controllerListProjection, "guard !normalizedQuery.isEmpty else { return profiles }", "Empty controller search must preserve persisted order");
assertExcludes(controllerListProjection, ".sorted", "Controllers must never reorder profiles automatically");
assertIncludes(controllersSource, "appModel.selectRouter(profile)", "Only explicit Use may switch the active controller");
assertIncludes(controllersSource, "appModel.moveRouter", "Controller order changes must use the persisted move operation");
assertIncludes(controllersSource, "pendingDelete", "Controller deletion must confirm inline");
assertIncludes(controllersSource, "profile.endpointURL", "Controllers must show the complete endpoint");
for (const canvasMetric of [
  "static let formCanvasWidth: CGFloat = 1_040",
  "static let maximumCanvasWidth: CGFloat = 1_180",
  "static let preferenceWindowWidth: CGFloat = 820",
]) {
  assertIncludes(management, canvasMetric, `Management pages must retain constrained canvas metric ${canvasMetric}`);
}
assertIncludes(management, ".frame(maxWidth: .infinity, alignment: .top)", "Management canvases must stay centered within wide windows");
assertIncludes(management, "WorkbenchAnimatedDisclosure", "Diagnostics must use the shared animated disclosure treatment");
assertExcludes(management, "Spacer(minLength: 0)\n\n                Form {", "Management forms must not return to centered spacer framing");
assertIncludes(management, "appModel.updateControllerConfig", "Configuration must use typed AppModel writes");
const configurationSource = sourceSection(management, "struct WorkbenchConfigurationView", "private struct WorkbenchPortField");
for (const stateKind of ["kind: .noController", "kind: .loading", "kind: .unsupported", "kind: .empty", "kind: .failed"]) {
  assertIncludes(configurationSource, stateKind, `Configuration must distinguish ${stateKind}`);
}
assertIncludes(management, "appModel.performDiagnosticsRuntimeOperation", "Actions must use capability-gated AppModel operations");
assertIncludes(management, "appModel.supportsUnifiedAction", "Actions must honor runtime capabilities");
assertIncludes(management, "appModel.copyDiagnosticsReport", "Diagnostics must retain credential-safe report copying");
assertIncludes(management, "appModel.copyEndpointResults", "Diagnostics must retain endpoint result copying");
assertIncludes(management, "appModel.copyCheckResults", "Diagnostics must retain check-results copying");
assertIncludes(management, "endpointWorkflowSection", "Diagnostics must expose the endpoint-check workflow in the main window");
assertIncludes(management, "appModel.performEndpointCheckAction", "Endpoint-check recovery must use typed AppModel actions");
for (const diagnosticsDetail of [
  "appModel.checkResultRows",
  "appModel.observabilityReadinessRows",
  "appModel.diagnosticsReportSections",
  "expandedPanels",
  "WorkbenchAnimatedDisclosure",
]) {
  assertIncludes(management, diagnosticsDetail, `Diagnostics must retain same-window detail through ${diagnosticsDetail}`);
}
const diagnosticsSource = sourceSection(management, "private enum WorkbenchDiagnosticsPanel", "private struct WorkbenchEndpointCheckStepRow");
for (const interactionContract of [
  "withTransaction(",
  "Transaction(animation: reduceMotion ? nil : WorkbenchMotion.expand)",
  ".contentShape(Rectangle())",
  ".rotationEffect(.degrees(isExpanded ? 90 : 0))",
  ".overlay(alignment: .bottom)",
  ".transition(",
]) {
  assertIncludes(diagnosticsSource, interactionContract, `Diagnostics disclosures must retain ${interactionContract}`);
}
for (const visibilityContract of [
  "availableCapabilityRows",
  "availableObservabilityRows",
  "availableEndpointSteps",
  "availableCheckResults",
  "if !projection.capabilityRows.isEmpty",
  "if !projection.coverageRows.isEmpty",
  "if !projection.observabilityRows.isEmpty",
]) {
  assertIncludes(diagnosticsSource, visibilityContract, `Diagnostics must filter unsupported rows through ${visibilityContract}`);
}
assertExcludes(
  diagnosticsSource,
  "DisclosureGroup",
  "Diagnostics must use one animated full-row disclosure implementation at both levels",
);
assertIncludes(diagnosticsSource, "diagnosisSummarySection", "Diagnostics must lead with a readable diagnosis summary");
assertIncludes(diagnosticsSource, "diagnosticsDetailsSection", "Diagnostics details must share one continuous section");
assertIncludes(diagnosticsSource, "WorkbenchDiagnosticsSummaryFact", "Diagnostics summary must use a compact fact layout instead of form rows");
assertIncludes(diagnosticsSource, "WorkbenchDiagnosticsMetadataGrid", "Controller metadata must use an adaptive fact grid instead of a long form table");
assertIncludes(diagnosticsSource, "WorkbenchDiagnosticStatusLabel", "Diagnostics rows must use restrained status signals instead of repeated filled badges");
assertIncludes(diagnosticsSource, "controllerDetailsSection", "Controller metadata must live in the continuous diagnostics detail list");
assertExcludes(diagnosticsSource, ".fill(MicaDesignTokens.contentFill)", "Diagnostics must remain an unframed outline instead of returning to opaque cards");
assertExcludes(diagnosticsSource, "Text(verbatim: section.value)", "Raw diagnostics report values must stay out of the visible UI");
assertExcludes(diagnosticsSource, "Text(verbatim: row.evidence)", "API evidence must stay out of the visible capability rows");
assertExcludes(diagnosticsSource, "diagnostics.operation_source_backend_boundary", "Monitoring rows must not expose backend-boundary terminology");
assertIncludes(management, "struct WorkbenchConnectionTestProjection", "Controller connection tests must retain complete typed reports");
assertIncludes(management, "report.steps", "Controller connection reports must expose every reported step");
assertIncludes(management, "Link(destination: authenticationLinkURL)", "Tailscale authentication URLs must be actionable with a native Link");
assertIncludes(management, "WorkbenchSingBoxTailscaleSection", "Configuration must retain in-window sing-box Tailscale state");
assertIncludes(management, "DisclosureGroup", "Tailscale detail must expand in the same window");
assertIncludes(management, "|| appModel.singBoxTailscaleStatus != nil", "Tailscale status must remain visible even without reported configuration fields");
assertIncludes(management, "|| appModel.singBoxTailscaleError != nil", "Tailscale errors must remain visible even without reported configuration fields");
assertIncludes(sourceSection(management, "struct WorkbenchActionsProjection", "struct WorkbenchActionsView"), ".reloadProfile", "Supported operations must include Surge profile reload");

assertIncludes(surgeProjection, "static func surgeEventLogEntries", "Surge events must project into typed controller log entries");
assertIncludes(surgeProjection, "static func surgeRecentRequestConnections", "Surge recent requests must project into retained closed connections");
assertIncludes(liveSession, "DashboardSnapshot.surgeEventLogEntries", "Surge snapshots must stage event logs in the generation-owned log buffer");
assertIncludes(surgeOperations, "DashboardSnapshot.surgeRecentRequestConnections", "Surge snapshots must publish recent requests");

const settingsSource = sourceSection(management, "// MARK: - Settings", "// MARK: - Controllers");
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
assertIncludes(settingsSource, "WorkbenchManagementMetrics.preferenceWindowWidth", "Native Settings must retain a centered reading width");
assertExcludes(settingsSource, "preferenceCanvasWidth", "Settings must not return to the old fixed leading-width canvas");
assertExcludes(settingsSource, "preferenceColumnMinimumWidth", "Settings must not return to an unbalanced two-column composition");
assertIncludes(settingsSource, "min(\n                    geometry.size.width,\n                    WorkbenchManagementMetrics.preferenceWindowWidth", "Native Settings must cap the form at the approved reading width");
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
assertIncludes(micaApp, "containerBackground(MicaDesignTokens.pageFill, for: .window)", "Window containers must use the shared page fill");
assertIncludes(micaApp, ".toolbarBackground(MicaDesignTokens.pageFill, for: .windowToolbar)", "Native toolbars must use the shared page fill");
assertIncludes(micaApp, ".toolbarBackgroundVisibility(.visible, for: .windowToolbar)", "Native toolbar fill must remain visible in every appearance");
assertIncludes(micaApp, 'CommandMenu(menuLocalized("controller.command_menu"))', "The custom top-level menu must follow the macOS menu language");
assertIncludes(appLanguage, "static var menuBarLanguage: AppLanguage", "Custom menu commands must resolve from the same bundle language as AppKit menus");
assertIncludes(micaApp, ".defaultSize(width: 880, height: 700)", "Native Settings must open at a practical size for larger interface text");
assertIncludes(visualSystem, "content\n                .frame(maxWidth: .infinity, maxHeight: .infinity)\n                .background(MicaDesignTokens.pageFill)", "Every page content root must paint the shared page fill");
assertIncludes(dataPages, ".background(MicaDesignTokens.pageFill)", "Data browser loading and empty states must use the shared page fill");
assertExcludes(diagnosticsSource, ".animation(disclosureAnimation, value: isExpanded)", "Expanded diagnostics must not attach a persistent animation transaction to the full subtree");
assertIncludes(diagnosticsSource, ".transition(.opacity)", "Diagnostics must retain a lightweight expansion transition");
assertIncludes(visualSystem, "static let groupedPageFill = pageFill", "Management surfaces must share the window page fill");
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
  "proxyMasterDetailWidthsStayWithinApprovedBounds",
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
  "diagnosticsCheckResultProjectionKeepsUserFacingValuesInDisplayOrder",
  "diagnosticsProjectionOmitsEmptyAndMachineFacingValues",
  "diagnosticsVisibilityRemovesUnsupportedItemsFromBothLevels",
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
  "diagnostics.runtime_operations_count %lld",
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
