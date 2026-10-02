import Foundation
import Testing
@testable import Mica

@MainActor
struct WorkbenchProxyNodeDetailCompositionTests {
    private func field(
        _ id: String,
        _ value: String = "value",
        booleanValue: Bool? = nil
    ) -> OverviewPolicyInspectionField {
        OverviewPolicyInspectionField(
            id: id,
            label: .verbatim(id),
            value: value,
            booleanValue: booleanValue
        )
    }

    private func snapshot(_ sections: [OverviewPolicyInspectionSection]) -> OverviewPolicyInspectionSnapshot {
        OverviewPolicyInspectionSnapshot(kind: .policyMember, title: "Node", subtitle: nil, sections: sections)
    }

    @Test
    func compositionShowsEveryFieldExactlyOnceInPresentationOrder() {
        let source = snapshot([
            OverviewPolicyInspectionSection(id: "overview", titleKey: "routing.node_section_overview", fields: [
                field("availability"), field("latency"), field("type"), field("provider"),
                field("interface"), field("metadata.id"),
            ]),
            OverviewPolicyInspectionSection(id: "protocol", titleKey: "routing.node_section_protocol", fields: [
                field("metadata.server"), field("metadata.port"),
            ]),
            OverviewPolicyInspectionSection(id: "transport", titleKey: "routing.node_section_transport", fields: [
                field("transport.udp", "Enabled", booleanValue: true),
                field("transport.tfo", "Disabled", booleanValue: false),
            ]),
            OverviewPolicyInspectionSection(id: "testing", titleKey: "routing.node_section_testing", fields: [
                field("test-delay"), field("test-time"),
            ]),
            OverviewPolicyInspectionSection(id: "reported-fields", titleKey: "routing.node_section_reported_fields", fields: [
                field("metadata.vendor"),
            ]),
        ])

        let composition = ProxyNodeDetailComposition(snapshot: source)

        #expect(composition.summary.map(\.id) == ["availability", "latency", "type", "provider"])
        #expect(composition.capabilities.map(\.id) == ["transport.udp", "transport.tfo"])
        #expect(composition.sections.map(\.id) == ["protocol", "overview", "testing", "reported-fields"])
        #expect(composition.sections.first { $0.id == "overview" }?.fields.map(\.id) == ["interface", "metadata.id"])

        let presented = composition.summary.map(\.id)
            + composition.capabilities.map(\.id)
            + composition.sections.flatMap { $0.fields.map(\.id) }
        #expect(presented.count == Set(presented).count, "No field may render twice.")
        #expect(Set(presented) == Set(source.fields.map(\.id)), "Every projected field must render.")
    }

    @Test
    func runtimeOnlyNodeDoesNotGainAProtocolSection() {
        let composition = ProxyNodeDetailComposition(snapshot: snapshot([
            OverviewPolicyInspectionSection(id: "overview", titleKey: "routing.node_section_overview", fields: [
                field("availability"), field("metadata.id"),
            ]),
        ]))

        #expect(composition.sections.map(\.id) == ["overview"])
        #expect(!composition.isEmpty)
        #expect(ProxyNodeDetailComposition(snapshot: snapshot([])).isEmpty)
    }

    @Test
    func transportFieldWithoutReportedBooleanStaysARow() {
        let composition = ProxyNodeDetailComposition(snapshot: snapshot([
            OverviewPolicyInspectionSection(id: "transport", titleKey: "routing.node_section_transport", fields: [
                field("transport.custom", "reported"),
            ]),
        ]))

        #expect(composition.capabilities.isEmpty)
        #expect(composition.sections.first?.fields.map(\.id) == ["transport.custom"])
    }

    @Test(arguments: [
        "2026-05-29T04:26:40Z",
        "2026-05-29T12:26:40+08:00",
        "2026-05-29T12:26:40.123+08:00",
        "2026-05-29T12:26:40.123456789+08:00",
    ])
    func reportedTestTimesParseToTheSameInstant(raw: String) throws {
        let date = try #require(ProxyNodeTimeFormat.date(from: raw))
        #expect(abs(date.timeIntervalSince1970 - 1_780_028_800) < 1)
    }

    @Test
    func onlyParseableTestTimesAreReformatted() {
        let locale = Locale(identifier: "en_US")
        #expect(ProxyNodeTimeFormat.display(field: field("test-time", "not a time"), locale: locale) == nil)
        #expect(ProxyNodeTimeFormat.display(field: field("metadata.time", "2026-05-29T04:26:40Z"), locale: locale) == nil)
        #expect(ProxyNodeTimeFormat.display(field: field("test-time", "2026-05-29T04:26:40Z"), locale: locale) != nil)
    }
}
