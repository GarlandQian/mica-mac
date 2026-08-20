import SwiftUI

private enum MicaSettingsMetrics {
    static let readingWidth: CGFloat = 820
    static let controlColumnWidth: CGFloat = 196
}

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
            HStack(spacing: MicaTheme.Spacing.space2) {
                Image(systemName: optionSystemImage(selection))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(MicaTheme.accent)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                Text(verbatim: localized(optionTitleKey(selection)))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: MicaTheme.Spacing.space1)

                Image(systemName: "chevron.down")
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .micaThemeFont(.label)
            .frame(width: MicaSettingsMetrics.controlColumnWidth, alignment: .leading)
            .frame(minHeight: MicaTheme.Metrics.controlMinHeight, alignment: .leading)
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
                HStack(alignment: .center, spacing: MicaTheme.Spacing.space5) {
                    explanation
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    control
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(alignment: .trailing)
                }
            case .compact:
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                    explanation
                    control
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.vertical, MicaTheme.Spacing.space1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localized(titleKey))
                .micaThemeFont(.label, weight: .medium)

            Text(localized(detailKey))
                .micaThemeFont(.caption)
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
            .background(MicaTheme.canvas)
            .navigationTitle(
                MicaStrings.localizedKey("workbench.settings", language: language)
            )
    }
}

private struct WorkbenchPreferenceForm: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    var body: some View {
        GeometryReader { geometry in
            let horizontalMargin = MicaTheme.Metrics.pagePadding(for: geometry.size.width)
            let availableContentWidth = max(
                0,
                min(
                    geometry.size.width,
                    MicaSettingsMetrics.readingWidth
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
                sectionHeader(
                    "settings.appearance_section",
                    systemImage: "paintpalette"
                )
            }

            Section {
                routingRows
            } header: {
                sectionHeader(
                    "settings.routing_section",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
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
        .contentMargins(.vertical, MicaTheme.Spacing.space4, for: .scrollContent)
        .frame(
            maxWidth: MicaSettingsMetrics.readingWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func sectionHeader(_ titleKey: String, systemImage: String) -> some View {
        Label {
            Text(localized(titleKey))
                .micaThemeFont(.body, weight: .semibold)
        } icon: {
            WorkbenchSymbol(
                systemName: systemImage,
                tint: MicaTheme.textSecondary,
                size: .inline
            )
        }
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
