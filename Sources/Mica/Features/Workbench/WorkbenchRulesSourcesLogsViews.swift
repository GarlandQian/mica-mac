import Foundation
import MicaCore
import SwiftUI

struct WorkbenchRulesView: View {
    var appModel: AppModel
    @Binding var searchText: String

    @Environment(\.micaAppLanguage) private var appLanguage
    @Environment(\.micaFontMultiplier) private var fontMultiplier
    @State private var selectedRuleRowID: String?
    @State private var ruleSortOrder: [KeyPathComparator<WorkbenchRuleRow>] = []

    var body: some View {
        VStack(spacing: 0) {
            commandRow
            Divider()
            surfaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(MicaStyle.pageFill)
        .onChange(of: appModel.selectedRouterID) {
            selectedRuleRowID = nil
        }
        .onChange(of: ruleRows.map(\.id)) { _, _ in
            selectedRuleRowID = RulesWorkbenchPresentation.reconciledSelection(
                selectedRuleRowID,
                in: ruleRows
            )
        }
    }

    private var commandRow: some View {
        HStack(spacing: 10) {
            Text(appModel.rulesSnapshotState.summaryValue(count: appModel.dashboard.rules.count, language: appLanguage))
                .font(.system(size: 11.5 * fontMultiplier, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            if appModel.rulesSnapshotState.isLoading {
                ProgressView()
                    .accessibilityLabel(MicaStrings.localizedKey("snapshot.loading", language: appLanguage))
            }

            Spacer()

            Button {
                appModel.reloadRules()
            } label: {
                MicaLabel("action.reload_rules", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(!appModel.canRefreshSelectedRouter || !appModel.supportsUnifiedAction(.reloadRules))
            .accessibilityLabel(MicaStrings.localizedKey("action.reload_rules", language: appLanguage))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MicaStyle.contentFill)
    }

    @ViewBuilder
    private var surfaceContent: some View {
        switch surfaceState {
        case .unavailable:
            unavailable(
                titleKey: "dashboard.rules_header",
                message: appModel.rulesSnapshotState.message
                    ?? MicaStrings.localizedKey("dashboard.rules_unavailable_message", language: appLanguage)
            )
        case .empty:
            unavailable(
                titleKey: "dashboard.rules_header",
                message: MicaStrings.localizedKey("dashboard.no_matching_rules", language: appLanguage)
            )
        case .filteredEmpty:
            unavailable(
                titleKey: "dashboard.no_matching_rules",
                message: MicaStrings.localizedKey("traffic.empty_filtered", language: appLanguage)
            )
        case .content:
            rulesTable
                .inspector(isPresented: ruleInspectorPresented) {
                    ruleInspector
                        .inspectorColumnWidth(min: 280 * fontMultiplier, ideal: 350 * fontMultiplier, max: 500 * fontMultiplier)
                }
        }
    }

    private var ruleInspectorPresented: Binding<Bool> {
        Binding(
            get: { selectedRuleRowID != nil },
            set: { presented in
                if !presented { selectedRuleRowID = nil }
            }
        )
    }

    private var rulesTable: some View {
        Table(sortedRuleRows, selection: $selectedRuleRowID, sortOrder: $ruleSortOrder) {
            TableColumn(MicaStrings.localizedKey("dashboard.col_payload", language: appLanguage), value: \.sortablePayload) { row in
                Text(row.rule.payload.isEmpty ? unavailableValue : row.rule.payload)
                    .font(.system(size: 12 * fontMultiplier, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .width(min: 260 * fontMultiplier, ideal: 420 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("dashboard.col_type", language: appLanguage), value: \.sortableType) { row in
                Text(row.rule.type.isEmpty ? unavailableValue : row.rule.type)
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .width(min: 120 * fontMultiplier, ideal: 170 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("dashboard.col_proxy", language: appLanguage), value: \.sortableProxy) { row in
                Text(row.rule.proxy.isEmpty ? unavailableValue : row.rule.proxy)
                    .font(.system(size: 11.5 * fontMultiplier))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .width(min: 150 * fontMultiplier, ideal: 240 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("dashboard.col_index", language: appLanguage), value: \.sortableIndex) { row in
                Text(row.rule.index.map(String.init) ?? unavailableValue)
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .width(min: 64 * fontMultiplier, ideal: 78 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("dashboard.col_status", language: appLanguage), value: \.sortableStatus) { row in
                Label {
                    Text(ruleStatusLabel(row.rule))
                } icon: {
                    Image(systemName: ruleStatusSymbol(row.rule))
                }
                .font(.system(size: 11 * fontMultiplier, weight: .medium))
                .foregroundStyle(ruleStatusTint(row.rule))
                .fixedSize(horizontal: true, vertical: false)
            }
            .width(min: 96 * fontMultiplier, ideal: 118 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("traffic.rule_hits", language: appLanguage), value: \.sortableHitCount) { row in
                Text(row.rule.hitCount.map(String.init) ?? unavailableValue)
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .width(min: 72 * fontMultiplier, ideal: 90 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("traffic.rule_misses", language: appLanguage), value: \.sortableMissCount) { row in
                Text(row.rule.missCount.map(String.init) ?? unavailableValue)
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .width(min: 72 * fontMultiplier, ideal: 90 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("dashboard.col_size", language: appLanguage), value: \.sortableSize) { row in
                Text(row.rule.size.map(String.init) ?? unavailableValue)
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 80 * fontMultiplier, ideal: 100 * fontMultiplier)
        }
        .tableStyle(.inset)
        .accessibilityLabel(MicaStrings.localizedKey("dashboard.tab_rules", language: appLanguage))
    }

    @ViewBuilder
    private var ruleInspector: some View {
        if let rule = selectedRule {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        MicaText("traffic.detail_rule")
                            .font(.system(size: 15 * fontMultiplier, weight: .semibold))
                        Text(rule.payload.isEmpty ? unavailableValue : rule.payload)
                            .font(.system(size: 12 * fontMultiplier, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        if appModel.updatingRuleID == rule.id {
                            ProgressView {
                                MicaText("traffic.rule_updating")
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                    if rule.hasMutableExtra,
                       rule.index != nil,
                       appModel.supportsUnifiedAction(.setRuleDisabled) {
                        Toggle(
                            MicaStrings.localizedKey("traffic.rule_disabled", language: appLanguage),
                            isOn: Binding(
                                get: { rule.disabled ?? false },
                                set: { appModel.setRuleDisabled(rule, disabled: $0) }
                            )
                        )
                        .toggleStyle(.switch)
                        .disabled(appModel.updatingRuleID != nil || !appModel.canRefreshSelectedRouter)
                        .padding(.horizontal, 12)
                        .frame(minHeight: max(44, 44 * fontMultiplier))
                        .accessibilityHint(MicaStrings.localizedKey("traffic.help_rule_disabled", language: appLanguage))

                        Divider()
                    }

                    if let failure = appModel.ruleUpdateFailures[rule.id] {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11 * fontMultiplier, weight: .medium))
                            .foregroundStyle(MicaStyle.signalRed)
                            .padding(12)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()
                    }

                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_payload", value: rule.payload.isEmpty ? unavailableValue : rule.payload, monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_type", value: rule.type.isEmpty ? unavailableValue : rule.type, monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_proxy", value: rule.proxy.isEmpty ? unavailableValue : rule.proxy)
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_index", value: rule.index.map(String.init), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_size", value: rule.size.map(String.init) ?? unavailableValue, monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_status", value: ruleStatusLabel(rule))
                    WorkbenchInspectorValueRow(titleKey: "traffic.rule_hits", value: rule.hitCount.map(String.init), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.rule_hit_at", value: rule.hitAt, monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.rule_misses", value: rule.missCount.map(String.init), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.rule_miss_at", value: rule.missAt, monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.rule_hit_rate", value: ruleHitRateLabel(rule), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.rule_extra_fields", value: rule.additionalExtraText, monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "routing.additional_fields", value: rule.additionalMetadataText, monospaced: true)
                }
            }
            .background(MicaStyle.contentFill)
        } else {
            emptyInspector("traffic.detail_rule", messageKey: "traffic.context_empty_rule")
        }
    }

    private var ruleRows: [WorkbenchRuleRow] {
        RulesWorkbenchPresentation.rows(from: appModel.dashboard.rules)
    }

    private var filteredRuleRows: [WorkbenchRuleRow] {
        RulesWorkbenchPresentation.filtered(ruleRows, matching: searchText)
    }

    private var sortedRuleRows: [WorkbenchRuleRow] {
        RulesWorkbenchPresentation.ordered(filteredRuleRows, using: ruleSortOrder)
    }

    private var selectedRule: RuleViewState? {
        guard let selectedRuleRowID else { return nil }
        return ruleRows.first { $0.id == selectedRuleRowID }?.rule
    }

    private var surfaceState: WorkbenchDataSurfaceState {
        WorkbenchDataSurfaceState.resolve(
            isUnavailable: appModel.rulesSnapshotState.isUnavailable,
            sourceCount: ruleRows.count,
            visibleCount: filteredRuleRows.count
        )
    }

    private func unavailable(titleKey: String, message: String) -> some View {
        ContentUnavailableView {
            Label {
                MicaText(titleKey)
            } icon: {
                Image(systemName: "list.bullet.rectangle")
            }
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyInspector(_ titleKey: String, messageKey: String) -> some View {
        ContentUnavailableView {
            Label {
                MicaText(titleKey)
            } icon: {
                Image(systemName: "sidebar.right")
            }
        } description: {
            MicaText(messageKey)
        }
        .background(MicaStyle.contentFill)
    }

    private var unavailableValue: String {
        MicaStrings.localizedKey("overview.config_not_reported", language: appLanguage)
    }

    private func ruleStatusLabel(_ rule: RuleViewState) -> String {
        guard let disabled = rule.disabled else { return unavailableValue }
        return MicaStrings.localizedKey(
            disabled ? "traffic.rule_status_disabled" : "traffic.rule_status_enabled",
            language: appLanguage
        )
    }

    private func ruleStatusSymbol(_ rule: RuleViewState) -> String {
        switch rule.disabled {
        case true:
            return "pause.circle.fill"
        case false:
            return "checkmark.circle.fill"
        case nil:
            return "questionmark.circle"
        }
    }

    private func ruleStatusTint(_ rule: RuleViewState) -> Color {
        switch rule.disabled {
        case true:
            return MicaStyle.signalAmber
        case false:
            return MicaStyle.signalMint
        case nil:
            return .secondary
        }
    }

    private func ruleHitRateLabel(_ rule: RuleViewState) -> String? {
        guard let hitRate = rule.hitRate else { return nil }
        return hitRate.formatted(.percent.precision(.fractionLength(0...1)))
    }
}

struct WorkbenchSourcesView: View {
    var appModel: AppModel
    @Binding var searchText: String

    @Environment(\.micaAppLanguage) private var appLanguage
    @Environment(\.micaFontMultiplier) private var fontMultiplier
    @State private var kind: ProviderSessionKind = .all
    @State private var selectedSourceID: String?
    @State private var sourceSortOrder: [KeyPathComparator<ProxyProviderViewState>] = []

    var body: some View {
        VStack(spacing: 0) {
            commandRow
            Divider()
            surfaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(MicaStyle.pageFill)
        .onChange(of: appModel.selectedRouterID) {
            kind = .all
            selectedSourceID = nil
        }
        .onChange(of: allSources.map(\.id)) { _, _ in
            selectedSourceID = SourcesWorkbenchPresentation.reconciledSelection(selectedSourceID, in: allSources)
        }
    }

    private var commandRow: some View {
        HStack(spacing: 12) {
            Picker(
                MicaStrings.localizedKey("traffic.source_kind", language: appLanguage),
                selection: $kind
            ) {
                ForEach(ProviderSessionKind.allCases) { option in
                    Text(MicaStrings.localizedKey(option.titleKey, language: appLanguage)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360 * fontMultiplier)
            .accessibilityLabel(MicaStrings.localizedKey("traffic.source_kind", language: appLanguage))

            Text(appModel.providersSnapshotState.summaryValue(count: allSources.count, language: appLanguage))
                .font(.system(size: 11.5 * fontMultiplier, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            if appModel.providersSnapshotState.isLoading || appModel.reloadingProviders {
                ProgressView()
                    .accessibilityLabel(MicaStrings.localizedKey("snapshot.loading", language: appLanguage))
            }

            Spacer()

            Button {
                appModel.reloadProviders()
            } label: {
                MicaLabel("action.reload_providers", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(!appModel.canRefreshSelectedRouter || !appModel.supportsUnifiedAction(.reloadProviders))
            .accessibilityLabel(MicaStrings.localizedKey("action.reload_providers", language: appLanguage))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MicaStyle.contentFill)
    }

    @ViewBuilder
    private var surfaceContent: some View {
        switch surfaceState {
        case .unavailable:
            unavailable(
                titleKey: "dashboard.providers_header",
                message: appModel.providersSnapshotState.message
                    ?? MicaStrings.localizedKey("dashboard.providers_unavailable_message", language: appLanguage)
            )
        case .empty:
            unavailable(
                titleKey: emptySourceKey,
                message: MicaStrings.localizedKey("traffic.sources_empty_message", language: appLanguage)
            )
        case .filteredEmpty:
            unavailable(
                titleKey: "dashboard.no_matching_sources",
                message: MicaStrings.localizedKey("traffic.empty_filtered", language: appLanguage)
            )
        case .content:
            sourcesTable
                .inspector(isPresented: sourceInspectorPresented) {
                    sourceInspector
                        .inspectorColumnWidth(min: 290 * fontMultiplier, ideal: 350 * fontMultiplier, max: 500 * fontMultiplier)
                }
        }
    }

    private var sourceInspectorPresented: Binding<Bool> {
        Binding(
            get: { selectedSourceID != nil },
            set: { presented in
                if !presented { selectedSourceID = nil }
            }
        )
    }

    private var sourcesTable: some View {
        Table(sortedSources, selection: $selectedSourceID, sortOrder: $sourceSortOrder) {
            TableColumn(MicaStrings.localizedKey("dashboard.col_provider", language: appLanguage), value: \.sortableName) { source in
                Text(source.name)
                    .font(.system(size: 12 * fontMultiplier, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 200 * fontMultiplier, ideal: 280 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("traffic.provider_kind", language: appLanguage), value: \.sortableKind) { source in
                Text(sourceKindLabel(source.kind))
                    .font(.system(size: 11 * fontMultiplier))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 100 * fontMultiplier, ideal: 125 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("dashboard.col_provider_type", language: appLanguage), value: \.sortableType) { source in
                Text(source.type)
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 110 * fontMultiplier, ideal: 150 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("dashboard.col_vehicle", language: appLanguage)) { source in
                Text(reported(source.vehicleType))
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 115 * fontMultiplier, ideal: 150 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("traffic.provider_behavior", language: appLanguage)) { source in
                Text(reported(source.behavior))
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 110 * fontMultiplier, ideal: 150 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("traffic.provider_items", language: appLanguage), value: \.sortableItemCount) { source in
                Text(String(source.itemCount))
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 75 * fontMultiplier, ideal: 90 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("traffic.updated_at", language: appLanguage), value: \.sortableUpdatedAt) { source in
                if let updatedAt = updatedAtDisplay(source.updatedAt) {
                    Text(updatedAt)
                        .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(unavailableValue)
                        .font(.system(size: 10.5 * fontMultiplier))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .width(min: 135 * fontMultiplier, ideal: 190 * fontMultiplier)
        }
        .tableStyle(.inset)
        .accessibilityLabel(MicaStrings.localizedKey("dashboard.tab_providers", language: appLanguage))
    }

    @ViewBuilder
    private var sourceInspector: some View {
        if let source = selectedSource {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        MicaText("traffic.detail_source")
                            .font(.system(size: 15 * fontMultiplier, weight: .semibold))
                        Text(source.name)
                            .font(.system(size: 12.5 * fontMultiplier, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_provider", value: source.name)
                    WorkbenchInspectorValueRow(titleKey: "traffic.provider_kind", value: sourceKindLabel(source.kind))
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_provider_type", value: source.type, monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_vehicle", value: reported(source.vehicleType), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.provider_behavior", value: reported(source.behavior), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.provider_format", value: reported(source.format), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.provider_updatable", value: updatableLabel(source.updatable))
                    WorkbenchInspectorValueRow(titleKey: "traffic.provider_health_check", value: source.healthCheckText, monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.provider_items", value: String(source.itemCount), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.updated_at", value: updatedAtDisplay(source.updatedAt), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.update_status", value: updateStatus(source))
                    WorkbenchInspectorValueRow(titleKey: "traffic.health_check_status", value: healthCheckStatus(source))

                    Divider()
                    if source.updatable || source.supportsHealthCheck {
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)

                            if source.supportsHealthCheck {
                                Button {
                                    appModel.healthCheckProxyProvider(source)
                                } label: {
                                    MicaLabel("action.provider_health_check", systemImage: "waveform.path.ecg")
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    appModel.isBusy
                                        || appModel.dashboardSessionControls.dashboardUpdatesPaused
                                        || appModel.checkingProviderName == source.id
                                        || !appModel.supportsUnifiedAction(.healthCheckProvider)
                                )
                                .help(MicaStrings.localizedKey("traffic.help_inspector_health_check_provider", language: appLanguage))
                                .accessibilityLabel(MicaStrings.localizedKey("action.provider_health_check", language: appLanguage))
                            }

                            if source.updatable {
                                Button {
                                    appModel.updateProxyProvider(source)
                                } label: {
                                    MicaLabel("dashboard.update", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    appModel.isBusy
                                        || appModel.dashboardSessionControls.dashboardUpdatesPaused
                                        || appModel.updatingProviderName == source.id
                                        || !appModel.supportsUnifiedAction(.updateProvider)
                                )
                                .help(MicaStrings.localizedKey("traffic.help_inspector_update_provider", language: appLanguage))
                                .accessibilityLabel(MicaStrings.localizedKey("dashboard.update", language: appLanguage))
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .background(MicaStyle.contentFill)
        } else {
            emptyInspector("traffic.detail_source", messageKey: "traffic.context_empty_provider")
        }
    }

    private var allSources: [ProxyProviderViewState] {
        appModel.dashboard.providers
    }

    private var filteredSources: [ProxyProviderViewState] {
        SourcesWorkbenchPresentation.filtered(allSources, kind: kind, matching: searchText)
    }

    private var sortedSources: [ProxyProviderViewState] {
        SourcesWorkbenchPresentation.ordered(filteredSources, using: sourceSortOrder)
    }

    private var selectedSource: ProxyProviderViewState? {
        guard let selectedSourceID else { return nil }
        return allSources.first { $0.id == selectedSourceID }
    }

    private var surfaceState: WorkbenchDataSurfaceState {
        WorkbenchDataSurfaceState.resolve(
            isUnavailable: appModel.providersSnapshotState.isUnavailable,
            sourceCount: allSources.filter { kind.matches($0.kind) }.count,
            visibleCount: filteredSources.count
        )
    }

    private var emptySourceKey: String {
        switch kind {
        case .all: "dashboard.no_providers_snapshot"
        case .proxy: "traffic.no_proxy_sources"
        case .rule: "traffic.no_rule_sources"
        }
    }

    private func updateStatus(_ source: ProxyProviderViewState) -> String {
        guard source.updatable else {
            return MicaStrings.localizedKey("traffic.provider_not_updatable", language: appLanguage)
        }
        switch SourcesWorkbenchPresentation.updateState(
            sourceID: source.id,
            updatingSourceID: appModel.updatingProviderName,
            failures: appModel.providerUpdateFailures
        ) {
        case .updating:
            return MicaStrings.localizedKey("dashboard.updating", language: appLanguage)
        case .failed(let failure):
            return MicaStrings.localized("traffic.provider_failed \(failure)", language: appLanguage)
        case .ready:
            return MicaStrings.localizedKey("dashboard.ready", language: appLanguage)
        }
    }

    private func healthCheckStatus(_ source: ProxyProviderViewState) -> String {
        guard source.supportsHealthCheck else {
            return MicaStrings.localizedKey("traffic.provider_health_check_unavailable", language: appLanguage)
        }

        if appModel.checkingProviderName == source.id {
            return MicaStrings.localizedKey("traffic.provider_health_check_running", language: appLanguage)
        }

        if let failure = appModel.providerHealthCheckFailures[source.id] {
            return MicaStrings.localized("traffic.provider_health_check_failed \(failure)", language: appLanguage)
        }

        return MicaStrings.localizedKey("traffic.provider_health_check_available", language: appLanguage)
    }

    private func updatableLabel(_ updatable: Bool) -> String {
        MicaStrings.localizedKey(
            updatable ? "traffic.provider_updatable_yes" : "traffic.provider_updatable_no",
            language: appLanguage
        )
    }

    private func sourceKindLabel(_ kind: ProviderKind) -> String {
        switch kind {
        case .proxy: MicaStrings.localizedKey("traffic.provider_kind_proxy", language: appLanguage)
        case .rule: MicaStrings.localizedKey("traffic.provider_kind_rule", language: appLanguage)
        }
    }

    private func reported(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? unavailableValue
    }

    /// Presents the controller-reported update time. Returns `nil` for a
    /// missing value so callers can render the de-emphasized not-reported
    /// treatment; the Go zero time becomes localized "never updated" wording.
    private func updatedAtDisplay(_ raw: String?) -> String? {
        switch SourcesWorkbenchPresentation.classifyUpdatedAt(raw) {
        case .notReported:
            nil
        case .neverUpdated:
            MicaStrings.localizedKey("live.last_update_never", language: appLanguage)
        case .updated(let date):
            date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(appLanguage.resolvedLocale))
        case .reported(let text):
            text
        }
    }

    private func unavailable(titleKey: String, message: String) -> some View {
        ContentUnavailableView {
            Label {
                MicaText(titleKey)
            } icon: {
                Image(systemName: "tray.full")
            }
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyInspector(_ titleKey: String, messageKey: String) -> some View {
        ContentUnavailableView {
            Label {
                MicaText(titleKey)
            } icon: {
                Image(systemName: "sidebar.right")
            }
        } description: {
            MicaText(messageKey)
        }
        .background(MicaStyle.contentFill)
    }

    private var unavailableValue: String {
        MicaStrings.localizedKey("overview.config_not_reported", language: appLanguage)
    }
}

struct WorkbenchLogsView: View {
    var appModel: AppModel
    @Binding var searchText: String

    @Environment(\.micaAppLanguage) private var appLanguage
    @Environment(\.micaFontMultiplier) private var fontMultiplier
    @State private var followBottom = true
    private let logBottomID = "controller-log-bottom"

    var body: some View {
        VStack(spacing: 0) {
            logCommands
            Divider()

            Group {
                if visibleLogs.isEmpty {
                    let emptyState = LogsWorkbenchPresentation.emptyState(isFiltering: isFilteringLogs)

                    ContentUnavailableView {
                        Label {
                            MicaText(emptyState.titleKey)
                        } icon: {
                            Image(systemName: "text.alignleft")
                        }
                    } description: {
                        MicaText(emptyState.messageKey)
                    }
                } else {
                    logList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(MicaStyle.pageFill)
        .onChange(of: appModel.selectedRouterID) {
            followBottom = true
        }
    }

    private var logCommands: some View {
        HStack(spacing: 10) {
            Picker(
                MicaStrings.localizedKey("traffic.log_level", language: appLanguage),
                selection: controllerLogLevelBinding
            ) {
                ForEach(LogSessionLevel.allCases) { option in
                    Text(MicaStrings.localizedKey(option.titleKey, language: appLanguage)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 170 * fontMultiplier)
            .disabled(
                appModel.selectedRouter == nil
                    || appModel.isBusy
                    || !canAdjustLogLevel
            )
            .accessibilityLabel(MicaStrings.localizedKey("traffic.log_level", language: appLanguage))

            if appModel.changingControllerLogLevel {
                ProgressView()
                    .accessibilityLabel(MicaStrings.localizedKey("operation.setting_log_level", language: appLanguage))
            }

            Button {
                appModel.toggleControllerLogsPaused()
            } label: {
                MicaLabel(
                    appModel.dashboardSessionControls.logsPresentationPaused ? "traffic.resume_logs" : "traffic.pause_logs",
                    systemImage: appModel.dashboardSessionControls.logsPresentationPaused ? "play" : "pause"
                )
            }
            .buttonStyle(.bordered)
            .help(MicaStrings.localizedKey("traffic.help_pause_logs", language: appLanguage))
            .accessibilityLabel(
                MicaStrings.localizedKey(
                    appModel.dashboardSessionControls.logsPresentationPaused ? "traffic.resume_logs" : "traffic.pause_logs",
                    language: appLanguage
                )
            )

            Toggle(
                MicaStrings.localizedKey("traffic.follow_bottom", language: appLanguage),
                isOn: $followBottom
            )
            .toggleStyle(.checkbox)
            .font(.system(size: 11.5 * fontMultiplier))

            Spacer()

            Button {
                appModel.clearControllerLogs()
            } label: {
                MicaLabel("traffic.clear_logs", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(appModel.controllerSession.logBuffer.entries.isEmpty || appModel.isBusy)
            .accessibilityLabel(MicaStrings.localizedKey("traffic.clear_logs", language: appLanguage))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MicaStyle.contentFill)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleLogs) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                if let remoteTime = entry.message.time?.nilIfEmpty {
                                    Text(verbatim: remoteTime)
                                        .textSelection(.enabled)
                                } else {
                                    Text(entry.receivedAt, format: .dateTime.hour().minute().second())
                                }
                                Text(verbatim: entry.message.type)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(logTint(entry.message.type))
                            }
                            .font(.system(size: 10.5 * fontMultiplier, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: 100 * fontMultiplier, maxWidth: 180 * fontMultiplier, alignment: .leading)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: entry.message.payload)
                                    .foregroundStyle(.primary)
                                if let fields = entry.structuredFieldsText {
                                    Text(verbatim: fields)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.system(size: 11.5 * fontMultiplier, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .accessibilityElement(children: .combine)
                        .id(entry.id)

                        Divider()
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(logBottomID)
                        .onAppear {
                            followBottom = true
                        }
                        .onDisappear {
                            if !visibleLogs.isEmpty {
                                followBottom = false
                            }
                        }
                }
            }
            .onChange(of: visibleLogs.map(\.id)) { _, _ in
                scrollToNewest(proxy)
            }
            .onChange(of: followBottom) { _, follows in
                if follows {
                    scrollToNewest(proxy, force: true)
                }
            }
            .onAppear {
                scrollToNewest(proxy)
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                if !followBottom {
                    Button {
                        scrollToNewest(proxy, force: true)
                    } label: {
                        MicaLabel("traffic.jump_to_newest", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.bordered)
                    .padding(10)
                    .accessibilityLabel(MicaStrings.localizedKey("traffic.jump_to_newest", language: appLanguage))
                }
            }
        }
        .background(MicaStyle.contentFill)
        .accessibilityLabel(MicaStrings.localizedKey("dashboard.tab_logs", language: appLanguage))
    }

    private var visibleLogs: [ControllerLogEntry] {
        LogsWorkbenchPresentation.visible(
            appModel.dashboard.controllerLogs,
            level: appModel.controllerLogLevel,
            matching: searchText
        )
    }

    private var isFilteringLogs: Bool {
        appModel.controllerLogLevel != .all
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAdjustLogLevel: Bool {
        appModel.selectedUnifiedCapabilities.logs
            || appModel.supportsUnifiedAction(.setLogLevel)
    }

    private var controllerLogLevelBinding: Binding<LogSessionLevel> {
        Binding(
            get: { appModel.controllerLogLevel },
            set: { appModel.setControllerLogLevel($0) }
        )
    }

    private func scrollToNewest(_ proxy: ScrollViewProxy, force: Bool = false) {
        guard force || followBottom, !visibleLogs.isEmpty else { return }
        proxy.scrollTo(logBottomID, anchor: .bottom)
    }

    private func logTint(_ type: String) -> Color {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "error", "err": MicaStyle.signalRed
        case "warning", "warn": MicaStyle.signalAmber
        case "debug": MicaStyle.signalViolet
        default: MicaStyle.signalCyan
        }
    }
}
