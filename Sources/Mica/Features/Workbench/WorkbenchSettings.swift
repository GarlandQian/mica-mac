import SwiftUI

private enum MicaSettingsMetrics {
    static let readingWidth: CGFloat = 760
    static let controlColumnWidth: CGFloat = 204
    static let compactBreakpoint: CGFloat = 480
}

private struct WorkbenchPreferenceMenu<Option: Hashable & Identifiable>: View {
    @Environment(\.micaAppLanguage) private var language
    @State private var isHovered = false

    let labelKey: String
    @Binding var selection: Option
    let options: [Option]
    let optionTitleKey: (Option) -> String
    let optionSystemImage: (Option) -> String

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
    }

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
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(verbatim: localized(optionTitleKey(selection)))
                    .foregroundStyle(MicaTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: MicaTheme.Spacing.space1)

                Image(systemName: "chevron.down")
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(MicaTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            .micaThemeFont(.label)
            .padding(.horizontal, 10)
            .frame(width: MicaSettingsMetrics.controlColumnWidth, alignment: .leading)
            .frame(minHeight: MicaTheme.Metrics.controlMinHeight, alignment: .leading)
            .background(isHovered ? MicaTheme.surfaceHover : MicaTheme.surface, in: shape)
            .overlay {
                shape.strokeBorder(
                    isHovered ? MicaTheme.surfaceBorderStrong : MicaTheme.surfaceBorder,
                    lineWidth: 1
                )
            }
            .contentShape(shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { isHovered = $0 }
        .micaStateChangeAnimation(MicaTheme.Motion.press, value: isHovered)
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
                    availableContentWidth < MicaSettingsMetrics.compactBreakpoint
                        ? .compact
                        : .regular
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
        .micaObserveScrollPerformance()
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
        nativePreferenceRow(
            "settings.menu_bar_extra",
            detailKey: "settings.help_menu_bar_extra"
        ) {
            Toggle(isOn: $preferences.showsMenuBarExtra) {
                Text(localized("settings.menu_bar_extra"))
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .help(localized("settings.help_menu_bar_extra"))
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
            selection: $preferences.language,
            options: AppLanguage.allCases,
            optionTitleKey: \.titleKey,
            optionSystemImage: languageSystemImage
        )
        .help(localized("settings.help_language"))
    }

    /// Appearance and text size preview their result, as System Settings
    /// does, instead of naming it in a menu.
    private var appearancePicker: some View {
        WorkbenchPreferenceTiles(
            labelKey: "settings.appearance",
            selection: $preferences.appearance,
            options: AppAppearance.allCases,
            optionTitleKey: \.titleKey
        ) { option in
            WorkbenchAppearancePreview(appearance: option)
        }
        .help(localized("settings.help_appearance"))
    }

    private var fontScalePicker: some View {
        WorkbenchPreferenceTiles(
            labelKey: "settings.font_scale",
            selection: $preferences.fontScale,
            options: AppFontScale.allCases,
            optionTitleKey: \.titleKey
        ) { option in
            Text(verbatim: "Aa")
                .font(MicaTheme.font(for: .title3, scale: option, weight: .medium))
                .foregroundStyle(MicaTheme.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MicaTheme.surface)
        }
        .help(localized("settings.help_font_scale"))
    }

    private var globalGroupVisibilityPicker: some View {
        WorkbenchPreferenceMenu(
            labelKey: "settings.global_group_visibility",
            selection: $preferences.globalGroupVisibility,
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

    private func localized(_ key: String) -> String {
        MicaStrings.localizedKey(key, language: preferences.language)
    }
}

/// A row of labeled preview tiles for a small, visual choice. The selected
/// tile carries an accent ring and the native selected trait.
private struct WorkbenchPreferenceTiles<Option: Hashable & Identifiable, Preview: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let labelKey: String
    @Binding var selection: Option
    let options: [Option]
    let optionTitleKey: (Option) -> String
    @ViewBuilder let preview: (Option) -> Preview

    var body: some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space3) {
            ForEach(options) { option in
                let isSelected = option == selection
                let title = MicaStrings.localizedKey(optionTitleKey(option), language: language)
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

                Button {
                    selection = option
                } label: {
                    VStack(spacing: MicaTheme.Spacing.space1 + 2) {
                        preview(option)
                            .frame(width: 68, height: 44)
                            .clipShape(shape)
                            .overlay {
                                shape.strokeBorder(
                                    isSelected ? MicaTheme.accent : MicaTheme.surfaceBorderStrong,
                                    lineWidth: isSelected ? 2 : 1
                                )
                            }
                        Text(verbatim: title)
                            .micaThemeFont(.caption, weight: isSelected ? .semibold : .regular)
                            .foregroundStyle(isSelected ? MicaTheme.textPrimary : MicaTheme.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MicaStrings.localizedKey(labelKey, language: language))
    }
}

/// A miniature window in the appearance it represents; Follow System shows
/// both halves.
private struct WorkbenchAppearancePreview: View {
    let appearance: AppAppearance

    var body: some View {
        switch appearance {
        case .light:
            miniature(dark: false)
        case .dark:
            miniature(dark: true)
        case .system:
            miniature(dark: false)
                .overlay {
                    miniature(dark: true)
                        .mask(alignment: .trailing) {
                            GeometryReader { proxy in
                                Rectangle().frame(width: proxy.size.width / 2)
                            }
                        }
                }
        }
    }

    private func miniature(dark: Bool) -> some View {
        let window = dark ? MicaTheme.AppearancePreview.darkWindow : MicaTheme.AppearancePreview.lightWindow
        let sidebar = dark ? MicaTheme.AppearancePreview.darkSidebar : MicaTheme.AppearancePreview.lightSidebar
        let line = dark ? MicaTheme.AppearancePreview.darkLine : MicaTheme.AppearancePreview.lightLine

        return HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(sidebar)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(MicaTheme.accent).frame(width: 18, height: 3)
                Capsule().fill(line).frame(width: 30, height: 3)
                Capsule().fill(line).frame(width: 22, height: 3)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(window)
    }
}
