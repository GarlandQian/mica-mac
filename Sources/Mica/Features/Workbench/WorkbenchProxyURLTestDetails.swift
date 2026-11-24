import SwiftUI

/// A controller-reported health check, grouped by its literal URL. History
/// keeps each timestamp with the measurements from that same sample.
struct ProxyURLTestDetails: View {
    @Environment(\.micaAppLanguage) private var language
    @State private var showsHistory = false
    @State private var showsAdditionalFields = false

    let result: ProxyURLTestResult

    init(result: ProxyURLTestResult, initiallyShowsHistory: Bool = false) {
        self.result = result
        _showsHistory = State(initialValue: initiallyShowsHistory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space2) {
                Text(verbatim: result.url)
                    .micaThemeFont(.caption, weight: .medium)
                    .foregroundStyle(MicaTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(result.url)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let alive = result.alive {
                    Label(
                        MicaStrings.localizedKey(
                            alive ? "routing.node_alive" : "routing.node_unavailable",
                            language: language
                        ),
                        systemImage: alive ? "checkmark.circle" : "xmark.circle"
                    )
                    .micaThemeFont(.caption)
                    .foregroundStyle(alive ? MicaTheme.statusOK : MicaTheme.statusError)
                    .fixedSize()
                }
            }

            if let latest = result.history.last {
                ProxyURLTestSampleRow(sample: latest)
            }

            let priorSamples = Array(result.history.dropLast().reversed().prefix(12))
            if !priorSamples.isEmpty {
                DisclosureGroup(isExpanded: $showsHistory) {
                    if showsHistory {
                        VStack(spacing: MicaTheme.Spacing.space2) {
                            ForEach(priorSamples) { sample in
                                ProxyURLTestSampleRow(sample: sample)
                            }
                        }
                        .padding(.top, MicaTheme.Spacing.space1)
                    }
                } label: {
                    HStack(spacing: MicaTheme.Spacing.space1) {
                        Text(MicaStrings.localizedKey("routing.delay_history", language: language))
                        Text(verbatim: "· \(result.history.count)")
                            .monospacedDigit()
                    }
                }
                .micaThemeFont(.caption)
                .foregroundStyle(MicaTheme.textSecondary)
            }

            if !result.additionalFields.isEmpty {
                DisclosureGroup(isExpanded: $showsAdditionalFields) {
                    if showsAdditionalFields {
                        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                            ForEach(result.additionalFields) { field in
                                WorkbenchPolicyInspectionFieldRow(field: field)
                            }
                        }
                        .padding(.top, MicaTheme.Spacing.space1)
                    }
                } label: {
                    Text(MicaStrings.localizedKey("routing.node_section_reported_fields", language: language))
                }
                .micaThemeFont(.caption)
                .foregroundStyle(MicaTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proxy-url-test-details:\(result.id)")
    }
}

private struct ProxyURLTestSampleRow: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.locale) private var locale

    let sample: ProxyURLTestSample

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space2) {
                if let time = sample.time {
                    Text(verbatim: ProxyNodeTimeFormat.display(time: time, locale: locale, compact: true) ?? time)
                        .micaThemeFont(.caption)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .help(time)
                }
                Spacer(minLength: 0)
                if let delay = sample.delay {
                    latency(delay)
                }
            }

            if let meanDelay = sample.meanDelay {
                HStack(alignment: .firstTextBaseline) {
                    Text(MicaStrings.localizedKey("routing.test_mean_delay", language: language))
                        .micaThemeFont(.caption)
                        .foregroundStyle(MicaTheme.textSecondary)
                    Spacer(minLength: 0)
                    latency(meanDelay)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func latency(_ delay: Int) -> some View {
        let formatted = delay > 0
            ? OverviewFormat.latency(delay)
            : MicaStrings.localizedKey("latency.timeout", language: language)
        return Text(verbatim: formatted)
            .micaThemeFont(.dataCaption, weight: .medium)
            .foregroundStyle(delay > 0 ? OverviewFormat.latencyTint(delay) : MicaTheme.statusError)
            .fixedSize()
            .help(formatted)
    }
}
