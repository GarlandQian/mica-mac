import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function read(relativePath) {
  return readFileSync(path.join(root, relativePath), "utf8");
}

function exists(relativePath) {
  return existsSync(path.join(root, relativePath));
}

function listFiles(relativeDir) {
  const absoluteDir = path.join(root, relativeDir);
  if (!existsSync(absoluteDir)) return [];

  return readdirSync(absoluteDir).flatMap((entry) => {
    const absoluteEntry = path.join(absoluteDir, entry);
    const relativeEntry = path.relative(root, absoluteEntry);
    return statSync(absoluteEntry).isDirectory() ? listFiles(relativeEntry) : [relativeEntry];
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

function assertLocalized(strings, key) {
  assert(strings[key]?.localizations?.en?.stringUnit?.value, `${key} should have English localization`);
  assert(strings[key]?.localizations?.["zh-Hans"]?.stringUnit?.value, `${key} should have Simplified Chinese localization`);
}

function assertDirectWorkbenchLocalizationKeys(files, strings) {
  const keys = new Set();
  const patterns = [
    /Mica(?:Text|Label)\("([^"]+)"/g,
    /MicaStrings\.localizedKey\("([^"]+)"/g,
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
    assert(strings[key], `Workbench localization key is missing from the string catalog: ${key}`);
  }
}

function assertNoUnscaledFonts(files) {
  const fixedSystemFont = /\.font\(\.system\(size:\s*\d+(?:\.\d+)?\s*(?:,|\))/g;
  for (const file of files) {
    const source = read(file);
    const matches = source.match(fixedSystemFont) ?? [];
    assert(matches.length === 0, `${file} contains unscaled fixed system fonts: ${matches.join(", ")}`);
    if (source.includes(".font(.system(size:")) {
      assert(source.includes("@Environment(\\.micaFontMultiplier)"), `${file} should observe micaFontMultiplier`);
    }
  }
}

const requiredFiles = [
  "Package.resolved",
  "AGENTS.md",
  "docs/UI_GUIDELINES.md",
  "docs/ARCHITECTURE.md",
  "docs/DEVELOPMENT.md",
  ".trellis/spec/frontend/workbench-ui-contract.md",
  ".trellis/spec/frontend/live-session-controller-contract.md",
  ".trellis/spec/backend/controller-data-contract.md",
  "Sources/Mica/App/AppAppearance.swift",
  "Sources/Mica/App/AppFontScale.swift",
  "Sources/Mica/App/AppPreferenceEnvironment.swift",
  "Sources/Mica/App/AppRuntimeSmokeProbe.swift",
  "Sources/Mica/App/AppModel.swift",
  "Sources/Mica/App/AppModelLiveSession.swift",
  "Sources/Mica/App/AppModelReadiness.swift",
  "Sources/Mica/App/AppModelRuntimeOperations.swift",
  "Sources/Mica/App/AppModelSurgeOperations.swift",
  "Sources/Mica/App/MainWindowCloseGuard.swift",
  "Sources/Mica/App/LiveSessionRefreshModels.swift",
  "Sources/Mica/App/SessionBuffers.swift",
  "Sources/Mica/App/AppModelSelectionState.swift",
  "Sources/Mica/App/ControllerPresentation.swift",
  "Sources/Mica/App/DashboardSessionControls.swift",
  "Sources/Mica/App/MicaApp.swift",
  "Sources/Mica/App/MicaCommandFocus.swift",
  "Sources/Mica/App/MicaStyle.swift",
  "Sources/Mica/App/MicaSurfaces.swift",
  "Sources/Mica/App/RouterDraft.swift",
  "Sources/Mica/Features/Workbench/ContentView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDestination.swift",
  "Sources/Mica/Features/Workbench/WorkbenchRootView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSidebarView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchControllersView.swift",
  "Sources/Mica/Features/Workbench/ControllerManagementPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchOverviewView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchPolicyGroupsView.swift",
  "Sources/Mica/Features/Workbench/TrafficTimeline.swift",
  "Sources/Mica/Features/Workbench/PolicyGroupPresentation.swift",
  "Sources/Mica/Features/Workbench/PolicyGroupInteractionState.swift",
  "Sources/Mica/Features/Workbench/ActivityResourcesPresentation.swift",
  "Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchRulesSourcesLogsViews.swift",
  "Sources/Mica/Features/Workbench/WorkbenchCoreViews.swift",
  "Sources/Mica/Features/Workbench/WorkbenchDiagnosticsView.swift",
  "Sources/Mica/Features/Workbench/WorkbenchSettingsView.swift",
  "Sources/Mica/Resources/Localizable.xcstrings",
  "Sources/MicaCore/API/ControllerHTTPTransport.swift",
  "Sources/MicaCore/API/ControllerHTTPProbeResolver.swift",
  "Sources/MicaCore/API/ControllerProbeResolver.swift",
  "Sources/MicaCore/API/MihomoClient.swift",
  "Sources/MicaCore/API/SingBoxGRPCClient.swift",
  "Sources/MicaCore/API/MihomoEndpoint.swift",
  "Sources/MicaCore/API/SurgeHttpAPIClient.swift",
  "Sources/MicaCore/API/UnifiedControllerAdapters.swift",
  "Sources/MicaCore/Models/MihomoModels.swift",
  "Sources/MicaCore/Models/SingBoxModels.swift",
  "Sources/MicaCore/Models/UnifiedControllerModels.swift",
  "Sources/MicaCore/Protocols/SingBox/started_service.proto",
  "Sources/MicaCore/Protocols/SingBox/Generated/Sources/MicaCore/Protocols/SingBox/started_service.pb.swift",
  "Sources/MicaCore/Protocols/SingBox/Generated/Sources/MicaCore/Protocols/SingBox/started_service.grpc.swift",
  "Tests/MicaCoreTests/MihomoClientContractTests.swift",
  "Tests/MicaCoreTests/ControllerHTTPProbeResolverTests.swift",
  "Tests/MicaCoreTests/MihomoGroupDelayFallbackTests.swift",
  "Tests/MicaCoreTests/Fixtures/Mihomo/version-success.json",
  "Tests/MicaCoreTests/Fixtures/Mihomo/cmfa-version.json",
  "Tests/MicaCoreTests/Fixtures/Mihomo/stash-root.json",
  "Tests/MicaCoreTests/Fixtures/Mihomo/configs-success.json",
  "Tests/MicaCoreTests/Fixtures/Mihomo/malformed.json",
  "Tests/MicaCoreTests/Fixtures/Mihomo/proxies-stash-group.json",
  "Tests/MicaCoreTests/Fixtures/Surge/outbound-success.json",
  "Tests/MicaTests/ControllerVariantCapabilityTests.swift",
  "scripts/generate-sing-box-grpc.sh",
  "scripts/verify-runtime-smoke.mjs",
  ".trellis/config.yaml",
  ".codex/agents/trellis-implement.toml",
  ".codex/agents/trellis-check.toml",
];

for (const file of requiredFiles) {
  assert(exists(file), `Required durable-contract file is missing: ${file}`);
}

for (const removedPath of [
  "Sources/Mica/App/AppWorkspace.swift",
  "Sources/Mica/App/AppModelWorkbenchAliases.swift",
  "Sources/Mica/App/PreviewData.swift",
  "Sources/Mica/Features/Dashboard/Views/DashboardView.swift",
  "Sources/Mica/Features/Dashboard/Views/DashboardCommandBar.swift",
  "Sources/Mica/Features/Dashboard/Views/DashboardCommandPalette.swift",
  "Sources/Mica/Features/Settings/Views/SettingsView.swift",
  "Sources/Mica/Features/Routers/Views/RouterSidebarView.swift",
  "Sources/Mica/Features/Routers/Views/ControllerBayRow.swift",
  "scripts/mock-mihomo-controller.mjs",
  "scripts/verify-mock-controller.mjs",
  "scripts/verify-mock-mvp-source.mjs",
]) {
  assert(!exists(removedPath), `Legacy or mock surface should stay removed: ${removedPath}`);
}

const packageManifest = read("Package.swift");
const packageResolved = JSON.parse(read("Package.resolved"));
const agentsRules = read("AGENTS.md");
const uiGuidelines = read("docs/UI_GUIDELINES.md");
const architecture = read("docs/ARCHITECTURE.md");
const development = read("docs/DEVELOPMENT.md");
const workbenchContract = read(".trellis/spec/frontend/workbench-ui-contract.md");
const liveSessionContract = read(".trellis/spec/frontend/live-session-controller-contract.md");
const controllerContract = read(".trellis/spec/backend/controller-data-contract.md");
const micaApp = read("Sources/Mica/App/MicaApp.swift");
const micaCommandFocus = read("Sources/Mica/App/MicaCommandFocus.swift");
const micaStyle = read("Sources/Mica/App/MicaStyle.swift");
const micaSurfaces = read("Sources/Mica/App/MicaSurfaces.swift");
const appAppearance = read("Sources/Mica/App/AppAppearance.swift");
const appFontScale = read("Sources/Mica/App/AppFontScale.swift");
const preferenceEnvironment = read("Sources/Mica/App/AppPreferenceEnvironment.swift");
const runtimeProbe = read("Sources/Mica/App/AppRuntimeSmokeProbe.swift");
const runtimeVerifier = read("scripts/verify-runtime-smoke.mjs");
const appModelSource = read("Sources/Mica/App/AppModel.swift");
const liveSessionSource = read("Sources/Mica/App/AppModelLiveSession.swift");
const readinessSource = read("Sources/Mica/App/AppModelReadiness.swift");
const runtimeOperationsSource = read("Sources/Mica/App/AppModelRuntimeOperations.swift");
const configOperationsSource = read("Sources/Mica/App/AppModelConfigurationOperations.swift");
const surgeOperationsSource = read("Sources/Mica/App/AppModelSurgeOperations.swift");
const windowCloseGuardSource = read("Sources/Mica/App/MainWindowCloseGuard.swift");
const liveSessionModelsSource = read("Sources/Mica/App/LiveSessionRefreshModels.swift");
const sessionBuffersSource = read("Sources/Mica/App/SessionBuffers.swift");
const routerProfilesSource = read("Sources/Mica/App/AppModelRouterProfiles.swift");
const operationSessionSource = read("Sources/Mica/App/OperationSessionModels.swift");
const selectionStateSource = read("Sources/Mica/App/AppModelSelectionState.swift");
const controllerPresentationSource = read("Sources/Mica/App/ControllerPresentation.swift");
const dashboardSessionControlsSource = read("Sources/Mica/App/DashboardSessionControls.swift");
const dashboardSurgeProjectionSource = read("Sources/Mica/App/DashboardSurgeProjectionModels.swift");
const routerDraftSource = read("Sources/Mica/App/RouterDraft.swift");
const contentView = read("Sources/Mica/Features/Workbench/ContentView.swift");
const destinationSource = read("Sources/Mica/Features/Workbench/WorkbenchDestination.swift");
const rootSource = read("Sources/Mica/Features/Workbench/WorkbenchRootView.swift");
const sidebarSource = read("Sources/Mica/Features/Workbench/WorkbenchSidebarView.swift");
const controllersSource = read("Sources/Mica/Features/Workbench/WorkbenchControllersView.swift");
const controllerManagementSource = read("Sources/Mica/Features/Workbench/ControllerManagementPresentation.swift");
const overviewSource = read("Sources/Mica/Features/Workbench/WorkbenchOverviewView.swift");
const policySource = read("Sources/Mica/Features/Workbench/WorkbenchPolicyGroupsView.swift");
const trafficTimelineSource = read("Sources/Mica/Features/Workbench/TrafficTimeline.swift");
const policyPresentationSource = read("Sources/Mica/Features/Workbench/PolicyGroupPresentation.swift");
const policyInteractionSource = read("Sources/Mica/Features/Workbench/PolicyGroupInteractionState.swift");
const activityResourcesPresentationSource = read("Sources/Mica/Features/Workbench/ActivityResourcesPresentation.swift");
const connectionsSource = read("Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift");
const dataSource = read("Sources/Mica/Features/Workbench/WorkbenchRulesSourcesLogsViews.swift");
const coreSource = read("Sources/Mica/Features/Workbench/WorkbenchCoreViews.swift");
const diagnosticsSource = read("Sources/Mica/Features/Workbench/WorkbenchDiagnosticsView.swift");
const settingsSource = read("Sources/Mica/Features/Workbench/WorkbenchSettingsView.swift");
const controllerHTTPTransport = read("Sources/MicaCore/API/ControllerHTTPTransport.swift");
const controllerHTTPProbeResolver = read("Sources/MicaCore/API/ControllerHTTPProbeResolver.swift");
const controllerProbeResolver = read("Sources/MicaCore/API/ControllerProbeResolver.swift");
const mihomoEndpoint = read("Sources/MicaCore/API/MihomoEndpoint.swift");
const mihomoClient = read("Sources/MicaCore/API/MihomoClient.swift");
const mihomoModels = read("Sources/MicaCore/Models/MihomoModels.swift");
const singBoxGRPCClient = read("Sources/MicaCore/API/SingBoxGRPCClient.swift");
const singBoxModels = read("Sources/MicaCore/Models/SingBoxModels.swift");
const singBoxProto = read("Sources/MicaCore/Protocols/SingBox/started_service.proto");
const singBoxGeneratedMessages = read("Sources/MicaCore/Protocols/SingBox/Generated/Sources/MicaCore/Protocols/SingBox/started_service.pb.swift");
const singBoxGeneratedClient = read("Sources/MicaCore/Protocols/SingBox/Generated/Sources/MicaCore/Protocols/SingBox/started_service.grpc.swift");
const singBoxCodegenScript = read("scripts/generate-sing-box-grpc.sh");
const surgeClient = read("Sources/MicaCore/API/SurgeHttpAPIClient.swift");
const surgeModels = read("Sources/MicaCore/Models/SurgeModels.swift");
const unifiedAdapterSource = read("Sources/MicaCore/API/UnifiedControllerAdapters.swift");
const unifiedModels = read("Sources/MicaCore/Models/UnifiedControllerModels.swift");
const mihomoClientContractTests = read("Tests/MicaCoreTests/MihomoClientContractTests.swift");
const controllerHTTPProbeTests = read("Tests/MicaCoreTests/ControllerHTTPProbeResolverTests.swift");
const mihomoGroupDelayFallbackTests = read("Tests/MicaCoreTests/MihomoGroupDelayFallbackTests.swift");
const controllerVariantCapabilityTests = read("Tests/MicaTests/ControllerVariantCapabilityTests.swift");
const stringCatalog = JSON.parse(read("Sources/Mica/Resources/Localizable.xcstrings"));
const strings = stringCatalog.strings ?? {};
for (const [key, entry] of Object.entries(strings)) {
  const english = entry.localizations?.en?.stringUnit?.value ?? "";
  const chinese = entry.localizations?.["zh-Hans"]?.stringUnit?.value ?? "";
  assert(!/(?:Session Sync|Start Sync|Stop Sync|Start Live|Stop Live)/i.test(english), `Legacy live/sync mode copy must stay removed: ${key}`);
  assert(!/(?:会话同步|开始同步|停止同步|开启实时|停止实时)/.test(chinese), `旧实时/同步模式文案不得恢复: ${key}`);
}
const workbenchFiles = listFiles("Sources/Mica/Features/Workbench").filter((file) => file.endsWith(".swift"));
const workbenchSource = workbenchFiles.map(read).join("\n");
const routerEditorFiles = listFiles("Sources/Mica/Features/Routers/Views").filter((file) => file.endsWith(".swift"));
const routerEditorSource = routerEditorFiles.map(read).join("\n");
const executableSource = listFiles("Sources/Mica").filter((file) => file.endsWith(".swift")).map(read).join("\n");

assertIncludes(packageManifest, '.macOS("27.0")', "Mica must retain the macOS 27 target");
assertIncludes(packageManifest, '.executable(name: "Mica"', "Package must expose the Mica executable");
for (const durableSource of [agentsRules, uiGuidelines, architecture, workbenchContract]) {
  assertIncludes(durableSource, "Liquid Glass", "Durable UI contract must describe Liquid Glass");
}
for (const signature of [
  "func enterLiveSession(for router: RouterProfile)",
  "func upsertRouter(from draft: RouterDraft) async throws -> RouterProfile",
  "var canRefreshSelectedRouter: Bool",
]) {
  assertIncludes(liveSessionContract, signature, `Live-session transaction contract must retain signature: ${signature}`);
}
assertIncludes(agentsRules, "design-taste-frontend", "Repository rules must require the design-taste audit");
assertIncludes(agentsRules, "Active controller workspaces are full-visible UI surfaces", "Repository rules must preserve full-visible controller data");
assertIncludes(agentsRules, "tmp/codex/", "Repository rules must keep scratch artifacts under tmp/codex");
assertIncludes(controllerContract, "proxyOrder", "Durable controller contract must preserve proxy order");
assertIncludes(development, "verify-real-controller-source.mjs", "Development guide must document the source verifier");
assertIncludes(uiGuidelines, "stable-partitioned last", "UI guidelines must keep visible GLOBAL groups at the end");
assertIncludes(uiGuidelines, "before pagination", "UI guidelines must require node filtering before pagination");

assertIncludes(contentView, "WorkbenchSidebarView(", "Main window must use the workbench sidebar");
assertIncludes(contentView, "WorkbenchRootView(", "Main window must use the workbench root");
assertIncludes(contentView, "RouterEditorView(", "Controller editing must remain in the main-window detail area");
assertIncludes(contentView, "attachToCurrentMainWindow", "Main-window lifecycle must install the dirty-editor close guard");
assertIncludes(contentView, "editorIsSaving ? nil", "Saving must disable focused add/edit command routing");
assertIncludes(contentView, "guard !editorIsSaving else { return }", "Saving must block destination and editor replacement intents");
assertIncludes(routerEditorSource, "onEditingStateChange", "Controller editor must publish dirty and saving state to the window close guard");
assertIncludes(windowCloseGuardSource, "NSWindowDelegate", "Dirty-editor window close handling must remain an AppKit lifecycle bridge");
assertIncludes(windowCloseGuardSource, "windowShouldClose", "Dirty-editor window close handling must intercept the native close command");
assertIncludes(windowCloseGuardSource, "beginSheetModal", "Dirty-editor window close must use a native destructive confirmation");
assertIncludes(windowCloseGuardSource, "hasDestructiveAction = true", "Discard confirmation must mark its destructive action");
for (const forbiddenContentBridge of ["NSTableView", "NSOutlineView", "NSViewRepresentable", "NSViewControllerRepresentable"]) {
  assertExcludes(windowCloseGuardSource, forbiddenContentBridge, `Window close guard must not become AppKit content UI: ${forbiddenContentBridge}`);
}
assertIncludes(contentView, "240 * appFontScale.multiplier", "Sidebar width must grow with the selected font scale");
assertIncludes(contentView, "NavigationSplitView", "Main workbench must use native split navigation");
assertIncludes(contentView, '@AppStorage("workbenchDestination")', "Destination selection must persist");
assertExcludes(contentView, '@AppStorage("workbenchArea")', "Legacy area storage must not return as the live selection key");
assertIncludes(contentView, "migrateLegacyNavigationIfNeeded", "Legacy navigation must migrate safely");
assertIncludes(contentView, 'defaults.string(forKey: "workbenchArea")', "Migration must read the legacy area key");
assertIncludes(contentView, 'defaults.string(forKey: "workbenchActivitySection")', "Migration must read the legacy activity section key");
assertIncludes(contentView, "WorkbenchDestination.migrated(", "Migration must map legacy values through the destination model");
assertExcludes(contentView, ".sheet(", "Controller editing must not use a sheet");
assertExcludes(contentView, ".popover(", "Main workbench must not use popovers");
assertIncludes(routerEditorSource, "let onClose: () -> Void", "Controller editor must close through an in-window callback");
assertExcludes(routerEditorSource, "@Environment(\\.dismiss)", "Controller editor must not depend on modal dismissal");
assertIncludes(routerEditorSource, "Form", "Controller editor must use native forms");
assertIncludes(routerEditorSource, "SecureField", "Controller credentials must remain secure fields");
assertIncludes(routerEditorSource, "editor.controller_preview", "Untested controllers must use a neutral preview state");
assertIncludes(routerEditorSource, "showsValidation", "Controller validation must appear after an attempted action");
assertIncludes(routerEditorSource, "isSaving", "Controller save must prevent duplicate submission and navigation");
assertIncludes(routerEditorSource, "saveError", "Controller save failure must remain inline");
assertIncludes(routerEditorSource, "showsDiscardConfirmation", "Dirty controller drafts must use an inline discard gate");
assertIncludes(routerEditorSource, "try await appModel.upsertRouter", "Controller editor must await persistence before closing");
assertExcludes(routerEditorSource, ".truncationMode(.middle)", "Controller editor must not middle-truncate endpoint or diagnosis data");
assertIncludes(routerDraftSource, "editor.target_not_configured", "An empty controller target must not render a placeholder endpoint");
assertIncludes(routerDraftSource, 'displayHost = "[\\(normalizedHost)]"', "Draft IPv6 endpoints must use bracketed host notation");
assertIncludes(controllerPresentationSource, 'displayHost = "[\\(normalizedHost)]"', "Stored IPv6 endpoints must use bracketed host notation");
assertIncludes(sidebarSource, "List(selection: $destination)", "Sidebar must use native List selection");
assertIncludes(sidebarSource, "ForEach(WorkbenchDestination.Group.allCases)", "Sidebar must render the grouped destination sections");
assertExcludes(sidebarSource, "appModel.routers", "Sidebar must remain independent of controller count");
assertExcludes(sidebarSource, "deleteRouter", "Controller deletion belongs only on the Controllers page");
assertIncludes(controllersSource, "Table(visibleProfiles, selection: $managementSelection)", "Controllers page must use native selectable tables");
assertIncludes(controllersSource, "Text(verbatim: profile.endpointURL)", "Controllers page must show the complete endpoint");
assertIncludes(controllersSource, ".textSelection(.enabled)", "Controller endpoints must be selectable and copyable");
assertIncludes(controllersSource, ".frame(maxWidth: .infinity, alignment: .trailing)", "Controller actions must remain at the far trailing edge");
assertIncludes(controllersSource, "appModel.selectRouter(profile)", "Only the explicit Use action may switch controller session");
assertIncludes(controllersSource, "pendingDelete", "Controller deletion must confirm inline");
assertExcludes(controllersSource, "confirmationDialog", "Controller deletion must not use a modal confirmation");
assertExcludes(controllersSource, ".sorted", "Controllers page must preserve persisted manual order");
assertIncludes(controllerManagementSource, "case wide", "Controllers presentation must expose wide columns");
assertIncludes(controllerManagementSource, "case compact", "Controllers presentation must expose compact columns");
assertIncludes(controllerManagementSource, "return profiles", "Empty controller search must preserve the stored array unchanged");

assertIncludes(destinationSource, "enum WorkbenchDestination", "Workbench must use the flattened eleven-destination navigation model");
assertOrdered(
  destinationSource,
  [
    "case overview",
    "case proxies",
    "case connections",
    "case logs",
    "case rules",
    "case sources",
    "case controllers",
    "case configuration",
    "case actions",
    "case diagnostics",
    "case settings",
  ],
  "Workbench destinations must have a fixed order",
);
assertIncludes(destinationSource, "enum Group", "Destinations must expose a sidebar grouping model");
assertOrdered(destinationSource, ["case workbench", "case controllerManagement", "case appSettings"], "Sidebar groups must have a fixed order");
assertIncludes(destinationSource, "static let workbenchTabCases", "Destinations must expose the shortcut-bearing workbench subset");
assertOrdered(
  destinationSource,
  ["static let workbenchTabCases", ".overview, .proxies, .connections, .logs, .rules, .sources,"],
  "Workbench tab cases must cover the six data destinations in order",
);
assertIncludes(destinationSource, "static func migrated(", "Destination model must own the legacy navigation mapping");
for (const removedNavigationModel of ["enum WorkbenchArea", "enum ActivitySection", "enum ResourcesSection", "enum SystemSection"]) {
  assertExcludes(executableSource, removedNavigationModel, `Flattened navigation must not retain legacy model ${removedNavigationModel}`);
}
for (const surface of [
  "WorkbenchControllersView(",
  "WorkbenchOverviewView(",
  "WorkbenchPolicyGroupsView(",
  "WorkbenchConnectionsView(",
  "WorkbenchRulesView(",
  "WorkbenchSourcesView(",
  "WorkbenchLogsView(",
  "WorkbenchCoreConfigView(",
  "WorkbenchCoreActionsView(",
  "WorkbenchDiagnosticsView(",
  "WorkbenchSettingsView(",
]) {
  assertIncludes(rootSource, surface, `Workbench root must route to ${surface}`);
}
assertIncludes(rootSource, ".searchable(", "Searchable data surfaces must use native toolbar search");
assertIncludes(rootSource, "ControlGroup", "Controller toolbar actions must use native grouping");
assertIncludes(rootSource, ".buttonStyle(.glass)", "Toolbar controls must use native glass controls");
assertIncludes(rootSource, ".focusedValue(\\.micaFocusedWorkbenchDestination", "Menu navigation must target the focused window");
assertExcludes(rootSource, ".safeAreaInset(edge: .top", "The competing top operation strip must stay removed");
assertIncludes(rootSource, ".safeAreaInset(edge: .bottom", "Operation feedback must use the bottom status bar");
assertIncludes(rootSource, "WorkbenchSessionStatusBar", "Main workbench must keep a persistent fixed-height session bar");
assertIncludes(rootSource, "controllerSwitcher", "Toolbar must expose the current controller switcher");
assertIncludes(rootSource, ".onChange(of: appModel.selectedRouterID)", "Every explicit controller switch path must update the independent recent-controller history");
assertIncludes(rootSource, "recordRecentController", "Recent-controller tracking must not be limited to the toolbar switcher action");
assertIncludes(micaApp, "CommandGroup(after: .sidebar)", "Navigation must extend the standard View menu");
assertIncludes(micaApp, "WorkbenchDestination.workbenchTabCases", "View menu must route to the six workbench destinations");
assertExcludes(micaApp, "command.palette_open", "Removed command palette must not remain in the app menu");
assertExcludes(micaApp, "commandPaletteRequestID", "Removed command palette plumbing must not return");
assertIncludes(micaCommandFocus, "micaFocusedWorkbenchDestination", "Focused values must expose the destination binding");
assertIncludes(micaCommandFocus, "Binding<WorkbenchDestination>", "Focused destination binding must use the destination model");
assertExcludes(micaCommandFocus, "micaCommandPaletteRequestID", "Focused values must not retain command-palette plumbing");
assertIncludes(micaCommandFocus, "micaEditControllerRequestID", "Controller menu edit must target the focused main-window editor");
assertExcludes(micaApp, "toggleLiveStreams", "Controller menu must not restore a user-visible live toggle");
assertExcludes(micaApp, "toggleSessionAutoSync", "Controller menu must not restore a user-visible sync toggle");
assertIncludes(micaApp, "MicaSymbols.Operation.pause", "Pause command must use the native pause symbol");
assertIncludes(micaApp, "MicaSymbols.Operation.resume", "Resume command must use the native resume symbol");
for (const commandSurface of [micaApp, rootSource]) {
  assertIncludes(commandSurface, "canTestSelectedRouter", "Test capability must be shared by menu and toolbar");
  assertIncludes(commandSurface, "canRefreshSelectedRouter", "Refresh capability must be shared by menu and toolbar");
  assertIncludes(commandSurface, "canTogglePresentationPause", "Pause capability must be shared by menu and toolbar");
}
assert((dataSource.match(/canRefreshSelectedRouter/g) ?? []).length >= 2, "Rules and sources refresh controls must share the paused-session refresh capability");
assertIncludes(coreSource, "isCommandEnabled", "Actions page commands must share the session command capabilities");
assertIncludes(coreSource, "appModel.canRefreshSelectedRouter", "Actions page refresh and reload commands must disable while presentation is paused");
assert((appModelSource.match(/guard canRefreshSelectedRouter/g) ?? []).length >= 3, "Rules, sources, and provider updates must guard the shared refresh capability in the model");

for (const forbiddenPresentation of [".sheet(", ".popover(", ".contextMenu("]) {
  assertExcludes(workbenchSource, forbiddenPresentation, `Ordinary workbench interaction must not use ${forbiddenPresentation}`);
}
for (const legacyConcept of ["DashboardCommandBar", "DashboardCommandPalette", "AppWorkspace", "WorkspaceActionRail", "MicaControlButtonStyle"]) {
  assertExcludes(workbenchSource, legacyConcept, `Workbench must not reuse legacy concept ${legacyConcept}`);
}

assertIncludes(micaSurfaces, "struct MicaGlassSelectionSurface", "Only one semantic custom glass selection primitive is allowed");
assertExcludes(micaSurfaces, "struct MicaSurface", "Dead custom card surfaces must stay removed");
assertExcludes(policySource, "GlassEffectContainer", "Policy content is a content-layer list and must not host a glass container (HIG: no Liquid Glass in the content layer)");
assertExcludes(policySource, ".glassEffect(", "Policy rows are content-layer data and must use standard materials, never per-row Liquid Glass");
assertExcludes(micaSurfaces, "GlassEffectContainer", "The selection primitive must not nest a glass container inside the policy selector container");
assertIncludes(micaSurfaces, "ConcentricRectangle", "Custom selection glass must use concentric geometry");
assertIncludes(micaSurfaces, "accessibilityReduceTransparency", "Glass must provide an opaque accessibility fallback");
assertIncludes(micaSurfaces, "accessibilityReduceMotion", "Glass transitions must respect Reduce Motion");
assertExcludes(micaSurfaces, "struct MicaPanel", "Dead panel compatibility helper must stay removed");
assert(!exists("Sources/Mica/App/MicaControlViews.swift"), "Dead custom icon and button chrome must stay deleted");
assertIncludes(micaStyle, "Color(nsColor: .windowBackgroundColor)", "Window content must use semantic system color");
assert(!exists("Sources/Mica/App/MicaDashboardStyle.swift"), "Removed MicaDashboard compatibility style must stay deleted");
assertExcludes(executableSource, ".environment(\.colorScheme, .dark)", "Workbench must not force a dark color scheme");
for (const forbiddenAppKitContent of ["NSTableView", "NSOutlineView", "NSViewRepresentable", "NSViewControllerRepresentable"]) {
  assertExcludes(executableSource, forbiddenAppKitContent, `Workbench content must remain pure SwiftUI: ${forbiddenAppKitContent}`);
}

assertIncludes(liveSessionModelsSource, "case fast", "Live session must expose the fast refresh lane");
assertIncludes(liveSessionModelsSource, "case medium", "Live session must expose the medium refresh lane");
assertIncludes(liveSessionModelsSource, "case slow", "Live session must expose the slow refresh lane");
assertIncludes(liveSessionModelsSource, "case .fast: .seconds(2)", "Fast refresh lane must run every two seconds");
assertIncludes(liveSessionModelsSource, "case .medium: .seconds(5)", "Medium refresh lane must run every five seconds");
assertIncludes(liveSessionModelsSource, "case .slow: .seconds(30)", "Slow refresh lane must run every thirty seconds");
assertIncludes(liveSessionSource, "controllerSession.generation == generation", "Every async apply must validate the session generation");
assertIncludes(liveSessionSource, "controllerSession.controllerID == selectedRouterID", "Global controller commands must require the selected generation to be active");
assertIncludes(selectionStateSource, "func cancelControllerOperationTasks()", "Controller lifecycle must centralize operation task cancellation");
assertIncludes(liveSessionSource, "cancelControllerOperationTasks()", "Leaving a live session must cancel controller operations");
assertIncludes(appModelSource, "isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled", "Mihomo actions must reject stale or superseded completions");
assertIncludes(surgeOperationsSource, "isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled", "Surge actions must reject stale or superseded completions");
assertIncludes(runtimeOperationsSource, "isCurrentSession(routerID: routerID, generation: generation), !Task.isCancelled", "Runtime actions must reject stale or superseded completions");
assertExcludes(runtimeOperationsSource, "guard selectedRouterID == routerID", "Runtime actions must not rely on controller ID without generation");
assertIncludes(liveSessionSource, "pendingPresentation", "Paused sessions must retain a bounded latest presentation");
assertIncludes(dashboardSessionControlsSource, "presentationPausedAt", "Paused presentation must expose a stable pause timestamp instead of a moving network timestamp");
assertIncludes(rootSource, "presentationPausedAt", "Status bar must show the frozen pause timestamp while presentation is paused");
assertIncludes(liveSessionSource, "requestImmediateSessionRefresh", "Manual and initial refresh must share the live coordinator");
assertExcludes(liveSessionSource, "sessionAutoSync", "The legacy ten-second session-sync loop must stay removed");
assertExcludes(executableSource, "func refreshSurgeRouter", "Legacy Surge snapshot refresh path must stay removed");
assertExcludes(executableSource, "func probeSurgeRouter", "Legacy Surge snapshot probe path must stay removed");
assertExcludes(operationSessionSource, "syncRequested", "User-visible sync intent must stay removed from session state");
assertExcludes(operationSessionSource, "ControllerSessionSyncState", "Legacy sync status must stay removed");
assertExcludes(operationSessionSource, "ControllerSessionSyncFailure", "Legacy sync failure wrapper must stay removed");
assertExcludes(appModelSource, "shortConnectionID", "Full-visible controller data must not retain an ID truncation helper");
assertIncludes(appModelSource, 'selectedControllerDefaultsKey = "selectedControllerID"', "Selected controller ID must persist separately");
assertIncludes(selectionStateSource, "persistSelectedRouterID(router.id)", "Explicit controller selection must update persistence");
assertIncludes(routerProfilesSource, "func upsertRouter(from draft: RouterDraft) async throws", "Controller save must be awaitable and transactional");
assertIncludes(routerProfilesSource, "func deleteRouterTransaction", "Controller deletion must expose a transactional path");
assertIncludes(routerProfilesSource, "try await profileStore.saveProfiles(nextRouters)", "Profile mutations must persist before observable commit");
assertIncludes(sessionBuffersSource, "maximumEntryCount = 2_000", "Log history must cap at 2000 entries");
assertIncludes(sessionBuffersSource, "maximumUTF8Bytes = 8 * 1_024 * 1_024", "Log history must cap at 8 MiB UTF-8");
assertIncludes(sessionBuffersSource, "maximumEntryCount = 1_000", "Closed connections must cap at 1000 entries");
assertIncludes(sessionBuffersSource, "maximumEstimatedBytes = 16 * 1_024 * 1_024", "Closed connections must cap at 16 MiB estimated data");

assertIncludes(policyPresentationSource, "return groups", "Unfiltered policy groups must retain controller order");
assertIncludes(policyPresentationSource, "return groups.filter", "Policy search may only filter visible groups");
assertIncludes(policyPresentationSource, "func filteredOptions(", "Presentation layer must expose ordered node filtering");
assertIncludes(policyPresentationSource, "return options", "An empty node filter must return controller options unchanged");
assertIncludes(policyPresentationSource, "return options.filter", "Node filtering may only filter controller options");
assertExcludes(policySource, ".sorted", "Policy groups and node options must never be sorted by the UI");
assertExcludes(policyPresentationSource, ".sorted", "Policy filtering must never sort controller groups");
assertIncludes(policySource, "columnAssignment.leadingColumn", "Policy groups must render the fixed leading parity column");
assertIncludes(policySource, "columnAssignment.trailingColumn", "Policy groups must render the fixed trailing parity column");
assertIncludes(policySource, "columnAssignment.semanticOrder", "Narrow policy layout must preserve flat semantic order");
assertIncludes(policySource, "PolicyGroupInteractionStore", "Policy groups must keep controller-scoped multi-expand state");
assertIncludes(policySource, "stalePolicyMessage", "Policy groups must keep last successful data visible with an explicit stale marker");
assertIncludes(policySource, "PolicyGroupPresentation.arrangedGroups(", "Arranged groups must come from the presentation helper");
assertIncludes(policyPresentationSource, "func arrangedGroups(", "Presentation layer must expose the GLOBAL arrangement helper");
assertIncludes(policyPresentationSource, "groups.filter", "GLOBAL arrangement must partition via filter, never sort");
assertIncludes(policyPresentationSource, "return otherGroups + globalGroups", "Visible GLOBAL groups must be appended after controller-ordered peer groups");
assertExcludes(policyPresentationSource, "globalGroupPositions", "GLOBAL pin-last must not reorder controller groups via decoded metadata");
assertExcludes(policySource, "globalGroupPositions", "GLOBAL pin-last must live in the presentation layer, not decoded metadata");
assertIncludes(policySource, "DisclosureGroup", "Policy groups must use the native disclosure mechanism to expand in place");
assertIncludes(policySource, "appModel.selectPolicyGroup(group.id)", "Policy actions must retain active selection identity by group ID");
assertIncludes(policySource, "reconcilePolicyGroupPresentation", "Search must not reconcile policy selection against a filtered collection");
assertExcludes(policySource, "reconcile(with: filteredGroups)", "Search filtering must never change selected policy identity");
assertIncludes(policySource, "visibleMembers(filteredOptions, in: group)", "Policy members must page through ordered controller nodes");
assertIncludes(policySource, "PolicyGroupPresentation.filteredOptions(", "Expanded policy groups must filter the complete ordered node collection");
assertIncludes(policySource, "visibleMembers(filteredOptions, in: group)", "Node filtering must feed the filtered collection into member pagination");
assertIncludes(policySource, "hasMoreMembers(filteredOptions, in: group.id)", "Member pagination state must use the filtered node count");
assertIncludes(policySource, "totalCount: filteredOptions.count", "Loading more nodes must advance the filtered member window");
assert(
  policySource.indexOf("PolicyGroupPresentation.filteredOptions(") < policySource.indexOf("visibleMembers(filteredOptions, in: group)"),
  "Policy node filtering must run before the local member window is applied",
);
assertIncludes(policySource, "selectNode(member.name, in: group.id)", "Mihomo policy selection must be inline");
assertIncludes(policySource, "selectSurgePolicy(member.name, in: group.id)", "Surge policy selection must be inline");
assertIncludes(policySource, "measureDelay(in: groupID)", "Mihomo latency tests must be inline");
assertIncludes(policySource, "measureDelay(for: member.name, in: group.id)", "Single-node latency tests must stay inline beside the reported node");
assertIncludes(policySource, "routing.test_node", "Single-node latency controls must expose localized accessibility copy");
assertIncludes(policySource, "testSurgePolicyGroup(groupID)", "Surge latency tests must be inline");
assertIncludes(policySource, "runtimeControllerKind(for: router) == .surgeCompatible", "Auto Detect policy actions must use the detected runtime backend");
assertIncludes(policySource, "group.detail(for: option)", "Policy members must consume complete decoded node details");
for (const field of ["member.alive", "member.providerName", "member.interfaceName", "member.transportNames", "member.testURL", "member.icon", "member.additionalMetadataText"]) {
  assertIncludes(policySource, field, `Policy members must expose ${field}`);
}
assertIncludes(policySource, "group.details?.fixed?.nilIfEmpty != nil", "Fixed-selection cancellation must appear only when the controller reports a real fixed state");
assertIncludes(policySource, "appModel.clearFixedSelection(in: group.id)", "Fixed-selection cancellation must stay inline in the policy group");
assertIncludes(appModelSource, "func clearFixedSelection(in groupID: String)", "AppModel must own the generation-guarded fixed-selection transaction");
assertIncludes(appModelSource, "func measureDelay(for node: String, in groupID: String)", "AppModel must own generation-guarded single-node latency tests");
assertIncludes(appModelSource, "client.providerProxyDelay", "Provider-backed nodes must use the provider proxy delay endpoint");
assertIncludes(appModelSource, "mutateSessionDashboard", "Controller actions must respect presentation pause when publishing dashboard changes");
assertIncludes(appModelSource, "recordClosedSessionConnections", "Connection actions must buffer closed rows while presentation is paused");
assertIncludes(surgeOperationsSource, "operation.surge_request_killed_refresh_failed", "Surge request termination must report refresh-after-write failure as partial success");
assertIncludes(surgeOperationsSource, "removeSessionConnections", "Confirmed Surge closures must leave the active presentation even if refresh fails");
assertIncludes(surgeOperationsSource, "operation.surge_mode_changed_refresh_failed", "Surge mode writes must report refresh-after-write failures as partial success");
assertIncludes(surgeOperationsSource, "operation.surge_policy_switched_refresh_failed", "Surge policy writes must report refresh-after-write failures as partial success");
assertIncludes(appModelSource, "operation.mode_changed_refresh_failed", "Mihomo mode writes must report refresh-after-write failures as partial success");
assertIncludes(appModelSource, "operation.route_switched_refresh_failed", "Mihomo node writes must report refresh-after-write failures as partial success");
assertIncludes(appModelSource, "operation.fixed_selection_cleared_refresh_failed", "Fixed-selection clearing must report refresh-after-write failures as partial success");
assertIncludes(appModelSource, "client.clearFixedProxy(group: groupID)", "Fixed-selection cancellation must call the remote controller endpoint");
for (const legacySessionState of ["ConnectionSessionSort", "ConnectionSessionGrouping", "RuleSessionSort", "ProviderSessionSort", "sortedRules", "sortedProviders"]) {
  assertExcludes(dashboardSessionControlsSource, legacySessionState, `Legacy local ordering state must stay removed: ${legacySessionState}`);
}
assertIncludes(workbenchContract, "Fixed-selection cancellation stays inline in the expanded policy group and appears only when the controller exposes both a real fixed state and cancellation capability", "Durable UI contract must gate fixed-selection cancellation on real controller support");
assertIncludes(workbenchContract, "when shown it is placed last via stable partition", "Durable UI contract must keep GLOBAL at the end");
assertIncludes(workbenchContract, "before `PolicyGroupInteractionStore` applies that group's local member window", "Durable UI contract must filter policy nodes before pagination");
assertExcludes(dashboardSessionControlsSource, "proxyMemberLimitByGroup", "Policy member pagination must have one controller-scoped state owner");
assertExcludes(selectionStateSource, "showMoreProxyOptions", "Removed policy pagination wrappers must not return to AppModel");
assertIncludes(policyInteractionSource, "static let memberWindowSize = 48", "Policy member pagination must retain its 48-item controller-scoped window");
assertIncludes(activityResourcesPresentationSource, "if sourceCount > 0", "Unavailable rules and sources must keep last successful rows visible");
assertIncludes(workbenchContract, "Never render the same localization key or sentence in both positions", "Durable UI contract must prevent repeated empty-state copy");
assertIncludes(workbenchContract, "center the empty state horizontally and vertically in the remaining content region", "Durable UI contract must center data empty states below command areas");
assertIncludes(policySource, "group.hidden", "Controller-reported hidden state must remain visible");
assertExcludes(policySource, ".lineLimit(", "Policy and node business text must not be line-limited");
assertExcludes(policySource, ".truncationMode(", "Policy and node business text must not be middle-truncated");
assertExcludes(policySource, ".buttonStyle(.glass)", "Policy selection actions must not layer glass controls inside glass selector blocks");
assertExcludes(policySource, ".controlSize(.small)", "Policy operations must inherit the selected font and control scale");
assertIncludes(mihomoModels, "return orderedGroups", "Mihomo policy groups must preserve controller order");
assertExcludes(mihomoModels, "globalGroupPositions", "GLOBAL metadata must not reorder controller policy groups");
for (const fabricatedLabel of ["Routing Module ", "Selected Node", "Policy Group ", "Selected Policy"]) {
  assertExcludes(unifiedAdapterSource, fabricatedLabel, `Adapters must not fabricate controller label ${fabricatedLabel}`);
}

for (const field of [
  "connection.id",
  "metadata?.host",
  "metadata?.process",
  "metadata?.processPath",
  "metadata?.sourceIP",
  "metadata?.destinationIP",
  "connection.rulePayload",
  "connection.chains",
]) {
  assertIncludes(connectionsSource, field, `Connections must expose full controller field ${field}`);
}
for (const field of [
  "metadata?.specialProxy",
  "metadata?.specialRules",
  "metadata?.remoteDestination",
  "metadata?.connectionLogs",
  "connection.providerChains",
  "connection.uploadSpeed",
  "connection.downloadSpeed",
  "connection.additionalFieldsText",
  "metadata?.additionalFieldsText",
]) {
  assertIncludes(connectionsSource, field, `Connections must expose complete controller field ${field}`);
}
for (const field of [
  "public var uploadSpeed: Int?",
  "public var downloadSpeed: Int?",
  "public var providerChains: [String]?",
  "public var specialProxy: String?",
  "public var specialRules: String?",
  "public var remoteDestination: String?",
  "public var connectionLogs: [String]?",
  "public var fields: [String: MihomoJSONValue]",
]) {
  assertIncludes(mihomoModels, field, `Connection decoding must preserve ${field}`);
}
assertIncludes(operationSessionSource, "struct ConnectionTransferRateTracker", "Connection rates must be session-owned");
assertIncludes(operationSessionSource, "current >= previous ? current - previous : 0", "Connection counter resets must not create negative rates");
assertIncludes(liveSessionSource, "controllerSession.connectionTransferRates.enriching(", "Live connection frames must derive per-connection rates");
assertIncludes(surgeOperationsSource, "func projectedSurgeDashboard(", "Surge request frames must share the session-owned connection rate projection");
assertIncludes(surgeOperationsSource, "controllerSession.connectionTransferRates.enriching(", "Surge request rates must derive from successive near-live frames when absent upstream");
assertIncludes(liveSessionSource, "connectionRatesReceivedAt: checkedAt", "Surge near-live frames must timestamp per-request rate derivation");
for (const field of ["metadata?.inboundIP", "metadata?.inboundPort", "metadata?.uid", "WorkbenchInspectorValueRow", "of: ConnectionSnapshot.self"]) {
  assertIncludes(connectionsSource, field, `Connections must use a native table and expose ${field}`);
}
assertIncludes(activityResourcesPresentationSource, "static func ownerGroups", "Connections must group by process/source in the presentation layer");
assertIncludes(activityResourcesPresentationSource, "case inner", "Internally generated connections need a distinct owner group");
assertIncludes(connectionsSource, "Section {", "Grouped connections must remain native Table sections");
assertIncludes(connectionsSource, "groupsByOwner", "Connection owner grouping must be user-controlled");
assertIncludes(connectionsSource, "appModel.closeConnectionGroup(", "Connection owner groups must support same-window close actions");
assertIncludes(appModelSource, "func closeConnectionGroup(", "Connection group closing must stay outside the View network layer");
assertIncludes(selectionStateSource, "closingConnectionGroupID", "Connection group operations must reset with the session generation");
assertIncludes(connectionsSource, "sortOrder: $connectionSortOrder", "Connection column sorting must use the native table sortOrder binding");
assertIncludes(connectionsSource, "ConnectionWorkbenchPresentation.ordered(", "Connection sorting must run in the presentation layer");
assertExcludes(connectionsSource, ".sorted", "Connections view must not sort inline; ordering lives in the presentation layer");
assertIncludes(connectionsSource, ".inspector(isPresented:", "Connection detail must open as an on-demand inspector");
assertExcludes(connectionsSource, "HSplitView", "Connections must not keep a resident split placeholder pane");
assertExcludes(connectionsSource, "VSplitView", "Connections must not keep a resident split placeholder pane");
assertIncludes(connectionsSource, "pendingCloseID", "Connection close must confirm inline");
assertExcludes(connectionsSource, "confirmationDialog", "Connection close must not use a modal confirmation");
assertExcludes(connectionsSource, ".truncationMode(.middle)", "Connections must not middle-truncate controller data");
assertIncludes(connectionsSource, "activeConnectionStaleMessage", "Connections must keep last successful rows visible with an explicit stale marker");
assertExcludes(connectionsSource, ".lineLimit(1)", "Connections must not hide controller data in a single line");
assertIncludes(connectionsSource, 'titleKey: "dashboard.no_matching_connections"', "Filtered connections must use a distinct empty-state title");
assertExcludes(connectionsSource, 'titleKey: "traffic.empty_filtered"', "Filtered connection title must not duplicate its description");
assertIncludes(connectionsSource, ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)", "Connection empty states must center in the remaining content area");
assertIncludes(dataSource, "Table(sortedRuleRows, selection:", "Rules must use a native selectable table");
assertIncludes(dataSource, "sortOrder: $ruleSortOrder", "Rule column sorting must use the native table sortOrder binding");
assertIncludes(dataSource, "RulesWorkbenchPresentation.ordered(", "Rule sorting must run in the presentation layer");
assertOrdered(dataSource, ["row.rule.payload", "row.rule.type", "row.rule.proxy"], "Rules must stay payload-first");
for (const field of ["row.rule.index", "rule.disabled", "row.rule.hitCount", "row.rule.missCount", "rule.hitAt", "rule.missAt", "rule.additionalExtraText", "rule.additionalMetadataText"]) {
  assertIncludes(dataSource, field, `Rules must expose ${field}`);
}
assertIncludes(dataSource, "rule.hasMutableExtra", "Rule state controls must require controller-reported extra state");
assertIncludes(dataSource, "appModel.supportsUnifiedAction(.setRuleDisabled)", "Rule state controls must require a real backend capability");
assertIncludes(dataSource, "appModel.setRuleDisabled(rule, disabled: $0)", "Rule state changes must stay in the same-window inspector");
assertIncludes(appModelSource, "func setRuleDisabled(_ rule: RuleViewState, disabled: Bool)", "AppModel must own generation-guarded rule state changes");
assertIncludes(appModelSource, "client.setRuleDisabled(index: index, disabled: disabled)", "Rule state changes must call the official controller endpoint");
assertExcludes(dataSource, ".truncationMode(.middle)", "Rules and sources must not middle-truncate controller data");
assertExcludes(dataSource, ".sorted", "Rules and sources views must not sort inline; ordering lives in the presentation layer");
assertIncludes(dataSource, ".inspector(isPresented:", "Rules and sources detail must open as on-demand inspectors");
assertExcludes(dataSource, "HSplitView", "Rules and sources must not keep a resident split placeholder pane");
assertExcludes(dataSource, "VSplitView", "Rules and sources must not keep a resident split placeholder pane");
assertIncludes(activityResourcesPresentationSource, "static func ordered(", "Presentation layer must own user-initiated table ordering");
assertIncludes(activityResourcesPresentationSource, "classifyUpdatedAt", "Sources must classify controller updatedAt values instead of echoing zero times");
assertIncludes(activityResourcesPresentationSource, "neverUpdated", "Go zero-time updatedAt must map to a dedicated never-updated state");
for (const field of ["source.name", "source.vehicleType", "source.behavior", "source.format", "source.healthCheckText", "source.updatable", "source.itemCount", "source.updatedAt"]) {
  assertIncludes(dataSource, field, `Sources must expose ${field}`);
}
assertIncludes(dataSource, "Table(sortedSources, selection:", "Sources must use a native selectable table");
assertIncludes(dataSource, "sortOrder: $sourceSortOrder", "Source column sorting must use the native table sortOrder binding");
assertIncludes(dataSource, "SourcesWorkbenchPresentation.ordered(", "Source sorting must run in the presentation layer");
assertIncludes(dataSource, "updateProxyProvider(source)", "Sources must use the AppModel remote update operation");
assertIncludes(dataSource, "if source.updatable", "Sources must hide update actions for read-only providers");
assertIncludes(appModelSource, "guard provider.updatable else", "Provider updates must enforce per-record capability in AppModel");
assertIncludes(dataSource, "source.supportsHealthCheck", "Sources must gate health checks with per-record metadata");
assertIncludes(dataSource, "healthCheckProxyProvider(source)", "Sources must use the AppModel remote health-check operation");
assertIncludes(dataSource, "appModel.supportsUnifiedAction(.healthCheckProvider)", "Provider health checks must require a real backend capability");
assertIncludes(appModelSource, "func healthCheckProxyProvider(_ provider: ProxyProviderViewState)", "AppModel must own generation-guarded provider health checks");
assertIncludes(appModelSource, "guard provider.supportsHealthCheck else", "Provider health checks must enforce per-record capability in AppModel");
assertIncludes(appModelSource, "client.healthCheckProxyProvider(name: provider.name)", "Provider health checks must call the official controller endpoint");
assertIncludes(selectionStateSource, "checkingProviderName", "Provider health-check markers must reset with the session generation");
assertIncludes(activityResourcesPresentationSource, "ProviderUpdatePresentationState", "Sources must expose ready, updating, and failure presentation states");
assertIncludes(dataSource, "entry.message.payload", "Logs must show original controller messages");
assertIncludes(dataSource, "entry.message.time", "Logs must preserve controller-reported timestamps");
assertIncludes(dataSource, "entry.structuredFieldsText", "Logs must expose structured controller fields");
assertIncludes(liveSessionSource, "operation.full_refresh_loaded", "Manual refresh must report completion through the localized session coordinator");
assertIncludes(dataSource, "toggleControllerLogsPaused", "Logs must support an independent presentation pause");
assertExcludes(dataSource, "toggleDashboardUpdatesPaused", "The Logs pause control must not freeze the whole workbench");
assertIncludes(dataSource, "clearControllerLogs", "Logs must support clearing controller rows");
assertIncludes(dataSource, "followBottom", "Logs must support follow-bottom state");
assertIncludes(dataSource, "traffic.jump_to_newest", "Logs must expose jump-to-newest when follow-bottom is off");
assertIncludes(dataSource, "LogsWorkbenchPresentation.emptyState(", "Logs must resolve distinct empty-state title and message keys in the presentation layer");
assertIncludes(dataSource, "MicaText(emptyState.titleKey)", "Logs must render the resolved empty-state title");
assertIncludes(dataSource, "MicaText(emptyState.messageKey)", "Logs must render the resolved empty-state description");
assertIncludes(dataSource, 'titleKey: "dashboard.no_matching_sources"', "Filtered sources must use a distinct empty-state title");
assertIncludes(dataSource, '"traffic.sources_empty_message"', "Empty source categories must use a distinct explanatory message");
assertExcludes(dataSource, 'titleKey: "traffic.empty_filtered"', "Filtered data titles must not duplicate the generic filter description");
assertIncludes(activityResourcesPresentationSource, 'titleKey: "dashboard.no_matching_logs"', "Filtered logs must use a distinct title key");
assertIncludes(activityResourcesPresentationSource, 'messageKey: "dashboard.no_logs_yet_message"', "Empty logs must use a distinct explanatory message key");
assert((dataSource.match(/\.frame\(maxWidth: \.infinity, maxHeight: \.infinity, alignment: \.center\)/g) ?? []).length >= 3, "Rules, sources, and logs must center empty states in their remaining content areas");
assertExcludes(dataSource, ".reversed()", "Logs must preserve AppModel message order while filtering");
assertIncludes(sessionBuffersSource, "entries.append(entry)", "Controller logs must remain oldest-to-newest for follow-bottom behavior");
assertIncludes(liveSessionSource, "logsStream(level: upstreamLevel)", "Changing the log level must rebuild the upstream subscription");
assertIncludes(liveSessionSource, "ControllerLogEntry(message: log)", "Only controller log frames may enter the controller log buffer");
assertExcludes(executableSource, "DashboardLogEntry", "Legacy mixed dashboard log entries must stay removed");
assertExcludes(executableSource, "dashboard.appendLog", "Application operation messages must not enter controller logs");
assertExcludes(dataSource, ".sheet(", "Activity and resources must not use ordinary sheets");
assertExcludes(dataSource, ".popover(", "Activity and resources must not use ordinary popovers");

for (const key of [
  "dashboard.no_logs_yet_message",
  "dashboard.no_matching_logs",
  "dashboard.no_matching_sources",
  "traffic.sources_empty_message",
  "traffic.provider_health_check_failed %@",
  "operation.configuration_reload_running",
  "operation.configuration_reload_done",
  "operation.geo_data_update_running",
  "operation.geo_data_update_done",
  "capability.impact_configuration_reload_supported",
  "capability.impact_geo_update_supported",
  "diagnostics.operation_configuration_reload_evidence %lld",
  "diagnostics.operation_geo_update_evidence %lld",
  "controller_kind.cmfa",
  "controller_kind.stash",
  "unified.label_cmfa",
  "unified.label_stash",
  "unified.boundary_cmfa",
  "unified.boundary_stash",
  "adapter.source_cmfa",
  "adapter.source_stash",
  "capability.impact_configs_read_only",
]) {
  assertLocalized(strings, key);
}
for (const language of ["en", "zh-Hans"]) {
  const localization = (key) => strings[key]?.localizations?.[language]?.stringUnit?.value;
  assert(localization("dashboard.no_logs_yet") !== localization("dashboard.no_logs_yet_message"), `Log empty title and description must differ in ${language}`);
  assert(localization("dashboard.no_matching_logs") !== localization("traffic.empty_filtered"), `Filtered log title and description must differ in ${language}`);
}

for (const realOverviewValue of [
  "appModel.liveTrafficRate.upload",
  "appModel.liveTrafficRate.download",
  "appModel.dashboard.traffic.upload",
  "appModel.dashboard.traffic.download",
  "appModel.dashboard.connections.count",
  "appModel.dashboard.groups.count",
  "appModel.controllerHealth.endpoints",
]) {
  assertIncludes(overviewSource, realOverviewValue, `Overview must use real controller value ${realOverviewValue}`);
}
assertIncludes(overviewSource, "import Charts", "Overview may use Charts only with a real traffic timeline contract");
assertIncludes(overviewSource, "appModel.trafficTimeline.isEmpty", "Overview must not draw a chart without received traffic samples");
assertIncludes(overviewSource, "appModel.trafficTimeline.samples", "Overview charts must read the bounded real traffic timeline");
assertIncludes(overviewSource, ".interpolationMethod(.linear)", "Traffic charts must not smooth or overshoot real samples");
assertIncludes(overviewSource, "overview.traffic_timeline_samples", "Traffic chart accessibility must use a dedicated sample-count label");
assertIncludes(overviewSource, "appModel.dashboard.insight", "Overview insight modules must bind the shared insight snapshot");
assertIncludes(overviewSource, "insight.routeHealth", "Latency distribution must bind real insight buckets");
assertIncludes(overviewSource, "insight.connectionDistribution", "Link share must bind real insight distribution");
assertIncludes(overviewSource, "insight.topConnections", "Top connections must bind real insight ranking");
assertIncludes(overviewSource, "insight.hasLatencySamples", "Latency distribution must guard its empty state");
assertIncludes(overviewSource, "insight.hasConnectionDistribution", "Link share must guard its empty state");
assertIncludes(overviewSource, 'x: .value("Grade"', "Snapshot latency chart must use a category X axis, not a time axis");
assert(
  (overviewSource.match(/\.value\("Time"/g) ?? []).length === (overviewSource.match(/x: \.value\("Time", sample\.receivedAt\)/g) ?? []).length,
  "Time axes must bind only the received traffic samples",
);
assertExcludes(overviewSource, "Timer", "Overview must not synthesize chart samples");
assertIncludes(trafficTimelineSource, "static let maximumSampleCount = 300", "Traffic timeline must retain at most 300 received samples");
assertIncludes(trafficTimelineSource, "static let retentionDuration: TimeInterval = 5 * 60", "Traffic timeline must retain only five minutes of real samples");
assertIncludes(trafficTimelineSource, "mutating func append", "Traffic timeline must append received traffic samples");
assertExcludes(trafficTimelineSource, "Timer", "Traffic timeline must not synthesize timer samples");
assertExcludes(trafficTimelineSource, "interpolationMethod", "Traffic timeline must not choose a synthetic interpolation mode");
assertIncludes(liveSessionSource, "controllerSession.trafficTimeline.append(", "Live traffic events must feed the session-owned real timeline");
assertIncludes(liveSessionSource, "upload: event.upload", "Mihomo traffic must remain controller-reported");
assertIncludes(liveSessionSource, "upload: traffic.upload", "Surge traffic must remain controller-reported");
assertIncludes(liveSessionSource, "controllerSession.trafficTimeline.reset()", "Starting a new generation must clear the session timeline");
assertIncludes(selectionStateSource, "trafficTimeline.reset()", "Controller switches must clear the traffic timeline");

for (const configField of ["logLevel", "allowLan", "ipv6", "tcpConcurrent", "tunEnabled", "port", "socksPort", "redirPort", "mixedPort"]) {
  assertIncludes(coreSource, `dashboard.config.${configField}`, `Core configuration must expose ${configField}`);
}
assertIncludes(coreSource, "appModel.setMode(newMode)", "Mode changes must use the existing real write path");
assertIncludes(coreSource, "appModel.modeChangeAction(for: router)", "Mode controls must use the detected backend capability route");
assertIncludes(appModelSource, "func modeChangeAction(for router: RouterProfile)", "Mode capability routing must have one AppModel source of truth");
assertIncludes(appModelSource, "setSurgeOutboundMode(mode)", "The shared mode intent must dispatch Surge to its official outbound-mode operation");
assertIncludes(coreSource, "appModel.updateControllerConfig", "Reported Mihomo configuration fields must use the typed runtime write path");
assertIncludes(coreSource, "Toggle(", "Boolean controller configuration must use native toggles");
assertIncludes(coreSource, "WorkbenchConfigPortRow", "Reported controller ports must use an explicit commit control");
assertIncludes(configOperationsSource, "client.updateConfigs(mutation.patch)", "Configuration writes must use PATCH /configs through MicaCore");
assertIncludes(configOperationsSource, "isCurrentSession(routerID: router.id, generation: generation)", "Configuration results must be generation-guarded");
assertIncludes(selectionStateSource, "configTask?.cancel()", "Controller lifecycle changes must cancel configuration writes");
assertIncludes(coreSource, "supportsUnifiedAction(action)", "Core actions must remain capability-gated");
assertIncludes(coreSource, "performDiagnosticsRuntimeOperation", "Core actions must use existing real remote API operations");
for (const remoteMaintenanceID of ["configuration-reload", "geo-resources", "cache-flush"]) {
  assertIncludes(coreSource, `performDiagnosticsRuntimeOperation("${remoteMaintenanceID}")`, `Actions must expose ${remoteMaintenanceID} through AppModel`);
  assertIncludes(runtimeOperationsSource, `case "${remoteMaintenanceID}"`, `AppModel must route ${remoteMaintenanceID} to a typed remote operation`);
}
assertIncludes(runtimeOperationsSource, "client.reloadConfigs()", "Configuration reload must call PUT /configs without local path or payload input");
assertIncludes(runtimeOperationsSource, "client.updateGeoData()", "GeoData update must call POST /configs/geo");
assertIncludes(runtimeOperationsSource, "client.flushFakeIPCache()", "FakeIP flush must call the remote cache endpoint");
assertExcludes(coreSource, "core-restart", "Ordinary Actions must not expose remote core restart without a dedicated high-risk confirmation flow");
assertExcludes(coreSource, "core-upgrade", "Ordinary Actions must not expose remote core upgrade without a dedicated high-risk confirmation flow");
assertIncludes(coreSource, "appModel.reloadSurgeProfile()", "Actions must expose the official Surge profile reload operation");
assertIncludes(dataSource, "appModel.supportsUnifiedAction(.setLogLevel)", "The Logs level control must follow the runtime capability matrix");
assertIncludes(dataSource, "appModel.selectedUnifiedCapabilities.logs", "Backends without a remote log-level action must still allow local filtering when logs are available");
assertIncludes(dataSource, "appModel.controllerSession.logBuffer.entries.isEmpty", "Log clearing must use the session source even while presentation is paused");
assertIncludes(selectionStateSource, "client.setLogLevel(level.surgeUpstreamValue)", "Surge log levels must update the upstream controller session");
assertIncludes(coreSource, "unifiedUnavailableReason", "Unavailable core actions must explain the capability boundary");
assertExcludes(coreSource, "confirmationDialog", "Core actions must not use modal confirmations");
assertIncludes(diagnosticsSource, "controllerHealth.endpoints", "Diagnostics must show real endpoint health");
assertIncludes(diagnosticsSource, "capabilityMatrixRows", "Diagnostics must show capability rows directly from AppModel");
assertIncludes(diagnosticsSource, "controllerDataCoverageRows", "Diagnostics must show data availability rows directly from AppModel");
assertIncludes(diagnosticsSource, "copyDiagnosticsReport", "Diagnostics must retain copy-report action");

assertIncludes(settingsSource, "@AppStorage(AppPreferencesStore.languageKey)", "Settings must persist language");
assertIncludes(settingsSource, "@AppStorage(AppPreferencesStore.appearanceKey)", "Settings must persist appearance");
assertIncludes(settingsSource, "@AppStorage(AppPreferencesStore.fontScaleKey)", "Settings must persist font scale");
assertIncludes(settingsSource, "appModel.applyPresentationLanguage(appLanguage)", "Language changes must repaint cached presentation strings");
assertIncludes(settingsSource, "appAppearance.applyToApplication()", "Appearance changes must apply immediately");
assertIncludes(settingsSource, "router.endpointURL", "Settings must show the full controller endpoint");
assertIncludes(appAppearance, "application.appearance = nsAppearance", "Appearance must apply to the application");
assertIncludes(appAppearance, "window.appearance = nsAppearance", "Appearance must apply to existing windows");
assertIncludes(appFontScale, "case extraLarge", "Font scale must expose four user choices");
for (const multiplier of ["0.92", "1.0", "1.16", "1.32"]) {
  assertIncludes(appFontScale, multiplier, `Font scale must include multiplier ${multiplier}`);
}
assertIncludes(preferenceEnvironment, "dynamicTypeSize(fontScale.dynamicTypeSize)", "Font scale must update Dynamic Type");
assertIncludes(preferenceEnvironment, "controlSize(fontScale.controlSize)", "Font scale must update native controls");
assert((micaApp.match(/\.micaScenePreferences\(/g) ?? []).length >= 2, "Main and Settings scenes must receive language, appearance, and font scale");

// Rose Pine semantic tokens. Light foreground variants are contrast-adjusted so
// the same constants meet WCAG 4.5:1 on light content surfaces; dark mint is
// likewise adjusted. The semantic mapping remains violet=selection,
// mint=healthy, cyan=information, amber=warning, and red=danger.
for (const token of [
  "light: nsColor(0.478, 0.404, 0.561)",
  "light: nsColor(0.492, 0.416, 0.577)",
  "dark: nsColor(0.769, 0.655, 0.906)",
  "light: nsColor(0.157, 0.412, 0.514)",
  "dark: nsColor(0.264, 0.626, 0.771)",
  "light: nsColor(0.263, 0.467, 0.498)",
  "dark: nsColor(0.612, 0.812, 0.847)",
  "light: nsColor(0.588, 0.392, 0.122)",
  "dark: nsColor(0.965, 0.757, 0.467)",
  "light: nsColor(0.635, 0.341, 0.427)",
  "dark: nsColor(0.922, 0.435, 0.573)",
]) {
  assertIncludes(micaStyle, token, `MicaStyle must retain Rose Pine token ${token}`);
}
assertNoUnscaledFonts([...workbenchFiles, ...routerEditorFiles]);

for (const key of [
  "workbench.settings",
  "workbench.actions",
  "workbench.configuration",
  "editor.controller_preview",
  "editor.target_not_configured",
  "traffic.follow_bottom",
  "traffic.clear_logs",
  "traffic.pause_logs",
  "traffic.resume_logs",
  "traffic.help_pause_logs",
  "traffic.provider_format",
  "traffic.provider_health_check",
  "traffic.provider_not_updatable",
  "traffic.provider_updatable",
  "traffic.provider_updatable_yes",
  "traffic.provider_updatable_no",
  "traffic.bytes_per_second %@",
  "traffic.connection_additional_fields",
  "traffic.connection_group_inner",
  "traffic.connection_group_summary %lld %@ %@",
  "traffic.connection_group_unreported",
  "traffic.connection_logs",
  "traffic.connection_metadata_fields",
  "traffic.download_speed",
  "traffic.group_connections_by_owner",
  "traffic.help_close_connection_group",
  "traffic.provider_chain",
  "traffic.remote_destination",
  "traffic.special_proxy",
  "traffic.special_rules",
  "traffic.upload_speed",
  "routing.additional_fields",
  "routing.clear_fixed_selection",
  "routing.clearing_fixed_selection",
  "routing.delay_history",
  "routing.fixed_selection",
  "routing.history_summary %lld %@ %@",
  "routing.help_clear_fixed_selection",
  "routing.icon_url",
  "routing.node_alive",
  "routing.node_interface",
  "routing.node_provider",
  "routing.node_status",
  "routing.node_transports",
  "routing.node_unavailable",
  "routing.test_url",
  "action.clear_fixed_selection",
  "action.apply_port",
  "action.close_connection_group",
  "action.help_surge_reload_profile",
  "action.remote_profile",
  "action.resume",
  "action.set_allow_lan",
  "action.set_config",
  "action.set_ipv6",
  "action.set_log_level",
  "action.set_port",
  "action.set_tcp_concurrent",
  "action.set_tun",
  "action.surge_reload_profile",
  "action.set_rule_state",
  "dashboard.col_index",
  "dashboard.confirm_close_connection_group_message %lld %@ %@",
  "operation.clearing_fixed_selection",
  "operation.config_field_update_failed",
  "operation.config_field_updated",
  "operation.config_field_updated_refresh_pending",
  "operation.close_connection_group_failed",
  "operation.close_connection_group_partial %lld %lld",
  "operation.closed_connection_group %lld",
  "operation.closing_connection_group %lld",
  "operation.closing_connection_group_progress %lld %@",
  "operation.reloading_surge_profile",
  "operation.select_router_config",
  "operation.select_surge_profile_reload",
  "operation.setting_log_level",
  "operation.setting_surge_log_level %@",
  "operation.surge_log_level_update_failed",
  "operation.surge_log_level_updated %@",
  "operation.surge_profile_reload_failed",
  "operation.surge_profile_reloaded",
  "operation.updating_config_field",
  "operation.fixed_selection_clear_failed",
  "operation.fixed_selection_cleared",
  "operation.fixed_selection_not_reported",
  "operation.rule_state_not_supported",
  "operation.rule_state_update_failed",
  "operation.rule_state_updated",
  "operation.updating_rule_state",
  "traffic.help_rule_disabled",
  "traffic.rule_disabled",
  "traffic.rule_extra_fields",
  "traffic.rule_hit_at",
  "traffic.rule_hit_rate",
  "traffic.rule_hits",
  "traffic.rule_miss_at",
  "traffic.rule_misses",
  "traffic.rule_status_disabled",
  "traffic.rule_status_enabled",
  "traffic.rule_updating",
  "workspace.overview",
  "dashboard.routing_modules_header",
  "dashboard.tab_connections",
  "dashboard.tab_rules",
  "dashboard.tab_providers",
  "dashboard.tab_logs",
  "workspace.diagnostics",
  "sidebar.group_workbench",
  "sidebar.group_controller_management",
  "sidebar.group_app_settings",
  "navigation.overview",
  "navigation.proxies",
  "overview.insight_dashboard",
  "overview.latency_distribution",
  "overview.latency_distribution_empty",
  "overview.connection_distribution",
  "overview.connection_distribution_empty",
  "overview.top_connections",
  "overview.top_connections_empty",
  "operation.refresh_loaded %lld %lld %lld",
  "dashboard.mode",
  "diagnostics.capability_matrix_title",
  "capability.unsupported_sing_box_data",
  "live.channel_sing_box_grpc",
  "live.last_update_never",
  "session.live_source_sing_box_grpc",
  "editor.window_close_unsaved_title",
  "editor.window_close_unsaved_message",
  "data.stale_count %lld",
  "data.stale_detail %@",
]) {
  assertLocalized(strings, key);
}
assertDirectWorkbenchLocalizationKeys(workbenchFiles, strings);
assertDirectWorkbenchLocalizationKeys(routerEditorFiles, strings);
for (const removedKey of [
  "sidebar.control_bay",
  "command.acc_bar",
  "command.search_placeholder",
  "command.palette_open",
  "command.palette_title",
  "overview.command_home_title",
  "overview.telemetry_rail",
  "routing.command_scope",
  "workspace.routing",
  "workspace.traffic",
  "diagnostics.operation_core_config",
  "workbench.core_actions",
  "editor.controller_handshake",
  "routing.cancel_fixed",
  "routing.help_cancel_fixed",
  "routing.unpin_next_step",
  "operation.route_unpin_unavailable",
  "log.route_unpin_unavailable",
  "sidebar.sync",
  "live.help_start",
  "live.help_start_near_live",
  "live.help_stop",
  "live.start",
  "live.start_near_live",
  "live.stop",
  "live.surge_snapshot_only",
  "log.session_sync_failed %@",
  "log.session_sync_reconnecting",
  "log.session_sync_retry_scheduled %lld",
  "log.session_sync_starting",
  "log.session_sync_stopped",
  "operation.session_sync_failed",
  "operation.session_sync_partial",
  "operation.session_sync_reconnecting",
  "operation.session_sync_starting",
  "operation.session_sync_stopped",
  "operation.session_sync_unavailable",
  "operation.refreshing_surge_progress",
  "operation.refreshing_surge_snapshot",
  "operation.surge_snapshot_failed",
  "operation.testing_surge_progress",
  "session.detail_idle",
  "session.detail_stopped",
  "session.detail_synced",
  "session.detail_syncing",
  "session.help_start_sync",
  "session.help_stop_sync",
  "session.no_controller",
  "session.start_sync",
  "session.state_failed",
  "session.state_idle",
  "session.state_partial",
  "session.state_stopped",
  "session.state_synced",
  "session.state_syncing",
  "session.state_unavailable",
  "session.stop_sync",
  "session.sync_summary %@ %lld %lld",
  "session.unsupported_backend",
  "snapshot.base_refresh_cleared",
  "snapshot.base_refresh_rules_unavailable",
  "snapshot.base_test_cleared",
  "snapshot.profile_test_cleared",
  "workspace.action_live_detail",
  "workspace.action_sync_detail",
]) {
  assert(!strings[removedKey], `Removed legacy localization key must stay deleted: ${removedKey}`);
}

const forbiddenChineseTerms = ["远端", "本地内核", "确认门控", "流式 UI", "载入", "本地 core", "内核", "提供器"];
const chineseCatalog = Object.values(strings)
  .map((entry) => entry.localizations?.["zh-Hans"]?.stringUnit?.value ?? "")
  .join("\n");
for (const term of forbiddenChineseTerms) {
  assert(!chineseCatalog.includes(term), `Simplified Chinese catalog must not regress to awkward term: ${term}`);
}

const lowerWorkbench = workbenchSource.toLowerCase();
for (const forbidden of ["redacted", "masked", "safe summary", "mock data", "sample data", "routing module 1", "selected node"]) {
  assert(!lowerWorkbench.includes(forbidden), `Active workbench must not include legacy or fabricated wording: ${forbidden}`);
}

for (const endpointDeclaration of [
  "static let version",
  "static let configs",
  "static let proxies",
  "static let connections",
  "static let rules",
  "static let proxyProviders",
  "static let ruleProviders",
]) {
  assertIncludes(mihomoEndpoint, endpointDeclaration, `Mihomo endpoint map must include ${endpointDeclaration}`);
}
assertIncludes(packageManifest, 'resources: [.copy("Fixtures")]', "MicaCore protocol tests must load repository fixture resources");
for (const dependency of [
  {
    identity: "grpc-swift-2",
    url: "https://github.com/grpc/grpc-swift-2.git",
    version: "2.4.2",
  },
  {
    identity: "grpc-swift-nio-transport",
    url: "https://github.com/grpc/grpc-swift-nio-transport.git",
    version: "2.9.0",
  },
  {
    identity: "grpc-swift-protobuf",
    url: "https://github.com/grpc/grpc-swift-protobuf.git",
    version: "2.4.1",
  },
  {
    identity: "swift-protobuf",
    url: "https://github.com/apple/swift-protobuf.git",
    version: "1.38.0",
  },
]) {
  assertIncludes(
    packageManifest,
    `.package(url: "${dependency.url}", exact: "${dependency.version}")`,
    `${dependency.identity} must stay pinned to the validated exact version ${dependency.version}`
  );
  const resolvedPin = packageResolved.pins?.find((pin) => pin.identity === dependency.identity);
  assert(
    resolvedPin?.state?.version === dependency.version,
    `Package.resolved must pin ${dependency.identity} to ${dependency.version}`
  );
}
for (const product of [
  '.product(name: "GRPCCore", package: "grpc-swift-2")',
  '.product(name: "GRPCNIOTransportHTTP2TransportServices", package: "grpc-swift-nio-transport")',
  '.product(name: "GRPCProtobuf", package: "grpc-swift-protobuf")',
  '.product(name: "SwiftProtobuf", package: "swift-protobuf")',
]) {
  assertIncludes(packageManifest, product, `MicaCore must link the native sing-box transport product ${product}`);
}
assertIncludes(packageManifest, 'exclude: ["Protocols/SingBox/started_service.proto"]', "The committed proto must remain a generation input rather than a Swift source file");
assertIncludes(singBoxCodegenScript, 'proto_path="Sources/MicaCore/Protocols/SingBox/started_service.proto"', "Sing-box code generation must use the committed StartedService proto");
assertIncludes(singBoxCodegenScript, 'output_path="Sources/MicaCore/Protocols/SingBox/Generated"', "Sing-box code generation must write to the committed generated-source tree");
assertIncludes(singBoxProto, "service StartedService", "The committed sing-box proto must define StartedService");
for (const rpc of ["GetVersion", "SubscribeStatus", "SubscribeGroups", "SubscribeConnections", "SubscribeTailscaleStatus"]) {
  assertIncludes(singBoxProto, `rpc ${rpc}(`, `StartedService proto must retain ${rpc}`);
}
assertIncludes(singBoxGeneratedMessages, "// DO NOT EDIT.", "Committed sing-box protobuf messages must remain generated output");
assertIncludes(singBoxGeneratedMessages, "nonisolated struct Daemon_Version", "Committed sing-box protobuf output must include StartedService message types");
assertIncludes(singBoxGeneratedClient, "// DO NOT EDIT.", "Committed sing-box gRPC client must remain generated output");
assertIncludes(singBoxGeneratedClient, "internal enum Daemon_StartedService", "Committed sing-box gRPC output must include the StartedService client namespace");
assertIncludes(singBoxGRPCClient, "public protocol SingBoxGRPCClientProtocol: Sendable", "Sing-box transport must expose a native domain-facing client protocol");
assertIncludes(singBoxGRPCClient, "private typealias GeneratedClient = Daemon_StartedService.Client<Transport>", "Generated StartedService types must stay behind SingBoxGRPCClient");
for (const domainType of [
  "SingBoxVersion",
  "SingBoxStatusSnapshot",
  "SingBoxPolicyCatalog",
  "SingBoxClashModeStatus",
  "SingBoxConnectionEventBatch",
  "SingBoxTailscaleStatus",
]) {
  assertIncludes(singBoxGRPCClient, domainType, `SingBoxGRPCClient must map StartedService payloads into ${domainType}`);
  assertIncludes(singBoxModels, `public struct ${domainType}`, `MicaCore must own the sing-box domain model ${domainType}`);
}
assertIncludes(singBoxGRPCClient, "private extension SingBoxVersion", "Generated sing-box messages must be converted at the client/domain boundary");
assertIncludes(singBoxGRPCClient, "private extension SingBoxTailscaleStatus", "Tailscale generated messages must be converted before leaving MicaCore transport");
assertExcludes(singBoxModels, "Daemon_", "Sing-box domain models must not depend on generated protobuf types");
assertExcludes(singBoxModels, "import GRPC", "Sing-box domain models must not depend on the gRPC runtime");
assertExcludes(executableSource, "Daemon_", "Generated sing-box protobuf types must not cross into the Mica presentation target");
assertIncludes(controllerProbeResolver, "private let singBoxProbe", "Auto Detect must include the native sing-box gRPC probe");
assertIncludes(controllerProbeResolver, "return .singBoxCompatible", "A successful StartedService probe must resolve the sing-box runtime kind");
assertIncludes(unifiedAdapterSource, "public actor SingBoxControllerAdapter: ControllerAdapterProtocol", "The unified adapter registry must expose a native sing-box adapter");
assertIncludes(unifiedAdapterSource, "return SingBoxControllerAdapter(profile: profile, credential: credential)", "The registry must construct the native sing-box adapter");
assertIncludes(unifiedModels, 'return "sing-box-started-service-grpc"', "The registry must report the native StartedService adapter source");
const singBoxCapabilitiesStart = unifiedModels.indexOf("public static let singBoxCompatible = ControllerCapabilities(");
const singBoxCapabilitiesEnd = unifiedModels.indexOf("public static let surgeHTTPAPI", singBoxCapabilitiesStart);
assert(singBoxCapabilitiesStart >= 0 && singBoxCapabilitiesEnd > singBoxCapabilitiesStart, "Sing-box must have a dedicated capability matrix");
const singBoxCapabilities = unifiedModels.slice(singBoxCapabilitiesStart, singBoxCapabilitiesEnd);
for (const capability of ["snapshot", "policyGroups", "connections", "traffic", "logs", "memory", "modeChange", "latencyTest", "killConnection"]) {
  assertIncludes(singBoxCapabilities, `${capability}: true`, `Sing-box native capability matrix must enable ${capability}`);
}
for (const capability of ["rules", "providers", "providerUpdate", "configurationReload", "dnsFlush", "profileReload", "logLevelChange", "portChange"]) {
  assertIncludes(singBoxCapabilities, `${capability}: false`, `Sing-box native capability matrix must keep unsupported ${capability} disabled`);
}
assertIncludes(singBoxCapabilities, "fixedSelectionClear: false", "Sing-box must not expose Clash fixed-selection cancellation");
assertIncludes(unifiedAdapterSource, "capabilities: UnifiedControllerAdapterRegistry.capabilities(for: resolvedControllerType)", "Clash-compatible snapshots must retain the detected CMFA/Stash capability matrix");
assertIncludes(unifiedModels, '"logs=\\(logs)"', "Capability diagnostics must report log readability independently");
assertIncludes(readinessSource, "let logsStatus = capabilities.logs ? singBoxLiveCapabilityStatus : .unavailable", "Sing-box log readiness must use the log capability rather than the traffic capability");
assertIncludes(appModelSource, "@ObservationIgnored var singBoxSessionTask: Task<Void, Never>?", "AppModel must own the generation-scoped sing-box session task");
assertIncludes(operationSessionSource, "var singBoxVersion: SingBoxVersion?", "ControllerSession must own sing-box version state");
assertIncludes(operationSessionSource, "var singBoxStatus: SingBoxStatusSnapshot?", "ControllerSession must own sing-box status state");
assertIncludes(operationSessionSource, "var singBoxGroups: SingBoxPolicyCatalog?", "ControllerSession must own sing-box policy state");
assertIncludes(operationSessionSource, "var singBoxTailscaleStatus: SingBoxTailscaleStatus?", "ControllerSession must own sing-box Tailscale state");
assertIncludes(liveSessionSource, "startSingBoxLiveSession(for: router, isRetry: isRetry, generation: generation)", "The selected runtime kind must route sing-box into its generation-owned live session");
assertIncludes(liveSessionSource, "singBoxSessionTask = Task", "Sing-box streams must share one AppModel-owned task slot");
for (const streamCall of [
  "client.runConnections()",
  "client.statusStream(intervalMilliseconds: 1_000)",
  "client.groupStream()",
  "client.clashModeStream()",
  "client.connectionStream(intervalMilliseconds: 1_000)",
  "client.logStream()",
  "client.tailscaleStatusStream()",
]) {
  assertIncludes(liveSessionSource, streamCall, `Sing-box live-session ownership must include ${streamCall}`);
}
assertIncludes(liveSessionSource, "withThrowingTaskGroup(of: Void.self)", "Sing-box streams must share a structured child-task tree");
assertIncludes(liveSessionSource, "consumeSingBoxSessionEvent", "Every sing-box stream must publish through the generation-checked reducer handoff");
assertIncludes(liveSessionSource, "try ensureCurrentSession(routerID: router.id, generation: generation)", "Every sing-box event must validate controller ID plus generation before publication");
assertExcludes(liveSessionSource, "bufferingNewest(256)", "Sing-box events must not pass through a second lossy cross-domain queue");
assertIncludes(liveSessionSource, "client.beginGracefulShutdown()", "Cancelling the sing-box generation must close the gRPC client channel");
assertIncludes(liveSessionSource, "singBoxSessionTask?.cancel()", "Controller lifecycle changes must cancel the sing-box session task");
assertExcludes(workbenchSource, "SingBoxGRPCClient(", "SwiftUI workbench views must not own sing-box network clients");
assertIncludes(controllerHTTPTransport, "protocol ControllerHTTPTransport: Sendable", "HTTP controller clients must share an injectable transport boundary");
assertIncludes(controllerHTTPTransport, "struct URLSessionControllerHTTPTransport", "Production HTTP transport must remain URLSession-backed");
assertIncludes(controllerHTTPTransport, "struct ClosureControllerHTTPTransport", "Protocol tests must be able to inject a recording transport");
assertIncludes(mihomoClient, "private let transport: any ControllerHTTPTransport", "Mihomo HTTP requests must use the injectable transport");
assertIncludes(surgeClient, "private let transport: any ControllerHTTPTransport", "Surge HTTP requests must use the shared injectable transport");
assertIncludes(mihomoClientContractTests, "testConfigurationReloadSendsPutWithAnEmptyJSONObject", "Mihomo fixtures must assert request method, path, and body");
assertIncludes(mihomoClientContractTests, "testUnauthorizedResponseUsesTheAuthenticationErrorBoundary", "Mihomo fixtures must cover authentication failures");
assertIncludes(mihomoClientContractTests, "testMalformedReadFixtureReportsTheEndpointPath", "Mihomo fixtures must cover malformed controller responses");
assertIncludes(controllerHTTPProbeResolver, "async let clashAttempt", "Auto Detect must probe HTTP backend families without side effects");
assertIncludes(controllerHTTPProbeResolver, "async let surgeAttempt", "Auto Detect must probe Clash-compatible and Surge HTTP families independently");
assertIncludes(controllerHTTPProbeResolver, "isAuthenticationFailure", "Probe authentication failures must not silently fall through to another backend family");
assertIncludes(controllerHTTPProbeResolver, "return .cmfaCompatible", "CMFA must be identified from the runtime version response");
assertIncludes(controllerHTTPProbeResolver, "return .stashCompatible", "Stash must be identified from the runtime root fallback");
assertIncludes(controllerHTTPProbeTests, "testCombinedStashCMFAHintSkipsSurgeProbe", "The legacy Stash / CMFA profile hint must resolve only within Clash-compatible variants");
assertIncludes(controllerHTTPProbeTests, "testAuthenticationFailureDoesNotBecomeAnotherBackend", "Probe fixtures must cover error-family isolation");
assertIncludes(mihomoClient, "catch MihomoClientError.unexpectedStatus(404)", "Group delay must fall back when a Clash-compatible runtime has no group endpoint");
assertIncludes(mihomoClient, "fallbackGroupDelay", "Stash group delay must use bounded node-level fallback requests");
assertIncludes(mihomoClient, "forceMemberFallback", "Known Stash sessions must bypass the unsupported group-delay endpoint");
assertIncludes(appModelSource, "runtimeControllerKind(for: router) == .stashCompatible", "Stash latency actions must select the member fallback from the detected runtime kind");
assertIncludes(mihomoClient, "let concurrency = min(32, probes.count)", "Node-level delay fallback must remain concurrency-bounded");
assertIncludes(mihomoClient, "providerProxyDelay", "Provider-backed nodes must use provider healthcheck endpoints");
assertIncludes(mihomoGroupDelayFallbackTests, "testGroupDelayFallsBackToBoundedNodeAndProviderRequestsAfter404", "Stash delay fallback must have request-level fixture coverage");
assertIncludes(mihomoGroupDelayFallbackTests, "testStashCanForceMemberFallbackWithoutCallingUnsupportedGroupEndpoint", "Known Stash sessions must have a no-group-endpoint regression fixture");
assertIncludes(controllerVariantCapabilityTests, "stashCapabilityMatrixUsesDelayFallbackButHidesUnsupportedRuntimeOperations", "Stash capability presentation must expose only implemented fallback actions");
assertIncludes(controllerVariantCapabilityTests, "cmfaCapabilityMatrixKeepsCacheAndMemoryButNotConfigurationWrites", "CMFA capability presentation must preserve its runtime limits");
assertIncludes(controllerVariantCapabilityTests, "legacyCombinedProfileUsesDetectedAdapterWithoutRewritingSavedKind", "The legacy profile kind must remain persisted while the runtime adapter is concrete");
for (const clientMethod of [
  "version",
  "configs",
  "proxies",
  "connections",
  "rules",
  "proxyProviders",
  "ruleProviders",
  "clearFixedProxy",
  "setRuleDisabled",
  "memory",
  "memoryStream",
  "connectionsStream",
  "logsStream",
  "flushDNSCache",
  "flushFakeIPCache",
  "restartCore",
  "upgradeCore",
  "updateConfigs",
  "healthCheckProxyProvider",
  "reloadConfigs",
  "updateGeoData",
]) {
  assertIncludes(mihomoClient, `func ${clientMethod}(`, `Mihomo client must keep real remote API method ${clientMethod}`);
}
assertIncludes(mihomoClient, "ProxiesResponse.decodePreservingProxyOrder", "Mihomo proxies must use the order-preserving decoder");
assertIncludes(mihomoClient, "MihomoEndpoint.logsEndpoint(level: level, structured: true)", "Mihomo logs must request upstream level and structured frames");
assertIncludes(mihomoEndpoint, 'URLQueryItem(name: "format", value: "structured")', "Mihomo structured logs must send format=structured");
assertIncludes(mihomoEndpoint, "public static func clearFixedProxy(group: String)", "Mihomo fixed selection must use DELETE /proxies/{group}");
assertIncludes(mihomoEndpoint, "public static func setRuleDisabled()", "Mihomo rule state must use PATCH /rules/disable");
assertIncludes(mihomoEndpoint, "public static func updateConfigs()", "Mihomo runtime configuration must use PATCH /configs");
assertIncludes(mihomoEndpoint, "public static func healthCheckProxyProvider(name: String)", "Mihomo provider health checks must use GET /providers/proxies/{name}/healthcheck");
assertIncludes(mihomoEndpoint, "public static func reloadConfigs(force: Bool = false)", "Mihomo configuration reload must use PUT /configs");
assertIncludes(mihomoEndpoint, "public static let updateGeoData", "Mihomo GeoData updates must use POST /configs/geo");
for (const field of [
  "public struct MihomoConfigPatch",
  "public var logLevel: String?",
  "public var allowLan: Bool?",
  "public var ipv6: Bool?",
  "public var tcpConcurrent: Bool?",
  "public var tun: TunConfig?",
  "public var socksPort: Int?",
  "public var redirPort: Int?",
  "public var mixedPort: Int?",
]) {
  assertIncludes(mihomoModels, field, `Mihomo config patches must preserve ${field}`);
}
assertIncludes(mihomoModels, "delay = try container.decode([String: Int].self)", "Mihomo group delay must decode the official top-level node map");
assertIncludes(mihomoModels, "public var memory: Int?", "Mihomo connection frames must preserve aggregate memory");
assertIncludes(mihomoModels, "public var format: String?", "Provider models must preserve controller-reported formats");
assertIncludes(mihomoModels, "public var healthCheck: MihomoJSONValue?", "Provider models must preserve health-check metadata");
assertIncludes(mihomoModels, "public var updatable: Bool", "Provider models must expose per-record update capability");
for (const field of ["public var alive: Bool?", "public var history: [ProxyDelayHistorySnapshot]", "public var icon: String?", "public var testURL: String?", "public var providerName: String?", "public var fixed: String?", "public var interfaceName: String?", "public var uot: Bool?", "public var xudp: Bool?", "public var tfo: Bool?", "public var mptcp: Bool?", "public var smux: Bool?", "public var metadata: [String: MihomoJSONValue]"]) {
  assertIncludes(mihomoModels, field, `Proxy snapshots must preserve ${field}`);
}
for (const field of ["public var index: Int?", "public var extra: RuleExtraSnapshot?", "public var hitCount: Int?", "public var hitAt: String?", "public var missCount: Int?", "public var missAt: String?", "public var hasMutableExtra: Bool"]) {
  assertIncludes(mihomoModels, field, `Rule snapshots must preserve ${field}`);
}
assertIncludes(mihomoModels, "public var providerOrder: [String]", "Provider responses must preserve controller order");
assertIncludes(mihomoModels, "providerOrder.compactMap", "Visible provider lists must follow controller order");
assertExcludes(mihomoModels, "providers.values.sorted", "Provider lists must not be alphabetically reordered");
assertIncludes(mihomoClient, "ProxyProvidersResponse.decodePreservingProviderOrder", "Proxy provider requests must preserve controller order");
assertIncludes(mihomoClient, "RuleProvidersResponse.decodePreservingProviderOrder", "Rule provider requests must preserve controller order");
assertExcludes(operationSessionSource, "memoryInUseKB", "Mihomo memory must remain in controller-reported bytes");
assertExcludes(operationSessionSource, "memoryLimitKB", "Mihomo memory must remain in controller-reported bytes");
assertIncludes(liveSessionSource, "client.memoryStream()", "Mihomo memory must be owned by the live session task tree");
assertIncludes(liveSessionSource, "client.connectionsStream()", "Mihomo connections must be owned by the live session task tree");
assertExcludes(liveSessionSource, "let connections = try await client.connections()", "Mihomo live sessions must not restore the two-second connection poll");
assertIncludes(liveSessionSource, "pendingPresentation.closedConnections.record(closed)", "Paused sessions must buffer closed connections until resume");
assertIncludes(liveSessionSource, "ControllerProbeResolver().resolve", "Auto Detect must resolve HTTP and sing-box runtime backends before starting lanes and streams");
assertIncludes(liveSessionSource, "activeSessionControllerKind = detectedKind", "Auto Detect must retain the detected backend for the current generation");
assertIncludes(liveSessionSource, "router.controllerKind == .stashCmfaCompatible", "The legacy combined profile hint must be runtime-probed without rewriting the profile");
assertIncludes(liveSessionSource, "if capabilities.memory", "Stash sessions must not start an unsupported memory stream");
assertIncludes(routerProfilesSource, "resolvedProfile.controllerKind = runtimeControllerKind(for: router)", "Unified adapters must use the detected runtime kind without mutating the saved profile");
assertIncludes(mihomoModels, "public var policyGroups", "Policy groups must have a dedicated ordered projection");
assertIncludes(mihomoModels, "proxyOrder.compactMap", "Policy groups must follow controller response order");
assertIncludes(mihomoModels, "decodePreservingProxyOrder", "Raw Mihomo responses must preserve JSON object-key order");
assertIncludes(mihomoModels, "JSONKeyOrderScanner.objectKeyOrder", "Policy order must come from the controller payload");
assertExcludes(mihomoModels, "orderedGroups.sort", "Policy groups must not sort after decoding");
assertExcludes(mihomoModels, "globalGroupPositions", "GLOBAL membership must not reorder controller policy groups");
assertIncludes(surgeClient, '"X-Key"', "Surge HTTP API must authenticate with X-Key only");
assertIncludes(surgeClient, 'pathComponents: ["v1", "policy_groups", "select"]', "Surge policy selection must use the official endpoint");
assertIncludes(surgeClient, 'pathComponents: ["v1", "policy_groups", "test"]', "Surge policy testing must use the official endpoint");
assertIncludes(surgeClient, 'pathComponents: ["v1", "requests", "kill"]', "Surge request termination must use the official endpoint");
assertIncludes(surgeClient, 'pathComponents: ["v1", "profiles", "reload"]', "Surge profile reload must use the official endpoint");
assertIncludes(surgeClient, 'pathComponents: ["v1", "log", "level"]', "Surge log level changes must use the official endpoint");
assertIncludes(surgeClient, "func reloadProfile()", "Surge client must expose remote profile reload");
assertIncludes(surgeClient, "func setLogLevel(_ level: String)", "Surge client must expose remote log level updates");
assertIncludes(surgeClient, 'case groupName = "group_name"', "Surge policy request bodies must use group_name");
for (const field of [
  "public var ruleType: String?",
  "public var rulePayload: String?",
  "public var originalPolicy: String?",
  "public var uploadSpeed: Int?",
  "public var downloadSpeed: Int?",
  "public var sourceAddress: String?",
  "public var destinationAddress: String?",
  "public var process: String?",
  "public var processPath: String?",
  "public var notes: [String]?",
  "public var fields: [String: ControllerJSONValue]",
]) {
  assertIncludes(surgeModels, field, `Surge active requests must preserve ${field}`);
}
assertIncludes(surgeModels, '["requests", "active", "data"]', "Surge request decoding must accept observed response wrappers");
assertIncludes(surgeModels, "public var additionalFields", "Surge request decoding must preserve unknown controller fields");
assertIncludes(dashboardSurgeProjectionSource, "fields: request.additionalFields", "Surge request unknown fields must remain visible in the shared connection inspector");
assertIncludes(unifiedModels, "public struct ControllerCapabilities", "Controller capabilities must gate workbench operations");
assertIncludes(unifiedModels, "public var profileReload: Bool", "Controller capabilities must distinguish remote profile reload");
assertIncludes(unifiedModels, "public var logLevelChange: Bool", "Controller capabilities must distinguish upstream log-level changes");
assertIncludes(unifiedModels, "public var providerHealthCheck: Bool", "Controller capabilities must distinguish provider health checks");
assertIncludes(unifiedModels, "public var fixedSelectionClear: Bool", "Controller capabilities must distinguish Clash fixed-selection cancellation");
assertIncludes(unifiedModels, "public static let cmfaCompatible", "CMFA must have a concrete capability matrix");
assertIncludes(unifiedModels, "public static let stashCompatible", "Stash must have a concrete capability matrix");
assertIncludes(unifiedModels, "public var memory: Bool", "Controller capabilities must distinguish memory stream support");
for (const field of ["configurationReload", "geoDataUpdate", "fakeIPFlush"]) {
  assertIncludes(unifiedModels, `public var ${field}: Bool`, `Controller capabilities must distinguish ${field}`);
}
for (const field of ["allowLANChange", "ipv6Change", "tcpConcurrentChange", "tunChange", "portChange"]) {
  assertIncludes(unifiedModels, `public var ${field}: Bool`, `Controller capabilities must distinguish ${field}`);
}

for (const forbiddenRuntimePrimitive of ["Process()", "ProcessInfo.processInfo.environment[\"http_proxy\"]", "networksetup", "pfctl", "iptables", "ubus ", "ssh "]) {
  assertExcludes(executableSource, forbiddenRuntimePrimitive, `Mica must not modify or launch forbidden runtime primitive ${forbiddenRuntimePrimitive}`);
}

for (const privacyField of [
  "activeUIFullControllerData: true",
  "credentialsExcludedFromExports: true",
  "rawResponseBodiesExcludedFromExports: true",
  "networkAccess: false",
  "controllerProfilesLoaded: false",
  "coreLaunched: false",
  "systemEnvironmentModified: false",
]) {
  assertIncludes(runtimeProbe, privacyField, `Runtime smoke must preserve boundary ${privacyField}`);
}
assertExcludes(runtimeProbe, "AppModel(", "Runtime smoke must not instantiate AppModel");
assertExcludes(runtimeProbe, "MihomoClient", "Runtime smoke must not contact a Mihomo controller");
assertExcludes(runtimeProbe, "SurgeHttpAPIClient", "Runtime smoke must not contact Surge");
for (const surface of ["settings", "sidebar", "toolbar", "overview", "policyGroups", "connections", "rules", "sources", "logs", "coreConfig", "coreActions", "diagnostics"]) {
  assertIncludes(runtimeProbe, `"${surface}": [`, `Runtime smoke probe must sample ${surface}`);
  assertIncludes(runtimeVerifier, `${surface}: [`, `Runtime smoke verifier must assert ${surface}`);
}
for (const smokeCase of ["zh-dark-extra-large", "en-light-standard", "en-dark-large", "zh-system-comfortable"]) {
  assertIncludes(runtimeVerifier, smokeCase, `Runtime smoke verifier must cover ${smokeCase}`);
}
assertIncludes(runtimeVerifier, "assertWorkbenchSurfaceContract", "Runtime smoke verifier must enforce the workbench surface set");
for (const legacySurface of ["commandPalette", "commandBar", "controlBay", "operationBanner", '"routing": [', '"traffic": [']) {
  assertExcludes(runtimeProbe, legacySurface, `Runtime smoke probe must not retain legacy surface ${legacySurface}`);
  assertExcludes(runtimeVerifier, legacySurface, `Runtime smoke verifier must not retain legacy surface ${legacySurface}`);
}
assertExcludes(runtimeVerifier, "tmpdir()", "Runtime smoke must not scatter artifacts into system temp directories");
assertExcludes(runtimeVerifier, "mkdtempSync", "Runtime smoke must use stdout instead of disposable temp directories");

const implementAgent = read(".codex/agents/trellis-implement.toml");
const checkAgent = read(".codex/agents/trellis-check.toml");
for (const [agentName, agentSource] of [["trellis-implement", implementAgent], ["trellis-check", checkAgent]]) {
  assertIncludes(agentSource, 'sandbox_mode = "workspace-write"', `${agentName} must stay inside the workspace-write sandbox`);
  assertIncludes(agentSource, "multi_agent = false", `${agentName} must keep recursive agent spawning disabled`);
}
for (const claudeAgent of ["trellis-implement", "trellis-check", "trellis-research"]) {
  assert(exists(`.claude/agents/${claudeAgent}.md`), `Claude Code must define the ${claudeAgent} sub-agent`);
}

console.log("macOS Liquid Glass workbench source contract passed");
