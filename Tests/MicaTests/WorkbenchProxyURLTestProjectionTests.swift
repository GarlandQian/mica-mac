import Foundation
import MicaCore
import Testing
@testable import Mica

@MainActor
struct WorkbenchProxyURLTestProjectionTests {
    private func project(_ states: [String: MihomoJSONValue]) -> ProxyProtocolInspectionProjection.Result {
        ProxyProtocolInspectionProjection.project(detail: ProxyNodeViewState(snapshot: ProxySnapshot(
            name: "Node", type: "Shadowsocks", metadata: ["extra": .object(states)]
        )))
    }

    @Test
    func partialSamplesPreservePairingOriginalPositionsAndReportedZero() throws {
        let url = "https://test.example.invalid/generate_204"
        let result = try #require(project([url: .object([
            "alive": .bool(false),
            "history": .array([
                .null,
                .object(["time": .string("2026-10-08T01:02:03Z")]),
                .object(["delay": .number(0)]),
                .object(["time": .string(" "), "delay": .null]),
                .object(["meanDelay": .number(35)]),
                .object(["time": .string("2026-10-08T01:02:06.123456789+08:00"), "delay": .number(42), "mean-delay": .number(40)]),
            ]),
        ])]).urlTests.first)

        #expect(result.alive == false)
        #expect(result.history == [
            ProxyURLTestSample(id: 1, time: "2026-10-08T01:02:03Z", delay: nil, meanDelay: nil),
            ProxyURLTestSample(id: 2, time: nil, delay: 0, meanDelay: nil),
            ProxyURLTestSample(id: 4, time: nil, delay: nil, meanDelay: 35),
            ProxyURLTestSample(id: 5, time: "2026-10-08T01:02:06.123456789+08:00", delay: 42, meanDelay: 40),
        ])
        #expect(result.additionalFields.isEmpty)
    }

    @Test
    func unknownAndMalformedValuesRemainAttachedToTheirURLAndKeepSensitivePaths() throws {
        let url = "https://test.example.invalid/a.b/c?key=x.y"
        let projection = project([url: .object([
            "alive": .string("unknown"),
            "history": .array([
                .object([
                    "time": .number(123), "delay": .number(1.5), "meanDelay": .bool(false),
                    "vendor": .object(["token": .string("fixture-secret"), "retries": .number(0)]),
                ]),
                .string("malformed sample"),
                .object(["time": .string("2026-10-08T01:02:03Z"), "delay": .number(42), "status": .string("reported")]),
            ]),
            "region": .string("JP"),
        ])])
        let result = try #require(projection.urlTests.first)
        #expect(result.url == url)
        #expect(result.id == url)
        #expect(result.alive == nil)
        #expect(result.history == [ProxyURLTestSample(id: 2, time: "2026-10-08T01:02:03Z", delay: 42, meanDelay: nil)])
        #expect(projection.additionalFields.isEmpty)

        let relativeValues = Dictionary(uniqueKeysWithValues: result.additionalFields.map {
            ($0.label.resolved(language: .english), $0.value)
        })
        #expect(relativeValues == [
            "alive": "unknown",
            "history.[0].time": "123",
            "history.[0].delay": "1.5",
            "history.[0].meanDelay": "false",
            "history.[0].vendor.token": "fixture-secret",
            "history.[0].vendor.retries": "0",
            "history.[1]": "malformed sample",
            "history.[2].status": "reported",
            "region": "JP",
        ])
        let token = try #require(result.additionalFields.first { $0.value == "fixture-secret" })
        #expect(token.isSensitive)
        #expect(token.displayValue() == "••••••••")
        #expect(token.reportedKey == "extra.https://test\\.example\\.invalid/a\\.b/c?key=x\\.y.history.[0].vendor.token")
        #expect(Set(result.additionalFields.map(\.id)).count == result.additionalFields.count)
    }

    @Test
    func distinctURLKeysAndLiteralPunctuationAreNeverReparsedAsPaths() throws {
        let firstURL = "https://test.example.invalid/a.b/c"
        let secondURL = "https://test.example.invalid/a/b.c"
        let entries: [(String, MihomoJSONValue)] = [
            (secondURL, .object(["alive": .bool(true)])),
            (firstURL, .object([
                "alive": .bool(true),
                "history": .array([.object([
                    "delay": .number(7),
                    "a.b": .string("literal dot"),
                    "a": .object(["b": .string("nested dot")]),
                    "a/b": .string("literal slash"),
                    "a~1b": .string("literal escape"),
                    "[0]": .string("literal bracket"),
                ])]),
            ])),
        ]
        let first = project(Dictionary(uniqueKeysWithValues: entries))
        let reordered = project(Dictionary(uniqueKeysWithValues: entries.reversed()))
        #expect(first == reordered)
        #expect(first.urlTests.map(\.url) == [firstURL, secondURL].sorted())
        let fields = try #require(first.urlTests.first { $0.url == firstURL }).additionalFields
        #expect(Set(fields.map(\.id)).count == 5)
        #expect(Set(fields.compactMap(\.reportedKey)).count == 5)
        #expect(Set(fields.map { $0.label.resolved(language: .english) }) == [
            "history.[0].a\\.b", "history.[0].a.b", "history.[0].a/b",
            "history.[0].a~1b", "history.[0].\\[0\\]",
        ])
    }

    @Test
    func emptyStatesAndMissingFieldsNeverManufactureResults() {
        let projection = project([
            "https://test.example.invalid/empty": .object(["alive": .null, "history": .array([])]),
            "https://test.example.invalid/blank": .object([
                "history": .array([.null, .object(["time": .string(" \n"), "delay": .null, "meanDelay": .null])]),
            ]),
            "https://test.example.invalid/unknown": .object(["region": .string("JP")]),
            "file:///test": .object(["alive": .bool(true)]),
        ])
        #expect(projection.urlTests.isEmpty)
        #expect(Set(projection.additionalFields.map(\.value)) == ["JP", "true"])
    }

    @Test
    func malformedContainersRetainTheirValuesWithoutPretendingToHaveHistory() throws {
        let url = "https://test.example.invalid/generate_204"
        let result = try #require(project([url: .object([
            "alive": .number(1),
            "history": .object(["delay": .number(7), "password": .string("fixture-secret")]),
        ])]).urlTests.first)
        #expect(result.alive == nil)
        #expect(result.history.isEmpty)
        #expect(result.additionalFields.map { $0.label.resolved(language: .english) } == ["alive", "history.delay", "history.password"])
        #expect(result.additionalFields.map(\.value) == ["1", "7", "fixture-secret"])
        #expect(result.additionalFields.last?.isSensitive == true)
    }

    @Test
    func meanDelayAliasesAndInvalidNumbersRemainLossless() throws {
        let url = "https://test.example.invalid/generate_204"
        let result = try #require(project([url: .object([
            "history": .array([
                .object(["meanDelay": .number(42), "mean-delay": .number(43)]),
                .object(["meanDelay": .string("invalid"), "mean-delay": .number(0)]),
                .object(["delay": .string("42")]),
                .object(["delay": .number(Double.greatestFiniteMagnitude)]),
                .object(["delay": .number(.infinity)]),
            ]),
        ])]).urlTests.first)
        #expect(result.history == [
            ProxyURLTestSample(id: 0, time: nil, delay: nil, meanDelay: 42),
            ProxyURLTestSample(id: 1, time: nil, delay: nil, meanDelay: 0),
        ])
        let fields = Dictionary(uniqueKeysWithValues: result.additionalFields.map {
            ($0.label.resolved(language: .english), $0.value)
        })
        #expect(fields["history.[0].mean-delay"] == "43")
        #expect(fields["history.[1].meanDelay"] == "invalid")
        #expect(fields["history.[2].delay"] == "42")
        #expect(fields["history.[3].delay"] != nil)
        #expect(fields["history.[4].delay"] != nil)
    }
}
