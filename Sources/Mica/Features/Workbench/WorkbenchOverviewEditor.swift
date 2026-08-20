import SwiftUI

struct OverviewPreferencesToolbarControl: View {
    @Environment(OverviewWindowRuntime.self) private var runtime
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        Button {
            runtime.togglePreferences()
        } label: {
            Label(
                MicaStrings.localizedKey(
                    "overview.preferences_title",
                    language: language
                ),
                systemImage: "slider.horizontal.3"
            )
        }
        .help(
            MicaStrings.localizedKey(
                "overview.preferences_help",
                language: language
            )
        )
        .accessibilityAddTraits(runtime.showsPreferences ? .isSelected : [])
    }
}

struct OverviewPreferencesBar: View {
    @Environment(OverviewPreferencesStore.self) private var store
    @Environment(OverviewWindowRuntime.self) private var runtime
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        if runtime.showsPreferences {
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                ViewThatFits(in: .horizontal) {
                    regularLayout
                    compactLayout
                }
            }
            .padding(.horizontal, MicaTheme.Spacing.space3)
            .padding(.vertical, MicaTheme.Spacing.space2)
            .background(MicaTheme.canvas)
            .overlay(alignment: .bottom) { MicaHairlineSeparator() }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var regularLayout: some View {
        HStack(alignment: .center, spacing: MicaTheme.Spacing.space4) {
            preferencesLabel
            metricControls
            MicaHairlineSeparator(axis: .vertical).frame(height: 26)
            timelinePicker
            MicaHairlineSeparator(axis: .vertical).frame(height: 26)
            optionalModuleControls
            Spacer(minLength: MicaTheme.Spacing.space2)
            resetButton
            closeButton
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            HStack(spacing: MicaTheme.Spacing.space2) {
                preferencesLabel
                Spacer(minLength: MicaTheme.Spacing.space2)
                resetButton
                closeButton
            }
            ScrollView(.horizontal) {
                HStack(spacing: MicaTheme.Spacing.space4) {
                    metricControls
                    MicaHairlineSeparator(axis: .vertical).frame(height: 26)
                    timelinePicker
                    MicaHairlineSeparator(axis: .vertical).frame(height: 26)
                    optionalModuleControls
                }
            }
            .scrollIndicators(.visible)
        }
    }

    private var preferencesLabel: some View {
        Label(
            MicaStrings.localizedKey(
                "overview.preferences_title",
                language: language
            ),
            systemImage: "slider.horizontal.3"
        )
        .micaThemeFont(.label, weight: .semibold)
        .fixedSize()
    }

    private var metricControls: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            Text(
                MicaStrings.localizedKey(
                    "overview.preferences_metrics",
                    language: language
                )
            )
            .micaThemeFont(.caption, weight: .semibold)
            .foregroundStyle(MicaTheme.textSecondary)

            ForEach(OverviewMetricID.allCases) { metric in
                Toggle(
                    MicaStrings.localizedKey(metric.titleKey, language: language),
                    isOn: Binding(
                        get: { store.isMetricVisible(metric) },
                        set: { store.setMetric(metric, isVisible: $0) }
                    )
                )
                .toggleStyle(.checkbox)
                .disabled(
                    store.isMetricVisible(metric)
                        && store.preferences.visibleMetrics.count == 1
                )
                .fixedSize()
            }
        }
    }

    private var timelinePicker: some View {
        Picker(
            MicaStrings.localizedKey(
                "overview.timeline_window",
                language: language
            ),
            selection: Binding(
                get: { store.preferences.timelineWindow },
                set: { window in
                    store.setTimelineWindow(window)
                }
            )
        ) {
            ForEach(OverviewTimelineWindow.allCases) { window in
                Text(MicaStrings.localizedKey(window.titleKey, language: language))
                    .tag(window)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var optionalModuleControls: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            Text(
                MicaStrings.localizedKey(
                    "overview.preferences_optional",
                    language: language
                )
            )
            .micaThemeFont(.caption, weight: .semibold)
            .foregroundStyle(MicaTheme.textSecondary)

            ForEach(OverviewOptionalModuleID.allCases) { module in
                Toggle(
                    MicaStrings.localizedKey(module.titleKey, language: language),
                    isOn: Binding(
                        get: { store.isOptionalModuleVisible(module) },
                        set: { store.setOptionalModule(module, isVisible: $0) }
                    )
                )
                .toggleStyle(.checkbox)
                .fixedSize()
            }
        }
    }

    private var resetButton: some View {
        Button {
            store.reset()
        } label: {
            Label(
                MicaStrings.localizedKey(
                    "overview.preferences_reset",
                    language: language
                ),
                systemImage: "arrow.counterclockwise"
            )
        }
        .disabled(store.preferences == .default)
    }

    private var closeButton: some View {
        WorkbenchIconCommand(
            titleKey: "overview.preferences_close",
            systemImage: MicaSymbols.Command.close
        ) {
            runtime.showsPreferences = false
        }
    }
}

extension OverviewMetricID {
    var titleKey: String {
        switch self {
        case .upload: "overview.upload_rate"
        case .download: "overview.download_rate"
        case .activeConnections: "dashboard.active_sessions"
        }
    }
}

extension OverviewOptionalModuleID {
    var titleKey: String {
        switch self {
        case .instrumentRail: "overview.instrument_rail"
        case .operationalSummaries: "overview.operational_summary"
        case .networkInformation: "overview.network_information"
        }
    }
}
