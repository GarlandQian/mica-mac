import Foundation
import MicaCore
import SwiftUI

// MARK: - Shared management structure

private enum WorkbenchManagementMetrics {
    static let formCanvasWidth: CGFloat = 1_040
    static let maximumCanvasWidth: CGFloat = 1_180
    static let controllerListWidth: CGFloat = 320
    static let preferenceWindowWidth: CGFloat = 820
}

enum WorkbenchManagementWidthMode: Equatable, Sendable {
    case compact
    case regular

    init(availableWidth: CGFloat) {
        self = availableWidth < MicaBounds.wideThreshold ? .compact : .regular
    }
}

extension EnvironmentValues {
    @Entry var workbenchManagementWidthMode: WorkbenchManagementWidthMode = .regular
}

struct WorkbenchManagementCanvas<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let widthMode = WorkbenchManagementWidthMode(
                availableWidth: geometry.size.width
            )

            ScrollView {
                VStack(alignment: .leading, spacing: MicaSpacing.section) {
                    content
                }
                .padding(.horizontal, MicaBounds.pagePadding(for: geometry.size.width))
                .padding(.vertical, MicaSpacing.section)
                .frame(
                    maxWidth: WorkbenchManagementMetrics.maximumCanvasWidth,
                    alignment: .topLeading
                )
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .micaObserveScrollPerformance()
            .environment(\.workbenchManagementWidthMode, widthMode)
        }
    }
}

struct WorkbenchManagementFormCanvas<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let widthMode = WorkbenchManagementWidthMode(
                availableWidth: geometry.size.width
            )

            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .contentMargins(
                .horizontal,
                MicaBounds.pagePadding(for: geometry.size.width),
                for: .scrollContent
            )
            .contentMargins(.top, MicaSpacing.module, for: .scrollContent)
            .micaObserveScrollPerformance()
            .frame(
                maxWidth: WorkbenchManagementMetrics.formCanvasWidth,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.workbenchManagementWidthMode, widthMode)
        }
    }
}

struct WorkbenchManagementHeader: View {
    @Environment(\.micaAppLanguage) private var language

    let systemImage: String
    let titleKey: String
    var detail: String?
    var value: String?
    var tint = MicaDesignTokens.signalCyan

    var body: some View {
        HStack(alignment: .top, spacing: MicaSpacing.row) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.row) {
                    Text(MicaStrings.localizedKey(titleKey, language: language))
                        .micaFont(.headline)

                    if let value = value?.managementNonEmpty {
                        Text(verbatim: value)
                            .micaFont(.caption, weight: .semibold, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let detail = detail?.managementNonEmpty {
                    Text(verbatim: detail)
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchManagementInlineState: View {
    let systemImage: String
    let title: String
    var detail: String?
    var tint: Color = .secondary
    var isLoading = false

    var body: some View {
        HStack(alignment: .top, spacing: MicaSpacing.module) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                Text(verbatim: title)
                    .micaFont(.callout, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = detail?.managementNonEmpty {
                    Text(verbatim: detail)
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchFormRow<Control: View>: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let titleKey: String
    var detailKey: String?
    var isBusy = false
    private let control: Control

    init(
        _ titleKey: String,
        detailKey: String? = nil,
        isBusy: Bool = false,
        @ViewBuilder control: () -> Control
    ) {
        self.titleKey = titleKey
        self.detailKey = detailKey
        self.isBusy = isBusy
        self.control = control()
    }

    /// Typography can grow without changing the information architecture.
    /// Only the actual available width decides when the columns stack.
    private var usesStackedLayout: Bool {
        widthMode == .compact
    }

    var body: some View {
        Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    label
                    controlColumn
                }
            } else {
                HStack(alignment: .top, spacing: MicaSpacing.module) {
                    label
                        .frame(width: MicaBounds.formLabelWidth, alignment: .leading)
                    controlColumn
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaFont(.callout, weight: .medium)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let detailKey {
                Text(MicaStrings.localizedKey(detailKey, language: language))
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controlColumn: some View {
        HStack(alignment: .center, spacing: MicaSpacing.row) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            control
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .labelsHidden()
    }
}

struct WorkbenchFormValue: View {
    let value: String
    var monospaced = false
    var placeholder = false

    var body: some View {
        Text(verbatim: value)
            .micaFont(.body, design: monospaced ? .monospaced : .default)
            .foregroundStyle(placeholder ? .secondary : .primary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchOperationLine<Command: View>: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let systemImage: String
    let tint: Color
    let titleKey: String
    let detailKey: String
    var reason: String?
    var isRunning = false
    private let command: Command

    init(
        systemImage: String,
        tint: Color,
        titleKey: String,
        detailKey: String,
        reason: String? = nil,
        isRunning: Bool = false,
        @ViewBuilder command: () -> Command
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.titleKey = titleKey
        self.detailKey = detailKey
        self.reason = reason
        self.isRunning = isRunning
        self.command = command()
    }

    var body: some View {
        Group {
            switch widthMode {
            case .regular:
                HStack(alignment: .top, spacing: MicaSpacing.module) {
                    explanation
                    Spacer(minLength: MicaSpacing.module)
                    commandColumn
                }
            case .compact:
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    explanation
                    commandColumn
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MicaBounds.controlMinHeight, alignment: .leading)
        .padding(.vertical, MicaSpacing.tight)
    }

    private var explanation: some View {
        HStack(alignment: .top, spacing: MicaSpacing.row) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.callout, weight: .medium)

                Text(MicaStrings.localizedKey(detailKey, language: language))
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let reason = reason?.managementNonEmpty {
                    Text(verbatim: reason)
                        .micaFont(.caption)
                        .foregroundStyle(MicaDesignTokens.signalAmber)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var commandColumn: some View {
        HStack(spacing: MicaSpacing.row) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            command
        }
        .frame(
            minWidth: 150,
            maxWidth: .infinity,
            minHeight: MicaBounds.controlMinHeight,
            alignment: .trailing
        )
    }
}

private extension String {
    var managementNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func workbenchDisplayableDate(_ date: Date?) -> Date? {
    guard let date, date.timeIntervalSince1970 >= 31_536_000 else {
        return nil
    }
    return date
}

// MARK: - Settings

private struct WorkbenchPreferenceMenu<Option: Hashable & Identifiable>: View {
    @Environment(\.micaAppLanguage) private var language

    let labelKey: String
    @Binding var selection: Option
    let options: [Option]
    let optionTitleKey: (Option) -> String
    let optionSystemImage: (Option) -> String

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Label(
                        localized(optionTitleKey(option)),
                        systemImage: option == selection
                            ? "checkmark"
                            : optionSystemImage(option)
                    )
                }
            }
        } label: {
            HStack(spacing: MicaSpacing.row) {
                Image(systemName: optionSystemImage(selection))
                    .foregroundStyle(MicaDesignTokens.signalCyan)
                    .frame(width: 18)

                Text(verbatim: localized(optionTitleKey(selection)))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .micaFont(.caption2, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .micaFont(.callout)
            .frame(
                minWidth: 168,
                minHeight: MicaBounds.controlMinHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(localized(labelKey))
        .accessibilityValue(localized(optionTitleKey(selection)))
    }

    private func localized(_ key: String) -> String {
        MicaStrings.localizedKey(key, language: language)
    }
}

private struct WorkbenchPreferenceRow<Control: View>: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let titleKey: String
    let detailKey: String
    private let control: Control

    init(
        _ titleKey: String,
        detailKey: String,
        @ViewBuilder control: () -> Control
    ) {
        self.titleKey = titleKey
        self.detailKey = detailKey
        self.control = control()
    }

    var body: some View {
        Group {
            switch widthMode {
            case .regular:
                HStack(alignment: .center, spacing: MicaSpacing.space5) {
                    explanation
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    control
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(alignment: .trailing)
                }
            case .compact:
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    explanation
                    control
                }
            }
        }
        .padding(.vertical, MicaSpacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localized(titleKey))
                .micaFont(.callout, weight: .medium)

            Text(localized(detailKey))
                .micaFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func localized(_ key: String) -> String {
        MicaStrings.localizedKey(key, language: language)
    }
}

struct MicaSettingsSceneView: View {
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        WorkbenchPreferenceForm()
            .frame(
                minWidth: 680,
                idealWidth: 860,
                maxWidth: .infinity,
                minHeight: 560,
                idealHeight: 680,
                maxHeight: .infinity
            )
            .background(MicaStyle.groupedPageFill)
            .navigationTitle(
                MicaStrings.localizedKey("workbench.settings", language: language)
            )
    }
}

private struct WorkbenchPreferenceForm: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    var body: some View {
        GeometryReader { geometry in
            let horizontalMargin = MicaBounds.pagePadding(for: geometry.size.width)
            let availableContentWidth = max(
                0,
                min(
                    geometry.size.width,
                    WorkbenchManagementMetrics.preferenceWindowWidth
                ) - (horizontalMargin * 2)
            )

            preferenceForm(horizontalMargin: horizontalMargin)
                .environment(
                    \.workbenchManagementWidthMode,
                    WorkbenchManagementWidthMode(
                        availableWidth: availableContentWidth
                    )
                )
        }
    }

    private func preferenceForm(horizontalMargin: CGFloat) -> some View {
        Form {
            Section {
                appearanceRows
            } header: {
                Label(
                    localized("settings.appearance_section"),
                    systemImage: "paintpalette"
                )
                .micaFont(.headline, weight: .semibold)
            }

            Section {
                routingRows
            } header: {
                Label(
                    localized("settings.routing_section"),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .micaFont(.headline, weight: .semibold)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .contentMargins(
            .horizontal,
            horizontalMargin,
            for: .scrollContent
        )
        .contentMargins(.top, MicaSpacing.module, for: .scrollContent)
        .frame(
            maxWidth: WorkbenchManagementMetrics.preferenceWindowWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var appearanceRows: some View {
        nativePreferenceRow(
            "settings.language",
            detailKey: "settings.help_language"
        ) {
            languagePicker
        }
        nativePreferenceRow(
            "settings.appearance",
            detailKey: "settings.help_appearance"
        ) {
            appearancePicker
        }
        nativePreferenceRow(
            "settings.font_scale",
            detailKey: "settings.help_font_scale"
        ) {
            fontScalePicker
        }
    }

    @ViewBuilder
    private var routingRows: some View {
        nativePreferenceRow(
            "settings.global_group_visibility",
            detailKey: "settings.help_global_group_visibility"
        ) {
            globalGroupVisibilityPicker
        }
    }

    private func nativePreferenceRow<Control: View>(
        _ titleKey: String,
        detailKey: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        WorkbenchPreferenceRow(titleKey, detailKey: detailKey) {
            control()
        }
    }

    private var languagePicker: some View {
        WorkbenchPreferenceMenu(
            labelKey: "settings.language",
            selection: languageBinding,
            options: AppLanguage.allCases,
            optionTitleKey: \.titleKey,
            optionSystemImage: languageSystemImage
        )
        .help(localized("settings.help_language"))
    }

    private var appearancePicker: some View {
        WorkbenchPreferenceMenu(
            labelKey: "settings.appearance",
            selection: appearanceBinding,
            options: AppAppearance.allCases,
            optionTitleKey: \.titleKey,
            optionSystemImage: appearanceSystemImage
        )
        .help(localized("settings.help_appearance"))
    }

    private var fontScalePicker: some View {
        WorkbenchPreferenceMenu(
            labelKey: "settings.font_scale",
            selection: fontScaleBinding,
            options: AppFontScale.allCases,
            optionTitleKey: \.titleKey,
            optionSystemImage: fontScaleSystemImage
        )
        .help(localized("settings.help_font_scale"))
    }

    private var globalGroupVisibilityPicker: some View {
        WorkbenchPreferenceMenu(
            labelKey: "settings.global_group_visibility",
            selection: globalGroupVisibilityBinding,
            options: GlobalGroupVisibility.allCases,
            optionTitleKey: \.titleKey,
            optionSystemImage: globalGroupVisibilitySystemImage
        )
        .help(localized("settings.help_global_group_visibility"))
    }

    private func languageSystemImage(_ option: AppLanguage) -> String {
        switch option {
        case .system:
            "globe"
        case .english:
            "textformat.abc"
        case .simplifiedChinese:
            "character.book.closed"
        }
    }

    private func appearanceSystemImage(_ option: AppAppearance) -> String {
        switch option {
        case .system:
            "circle.lefthalf.filled"
        case .light:
            "sun.max"
        case .dark:
            "moon"
        }
    }

    private func fontScaleSystemImage(_ option: AppFontScale) -> String {
        switch option {
        case .standard:
            "textformat.size.smaller"
        case .comfortable:
            "textformat"
        case .large, .extraLarge:
            "textformat.size.larger"
        }
    }

    private func globalGroupVisibilitySystemImage(
        _ option: GlobalGroupVisibility
    ) -> String {
        switch option {
        case .followMode:
            "arrow.triangle.branch"
        case .alwaysShow:
            "eye"
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { preferences.language },
            set: { preferences.language = $0 }
        )
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { preferences.appearance },
            set: { preferences.appearance = $0 }
        )
    }

    private var fontScaleBinding: Binding<AppFontScale> {
        Binding(
            get: { preferences.fontScale },
            set: { preferences.fontScale = $0 }
        )
    }

    private var globalGroupVisibilityBinding: Binding<GlobalGroupVisibility> {
        Binding(
            get: { preferences.globalGroupVisibility },
            set: { preferences.globalGroupVisibility = $0 }
        )
    }

    private func localized(_ key: String) -> String {
        MicaStrings.localizedKey(key, language: preferences.language)
    }
}

// MARK: - Controllers

private struct WorkbenchControllerStatus {
    let label: String
    let symbol: String
    let tint: Color
}

private enum WorkbenchControllerMove {
    case up
    case down
}

struct WorkbenchControllerDeleteConfirmation: Equatable {
    let profileID: RouterProfile.ID
    let selectedRouterID: RouterProfile.ID?
    let generation: UUID

    func isCurrent(
        selectedRouterID: RouterProfile.ID?,
        generation: UUID
    ) -> Bool {
        self.selectedRouterID == selectedRouterID && self.generation == generation
    }
}

enum WorkbenchControllerListProjection {
    static func filtered(
        _ profiles: [RouterProfile],
        query: String,
        controllerTypeLabel: (RouterProfile) -> String
    ) -> [RouterProfile] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return profiles }

        return profiles.filter { profile in
            [
                profile.displayName,
                profile.endpointURL,
                controllerTypeLabel(profile),
            ].contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
        }
    }

    static func reconciledSelection(
        storedID: RouterProfile.ID?,
        activeID: RouterProfile.ID?,
        candidates: [RouterProfile]
    ) -> RouterProfile.ID? {
        if let storedID, candidates.contains(where: { $0.id == storedID }) {
            return storedID
        }
        if let activeID, candidates.contains(where: { $0.id == activeID }) {
            return activeID
        }
        return candidates.first?.id
    }
}

struct WorkbenchConnectionTestProjection {
    struct ProfileIdentity: Equatable, Sendable {
        let id: RouterProfile.ID
        let displayName: String
        let scheme: ControllerScheme
        let host: String
        let port: Int
        let secretReference: String?
        let tlsPolicy: TLSValidationPolicy
        let controllerKind: ControllerKind
        let surgePlatform: SurgeControllerPlatform

        init(_ profile: RouterProfile) {
            id = profile.id
            displayName = profile.displayName
            scheme = profile.scheme
            host = profile.host
            port = profile.port
            secretReference = profile.secretReference
            tlsPolicy = profile.tlsPolicy
            controllerKind = profile.controllerKind
            surgePlatform = profile.surgePlatform
        }
    }

    struct Intent: Equatable, Sendable {
        let id: UUID
        let presentationID: UUID
        let profile: ProfileIdentity
    }

    private struct StoredReport: Equatable {
        let profile: ProfileIdentity
        let report: ConnectionTestReport
    }

    private(set) var presentationID: UUID
    private var reports: [RouterProfile.ID: StoredReport] = [:]
    private var activeIntents: [RouterProfile.ID: Intent] = [:]

    init(presentationID: UUID = UUID()) {
        self.presentationID = presentationID
    }

    mutating func replacePresentation(with presentationID: UUID = UUID()) {
        self.presentationID = presentationID
        reports.removeAll(keepingCapacity: true)
        activeIntents.removeAll(keepingCapacity: true)
    }

    mutating func begin(
        profile: RouterProfile,
        intentID: UUID = UUID()
    ) -> Intent {
        let identity = ProfileIdentity(profile)
        let intent = Intent(
            id: intentID,
            presentationID: presentationID,
            profile: identity
        )
        reports[profile.id] = nil
        activeIntents[profile.id] = intent
        return intent
    }

    @discardableResult
    mutating func receive(
        _ report: ConnectionTestReport,
        for intent: Intent,
        profiles: [RouterProfile]
    ) -> Bool {
        guard activeIntents[intent.profile.id] == intent else {
            return false
        }
        activeIntents[intent.profile.id] = nil

        guard intent.presentationID == presentationID,
              let profile = profiles.first(where: { $0.id == intent.profile.id }),
              ProfileIdentity(profile) == intent.profile else {
            reports[intent.profile.id] = nil
            return false
        }

        reports[intent.profile.id] = StoredReport(
            profile: intent.profile,
            report: report
        )
        return true
    }

    mutating func reconcile(profiles: [RouterProfile]) {
        let identities = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.id, ProfileIdentity($0)) }
        )
        reports = reports.filter { identities[$0.key] == $0.value.profile }
        activeIntents = activeIntents.filter {
            $0.value.presentationID == presentationID
                && identities[$0.key] == $0.value.profile
        }
    }

    func report(for profile: RouterProfile) -> ConnectionTestReport? {
        guard let stored = reports[profile.id],
              stored.profile == ProfileIdentity(profile) else {
            return nil
        }
        return stored.report
    }

    func isTesting(_ profile: RouterProfile) -> Bool {
        guard let intent = activeIntents[profile.id] else {
            return false
        }
        return intent.presentationID == presentationID
            && intent.profile == ProfileIdentity(profile)
    }
}

struct WorkbenchControllersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language

    @Binding var searchText: String
    @State private var pendingDelete: WorkbenchControllerDeleteConfirmation?
    @State private var connectionTests = WorkbenchConnectionTestProjection()

    let onAddController: () -> Void
    let onEditController: (RouterProfile) -> Void

    var body: some View {
        GeometryReader { proxy in
            let widthMode = WorkbenchManagementWidthMode(
                availableWidth: proxy.size.width
            )

            WorkbenchPageScaffold {
                commandBar
            } content: {
                if appModel.routers.isEmpty {
                    WorkbenchStateView(
                        kind: .empty,
                        titleKey: "sidebar.no_controllers",
                        detailKey: "sidebar.no_controllers_message",
                        actionTitleKey: "sidebar.add_controller",
                        actionSystemImage: "plus",
                        action: onAddController
                    )
                } else if filteredProfiles.isEmpty {
                    WorkbenchStateView(
                        kind: .filterEmpty,
                        titleKey: "controllers.no_match_title",
                        detailKey: "controllers.no_match_description"
                    )
                } else {
                    controllerContent(availableWidth: proxy.size.width)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let pendingDelete,
                   isCurrent(pendingDelete),
                   let profile = appModel.routers.first(where: {
                       $0.id == pendingDelete.profileID
                   }) {
                    deleteConfirmation(profile, confirmation: pendingDelete)
                }
            }
            .environment(\.workbenchManagementWidthMode, widthMode)
        }
        .onAppear {
            connectionTests.replacePresentation()
            connectionTests.reconcile(profiles: appModel.routers)
            reconcileManagementSelection()
        }
        .onDisappear {
            connectionTests.replacePresentation()
        }
        .onChange(of: appModel.routers) { _, profiles in
            connectionTests.reconcile(profiles: profiles)
            let ids = profiles.map(\.id)
            reconcileManagementSelection()
            if let pendingDelete, !ids.contains(pendingDelete.profileID) {
                self.pendingDelete = nil
            }
        }
        .onChange(of: appModel.selectedRouterID) { pendingDelete = nil }
        .onChange(of: appModel.controllerSessionPresentation.generation) { pendingDelete = nil }
        .onChange(of: searchText) {
            reconcileManagementSelection(visibleOnly: true)
        }
    }

    @ViewBuilder
    private func controllerContent(availableWidth: CGFloat) -> some View {
        if let profile = selectedReportProfile {
            if availableWidth >= 840 {
                HSplitView {
                    controllerList
                        .frame(
                            minWidth: 280,
                            idealWidth: WorkbenchManagementMetrics.controllerListWidth,
                            maxWidth: 360
                        )

                    controllerDetail(profile)
                        .frame(minWidth: 480)
                }
            } else {
                VSplitView {
                    controllerList
                        .frame(minHeight: 220)

                    controllerDetail(profile)
                        .frame(minHeight: 280)
                }
            }
        } else {
            controllerList
        }
    }

    private func controllerDetail(_ profile: RouterProfile) -> some View {
        WorkbenchManagementFormCanvas {
            Section {
                controllerIdentity(profile)
            }

            Section {
                WorkbenchFormRow("settings.controller_endpoint") {
                    WorkbenchFormValue(value: profile.endpointURL, monospaced: true)
                }
                WorkbenchFormRow("settings.controller_type") {
                    WorkbenchFormValue(
                        value: profile.controllerKind.micaLabel(language: language)
                    )
                }
                WorkbenchFormRow("settings.health") {
                    statusLabel(profile)
                }
                WorkbenchFormRow("diagnostics.last_connected") {
                    lastSuccess(profile)
                }
            } header: {
                Label(
                    MicaStrings.localizedKey("settings.connection", language: language),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            }

            Section {
                controllerDetailActions(profile)
            } header: {
                Label(
                    MicaStrings.localizedKey("controllers.actions", language: language),
                    systemImage: "slider.horizontal.3"
                )
            }

            if let report = connectionTests.report(for: profile) {
                WorkbenchConnectionTestReportView(
                    profile: profile,
                    report: report
                )
            } else {
                Section {
                    WorkbenchManagementInlineState(
                        systemImage: MicaSymbols.Command.test,
                        title: MicaStrings.localizedKey("editor.test", language: language),
                        detail: MicaStrings.localizedKey(
                            "command.action_test_detail",
                            language: language
                        ),
                        tint: MicaDesignTokens.signalCyan,
                        isLoading: isTesting(profile)
                    )
                } header: {
                    Label(
                        MicaStrings.localizedKey("editor.connection_diagnosis", language: language),
                        systemImage: "stethoscope"
                    )
                }
            }
        }
        .accessibilityLabel(
            MicaStrings.localizedKey("controllers.controller", language: language)
        )
    }

    private func controllerIdentity(_ profile: RouterProfile) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: MicaSpacing.module) {
                controllerIdentityLabel(profile)
                Spacer(minLength: MicaSpacing.row)
                statusLabel(profile)
            }

            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                controllerIdentityLabel(profile)
                statusLabel(profile)
            }
        }
        .frame(maxWidth: .infinity, minHeight: MicaBounds.controlMinHeight, alignment: .leading)
    }

    private func controllerIdentityLabel(_ profile: RouterProfile) -> some View {
        HStack(alignment: .top, spacing: MicaSpacing.row) {
            activeIndicator(profile)
                .micaFont(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: profile.displayName)
                    .micaFont(.title3, weight: .semibold)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: profile.endpointURL)
                    .micaFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func controllerDetailActions(_ profile: RouterProfile) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.row) {
                controllerDetailActionButtons(profile)
            }

            VStack(alignment: .trailing, spacing: MicaSpacing.row) {
                controllerDetailActionButtons(profile)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func controllerDetailActionButtons(_ profile: RouterProfile) -> some View {
        Button {
            appModel.selectRouter(profile)
        } label: {
            Label(
                MicaStrings.localizedKey("controllers.use", language: language),
                systemImage: appModel.selectedRouterID == profile.id ? "checkmark" : "play.fill"
            )
            .labelStyle(.titleAndIcon)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: MicaBounds.controlMinHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(MicaStyle.accent)
        .disabled(appModel.selectedRouterID == profile.id)
        Button {
            testConnection(profile)
        } label: {
            HStack(spacing: MicaSpacing.row) {
                if isTesting(profile) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: MicaSymbols.Command.test)
                }
                Text(
                    MicaStrings.localizedKey(
                        isTesting(profile) ? "editor.testing" : "action.test",
                        language: language
                    )
                )
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: MicaBounds.controlMinHeight)
        }
        .buttonStyle(.bordered)
        .disabled(isTesting(profile))
        .accessibilityLabel(MicaStrings.localizedKey("action.test", language: language))
    }

    private var commandBar: some View {
        WorkbenchCommandBar {
            WorkbenchManagementHeader(
                systemImage: "server.rack",
                titleKey: "sidebar.controllers",
                detail: MicaStrings.localizedKey("controllers.subtitle", language: language)
            )
        } controls: {
            HStack(spacing: MicaSpacing.row) {
                WorkbenchStatusBadge(
                    text: MicaStrings.localized(
                        "controllers.count \(filteredProfiles.count)",
                        language: language
                    ),
                    tint: MicaDesignTokens.signalCyan
                )

                HStack(spacing: 0) {
                    moveButton(.up)
                    moveButton(.down)
                }
            }
        } commands: {
            WorkbenchIconCommand(
                titleKey: "sidebar.add_controller",
                systemImage: "plus",
                action: onAddController
            )
        }
    }

    private var controllerList: some View {
        List(filteredProfiles, selection: managementSelectionBinding) { profile in
            controllerRow(profile)
                .tag(profile.id)
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .micaObserveScrollPerformance()
        .scrollContentBackground(.hidden)
        .background(MicaStyle.groupedPageFill)
        .accessibilityLabel(
            MicaStrings.localizedKey("sidebar.controllers", language: language)
        )
    }

    private func controllerRow(_ profile: RouterProfile) -> some View {
        HStack(alignment: .center, spacing: MicaSpacing.row) {
            activeIndicator(profile)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: profile.displayName)
                    .micaFont(.callout, weight: .semibold)
                    .lineLimit(1)

                Text(verbatim: profile.endpointURL)
                    .micaFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                statusLabel(profile)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                controllerIcon(titleKey: "sidebar.edit", symbol: "pencil") {
                    setManagementSelection(profile.id)
                    onEditController(profile)
                }

                controllerIcon(
                    titleKey: "sidebar.delete_button",
                    symbol: "trash",
                    tint: MicaDesignTokens.signalRed
                ) {
                    setManagementSelection(profile.id)
                    requestDelete(profile)
                }
            }
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    private var filteredProfiles: [RouterProfile] {
        WorkbenchControllerListProjection.filtered(
            appModel.routers,
            query: searchText
        ) { profile in
            profile.controllerKind.micaLabel(language: language)
        }
    }

    private var selectedReportProfile: RouterProfile? {
        let selectedID = managementSelection
            ?? appModel.selectedRouterID
            ?? filteredProfiles.first?.id
        guard let selectedID else { return nil }
        return appModel.routers.first { $0.id == selectedID }
    }

    private var managementSelection: RouterProfile.ID? {
        guard let storedID = workspaceStore.workspace(
            controllerID: appModel.selectedRouterID,
            destination: .controllers
        ).selectedItemID else {
            return nil
        }
        return RouterProfile.ID(uuidString: storedID)
    }

    private var managementSelectionBinding: Binding<RouterProfile.ID?> {
        Binding(
            get: { managementSelection },
            set: { setManagementSelection($0) }
        )
    }

    private func setManagementSelection(_ id: RouterProfile.ID?) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .controllers
        ) { workspace in
            workspace.selectedItemID = id?.uuidString
        }
    }

    private func reconcileManagementSelection(visibleOnly: Bool = false) {
        let candidates = visibleOnly ? filteredProfiles : appModel.routers
        let next = WorkbenchControllerListProjection.reconciledSelection(
            storedID: managementSelection,
            activeID: appModel.selectedRouterID,
            candidates: candidates
        )
        setManagementSelection(next)
    }

    private func activeIndicator(_ profile: RouterProfile) -> some View {
        let active = appModel.selectedRouterID == profile.id
        return Image(systemName: active ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(active ? MicaDesignTokens.signalMint : .secondary)
            .accessibilityLabel(
                MicaStrings.localizedKey(
                    active ? "controllers.active" : "controllers.inactive",
                    language: language
                )
            )
    }

    private func statusLabel(_ profile: RouterProfile) -> some View {
        let status = controllerStatus(profile)
        return Label(status.label, systemImage: status.symbol)
            .micaFont(.caption)
            .labelStyle(MicaStatusLabelStyle(tint: status.tint))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func controllerStatus(_ profile: RouterProfile) -> WorkbenchControllerStatus {
        if appModel.selectedRouterID == profile.id {
            switch appModel.connectionState {
            case .disconnected:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "circle",
                    tint: .secondary
                )
            case .connecting:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "arrow.triangle.2.circlepath",
                    tint: MicaDesignTokens.signalCyan
                )
            case .connected:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "checkmark.circle.fill",
                    tint: MicaDesignTokens.signalMint
                )
            case .failed:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "xmark.circle.fill",
                    tint: MicaDesignTokens.signalRed
                )
            }
        }

        let health = appModel.trialSession(for: profile).sessionHealth
        switch health {
        case .idle:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "minus.circle",
                tint: .secondary
            )
        case .fresh:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "checkmark.circle.fill",
                tint: MicaDesignTokens.signalMint
            )
        case .stale, .partial:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "exclamationmark.triangle.fill",
                tint: MicaDesignTokens.signalAmber
            )
        case .failed:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "xmark.circle.fill",
                tint: MicaDesignTokens.signalRed
            )
        }
    }

    private func lastSuccess(_ profile: RouterProfile) -> some View {
        let candidate = appModel.selectedRouterID == profile.id
            ? appModel.controllerSessionPresentation.lastSuccessAt ?? profile.lastConnectedAt
            : profile.lastConnectedAt
        let date = workbenchDisplayableDate(candidate)
        return WorkbenchDataText(
            value: date.map {
                $0.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened)
                        .locale(language.resolvedLocale)
                )
            } ?? MicaStrings.localizedKey("settings.never", language: language),
            style: .caption, design: .monospaced,
            tone: .secondary
        )
    }

    private func testConnection(_ profile: RouterProfile) {
        setManagementSelection(profile.id)
        let draft = appModel.draft(for: profile)
        let intent = connectionTests.begin(profile: profile)

        Task {
            let report = await appModel.testConnection(draft: draft)
            guard !Task.isCancelled else { return }
            connectionTests.receive(
                report,
                for: intent,
                profiles: appModel.routers
            )
        }
    }

    private func controllerIcon(
        titleKey: String,
        symbol: String,
        tint: Color = .primary,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: MicaBounds.iconControlSize, height: MicaBounds.iconControlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(tint)
        .disabled(!isEnabled)
        .help(MicaStrings.localizedKey(titleKey, language: language))
        .accessibilityLabel(MicaStrings.localizedKey(titleKey, language: language))
    }

    private func isTesting(_ profile: RouterProfile) -> Bool {
        connectionTests.isTesting(profile)
            || appModel.trialSession(for: profile).commandLog.contains {
                $0.action == .test && !$0.status.isTerminal
            }
    }

    private func moveButton(_ direction: WorkbenchControllerMove) -> some View {
        let key = direction == .up ? "controllers.move_up" : "controllers.move_down"
        return WorkbenchIconCommand(
            titleKey: key,
            systemImage: direction == .up ? "arrow.up" : "arrow.down",
            isEnabled: canMove(direction)
        ) {
            moveSelection(direction)
        }
    }

    private func canMove(_ direction: WorkbenchControllerMove) -> Bool {
        guard searchText.managementNonEmpty == nil,
              let managementSelection,
              let index = appModel.routers.firstIndex(where: { $0.id == managementSelection }) else {
            return false
        }
        switch direction {
        case .up: return index > 0
        case .down: return index < appModel.routers.count - 1
        }
    }

    private func moveSelection(_ direction: WorkbenchControllerMove) {
        guard let managementSelection,
              let index = appModel.routers.firstIndex(where: { $0.id == managementSelection }) else {
            return
        }
        let target = direction == .up ? index - 1 : index + 1
        guard appModel.routers.indices.contains(target) else { return }
        let profile = appModel.routers[index]
        let action = MicaStrings.localizedKey(
            direction == .up ? "controllers.move_up" : "controllers.move_down",
            language: language
        )
        Task {
            do {
                try await appModel.moveRouter(managementSelection, to: target)
            } catch {
                appModel.operationState = .error(
                    AppModel.routerTrialFailureMessage(for: error, language: language),
                    action: action,
                    target: profile.displayName,
                    nextStep: MicaStrings.localizedKey("action.retry", language: language)
                )
            }
        }
    }

    private func deleteConfirmation(
        _ profile: RouterProfile,
        confirmation: WorkbenchControllerDeleteConfirmation
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.module) {
                deleteConfirmationContent(profile, confirmation: confirmation)
            }
            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                deleteConfirmationContent(profile, confirmation: confirmation)
            }
        }
        .padding(.horizontal, MicaBounds.regularPagePadding)
        .padding(.vertical, MicaSpacing.row)
        .background(MicaStyle.groupedPageFill)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private func deleteConfirmationContent(
        _ profile: RouterProfile,
        confirmation: WorkbenchControllerDeleteConfirmation
    ) -> some View {
        Label {
            Text(verbatim: deleteMessage(profile))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "trash")
                .foregroundStyle(MicaDesignTokens.signalRed)
        }

        Spacer(minLength: MicaSpacing.row)

        Button(MicaStrings.localizedKey("editor.cancel", language: language)) {
            pendingDelete = nil
        }
        .frame(minHeight: MicaBounds.controlMinHeight)

        Button(
            MicaStrings.localizedKey("sidebar.delete_button", language: language),
            role: .destructive
        ) {
            guard pendingDelete == confirmation,
                  isCurrent(confirmation),
                  let currentProfile = appModel.routers.first(where: {
                      $0.id == confirmation.profileID
                  }) else {
                pendingDelete = nil
                return
            }
            pendingDelete = nil
            appModel.deleteRouter(currentProfile)
        }
        .buttonStyle(.borderedProminent)
        .tint(MicaDesignTokens.signalRed)
        .frame(minHeight: MicaBounds.controlMinHeight)
    }

    private func requestDelete(_ profile: RouterProfile) {
        pendingDelete = WorkbenchControllerDeleteConfirmation(
            profileID: profile.id,
            selectedRouterID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }

    private func isCurrent(
        _ confirmation: WorkbenchControllerDeleteConfirmation
    ) -> Bool {
        confirmation.isCurrent(
            selectedRouterID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }

    private func deleteMessage(_ profile: RouterProfile) -> String {
        guard appModel.selectedRouterID == profile.id,
              let index = appModel.routers.firstIndex(where: { $0.id == profile.id }) else {
            return MicaStrings.localized(
                "controllers.delete_confirm \(profile.displayName)",
                language: language
            )
        }

        var remaining = appModel.routers
        remaining.remove(at: index)
        let replacement = remaining.indices.contains(index) ? remaining[index] : remaining.last
        if let replacement {
            return MicaStrings.localized(
                "controllers.delete_active_confirm \(profile.displayName) \(replacement.displayName)",
                language: language
            )
        }
        return MicaStrings.localized(
            "controllers.delete_only_confirm \(profile.displayName)",
            language: language
        )
    }
}

private struct WorkbenchConnectionTestReportView: View {
    @Environment(\.micaAppLanguage) private var language

    let profile: RouterProfile
    let report: ConnectionTestReport

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: MicaSpacing.module) {
                Label(
                    report.summary.label(language: language),
                    systemImage: report.summary.workbenchSymbol
                )
                .micaFont(.callout, weight: .semibold)
                .labelStyle(MicaStatusLabelStyle(tint: report.summary.workbenchTint))

                Spacer(minLength: MicaSpacing.row)

                Text(verbatim: profile.displayName)
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(verbatim: localized(report.headline))
                .micaFont(.callout, weight: .semibold)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            WorkbenchFormRow("editor.hs_url") {
                WorkbenchFormValue(
                    value: localized(report.targetURL),
                    monospaced: true
                )
            }

            ForEach(report.steps) { step in
                WorkbenchConnectionTestStepRow(
                    title: localized(step.title),
                    value: localized(step.value),
                    state: step.state,
                    monospaced: step.id == "url"
                )
            }

            if let nextStep = report.nextStep.managementNonEmpty {
                Label {
                    Text(verbatim: localized(nextStep))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .micaFont(.callout)
                .labelStyle(MicaStatusLabelStyle(tint: report.summary.workbenchTint))
                .frame(
                    maxWidth: .infinity,
                    minHeight: MicaBounds.controlMinHeight,
                    alignment: .leading
                )
            }
        } header: {
            Label(
                MicaStrings.localizedKey("editor.connection_diagnosis", language: language),
                systemImage: report.summary.workbenchSymbol
            )
        }
        .accessibilityLabel(
            MicaStrings.localizedKey("editor.connection_diagnosis", language: language)
        )
    }

    private func localized(_ text: String) -> String {
        MicaStrings.relocalizedText(text, language: language)
    }
}

private struct WorkbenchConnectionTestStepRow: View {
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let title: String
    let value: String
    let state: ConnectionCheckState
    let monospaced: Bool

    private var usesStackedLayout: Bool {
        widthMode == .compact
    }

    var body: some View {
        Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    stepLabel
                    stepValue
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.module) {
                    stepLabel
                        .frame(width: MicaBounds.formLabelWidth, alignment: .leading)
                    stepValue
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MicaBounds.controlMinHeight, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var stepLabel: some View {
        Label(title, systemImage: state.workbenchSymbol)
            .micaFont(.callout)
            .labelStyle(MicaStatusLabelStyle(tint: state.workbenchTint))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stepValue: some View {
        WorkbenchFormValue(value: value, monospaced: monospaced)
    }
}

// MARK: - Configuration

struct WorkbenchConfigurationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        WorkbenchPageScaffold {
            commandBar
        } content: {
            configurationContent
        }
    }

    private var commandBar: some View {
        WorkbenchCommandBar {
            WorkbenchManagementHeader(
                systemImage: "slider.horizontal.3",
                titleKey: "workbench.configuration",
                detail: appModel.selectedRouter?.endpointURL
                    ?? MicaStrings.localizedKey(
                        "configuration.no_controller_detail",
                        language: language
                    )
            )
        } controls: {
            WorkbenchStatusBadge(
                text: MicaStrings.localized(
                    "overview.config_fields \(visibleConfigurationFieldCount)",
                    language: language
                ),
                tint: configStatus.workbenchTint
            )
        } commands: {
            WorkbenchIconCommand(
                titleKey: "action.refresh",
                systemImage: "arrow.clockwise",
                isEnabled: appModel.canRefreshSelectedRouter && !appModel.isRefreshingDashboard
            ) {
                appModel.refreshSelectedRouter()
            }
        }
    }

    @ViewBuilder
    private var configurationContent: some View {
        if appModel.selectedRouter == nil {
            WorkbenchStateView(
                kind: .noController,
                titleKey: "dashboard.connect_router",
                detailKey: "configuration.no_controller_detail"
            )
        } else if (appModel.isRefreshingDashboard
                    || appModel.controllerSessionPresentation.state == .connecting),
                  !hasConfigurationPresentation {
            WorkbenchStateView(
                kind: .loading,
                titleKey: "configuration.loading_title",
                detailKey: "configuration.loading_detail"
            )
        } else if (!appModel.selectedUnifiedCapabilities.snapshot
                    || !hasSupportedConfigurationCapability),
                  !hasConfigurationPresentation {
            WorkbenchStateView(
                kind: .unsupported,
                titleKey: "configuration.unsupported_title",
                detailKey: "configuration.unsupported_detail"
            )
        } else if configStatus.isFailure,
                  !hasConfigurationPresentation {
            WorkbenchStateView(
                kind: .failed,
                titleKey: "configuration.failed_title",
                detailKey: "configuration.failed_detail",
                message: configStatus.detail(language: language),
                actionTitleKey: "action.retry",
                action: appModel.refreshSelectedRouter
            )
        } else if !hasConfigurationPresentation {
            WorkbenchStateView(
                kind: .empty,
                titleKey: "configuration.empty_title",
                detailKey: "configuration.empty_detail",
                actionTitleKey: "action.refresh",
                action: appModel.refreshSelectedRouter
            )
        } else {
            VStack(spacing: 0) {
                if configStatus.isFailure {
                    WorkbenchStaleNotice(message: configStatus.detail(language: language))
                }

                WorkbenchManagementFormCanvas {
                    if hasModePresentation {
                        modeSection
                    }

                    if hasGeneralPresentation {
                        generalSection
                    }

                    if !reportedPorts.isEmpty {
                        portsSection
                    }

                    if hasTailscalePresentation {
                        WorkbenchSingBoxTailscaleSection()
                    }
                }
            }
        }
    }

    private var modeSection: some View {
        Section {
            configurationRow(
                "overview.config_outbound_mode",
                isBusy: appModel.changingMode
            ) {
                if !modeOptions.isEmpty {
                    Picker(
                        MicaStrings.localizedKey("overview.config_outbound_mode", language: language),
                        selection: modeBinding
                    ) {
                        ForEach(modeOptions, id: \.self) { mode in
                            Text(verbatim: MicaStrings.displayMode(mode, language: language))
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: MicaBounds.formControlMax, alignment: .leading)
                    .disabled(configWriteDisabled)
                } else {
                    configurationValue(
                        value: reported(reportedMode),
                        placeholder: reportedMode == nil
                    )
                }
            }

            if !appModel.controllerMetadata.config.modeOptions.isEmpty {
                configurationRow("overview.config_mode_options") {
                    configurationValue(
                        value: appModel.controllerMetadata.config.modeOptions.joined(separator: "\n")
                    )
                }
            }
        } header: {
            Label(
                MicaStrings.localizedKey("configuration.mode_section", language: language),
                systemImage: "arrow.triangle.branch"
            )
        }
    }

    private var generalSection: some View {
        Section {
            if let logLevel = appModel.controllerMetadata.config.logLevel,
               appModel.supportsUnifiedAction(.setLogLevel) {
                logLevelRow(logLevel)
            }
            if let value = appModel.controllerMetadata.config.allowLan,
               appModel.supportsUnifiedAction(.setAllowLAN) {
                booleanRow(
                    "overview.config_allow_lan",
                    value: value,
                    mutation: ControllerConfigMutation.allowLAN
                )
            }
            if let value = appModel.controllerMetadata.config.ipv6,
               appModel.supportsUnifiedAction(.setIPv6) {
                booleanRow(
                    "overview.config_ipv6",
                    value: value,
                    mutation: ControllerConfigMutation.ipv6
                )
            }
            if let value = appModel.controllerMetadata.config.tcpConcurrent,
               appModel.supportsUnifiedAction(.setTCPConcurrent) {
                booleanRow(
                    "overview.config_tcp_concurrent",
                    value: value,
                    mutation: ControllerConfigMutation.tcpConcurrent
                )
            }
            if let value = appModel.controllerMetadata.config.tunEnabled,
               appModel.supportsUnifiedAction(.setTUN) {
                booleanRow(
                    "overview.config_tun",
                    value: value,
                    mutation: ControllerConfigMutation.tun
                )
            }
        } header: {
            Label(
                MicaStrings.localizedKey("overview.config_snapshot", language: language),
                systemImage: "switch.2"
            )
        }
    }

    private var portsSection: some View {
        Section {
            let controllerID = appModel.selectedRouterID
            let generation = appModel.controllerSessionPresentation.generation
            ForEach(
                Array(reportedPorts.enumerated()),
                id: \.element.0.id
            ) { _, item in
                configurationRow(
                    item.0.titleKey,
                    isBusy: appModel.updatingConfigFieldID == "port:\(item.0.rawValue)"
                ) {
                    WorkbenchPortField(
                        titleKey: item.0.titleKey,
                        value: item.1,
                        disabled: configWriteDisabled
                    ) { next in
                        guard appModel.selectedRouterID == controllerID,
                              appModel.controllerSessionPresentation.generation == generation else {
                            return
                        }
                        appModel.updateControllerConfig(.port(item.0, next))
                    }
                    .id("\(controllerID?.uuidString ?? "none"):\(generation.uuidString):\(item.0.rawValue)")
                }
            }
        } header: {
            Label(
                MicaStrings.localizedKey("settings.connection", language: language),
                systemImage: "network"
            )
        }
    }

    private func logLevelRow(_ current: String) -> some View {
        configurationRow(
            "overview.config_log_level",
            isBusy: appModel.updatingConfigFieldID == "log-level"
        ) {
            Picker(
                MicaStrings.localizedKey("overview.config_log_level", language: language),
                selection: Binding(
                    get: { current },
                    set: { next in
                        guard next != current else { return }
                        appModel.updateControllerConfig(.logLevel(next))
                    }
                )
            ) {
                ForEach(logLevelOptions(current: current), id: \.self) { level in
                    Text(verbatim: logLevelLabel(level)).tag(level)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: MicaBounds.formControlMax, alignment: .leading)
            .disabled(configWriteDisabled)
        }
    }

    private func booleanRow(
        _ titleKey: String,
        value: Bool,
        mutation: @escaping (Bool) -> ControllerConfigMutation
    ) -> some View {
        configurationRow(
            titleKey,
            isBusy: appModel.updatingConfigFieldID == mutation(value).id
        ) {
            Toggle(
                MicaStrings.localizedKey(titleKey, language: language),
                isOn: Binding(
                    get: { value },
                    set: { appModel.updateControllerConfig(mutation($0)) }
                )
            )
            .disabled(configWriteDisabled)
        }
    }

    private func configurationRow<Control: View>(
        _ titleKey: String,
        isBusy: Bool = false,
        @ViewBuilder control: () -> Control
    ) -> some View {
        WorkbenchFormRow(titleKey, isBusy: isBusy) {
            control()
        }
    }

    private func configurationValue(
        value: String,
        monospaced: Bool = false,
        placeholder: Bool = false
    ) -> some View {
        Text(verbatim: value)
            .micaFont(.body, design: monospaced ? .monospaced : .default)
            .foregroundStyle(placeholder ? .secondary : .primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeOptions: [String] {
        var seen = Set<String>()
        var options = appModel.controllerMetadata.config.modeOptions.filter {
            guard let value = $0.managementNonEmpty else { return false }
            return seen.insert(normalizedMode(value)).inserted
        }

        if let reportedMode,
           !options.contains(where: { modesMatch($0, reportedMode) }) {
            options.insert(reportedMode, at: 0)
        }
        return options
    }

    private var modeBinding: Binding<String> {
        Binding(
            get: { modeSelection },
            set: { next in
                guard !modesMatch(next, appModel.controllerMetadata.mode) else { return }
                appModel.setMode(next)
            }
        )
    }

    private var modeSelection: String {
        modeOptions.first { modesMatch($0, appModel.controllerMetadata.mode) }
            ?? appModel.controllerMetadata.mode
    }

    private var modeAction: UnifiedControllerAction {
        appModel.selectedRouter.map(appModel.modeChangeAction(for:)) ?? .changeMode
    }

    private var reportedPorts: [(ControllerConfigPort, Int)] {
        guard appModel.supportsUnifiedAction(.setPort) else {
            return []
        }

        let ports: [(ControllerConfigPort, Int?)] = [
            (.http, appModel.controllerMetadata.config.port),
            (.socks, appModel.controllerMetadata.config.socksPort),
            (.redir, appModel.controllerMetadata.config.redirPort),
            (.mixed, appModel.controllerMetadata.config.mixedPort),
        ]
        return ports.compactMap { port, value in value.map { (port, $0) } }
    }

    private var configStatus: ControllerEndpointStatus {
        appModel.controllerHealth.status(for: .configs)
    }

    private var hasConfigurationPresentation: Bool {
        hasModePresentation
            || hasGeneralPresentation
            || !reportedPorts.isEmpty
            || hasTailscalePresentation
    }

    private var hasModePresentation: Bool {
        appModel.supportsUnifiedAction(modeAction)
            && (reportedMode != nil || !appModel.controllerMetadata.config.modeOptions.isEmpty)
    }

    private var hasGeneralPresentation: Bool {
        appModel.controllerMetadata.config.logLevel != nil
                && appModel.supportsUnifiedAction(.setLogLevel)
            || appModel.controllerMetadata.config.allowLan != nil
                && appModel.supportsUnifiedAction(.setAllowLAN)
            || appModel.controllerMetadata.config.ipv6 != nil
                && appModel.supportsUnifiedAction(.setIPv6)
            || appModel.controllerMetadata.config.tcpConcurrent != nil
                && appModel.supportsUnifiedAction(.setTCPConcurrent)
            || appModel.controllerMetadata.config.tunEnabled != nil
                && appModel.supportsUnifiedAction(.setTUN)
    }

    private var visibleConfigurationFieldCount: Int {
        var count = 0
        if hasModePresentation {
            count += reportedMode == nil ? 0 : 1
            count += appModel.controllerMetadata.config.modeOptions.isEmpty ? 0 : 1
        }
        if appModel.controllerMetadata.config.logLevel != nil,
           appModel.supportsUnifiedAction(.setLogLevel) {
            count += 1
        }
        if appModel.controllerMetadata.config.allowLan != nil,
           appModel.supportsUnifiedAction(.setAllowLAN) {
            count += 1
        }
        if appModel.controllerMetadata.config.ipv6 != nil,
           appModel.supportsUnifiedAction(.setIPv6) {
            count += 1
        }
        if appModel.controllerMetadata.config.tcpConcurrent != nil,
           appModel.supportsUnifiedAction(.setTCPConcurrent) {
            count += 1
        }
        if appModel.controllerMetadata.config.tunEnabled != nil,
           appModel.supportsUnifiedAction(.setTUN) {
            count += 1
        }
        return count + reportedPorts.count
    }

    private var hasTailscalePresentation: Bool {
        appModel.selectedUnifiedControllerType == .singBoxCompatible
            || appModel.singBoxTailscaleStatus != nil
            || appModel.singBoxTailscaleError != nil
    }

    private var hasSupportedConfigurationCapability: Bool {
        appModel.supportsUnifiedAction(modeAction)
            || appModel.supportsUnifiedAction(.setLogLevel)
            || appModel.supportsUnifiedAction(.setAllowLAN)
            || appModel.supportsUnifiedAction(.setIPv6)
            || appModel.supportsUnifiedAction(.setTCPConcurrent)
            || appModel.supportsUnifiedAction(.setTUN)
            || appModel.supportsUnifiedAction(.setPort)
            || hasTailscalePresentation
    }

    private var configWriteDisabled: Bool {
        appModel.isBusy || !appModel.canRefreshSelectedRouter || !permitsConfigurationWrites
    }

    private var permitsConfigurationWrites: Bool {
        switch appModel.controllerSessionPresentation.state {
        case .live, .partial:
            true
        case .idle, .connecting, .staleReconnecting, .failedBeforeFirstSnapshot,
             .failed, .stopped:
            false
        }
    }

    private func logLevelOptions(current: String) -> [String] {
        var options = ["silent", "error", "warning", "info", "debug"]
        if current.managementNonEmpty != nil, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
    }

    private func logLevelLabel(_ level: String) -> String {
        let key: String?
        switch level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "silent": key = "configuration.log_level_silent"
        case "error": key = "log_type.error"
        case "warning", "warn": key = "log_type.warning"
        case "info", "information": key = "log_type.info"
        case "debug": key = "log_type.debug"
        case "trace": key = "log_type.trace"
        default: key = nil
        }

        guard let key else { return level }
        return MicaStrings.localizedKey(key, language: language)
    }

    private var reportedMode: String? {
        guard let value = appModel.controllerMetadata.mode.managementNonEmpty else { return nil }
        switch value.lowercased() {
        case "unknown", "not loaded", "-":
            return nil
        default:
            return value
        }
    }

    private func normalizedMode(_ value: String) -> String {
        DashboardSnapshot.displayMode(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func modesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedMode(lhs) == normalizedMode(rhs)
    }

    private func reported(_ value: String?) -> String {
        value?.managementNonEmpty
            ?? MicaStrings.localizedKey("overview.config_not_reported", language: language)
    }
}

private struct WorkbenchPortField: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let value: Int
    let disabled: Bool
    let onCommit: (Int) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        titleKey: String,
        value: Int,
        disabled: Bool,
        onCommit: @escaping (Int) -> Void
    ) {
        self.titleKey = titleKey
        self.value = value
        self.disabled = disabled
        self.onCommit = onCommit
        _text = State(initialValue: String(value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: MicaSpacing.row) {
                TextField(
                    MicaStrings.localizedKey(titleKey, language: language),
                    text: $text
                )
                .textFieldStyle(.roundedBorder)
                .micaFont(.body).monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 104)
                .focused($isFocused)
                .onSubmit(commit)

                Button(action: commit) {
                    Image(systemName: "checkmark")
                        .frame(width: MicaBounds.iconControlSize, height: MicaBounds.iconControlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(disabled || parsedValue == nil || parsedValue == value)
                .help(MicaStrings.localizedKey("action.apply_port", language: language))
                .accessibilityLabel(
                    MicaStrings.localizedKey("action.apply_port", language: language)
                )
            }

            if showsValidationError {
                Text(MicaStrings.localizedKey("editor.validation_port_range", language: language))
                    .micaFont(.caption)
                    .foregroundStyle(MicaDesignTokens.signalRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: value) { _, next in
            if !isFocused { text = String(next) }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { text = String(value) }
        }
        .disabled(disabled)
    }

    private var parsedValue: Int? {
        guard let number = Int(text), (0...65_535).contains(number) else { return nil }
        return number
    }

    private var showsValidationError: Bool {
        isFocused && text != String(value) && parsedValue == nil
    }

    private func commit() {
        guard !disabled, let parsedValue, parsedValue != value else { return }
        onCommit(parsedValue)
    }
}

// MARK: - Actions

struct WorkbenchRuntimeConfirmation: Equatable {
    let routerID: RouterProfile.ID
    let generation: UUID
    let operationID: String

    func isCurrent(
        routerID: RouterProfile.ID?,
        generation: UUID,
        permitsLiveOperations: Bool
    ) -> Bool {
        self.routerID == routerID
            && self.generation == generation
            && permitsLiveOperations
    }
}

struct WorkbenchActionsProjection {
    static let connectionActions: [UnifiedControllerAction] = [
        .testConnection,
        .refreshSnapshot,
    ]
    static let snapshotActions: [UnifiedControllerAction] = [
        .reloadRules,
        .reloadProviders,
        .reloadProfile,
    ]
    static let runtimeOperationIDs = [
        "configuration-reload",
        "geo-resources",
        "memory",
        "dns-flush",
        "cache-flush",
    ]
    static let lifecycleOperationIDs = [
        "core-restart",
        "core-upgrade",
    ]

    let supportedDirectActionIDs: Set<String>
    let runtimeRows: [DiagnosticsRuntimeOperationRow]
    let lifecycleRows: [DiagnosticsRuntimeOperationRow]

    init(
        runtimeRows: [DiagnosticsRuntimeOperationRow],
        supports: (UnifiedControllerAction) -> Bool
    ) {
        let directActions = Self.connectionActions + Self.snapshotActions
        supportedDirectActionIDs = Set(
            directActions.lazy.filter(supports).map(\.rawValue)
        )
        self.runtimeRows = Self.supportedRuntimeRows(
            runtimeRows,
            ids: Self.runtimeOperationIDs
        )
        lifecycleRows = Self.supportedRuntimeRows(
            runtimeRows,
            ids: Self.lifecycleOperationIDs
        )
    }

    var supportedOperationCount: Int {
        supportedDirectActionIDs.count + runtimeRows.count + lifecycleRows.count
    }

    func supports(_ action: UnifiedControllerAction) -> Bool {
        supportedDirectActionIDs.contains(action.rawValue)
    }

    func runtimeRow(id: String) -> DiagnosticsRuntimeOperationRow? {
        (runtimeRows + lifecycleRows).first { $0.id == id }
    }

    static func supportedRuntimeRows(
        _ rows: [DiagnosticsRuntimeOperationRow],
        ids: [String]
    ) -> [DiagnosticsRuntimeOperationRow] {
        ids.compactMap { id in
            rows.first {
                $0.id == id
                    && $0.status == .supported
                    && $0.actionButtonKey != nil
            }
        }
    }
}

struct WorkbenchActionsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    @State private var pendingConfirmation: WorkbenchRuntimeConfirmation?

    var body: some View {
        let projection = WorkbenchActionsProjection(
            runtimeRows: appModel.diagnosticsRuntimeOperationRows,
            supports: appModel.supportsUnifiedAction
        )

        WorkbenchPageScaffold {
            commandBar(projection)
        } content: {
            actionsContent(projection)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let pendingConfirmation,
               isCurrent(pendingConfirmation),
               let row = projection.runtimeRow(id: pendingConfirmation.operationID) {
                confirmationBar(row)
            }
        }
        .onChange(of: appModel.selectedRouterID) { pendingConfirmation = nil }
        .onChange(of: appModel.controllerSessionPresentation.generation) { pendingConfirmation = nil }
        .onChange(of: appModel.controllerSessionPresentation.state) {
            if !permitsLiveOperations { pendingConfirmation = nil }
        }
    }

    @ViewBuilder
    private func actionsContent(_ projection: WorkbenchActionsProjection) -> some View {
        if appModel.selectedRouter == nil {
            WorkbenchStateView(
                kind: .noController,
                titleKey: "dashboard.connect_router",
                detailKey: "configuration.no_controller_detail"
            )
        } else if projection.supportedOperationCount == 0 {
            WorkbenchStateView(
                kind: .unsupported,
                titleKey: "diagnostics.capability_status_unavailable",
                detailKey: "diagnostics.runtime_operations_detail"
            )
        } else {
            VStack(spacing: 0) {
                if let retainedFailureMessage {
                    WorkbenchStaleNotice(message: retainedFailureMessage)
                }

                WorkbenchManagementFormCanvas {
                    connectionSection(projection)
                    snapshotSection(projection)
                    runtimeSection(projection)
                    lifecycleSection(projection)
                }
            }
        }
    }

    private func commandBar(_ projection: WorkbenchActionsProjection) -> some View {
        WorkbenchCommandBar {
            WorkbenchManagementHeader(
                systemImage: "bolt.badge.checkmark",
                titleKey: "workbench.actions",
                detail: appModel.selectedRouter?.endpointURL
                    ?? MicaStrings.localizedKey(
                        "configuration.no_controller_detail",
                        language: language
                    )
            )
        } controls: {
            WorkbenchStatusBadge(
                text: MicaStrings.localized(
                    "diagnostics.runtime_operations_count \(projection.supportedOperationCount)",
                    language: language
                ),
                tint: projection.supportedOperationCount > 0
                    ? MicaDesignTokens.signalMint
                    : MicaDesignTokens.signalAmber
            )
        }
    }

    @ViewBuilder
    private func connectionSection(_ projection: WorkbenchActionsProjection) -> some View {
        let showsTest = projection.supports(.testConnection)
        let showsRefresh = projection.supports(.refreshSnapshot)

        if showsTest || showsRefresh {
            Section {
                if showsTest {
                    directActionLine(
                        titleKey: "action.test",
                        detailKey: "command.action_test_detail",
                        systemImage: MicaSymbols.Command.test,
                        isRunning: appModel.connectionState == .connecting,
                        isEnabled: appModel.canTestSelectedRouter,
                        requiresLiveSession: false
                    ) {
                        appModel.testSelectedRouter()
                    }
                }

                if showsRefresh {
                    directActionLine(
                        titleKey: "action.refresh",
                        detailKey: "command.action_refresh_detail",
                        systemImage: MicaSymbols.Operation.refreshData,
                        isRunning: appModel.isRefreshingDashboard,
                        isEnabled: appModel.canRefreshSelectedRouter,
                        requiresLiveSession: false
                    ) {
                        appModel.refreshSelectedRouter()
                    }
                }
            } header: {
                Label(
                    MicaStrings.localizedKey("settings.connection", language: language),
                    systemImage: "antenna.radiowaves.left.and.right"
                )
            }
        }
    }

    @ViewBuilder
    private func snapshotSection(_ projection: WorkbenchActionsProjection) -> some View {
        let showsRules = projection.supports(.reloadRules)
        let showsProviders = projection.supports(.reloadProviders)
        let showsProfile = projection.supports(.reloadProfile)

        if showsRules || showsProviders || showsProfile {
            Section {
                if showsRules {
                    directActionLine(
                        titleKey: "action.reload_rules",
                        detailKey: "diagnostics.operation_rules_detail",
                        systemImage: MicaSymbols.Data.rules,
                        isRunning: appModel.reloadingRules
                    ) {
                        appModel.reloadRules()
                    }
                }

                if showsProviders {
                    directActionLine(
                        titleKey: "action.reload_providers",
                        detailKey: "diagnostics.operation_external_resources_detail",
                        systemImage: MicaSymbols.Data.providers,
                        isRunning: appModel.reloadingProviders
                    ) {
                        appModel.reloadProviders()
                    }
                }

                if showsProfile {
                    directActionLine(
                        titleKey: "action.surge_reload_profile",
                        detailKey: "action.help_surge_reload_profile",
                        systemImage: "doc.badge.arrow.up",
                        isRunning: appModel.reloadingSurgeProfile
                    ) {
                        appModel.reloadSurgeProfile()
                    }
                }
            } header: {
                Label(
                    MicaStrings.localizedKey(
                        "diagnostics.operation_external_resources",
                        language: language
                    ),
                    systemImage: "externaldrive.connected.to.line.below"
                )
            }
        }
    }

    @ViewBuilder
    private func runtimeSection(_ projection: WorkbenchActionsProjection) -> some View {
        if !projection.runtimeRows.isEmpty {
            Section {
                runtimeRows(projection.runtimeRows)
            } header: {
                Label(
                    MicaStrings.localizedKey("diagnostics.runtime_operations", language: language),
                    systemImage: "gauge.with.dots.needle.67percent"
                )
            }
        }
    }

    @ViewBuilder
    private func lifecycleSection(_ projection: WorkbenchActionsProjection) -> some View {
        if !projection.lifecycleRows.isEmpty {
            Section {
                runtimeRows(projection.lifecycleRows)
            } header: {
                Label(
                    MicaStrings.localizedKey(
                        "diagnostics.operation_core_lifecycle",
                        language: language
                    ),
                    systemImage: "powerplug"
                )
            } footer: {
                Text(
                    MicaStrings.localizedKey(
                        "diagnostics.operation_core_lifecycle_detail",
                        language: language
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func directActionLine(
        titleKey: String,
        detailKey: String,
        systemImage: String,
        isRunning: Bool,
        isEnabled: Bool = true,
        requiresLiveSession: Bool = true,
        command: @escaping () -> Void
    ) -> some View {
        WorkbenchOperationLine(
            systemImage: systemImage,
            tint: MicaDesignTokens.signalCyan,
            titleKey: titleKey,
            detailKey: detailKey,
            isRunning: isRunning
        ) {
            Button(action: command) {
                Label(
                    MicaStrings.localizedKey(titleKey, language: language),
                    systemImage: systemImage
                )
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: MicaBounds.controlMinHeight)
            }
            .buttonStyle(.bordered)
            .disabled(
                !isEnabled
                    || appModel.isBusy
                    || (requiresLiveSession && !permitsLiveOperations)
            )
        }
    }

    @ViewBuilder
    private func runtimeRows(_ rows: [DiagnosticsRuntimeOperationRow]) -> some View {
        ForEach(rows) { row in
            runtimeOperationLine(row)
        }
    }

    private func runtimeOperationLine(_ row: DiagnosticsRuntimeOperationRow) -> some View {
        WorkbenchOperationLine(
            systemImage: row.systemImage,
            tint: row.status.workbenchTint,
            titleKey: row.titleKey,
            detailKey: row.detailKey,
            reason: row.status == .supported ? nil : row.evidence,
            isRunning: appModel.runningRuntimeOperationID == row.id
        ) {
            if let buttonKey = row.actionButtonKey {
                Button(role: row.isDestructive ? .destructive : nil) {
                    if row.requiresConfirmation {
                        guard let routerID = appModel.selectedRouterID else { return }
                        pendingConfirmation = WorkbenchRuntimeConfirmation(
                            routerID: routerID,
                            generation: appModel.controllerSessionPresentation.generation,
                            operationID: row.id
                        )
                    } else {
                        appModel.performDiagnosticsRuntimeOperation(row.id)
                    }
                } label: {
                    Label(
                        MicaStrings.localizedKey(buttonKey, language: language),
                        systemImage: row.systemImage
                    )
                    .labelStyle(.titleAndIcon)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: MicaBounds.controlMinHeight)
                }
                .buttonStyle(.bordered)
                .disabled(
                    appModel.isBusy
                        || row.status != .supported
                        || !permitsLiveOperations
                )
            } else {
                WorkbenchStatusBadge(
                    text: row.status.label(language: language),
                    tint: row.status.workbenchTint
                )
            }
        }
    }

    private func confirmationBar(_ row: DiagnosticsRuntimeOperationRow) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.module) { confirmationContent(row) }
            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                confirmationContent(row)
            }
        }
        .padding(.horizontal, MicaBounds.regularPagePadding)
        .padding(.vertical, MicaSpacing.row)
        .background(MicaStyle.groupedPageFill)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private func confirmationContent(_ row: DiagnosticsRuntimeOperationRow) -> some View {
        Label {
            Text(
                MicaStrings.localizedKey(
                    row.confirmationMessageKey ?? "diagnostics.confirm_runtime_message",
                    language: language
                )
            )
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MicaDesignTokens.signalAmber)
        }

        Spacer(minLength: MicaSpacing.row)

        Button(MicaStrings.localizedKey("action.cancel", language: language)) {
            pendingConfirmation = nil
        }
        .frame(minHeight: MicaBounds.controlMinHeight)

        Button(
            MicaStrings.localizedKey(
                row.actionButtonKey ?? row.titleKey,
                language: language
            ),
            role: .destructive
        ) {
            guard let pendingConfirmation,
                  pendingConfirmation.operationID == row.id,
                  isCurrent(pendingConfirmation) else {
                self.pendingConfirmation = nil
                return
            }
            self.pendingConfirmation = nil
            appModel.performDiagnosticsRuntimeOperation(row.id)
        }
        .buttonStyle(.borderedProminent)
        .tint(MicaDesignTokens.signalRed)
        .frame(minHeight: MicaBounds.controlMinHeight)
    }

    private func isCurrent(_ confirmation: WorkbenchRuntimeConfirmation) -> Bool {
        confirmation.isCurrent(
            routerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation,
            permitsLiveOperations: permitsLiveOperations
        )
    }

    private var permitsLiveOperations: Bool {
        switch appModel.controllerSessionPresentation.state {
        case .live, .partial:
            true
        case .idle, .connecting, .staleReconnecting, .failedBeforeFirstSnapshot,
             .failed, .stopped:
            false
        }
    }

    private var retainedFailureMessage: String? {
        switch appModel.controllerSessionPresentation.state {
        case .staleReconnecting(let message), .partial(let message), .failed(let message):
            message.managementNonEmpty
        default:
            nil
        }
    }

}

private extension CapabilityStatus {
    var workbenchTint: Color {
        switch self {
        case .supported: MicaDesignTokens.signalMint
        case .partial, .untested: MicaDesignTokens.signalAmber
        case .failed: MicaDesignTokens.signalRed
        case .unavailable: .secondary
        }
    }
}

// MARK: - sing-box Tailscale

private struct WorkbenchSingBoxTailscaleSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        Section {
            if let status = appModel.singBoxTailscaleStatus {
                if let error = appModel.singBoxTailscaleError {
                    Label {
                        Text(verbatim: error)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .micaFont(.caption)
                    .foregroundStyle(MicaDesignTokens.signalAmber)

                    if !status.endpoints.isEmpty { Divider() }
                }

                if status.endpoints.isEmpty {
                    inlineState(
                        symbol: "network.slash",
                        titleKey: "tailscale.no_endpoints_title",
                        detail: MicaStrings.localizedKey(
                            "tailscale.no_endpoints_detail",
                            language: language
                        )
                    )
                } else {
                    ForEach(Array(status.endpoints.enumerated()), id: \.element.id) { index, endpoint in
                        if index > 0 { Divider() }
                        WorkbenchTailscaleEndpointView(
                            controllerID: appModel.selectedRouterID,
                            generation: appModel.controllerSessionPresentation.generation,
                            endpoint: endpoint
                        )
                    }
                }
            } else if let error = appModel.singBoxTailscaleError {
                inlineState(
                    symbol: "exclamationmark.triangle",
                    titleKey: "tailscale.stream_error_title",
                    detail: MicaStrings.localized(
                        "tailscale.stream_error_detail \(error)",
                        language: language
                    )
                )
            } else {
                HStack(spacing: MicaSpacing.row) {
                    ProgressView()
                        .controlSize(.small)
                    Text(MicaStrings.localizedKey("tailscale.loading", language: language))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            }
        } header: {
            Label(
                MicaStrings.localizedKey(
                    "diagnostics.operation_tailscale",
                    language: language
                ),
                systemImage: "network"
            )
        } footer: {
            Text(
                MicaStrings.localizedKey(
                    "diagnostics.operation_tailscale_detail",
                    language: language
                )
            )
        }
    }

    private func inlineState(
        symbol: String,
        titleKey: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: MicaSpacing.module) {
            Image(systemName: symbol)
                .micaFont(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.callout, weight: .semibold)
                Text(verbatim: detail)
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    }
}

private struct WorkbenchTailscaleEndpointView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let controllerID: RouterProfile.ID?
    let generation: UUID
    let endpoint: SingBoxTailscaleEndpoint

    @State private var pendingExitNodeID: String?
    @State private var confirmsLogout = false

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                detailRow("tailscale.endpoint_tag", endpoint.endpointTag)
                detailRow("tailscale.backend_state", endpoint.backendState)
                detailRow("tailscale.network_name", endpoint.networkName)
                detailRow("tailscale.magic_dns_suffix", endpoint.magicDNSSuffix)
                authenticationURLRow
                detailRow(
                    "tailscale.key_authentication",
                    booleanLabel(endpoint.usesKeyAuthentication)
                )

                if let peer = endpoint.selfPeer {
                    Divider()
                    peerDisclosure("tailscale.current_device", peer: peer)
                }

                if !exitNodeCandidates.isEmpty {
                    Divider()
                    WorkbenchFormRow("tailscale.exit_node_candidates") {
                        Picker(
                            MicaStrings.localizedKey(
                                "tailscale.exit_node_candidates",
                                language: language
                            ),
                            selection: exitNodeSelection
                        ) {
                            Text(
                                MicaStrings.localizedKey(
                                    "tailscale.exit_node_none",
                                    language: language
                                )
                            )
                            .tag("")

                            ForEach(exitNodeCandidates) { peer in
                                Text(verbatim: peerTitle(peer)).tag(peer.stableID)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: MicaBounds.formControlMax, alignment: .leading)
                        .disabled(appModel.isBusy)
                    }
                } else if let peer = endpoint.exitNode {
                    Divider()
                    peerDisclosure("tailscale.exit_node", peer: peer)
                }

                ForEach(endpoint.userGroups) { group in
                    Divider()
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: MicaSpacing.row) {
                            detailRow("tailscale.user_id", String(group.userID))
                            detailRow("tailscale.login_name", group.loginName)
                            detailRow("tailscale.display_name", group.displayName)
                            detailRow("tailscale.profile_picture_url", group.profilePictureURL)

                            ForEach(group.peers) { peer in
                                peerDisclosure("tailscale.peer", peer: peer)
                            }
                        }
                        .padding(.top, MicaSpacing.row)
                    } label: {
                        Label(groupTitle(group), systemImage: "person.2")
                            .textSelection(.enabled)
                    }
                }

                if endpoint.selfPeer != nil {
                    Divider()
                    logoutControls
                }
            }
            .padding(.top, MicaSpacing.row)
        } label: {
            HStack(spacing: MicaSpacing.row) {
                Image(systemName: "network")
                    .foregroundStyle(MicaDesignTokens.signalCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: endpointTitle)
                        .micaFont(.callout, weight: .semibold)
                        .textSelection(.enabled)
                    Text(verbatim: endpoint.backendState.managementNonEmpty ?? endpoint.endpointTag)
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .onChange(of: endpoint.exitNode?.stableID) { _, next in
            if pendingExitNodeID == next { pendingExitNodeID = nil }
        }
        .onChange(of: appModel.runningRuntimeOperationID) { _, next in
            if next == nil { pendingExitNodeID = nil }
        }
        .onChange(of: appModel.selectedRouterID) { _, next in
            if next != controllerID {
                pendingExitNodeID = nil
                confirmsLogout = false
            }
        }
        .onChange(of: appModel.controllerSessionPresentation.generation) { _, next in
            if next != generation {
                pendingExitNodeID = nil
                confirmsLogout = false
            }
        }
    }

    @ViewBuilder
    private var logoutControls: some View {
        if confirmsLogout {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MicaSpacing.row) { logoutConfirmationContent }
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    logoutConfirmationContent
                }
            }
        } else {
            HStack {
                Spacer(minLength: 0)
                Button {
                    if isCurrentSession { confirmsLogout = true }
                } label: {
                    Label(
                        MicaStrings.localizedKey("tailscale.logout", language: language),
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
                    .frame(minHeight: MicaBounds.controlMinHeight)
                }
                .buttonStyle(.bordered)
                .disabled(appModel.isBusy)
            }
        }
    }

    @ViewBuilder
    private var logoutConfirmationContent: some View {
        Text(MicaStrings.localizedKey("tailscale.logout", language: language))
            .foregroundStyle(MicaDesignTokens.signalRed)

        Spacer(minLength: MicaSpacing.row)

        Button(MicaStrings.localizedKey("action.cancel", language: language)) {
            confirmsLogout = false
        }
        .frame(minHeight: MicaBounds.controlMinHeight)

        Button(
            MicaStrings.localizedKey("tailscale.logout", language: language),
            role: .destructive
        ) {
            confirmsLogout = false
            guard isCurrentSession else { return }
            appModel.logoutSingBoxTailscale(endpointTag: endpoint.endpointTag)
        }
        .buttonStyle(.borderedProminent)
        .tint(MicaDesignTokens.signalRed)
        .disabled(appModel.isBusy)
        .frame(minHeight: MicaBounds.controlMinHeight)
    }

    private var endpointTitle: String {
        endpoint.networkName.managementNonEmpty
            ?? endpoint.endpointTag.managementNonEmpty
            ?? MicaStrings.localizedKey("diagnostics.operation_tailscale", language: language)
    }

    private var exitNodeSelection: Binding<String> {
        Binding(
            get: { pendingExitNodeID ?? endpoint.exitNode?.stableID ?? "" },
            set: { next in
                guard isCurrentSession else { return }
                guard next != (pendingExitNodeID ?? endpoint.exitNode?.stableID ?? "") else {
                    return
                }
                pendingExitNodeID = next
                appModel.setSingBoxTailscaleExitNode(
                    endpointTag: endpoint.endpointTag,
                    stableID: next
                )
            }
        )
    }

    private var exitNodeCandidates: [SingBoxTailscalePeer] {
        var seen = Set<String>()
        var peers: [SingBoxTailscalePeer] = []

        if let current = endpoint.exitNode,
           current.stableID.managementNonEmpty != nil,
           seen.insert(current.stableID).inserted {
            peers.append(current)
        }

        for group in endpoint.userGroups {
            for peer in group.peers
                where peer.canBeExitNode
                    && peer.stableID.managementNonEmpty != nil
                    && seen.insert(peer.stableID).inserted {
                peers.append(peer)
            }
        }

        return peers
    }

    private var isCurrentSession: Bool {
        appModel.selectedRouterID == controllerID
            && appModel.controllerSessionPresentation.generation == generation
            && permitsMutation
    }

    private var permitsMutation: Bool {
        switch appModel.controllerSessionPresentation.state {
        case .live, .partial:
            true
        case .idle, .connecting, .staleReconnecting, .failedBeforeFirstSnapshot,
             .failed, .stopped:
            false
        }
    }

    private func groupTitle(_ group: SingBoxTailscaleUserGroup) -> String {
        group.displayName.managementNonEmpty
            ?? group.loginName.managementNonEmpty
            ?? String(group.userID)
    }

    private func peerTitle(_ peer: SingBoxTailscalePeer) -> String {
        peer.hostName.managementNonEmpty
            ?? peer.dnsName.managementNonEmpty
            ?? peer.stableID
    }

    private func peerDisclosure(_ titleKey: String, peer: SingBoxTailscalePeer) -> some View {
        DisclosureGroup {
            WorkbenchTailscalePeerDetails(peer: peer)
                .padding(.top, MicaSpacing.row)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.row) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.caption, weight: .medium)
                    .foregroundStyle(.secondary)

                Text(verbatim: peerTitle(peer))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailRow(_ titleKey: String, _ value: String) -> some View {
        WorkbenchFormRow(titleKey) {
            WorkbenchFormValue(
                value: value.managementNonEmpty
                    ?? MicaStrings.localizedKey("overview.config_not_reported", language: language),
                placeholder: value.managementNonEmpty == nil
            )
        }
    }

    private var authenticationURLRow: some View {
        WorkbenchFormRow("tailscale.authentication_url") {
            HStack(alignment: .center, spacing: MicaSpacing.row) {
                WorkbenchFormValue(
                    value: endpoint.authenticationURL.managementNonEmpty == nil
                        ? MicaStrings.localizedKey(
                            "overview.config_not_reported",
                            language: language
                        )
                        : endpoint.authenticationURL,
                    monospaced: true,
                    placeholder: endpoint.authenticationURL.managementNonEmpty == nil
                )

                if let authenticationLinkURL {
                    Link(destination: authenticationLinkURL) {
                        Image(systemName: "arrow.up.right.square")
                            .frame(
                                width: MicaBounds.iconControlSize,
                                height: MicaBounds.iconControlSize
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(
                        MicaStrings.localizedKey(
                            "tailscale.authentication_url",
                            language: language
                        )
                    )
                    .accessibilityLabel(
                        MicaStrings.localizedKey(
                            "tailscale.authentication_url",
                            language: language
                        )
                    )
                }
            }
        }
    }

    private var authenticationLinkURL: URL? {
        guard let value = endpoint.authenticationURL.managementNonEmpty,
              let url = URL(string: value),
              url.scheme?.isEmpty == false else {
            return nil
        }
        return url
    }

    private func booleanLabel(_ value: Bool) -> String {
        MicaStrings.localizedKey(
            value ? "overview.config_enabled" : "overview.config_disabled",
            language: language
        )
    }
}

private struct WorkbenchTailscalePeerDetails: View {
    @Environment(\.micaAppLanguage) private var language

    let peer: SingBoxTailscalePeer

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            row("tailscale.host_name", peer.hostName)
            row("tailscale.dns_name", peer.dnsName)
            row("tailscale.operating_system", peer.operatingSystem)
            row("tailscale.ip_addresses", peer.ipAddresses.joined(separator: "\n"))
            row("tailscale.online", booleanLabel(peer.online))
            row("tailscale.active", booleanLabel(peer.active))
            row("tailscale.exit_node", booleanLabel(peer.isExitNode))
            row("tailscale.can_be_exit_node", booleanLabel(peer.canBeExitNode))
            row("tailscale.received_bytes", byteString(peer.receivedBytes))
            row("tailscale.transmitted_bytes", byteString(peer.transmittedBytes))
            row("tailscale.key_expiry", String(peer.keyExpiry))
            row("tailscale.stable_id", peer.stableID)
            row("tailscale.expired", booleanLabel(peer.expired))
            row("tailscale.ssh_host_keys", peer.sshHostKeys.joined(separator: "\n"))
            row("tailscale.sharee_node", booleanLabel(peer.isShareeNode))
            row("tailscale.last_seen", String(peer.lastSeen))
        }
    }

    private func row(_ titleKey: String, _ value: String) -> some View {
        WorkbenchFormRow(titleKey) {
            WorkbenchFormValue(
                value: value.managementNonEmpty
                    ?? MicaStrings.localizedKey("overview.config_not_reported", language: language),
                monospaced: true,
                placeholder: value.managementNonEmpty == nil
            )
        }
    }

    private func booleanLabel(_ value: Bool) -> String {
        MicaStrings.localizedKey(
            value ? "overview.config_enabled" : "overview.config_disabled",
            language: language
        )
    }

    private func byteString(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}

// MARK: - Diagnostics

struct WorkbenchDiagnosticsField: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let value: String
    let monospaced: Bool
}

enum WorkbenchDiagnosticsProjection {
    static func fields(for row: CheckResultRow) -> [WorkbenchDiagnosticsField] {
        let candidates: [(id: String, titleKey: String, value: String, monospaced: Bool)] = [
            ("current-state", "diagnostics.check_state", row.currentState, false),
            ("latest-result", "diagnostics.check_latest", row.latestResult, false),
            ("last-checked", "overview.last_health_check", row.lastChecked, true),
            ("next-action", "diagnostics.check_next", row.nextAction, false),
        ]

        return candidates.compactMap { candidate in
            guard let value = displayableText(candidate.value) else {
                return nil
            }
            return WorkbenchDiagnosticsField(
                id: candidate.id,
                titleKey: candidate.titleKey,
                value: value,
                monospaced: candidate.monospaced
            )
        }
    }

    static func displayableText(_ value: String) -> String? {
        guard let value = value.managementNonEmpty,
              !containsMachineAssignment(value),
              !containsAPIPath(value) else {
            return nil
        }
        return value
    }

    private static func containsMachineAssignment(_ value: String) -> Bool {
        value.split { character in
            character.isWhitespace || character == ";" || character == ","
        }.contains { fragment in
            guard let separator = fragment.firstIndex(of: "=") else {
                return false
            }
            let key = fragment[..<separator]
            let rawValue = fragment[fragment.index(after: separator)...]
            return !key.isEmpty
                && !rawValue.isEmpty
                && key.allSatisfy {
                    $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "."
                }
        }
    }

    private static func containsAPIPath(_ value: String) -> Bool {
        let uppercased = value.uppercased()
        let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
        if methods.contains(where: { uppercased.contains("\($0) /") }) {
            return true
        }

        let punctuation = CharacterSet(charactersIn: ".,;:!?()[]{}<>\"'")
        return value.split(whereSeparator: \.isWhitespace).contains { fragment in
            let token = String(fragment).trimmingCharacters(in: punctuation)
            if token.hasPrefix("/"), token.count > 1 {
                return true
            }
            guard let components = URLComponents(string: token),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  components.host != nil else {
                return false
            }
            return !components.path.isEmpty && components.path != "/"
        }
    }
}

private enum WorkbenchDiagnosticsPanel: Hashable {
    case controller
    case endpointResults
    case endpointWorkflow
    case checkResults
    case capabilities
    case coverage
    case observability
    case exportPolicy
}

struct WorkbenchDiagnosticsSupport: Equatable, Sendable {
    var enhancedSnapshot: Bool
    var providerUpdate: Bool
    var delayTest: Bool
    var connectionClose: Bool
}

struct WorkbenchDiagnosticsVisibleProjection: Equatable {
    let endpointHealthRows: [ControllerEndpointHealth]
    let capabilityRows: [CapabilityMatrixRow]
    let coverageRows: [CapabilityMatrixRow]
    let observabilityRows: [ObservabilityReadinessRow]
    let endpointCheckSteps: [EndpointCheckStep]
    let checkResultRows: [CheckResultRow]

    var hasRows: Bool {
        !endpointHealthRows.isEmpty
            || !capabilityRows.isEmpty
            || !coverageRows.isEmpty
            || !observabilityRows.isEmpty
            || !endpointCheckSteps.isEmpty
            || !checkResultRows.isEmpty
    }
}

enum WorkbenchDiagnosticsVisibility {
    static func availableCapabilityRows(
        _ rows: [CapabilityMatrixRow]
    ) -> [CapabilityMatrixRow] {
        rows.filter {
            $0.status != .unavailable
                && $0.id != "controller-family"
                && $0.id != "adapter-source"
                && $0.title.managementNonEmpty != nil
                && $0.operationImpact.managementNonEmpty != nil
        }
    }

    static func availableObservabilityRows(
        _ rows: [ObservabilityReadinessRow]
    ) -> [ObservabilityReadinessRow] {
        rows.filter {
            $0.state != .unavailable
                && $0.state != .futureOptionalStream
                && $0.title.managementNonEmpty != nil
                && $0.detail.managementNonEmpty != nil
        }
    }

    static func availableEndpointSteps(
        _ rows: [EndpointCheckStep],
        support: WorkbenchDiagnosticsSupport
    ) -> [EndpointCheckStep] {
        rows.filter { row in
            let isSupported = switch row.id {
            case "endpoint-enhanced-snapshot":
                support.enhancedSnapshot
            case "endpoint-provider-update":
                support.providerUpdate
            case "endpoint-delay-test":
                support.delayTest
            case "endpoint-connection-close":
                support.connectionClose
            default:
                true
            }
            return isSupported
                && row.title.managementNonEmpty != nil
                && row.detail.managementNonEmpty != nil
                && row.nextAction.managementNonEmpty != nil
        }
    }

    static func availableCheckResults(
        _ rows: [CheckResultRow],
        support: WorkbenchDiagnosticsSupport
    ) -> [CheckResultRow] {
        rows.filter { row in
            let isSupported = switch row.id {
            case "enhanced-snapshot":
                support.enhancedSnapshot
            case "provider-update":
                support.providerUpdate
            case "delay-test":
                support.delayTest
            case "close-connection", "close-all-connections":
                support.connectionClose
            default:
                true
            }
            return isSupported
                && row.title.managementNonEmpty != nil
                && !WorkbenchDiagnosticsProjection.fields(for: row).isEmpty
        }
    }

    static func projection(
        endpointHealthRows: [ControllerEndpointHealth],
        capabilityRows: [CapabilityMatrixRow],
        coverageRows: [CapabilityMatrixRow],
        observabilityRows: [ObservabilityReadinessRow],
        endpointCheckSteps: [EndpointCheckStep],
        checkResultRows: [CheckResultRow],
        support: WorkbenchDiagnosticsSupport
    ) -> WorkbenchDiagnosticsVisibleProjection {
        WorkbenchDiagnosticsVisibleProjection(
            endpointHealthRows: endpointHealthRows,
            capabilityRows: availableCapabilityRows(capabilityRows),
            coverageRows: availableCapabilityRows(coverageRows),
            observabilityRows: availableObservabilityRows(observabilityRows),
            endpointCheckSteps: availableEndpointSteps(
                endpointCheckSteps,
                support: support
            ),
            checkResultRows: availableCheckResults(
                checkResultRows,
                support: support
            )
        )
    }
}

private struct WorkbenchAnimatedDisclosure<Label: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var isExpanded: Bool

    private let label: Label
    private let content: () -> Content

    init(
        isExpanded: Binding<Bool>,
        @ViewBuilder label: () -> Label,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _isExpanded = isExpanded
        self.label = label()
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withTransaction(
                    Transaction(animation: reduceMotion ? nil : WorkbenchMotion.expand)
                ) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: MicaSpacing.row) {
                    Image(systemName: "chevron.right")
                        .micaFont(.caption2, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                        .accessibilityHidden(true)

                    label
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, MicaSpacing.row)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                content()
                    .transition(.opacity)
            }
        }
    }
}

private struct WorkbenchDiagnosticsDisclosure<Content: View>: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    @Binding var isExpanded: Bool
    let titleKey: String
    let systemImage: String
    var detailKey: String?
    var count: Int?
    var tint = MicaDesignTokens.signalCyan
    var showsBottomDivider = true
    private let content: () -> Content

    init(
        isExpanded: Binding<Bool>,
        titleKey: String,
        systemImage: String,
        detailKey: String? = nil,
        count: Int? = nil,
        tint: Color = MicaDesignTokens.signalCyan,
        showsBottomDivider: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _isExpanded = isExpanded
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.detailKey = detailKey
        self.count = count
        self.tint = tint
        self.showsBottomDivider = showsBottomDivider
        self.content = content
    }

    var body: some View {
        WorkbenchAnimatedDisclosure(isExpanded: $isExpanded) {
            Group {
                switch widthMode {
                case .regular:
                    HStack(alignment: .top, spacing: MicaSpacing.row) {
                        identity
                        Spacer(minLength: MicaSpacing.row)
                        countLabel
                    }
                case .compact:
                    VStack(alignment: .leading, spacing: MicaSpacing.row) {
                        identity
                        countLabel
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } content: {
            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                content()
            }
            .padding(.top, MicaSpacing.row)
            .padding(.leading, 34)
            .padding(.trailing, MicaSpacing.row)
            .padding(.bottom, MicaSpacing.module)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(tint.opacity(0.28))
                    .frame(width: 2)
                    .padding(.leading, 18)
                    .padding(.vertical, MicaSpacing.row)
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsBottomDivider {
                Divider()
            }
        }
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: MicaSpacing.row) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.subheadline, weight: .semibold)

                if let detailKey {
                    Text(MicaStrings.localizedKey(detailKey, language: language))
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var countLabel: some View {
        if let count {
            Text(verbatim: String(count))
                .micaFont(.caption, weight: .semibold, design: .monospaced)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
        }
    }
}

private struct WorkbenchDiagnosticStatusLabel: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: MicaSpacing.tight) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)

            Text(verbatim: text)
                .micaFont(.caption, weight: .semibold)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

private struct WorkbenchDiagnosticsResponsiveLayout<Regular: View, Compact: View>: View {
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    private let regular: Regular
    private let compact: Compact

    init(
        @ViewBuilder regular: () -> Regular,
        @ViewBuilder compact: () -> Compact
    ) {
        self.regular = regular()
        self.compact = compact()
    }

    var body: some View {
        switch widthMode {
        case .regular:
            regular
        case .compact:
            compact
        }
    }
}

private struct WorkbenchDiagnosticsSummaryFact: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.tight) {
            Label {
                Text(MicaStrings.localizedKey(titleKey, language: language))
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            .micaFont(.caption, weight: .medium)
            .foregroundStyle(.secondary)

            Text(verbatim: value)
                .micaFont(.callout, weight: .medium)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct WorkbenchDiagnosticsMetadataItem: Identifiable {
    let id: String
    let titleKey: String
    let value: String
    var monospaced = false
    var placeholder = false
    var statusTint: Color?
}

private struct WorkbenchDiagnosticsMetadataGrid: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let rows: [[WorkbenchDiagnosticsMetadataItem]]

    var body: some View {
        Group {
            switch widthMode {
            case .regular:
                regularGrid
            case .compact:
                compactList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var regularGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                if rowIndex > 0 {
                    Divider()
                }

                HStack(alignment: .top, spacing: MicaSpacing.section) {
                    ForEach(row) { item in
                        metadataCell(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, MicaSpacing.row)
            }
        }
    }

    private var compactList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.flatMap { $0 }.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                }

                metadataCell(item)
                    .padding(.vertical, MicaSpacing.row)
            }
        }
    }

    private func metadataCell(_ item: WorkbenchDiagnosticsMetadataItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(MicaStrings.localizedKey(item.titleKey, language: language))
                .micaFont(.caption, weight: .medium)
                .foregroundStyle(.secondary)

            if let statusTint = item.statusTint {
                WorkbenchDiagnosticStatusLabel(
                    text: item.value,
                    tint: statusTint
                )
            } else {
                Text(verbatim: item.value)
                    .micaFont(
                        .callout,
                        weight: .medium,
                        design: item.monospaced ? .monospaced : .default
                    )
                    .foregroundStyle(item.placeholder ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WorkbenchEndpointHealthRow: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let endpoint: ControllerEndpointHealth

    var body: some View {
        Group {
            switch widthMode {
            case .regular:
                HStack(alignment: .center, spacing: MicaSpacing.module) {
                    identity
                    Spacer(minLength: MicaSpacing.module)
                    status
                }
            case .compact:
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    identity
                    status
                }
            }
        }
        .padding(.vertical, MicaSpacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identity: some View {
        let detail = WorkbenchDiagnosticsProjection.displayableText(
            MicaStrings.displayEndpointDetail(
                endpoint.status.detail(language: language),
                language: language
            )
        )

        return VStack(alignment: .leading, spacing: 2) {
            Text(
                MicaStrings.localizedKey(
                    endpoint.endpoint.displayTitleKey,
                    language: language
                )
            )
            .micaFont(.callout, weight: .medium)

            if let detail {
                Text(verbatim: detail)
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var status: some View {
        WorkbenchDiagnosticStatusLabel(
            text: endpoint.status.label(language: language),
            tint: endpoint.status.workbenchTint
        )
    }
}

struct WorkbenchDiagnosticsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    @State private var expandedPanels: Set<WorkbenchDiagnosticsPanel> = []

    var body: some View {
        let projection = diagnosticsProjection

        WorkbenchPageScaffold {
            commandBar(projection)
        } content: {
            diagnosticsContent(projection)
        }
    }

    @ViewBuilder
    private func diagnosticsContent(
        _ projection: WorkbenchDiagnosticsVisibleProjection
    ) -> some View {
        if appModel.selectedRouter == nil {
            WorkbenchStateView(
                kind: .noController,
                titleKey: "dashboard.connect_router",
                detailKey: "configuration.no_controller_detail"
            )
        } else if !hasDiagnosticsPresentation(projection) {
            switch appModel.controllerSessionPresentation.state {
            case .connecting, .staleReconnecting:
                WorkbenchStateView(
                    kind: .loading,
                    titleKey: "live.state_connecting",
                    detailKey: "workspace.diagnostics_subtitle"
                )
            case .failedBeforeFirstSnapshot(let message), .failed(let message), .partial(let message):
                WorkbenchStateView(
                    kind: .failed,
                    titleKey: "live.state_failed",
                    detailKey: "workspace.diagnostics_subtitle",
                    message: message
                )
            case .idle, .stopped:
                WorkbenchStateView(
                    kind: .empty,
                    titleKey: "diagnostics.none",
                    detailKey: "workspace.diagnostics_subtitle"
                )
            case .live:
                WorkbenchStateView(
                    kind: .empty,
                    titleKey: "diagnostics.none",
                    detailKey: "workspace.diagnostics_subtitle"
                )
            }
        } else {
            VStack(spacing: 0) {
                if let retainedFailureMessage {
                    WorkbenchStaleNotice(message: retainedFailureMessage)
                }

                WorkbenchManagementCanvas {
                    diagnosisSummarySection
                    diagnosticsDetailsSection(projection)
                }
            }
        }
    }

    private func hasDiagnosticsPresentation(
        _ projection: WorkbenchDiagnosticsVisibleProjection
    ) -> Bool {
        appModel.controllerHealth.checkedAt != nil
            || projection.hasRows
            || appModel.controllerMetadata.versionLabel.managementNonEmpty != nil
                && appModel.controllerMetadata.versionLabel != "-"
            || appModel.controllerMetadata.mode.managementNonEmpty != nil
                && appModel.controllerMetadata.mode.lowercased() != "unknown"
    }

    private var retainedFailureMessage: String? {
        switch appModel.controllerSessionPresentation.state {
        case .staleReconnecting(let message), .partial(let message), .failed(let message):
            message.managementNonEmpty
        default:
            nil
        }
    }

    private func commandBar(
        _ projection: WorkbenchDiagnosticsVisibleProjection
    ) -> some View {
        WorkbenchCommandBar {
            WorkbenchManagementHeader(
                systemImage: "stethoscope",
                titleKey: "diagnostics.title",
                detail: MicaStrings.localizedKey(
                    "workspace.diagnostics_subtitle",
                    language: language
                )
            )
        } controls: {
            HStack(spacing: MicaSpacing.row) {
                WorkbenchDiagnosticStatusLabel(
                    text: appModel.controllerHealth.summary.label(language: language),
                    tint: appModel.controllerHealth.summary.workbenchTint
                )
                WorkbenchDiagnosticStatusLabel(
                    text: appModel.coreCompatibilitySummary.label(language: language),
                    tint: compatibilityTint
                )
            }
        } commands: {
            HStack(spacing: 0) {
                WorkbenchIconCommand(
                    titleKey: "diagnostics.copy_targets",
                    systemImage: "list.clipboard",
                    isEnabled: !projection.endpointHealthRows.isEmpty
                ) {
                    appModel.copyEndpointResults()
                }
                WorkbenchIconCommand(
                    titleKey: "export.copy_check_results",
                    systemImage: "tablecells",
                    isEnabled: !projection.checkResultRows.isEmpty
                ) {
                    appModel.copyCheckResults()
                }
                WorkbenchIconCommand(
                    titleKey: "diagnostics.copy_report",
                    systemImage: "doc.on.doc",
                    isEnabled: !appModel.diagnosticsReportSections.isEmpty
                ) {
                    appModel.copyDiagnosticsReport()
                }
            }
        }
    }

    private var controllerDetailsSection: some View {
        WorkbenchDiagnosticsDisclosure(
            isExpanded: panelBinding(.controller),
            titleKey: "diagnostics.section_controller_health",
            systemImage: "server.rack",
            tint: summaryTint
        ) {
            if let router = appModel.selectedRouter {
                WorkbenchDiagnosticsMetadataGrid(
                    rows: [
                        [
                            WorkbenchDiagnosticsMetadataItem(
                                id: "controller",
                                titleKey: "diagnostics.active_controller",
                                value: router.displayName
                            ),
                            WorkbenchDiagnosticsMetadataItem(
                                id: "type",
                                titleKey: "settings.controller_type",
                                value: router.controllerKind.micaLabel(language: language)
                            ),
                        ],
                        [
                            WorkbenchDiagnosticsMetadataItem(
                                id: "endpoint",
                                titleKey: "settings.controller_endpoint",
                                value: router.endpointURL,
                                monospaced: true
                            ),
                        ],
                        [
                            WorkbenchDiagnosticsMetadataItem(
                                id: "health",
                                titleKey: "diagnostics.controller_health",
                                value: appModel.controllerHealth.summary.label(language: language),
                                statusTint: appModel.controllerHealth.summary.workbenchTint
                            ),
                            WorkbenchDiagnosticsMetadataItem(
                                id: "version",
                                titleKey: "diagnostics.version",
                                value: appModel.controllerMetadata.versionLabel,
                                monospaced: true,
                                placeholder: appModel.controllerMetadata.versionLabel == "-"
                            ),
                        ],
                        [
                            WorkbenchDiagnosticsMetadataItem(
                                id: "mode",
                                titleKey: "diagnostics.mode",
                                value: MicaStrings.displayMode(
                                    appModel.controllerMetadata.mode,
                                    language: language
                                )
                            ),
                            WorkbenchDiagnosticsMetadataItem(
                                id: "checked-at",
                                titleKey: "diagnostics.check_latest",
                                value: checkedAtLabel,
                                monospaced: true,
                                placeholder: appModel.controllerHealth.checkedAt == nil
                            ),
                        ],
                    ]
                )
            }
        }
    }

    private var diagnosisSummarySection: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.module) {
            summaryHeader
            summaryFacts
            WorkbenchDiagnosticsResponsiveLayout {
                HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.module) {
                    summaryNextStepLabel
                    Spacer(minLength: MicaSpacing.module)
                    summaryNextStepValue
                        .multilineTextAlignment(.trailing)
                }
            } compact: {
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    summaryNextStepLabel
                    summaryNextStepValue
                }
            }
        }
        .padding(.horizontal, MicaSpacing.tight)
        .padding(.vertical, MicaSpacing.row)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func diagnosticsDetailsSection(
        _ projection: WorkbenchDiagnosticsVisibleProjection
    ) -> some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            HStack(spacing: MicaSpacing.row) {
                WorkbenchSymbol(
                    systemName: "list.bullet.rectangle",
                    font: .callout.weight(.semibold),
                    frameSize: 18
                )

                Text(
                    MicaStrings.localizedKey(
                        "diagnostics.details_title",
                        language: language
                    )
                )
                .micaFont(.headline, weight: .semibold)
            }

            VStack(alignment: .leading, spacing: 0) {
                controllerDetailsSection
                if !projection.endpointHealthRows.isEmpty {
                    endpointResultsSection(projection.endpointHealthRows)
                }
                if !projection.endpointCheckSteps.isEmpty {
                    endpointWorkflowSection(projection.endpointCheckSteps)
                }
                if !projection.checkResultRows.isEmpty {
                    checkResultsSection(projection.checkResultRows)
                }
                if !projection.capabilityRows.isEmpty {
                    capabilitySection(projection.capabilityRows)
                }
                if !projection.coverageRows.isEmpty {
                    coverageSection(projection.coverageRows)
                }
                if !projection.observabilityRows.isEmpty {
                    observabilitySection(projection.observabilityRows)
                }
                exportSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func endpointResultsSection(
        _ rows: [ControllerEndpointHealth]
    ) -> some View {
        WorkbenchDiagnosticsDisclosure(
            isExpanded: panelBinding(.endpointResults),
            titleKey: "diagnostics.endpoint_results_title",
            systemImage: "point.3.connected.trianglepath.dotted",
            count: rows.count,
            tint: appModel.controllerHealth.summary.workbenchTint
        ) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, endpoint in
                if index > 0 { Divider() }
                WorkbenchEndpointHealthRow(endpoint: endpoint)
            }
        }
    }

    private func capabilitySection(_ rows: [CapabilityMatrixRow]) -> some View {
        WorkbenchDiagnosticsDisclosure(
            isExpanded: panelBinding(.capabilities),
            titleKey: "diagnostics.capability_matrix_title",
            systemImage: "checklist",
            count: rows.count
        ) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                WorkbenchDiagnosticMatrixRow(row: row)
            }
        }
    }

    private func endpointWorkflowSection(_ steps: [EndpointCheckStep]) -> some View {
        WorkbenchDiagnosticsDisclosure(
            isExpanded: panelBinding(.endpointWorkflow),
            titleKey: "diagnostics.endpoint_checks",
            systemImage: "checklist.checked",
            count: steps.count,
            tint: appModel.controllerHealth.summary.workbenchTint
        ) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                if index > 0 { Divider() }
                WorkbenchEndpointCheckStepRow(step: step) {
                    guard let action = step.primaryAction else { return }
                    appModel.performEndpointCheckAction(action)
                }
            }
        }
    }

    private func checkResultsSection(_ rows: [CheckResultRow]) -> some View {
        WorkbenchDiagnosticsDisclosure(
            isExpanded: panelBinding(.checkResults),
            titleKey: "diagnostics.check_results_title",
            systemImage: "tablecells",
            count: rows.count
        ) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                WorkbenchCheckResultDisclosure(row: row)
            }
        }
    }

    private func coverageSection(_ rows: [CapabilityMatrixRow]) -> some View {
        WorkbenchDiagnosticsDisclosure(
            isExpanded: panelBinding(.coverage),
            titleKey: "diagnostics.coverage_title",
            systemImage: "rectangle.3.group",
            count: rows.count
        ) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                WorkbenchDiagnosticMatrixRow(row: row)
            }
        }
    }

    private func observabilitySection(
        _ rows: [ObservabilityReadinessRow]
    ) -> some View {
        WorkbenchDiagnosticsDisclosure(
            isExpanded: panelBinding(.observability),
            titleKey: "diagnostics.section_observability",
            systemImage: "waveform.path.ecg",
            count: rows.count
        ) {
            ForEach(
                Array(rows.enumerated()),
                id: \.element.id
            ) { index, row in
                if index > 0 { Divider() }
                WorkbenchObservabilityDisclosure(row: row)
            }
        }
    }

    private var exportSection: some View {
        WorkbenchDiagnosticsDisclosure(
            isExpanded: panelBinding(.exportPolicy),
            titleKey: "diagnostics.export_reports",
            systemImage: "square.and.arrow.up",
            showsBottomDivider: false
        ) {
            WorkbenchFormRow("diagnostics.report_scope") {
                WorkbenchFormValue(
                    value: MicaStrings.localizedKey("settings.privacy_full_ui", language: language)
                )
            }
            Divider()
            WorkbenchFormRow("diagnostics.report_excludes_credentials") {
                WorkbenchFormValue(
                    value: MicaStrings.localizedKey(
                        "settings.privacy_report_exports",
                        language: language
                    )
                )
            }
            Divider()
            WorkbenchFormRow("diagnostics.controller_health") {
                WorkbenchFormValue(
                    value: MicaStrings.localizedKey(
                        "settings.privacy_health_export",
                        language: language
                    )
                )
            }
        }
    }

    private var summaryHeader: some View {
        WorkbenchDiagnosticsResponsiveLayout {
            HStack(alignment: .top, spacing: MicaSpacing.module) {
                summaryIdentity
                Spacer(minLength: MicaSpacing.module)
                summaryRouterIdentity
            }
        } compact: {
            VStack(alignment: .leading, spacing: MicaSpacing.module) {
                summaryIdentity
                summaryRouterIdentity
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryIdentity: some View {
        HStack(alignment: .top, spacing: MicaSpacing.module) {
            summaryIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    MicaStrings.localizedKey(
                        "diagnostics.summary_title",
                        language: language
                    )
                )
                .micaFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)

                Text(appModel.controllerHealth.summary.label(language: language))
                    .micaFont(.title3, weight: .semibold)

                Text(MicaStrings.localizedKey(summaryDetailKey, language: language))
                    .micaFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var summaryIndicator: some View {
        if appModel.controllerHealth.summary == .checking {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        } else {
            WorkbenchSymbol(
                systemName: summarySystemImage,
                tint: summaryTint,
                font: .title2.weight(.semibold),
                frameSize: 28
            )
        }
    }

    @ViewBuilder
    private var summaryRouterIdentity: some View {
        if let router = appModel.selectedRouter {
            Label {
                Text(verbatim: router.displayName)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "server.rack")
                    .foregroundStyle(summaryTint)
            }
            .micaFont(.caption, weight: .medium)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
    }

    private var summaryFacts: some View {
        WorkbenchDiagnosticsResponsiveLayout {
            HStack(alignment: .top, spacing: 0) {
                connectionSummaryFact
                    .padding(.trailing, MicaSpacing.module)
                Divider()
                compatibilitySummaryFact
                    .padding(.horizontal, MicaSpacing.module)
                Divider()
                checkedAtSummaryFact
                    .padding(.leading, MicaSpacing.module)
            }
        } compact: {
            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                connectionSummaryFact
                Divider()
                compatibilitySummaryFact
                Divider()
                checkedAtSummaryFact
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionSummaryFact: some View {
        WorkbenchDiagnosticsSummaryFact(
            titleKey: "diagnostics.summary_connection",
            value: appModel.connectionState.label(language: language),
            systemImage: "network",
            tint: summaryTint
        )
    }

    private var compatibilitySummaryFact: some View {
        WorkbenchDiagnosticsSummaryFact(
            titleKey: "diagnostics.summary_compatibility",
            value: appModel.coreCompatibilitySummary.label(language: language),
            systemImage: "cpu",
            tint: compatibilityTint
        )
    }

    private var checkedAtSummaryFact: some View {
        WorkbenchDiagnosticsSummaryFact(
            titleKey: "diagnostics.check_latest",
            value: checkedAtLabel,
            systemImage: "clock",
            tint: .secondary
        )
    }

    private var summaryNextStepLabel: some View {
        Label {
            Text(
                MicaStrings.localizedKey(
                    "diagnostics.summary_next_step",
                    language: language
                )
            )
        } icon: {
            Image(systemName: "arrow.forward.circle")
                .foregroundStyle(summaryTint)
        }
        .micaFont(.callout, weight: .semibold)
    }

    private var summaryNextStepValue: some View {
        Text(MicaStrings.localizedKey(summaryNextStepKey, language: language))
            .micaFont(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var diagnosticsProjection: WorkbenchDiagnosticsVisibleProjection {
        let endpointRows = appModel.controllerHealth.endpoints.filter {
            appModel.capabilityStatus(for: $0.endpoint) != .unavailable
        }
        return WorkbenchDiagnosticsVisibility.projection(
            endpointHealthRows: endpointRows,
            capabilityRows: appModel.capabilityMatrixRows,
            coverageRows: appModel.controllerDataCoverageRows,
            observabilityRows: appModel.observabilityReadinessRows,
            endpointCheckSteps: appModel.endpointCheckSteps,
            checkResultRows: appModel.checkResultRows,
            support: diagnosticsSupport
        )
    }

    private var diagnosticsSupport: WorkbenchDiagnosticsSupport {
        WorkbenchDiagnosticsSupport(
            enhancedSnapshot: supportsEnhancedSnapshot,
            providerUpdate: appModel.supportsUnifiedAction(.updateProvider),
            delayTest: appModel.supportsUnifiedAction(.testLatency),
            connectionClose: appModel.supportsUnifiedAction(.closeConnection)
                || appModel.supportsUnifiedAction(.closeAllConnections)
                || appModel.supportsUnifiedAction(.killActiveRequest)
        )
    }

    private var supportsEnhancedSnapshot: Bool {
        if isSurgeController {
            return true
        }
        return appModel.capabilityStatus(for: .rules) != .unavailable
            || appModel.capabilityStatus(for: .providers) != .unavailable
    }

    private var isSurgeController: Bool {
        guard let router = appModel.selectedRouter else { return false }
        return appModel.runtimeControllerKind(for: router) == .surgeCompatible
    }

    private func panelBinding(_ panel: WorkbenchDiagnosticsPanel) -> Binding<Bool> {
        Binding(
            get: { expandedPanels.contains(panel) },
            set: { isExpanded in
                if isExpanded {
                    expandedPanels.insert(panel)
                } else {
                    expandedPanels.remove(panel)
                }
            }
        )
    }

    private var checkedAtLabel: String {
        guard let checkedAt = workbenchDisplayableDate(appModel.controllerHealth.checkedAt) else {
            return MicaStrings.localizedKey("diagnostics.never", language: language)
        }
        return checkedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .standard)
                .locale(language.resolvedLocale)
        )
    }

    private var compatibilityTint: Color {
        switch appModel.coreCompatibilitySummary {
        case .mihomoCompatible, .smartCompatible:
            MicaDesignTokens.signalMint
        case .partialCompatible, .unknownController:
            MicaDesignTokens.signalAmber
        case .unsupported:
            MicaDesignTokens.signalRed
        }
    }

    private var summaryTint: Color {
        appModel.controllerHealth.summary.workbenchTint
    }

    private var summarySystemImage: String {
        switch appModel.controllerHealth.summary {
        case .unknown:
            "questionmark.circle"
        case .checking:
            "arrow.clockwise"
        case .ready:
            "checkmark.circle"
        case .partial:
            "exclamationmark.circle"
        case .authFailed:
            "key.slash"
        case .wrongTarget:
            "point.3.connected.trianglepath.dotted"
        case .offline:
            "network.slash"
        }
    }

    private var summaryDetailKey: String {
        switch appModel.controllerHealth.summary {
        case .unknown:
            "diagnostics.summary_detail_unknown"
        case .checking:
            "diagnostics.summary_detail_checking"
        case .ready:
            "diagnostics.summary_detail_ready"
        case .partial:
            "diagnostics.summary_detail_partial"
        case .authFailed:
            "failure.auth_failed_headline"
        case .wrongTarget:
            "failure.wrong_target_headline"
        case .offline:
            "failure.network_failed_headline"
        }
    }

    private var summaryNextStepKey: String {
        switch appModel.controllerHealth.summary {
        case .unknown:
            "diagnostics.summary_next_unknown"
        case .checking:
            "diagnostics.summary_next_checking"
        case .ready:
            "diagnostics.summary_next_ready"
        case .partial:
            "diagnostics.summary_next_partial"
        case .authFailed:
            "failure.auth_failed_message"
        case .wrongTarget:
            "failure.wrong_target_message"
        case .offline:
            "failure.network_failed_message"
        }
    }
}

private struct WorkbenchCheckResultDisclosure: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    @State private var isExpanded = false

    let row: CheckResultRow

    var body: some View {
        WorkbenchAnimatedDisclosure(isExpanded: $isExpanded) {
            Group {
                switch widthMode {
                case .regular:
                    HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.module) {
                        title
                        Spacer(minLength: MicaSpacing.row)
                        status
                    }
                case .compact:
                    VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                        title
                        status
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } content: {
            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                    if index > 0 { Divider() }
                    WorkbenchFormRow(field.titleKey) {
                        WorkbenchFormValue(
                            value: field.value,
                            monospaced: field.monospaced
                        )
                    }
                }
            }
            .padding(.top, MicaSpacing.row)
        }
    }

    private var fields: [WorkbenchDiagnosticsField] {
        WorkbenchDiagnosticsProjection.fields(for: row)
    }

    private var title: some View {
        Text(verbatim: row.title)
            .micaFont(.callout, weight: .medium)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var status: some View {
        WorkbenchDiagnosticStatusLabel(
            text: row.state.label(language: language),
            tint: row.state.workbenchTint
        )
    }
}

private struct WorkbenchObservabilityDisclosure: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    @State private var isExpanded = false

    let row: ObservabilityReadinessRow

    var body: some View {
        WorkbenchAnimatedDisclosure(isExpanded: $isExpanded) {
            Group {
                switch widthMode {
                case .regular:
                    HStack(alignment: .top, spacing: MicaSpacing.module) {
                        title
                        Spacer(minLength: MicaSpacing.row)
                        status
                    }
                case .compact:
                    VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                        title
                        status
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } content: {
            Text(verbatim: row.detail)
                .micaFont(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            .padding(.top, MicaSpacing.row)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: row.title)
                .micaFont(.callout, weight: .medium)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: row.category)
                .micaFont(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var status: some View {
        WorkbenchDiagnosticStatusLabel(
            text: row.state.label(language: language),
            tint: row.state.workbenchTint
        )
    }
}

private struct WorkbenchEndpointCheckStepRow: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let step: EndpointCheckStep
    let performPrimaryAction: () -> Void

    var body: some View {
        Group {
            switch widthMode {
            case .regular:
                HStack(alignment: .top, spacing: MicaSpacing.module) {
                    content
                    Spacer(minLength: MicaSpacing.module)
                    controls
                }
            case .compact:
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    controls
                    content
                }
            }
        }
        .padding(.vertical, MicaSpacing.tight)
        .frame(maxWidth: .infinity, minHeight: MicaBounds.controlMinHeight, alignment: .leading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.tight) {
            Text(verbatim: step.title)
                .micaFont(.callout, weight: .semibold)
                .textSelection(.enabled)
            Text(verbatim: step.detail)
                .micaFont(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Label {
                Text(verbatim: step.nextAction)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.forward.circle")
                    .foregroundStyle(MicaDesignTokens.signalCyan)
            }
            .micaFont(.caption, weight: .medium)
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: MicaSpacing.row) {
            WorkbenchDiagnosticStatusLabel(
                text: step.state.label(language: language),
                tint: step.state.workbenchTint
            )
            if let action = step.primaryAction {
                Button(action: performPrimaryAction) {
                    Label(
                        action.title(language: language),
                        systemImage: action.systemImage
                    )
                }
                .buttonStyle(.borderless)
                .disabled(step.state == .running)
                .frame(minHeight: MicaBounds.controlMinHeight)
            }
        }
    }
}

private struct WorkbenchDiagnosticMatrixRow: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let row: CapabilityMatrixRow

    var body: some View {
        Group {
            switch widthMode {
            case .regular:
                HStack(alignment: .top, spacing: MicaSpacing.module) {
                    content
                    Spacer(minLength: MicaSpacing.module)
                    status
                }
            case .compact:
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    status
                    content
                }
            }
        }
        .padding(.vertical, MicaSpacing.tight)
        .frame(maxWidth: .infinity, minHeight: MicaBounds.controlMinHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.tight) {
            Text(verbatim: row.title)
                .micaFont(.callout, weight: .semibold)
                .textSelection(.enabled)

            Text(verbatim: row.operationImpact)
                .micaFont(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private var status: some View {
        WorkbenchDiagnosticStatusLabel(
            text: row.status.label(language: language),
            tint: row.status.workbenchTint
        )
    }
}

private extension ControllerHealthSummary {
    var workbenchTint: Color {
        switch self {
        case .ready: MicaDesignTokens.signalMint
        case .checking: MicaDesignTokens.signalCyan
        case .partial, .unknown: MicaDesignTokens.signalAmber
        case .authFailed, .wrongTarget, .offline: MicaDesignTokens.signalRed
        }
    }

    var workbenchSymbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .partial: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        case .authFailed, .wrongTarget, .offline: "xmark.octagon.fill"
        }
    }
}

private extension ConnectionCheckState {
    var workbenchTint: Color {
        switch self {
        case .ready: MicaDesignTokens.signalMint
        case .warning: MicaDesignTokens.signalAmber
        case .failed: MicaDesignTokens.signalRed
        }
    }

    var workbenchSymbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle"
        case .failed: "xmark.octagon"
        }
    }
}

private extension ControllerEndpointStatus {
    var workbenchTint: Color {
        switch self {
        case .ready: MicaDesignTokens.signalMint
        case .checking: MicaDesignTokens.signalCyan
        case .failed: MicaDesignTokens.signalRed
        case .idle: .secondary
        }
    }
}

private extension EndpointCheckState {
    var workbenchTint: Color {
        switch self {
        case .passed: MicaDesignTokens.signalMint
        case .ready, .running: MicaDesignTokens.signalCyan
        case .partial: MicaDesignTokens.signalAmber
        case .failed: MicaDesignTokens.signalRed
        case .skipped: .secondary
        }
    }
}

private extension CheckResultState {
    var workbenchTint: Color {
        switch self {
        case .ready: MicaDesignTokens.signalMint
        case .partial, .attention: MicaDesignTokens.signalAmber
        case .notChecked: .secondary
        }
    }
}

private extension ObservabilityReadinessState {
    var workbenchTint: Color {
        switch self {
        case .ready: MicaDesignTokens.signalMint
        case .partial, .notImplementedInUI, .controllerCapabilityUnknown:
            MicaDesignTokens.signalAmber
        case .futureOptionalStream, .unavailable:
            .secondary
        }
    }
}
