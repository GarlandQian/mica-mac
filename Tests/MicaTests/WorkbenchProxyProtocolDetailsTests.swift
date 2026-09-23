import Foundation
import MicaCore
import Testing
@testable import Mica

@MainActor
struct WorkbenchProxyProtocolDetailsTests {
    @Test(arguments: ProxyProtocolFixture.allCases)
    func explicitlyReportedProtocolConfigurationPreservesAllParameters(fixture: ProxyProtocolFixture) throws {
        let decodedObject = try JSONDecoder().decode(MihomoJSONValue.self, from: Data(fixture.json.utf8))
        guard case .object(var object) = decodedObject else {
            Issue.record("Expected an object fixture")
            return
        }
        object["id"] = .string("runtime-node-id")
        object["vendor"] = .object(["enabled": .bool(false), "zero": .number(0)])
        object["not-reported"] = .null
        object["empty"] = .string(" ")
        let payload = MihomoJSONValue.object(["proxies": .object(["Node": .object(object)])])
        let response = try ProxiesResponse.decodePreservingProxyOrder(from: JSONEncoder().encode(payload))
        let detail = ProxyNodeViewState(snapshot: try #require(response.proxies["Node"]))
        let projection = ProxyProtocolInspectionProjection.project(detail: detail)

        let actual = Dictionary(uniqueKeysWithValues: projection.parameters.compactMap { field in
            field.reportedKey.map { ($0, field.value) }
        })
        #expect(actual == fixture.expectedParameters)
        #expect(Set(projection.parameters.filter(\.isSensitive).compactMap(\.reportedKey)) == fixture.sensitivePaths)
        #expect(projection.parameters.allSatisfy {
            !$0.label.resolved(language: .english).hasPrefix("routing.")
                && !$0.label.resolved(language: .simplifiedChinese).hasPrefix("routing.")
        })
        #expect(projection.parameters.filter(\.isSensitive).allSatisfy { $0.displayValue() == "••••••••" })
        #expect(projection.parameters.filter { !$0.isSensitive }.allSatisfy { $0.displayValue() == $0.value })
        #expect(projection.runtimeFields.map(\.id) == ["metadata.id"])
        #expect(projection.runtimeFields.map(\.value) == ["runtime-node-id"])
        #expect(projection.additionalFields.map(\.id) == [
            "metadata.vendor/enabled", "metadata.vendor/zero",
        ])
        #expect(projection.additionalFields.map(\.value) == ["false", "0"])
        #expect(projection.additionalFields.allSatisfy { !$0.isSensitive })

        let snapshot = try inspection(detail)
        #expect(snapshot.sections.contains { $0.id == "protocol" && $0.fields == projection.parameters })
        #expect(!snapshot.fields.contains { $0.value == "Not reported" })
    }

    @Test(arguments: ProxyProtocolFixture.allCases)
    func protocolNamesNeverManufactureMissingParameters(fixture: ProxyProtocolFixture) throws {
        let decodedObject = try JSONDecoder().decode(MihomoJSONValue.self, from: Data(fixture.json.utf8))
        guard case .object(let object) = decodedObject, case .string(let type) = object["type"] else {
            Issue.record("Expected a reported protocol type")
            return
        }
        let detail = ProxyNodeViewState(snapshot: ProxySnapshot(name: "Node", type: type, metadata: [
            "server": .null, "password": .string(""), "tls": .object([:]), "peers": .array([]),
        ]))
        let projection = ProxyProtocolInspectionProjection.project(detail: detail)
        #expect(projection.parameters.isEmpty)
        #expect(projection.additionalFields.isEmpty)
        let snapshot = try inspection(detail)
        #expect(snapshot.sections.map(\.id) == ["overview"])
    }

    @Test func hysteriaObfuscationAndVlessEncryptionUseTheirProtocolsCredentialSemantics() {
        func parameters(type: String, metadata: [String: MihomoJSONValue]) -> [OverviewPolicyInspectionField] {
            ProxyProtocolInspectionProjection.project(detail: ProxyNodeViewState(
                snapshot: ProxySnapshot(name: "Node", type: type, metadata: metadata)
            )).parameters
        }
        let hy1 = parameters(type: "Hysteria", metadata: ["obfs": .string("fixture-xplus-key")])
        let hy2 = parameters(type: "Hysteria2", metadata: ["obfs": .string("salamander")])
        let encryptedVless = parameters(type: "VLESS", metadata: ["encryption": .string("mlkem768x25519plus.native.0rtt.fixture-password")])
        let plainVless = parameters(type: "VLESS", metadata: ["encryption": .string("none")])
        #expect(hy1.first?.isSensitive == true)
        #expect(hy1.first?.displayValue() == "••••••••")
        #expect(hy2.first?.isSensitive == false)
        #expect(hy2.first?.displayValue() == "salamander")
        #expect(encryptedVless.first?.isSensitive == true)
        #expect(plainVless.first?.isSensitive == false)
        #expect(plainVless.first?.displayValue() == "none")
    }

    @Test func explicitlyReportedShadowsocksConfigurationReachesTheIndividualNodeInspector() throws {
        let response = try ProxiesResponse.decodePreservingProxyOrder(from: Data("""
        {"proxies":{"SS Japan":{
          "type":"Shadowsocks","server":"ss.example.test","port":8443,
          "cipher":"2022-blake3-aes-128-gcm","password":"fixture-secret",
          "udp":false,"plugin":"v2ray-plugin","region":"JP"
        }}}
        """.utf8))
        let decoded = try #require(response.proxies["SS Japan"])
        let snapshot = try inspection(ProxyNodeViewState(snapshot: decoded))
        let protocolSection = try #require(snapshot.sections.first { $0.id == "protocol" })

        #expect(snapshot.kind == .policyMember)
        #expect(snapshot.title == "SS Japan")
        #expect(protocolSection.fields.map(\.id) == [
            "metadata.server", "metadata.port", "metadata.cipher",
            "metadata.password", "metadata.plugin",
        ])
        #expect(protocolSection.fields.map { $0.label.resolved(language: .simplifiedChinese) } == [
            "服务器", "端口", "加密方式", "密码", "插件",
        ])
        #expect(protocolSection.fields.first { $0.id == "metadata.server" }?.displayValue() == "ss.example.test")
        #expect(protocolSection.fields.first { $0.id == "metadata.port" }?.displayValue() == "8443")
        #expect(protocolSection.fields.first { $0.id == "metadata.cipher" }?.displayValue() == "2022-blake3-aes-128-gcm")
        let password = try #require(protocolSection.fields.first { $0.id == "metadata.password" })
        #expect(password.isSensitive)
        #expect(password.displayValue() == "••••••••")
        #expect(password.displayValue(revealingSensitiveValue: true) == "fixture-secret")
        #expect(snapshot.sections.first { $0.id == "reported-fields" }?.fields.map(\.id) == ["metadata.region"])
        #expect(snapshot.fields.filter { $0.id == "metadata.server" }.count == 1)
        #expect(snapshot.fields.first { $0.id == "transport.udp" }?.value == "Disabled")
    }

    @Test func protocolAliasesKeepReportedValuesAndShareHumanLabels() {
        let aliases = [
            ("server-address", MihomoJSONValue.string("alias.example.test"), "Server"),
            ("server_port", .number(443), "Port"),
            ("method", .string("aes-256-gcm"), "Cipher"),
            ("passphrase", .string("fixture-passphrase"), "Password"),
        ]
        let projection = ProxyProtocolInspectionProjection.project(
            detail: node(metadata: Dictionary(uniqueKeysWithValues: aliases.map { ($0.0, $0.1) }))
        )
        #expect(projection.parameters.map { $0.label.resolved(language: .english) } == aliases.map { $0.2 })
        #expect(projection.parameters.map(\.reportedKey) == aliases.map { Optional($0.0) })
        #expect(projection.additionalFields.isEmpty)
        #expect(projection.parameters.last?.isSensitive == true)
    }

    @Test func missingAndEmptyValuesCreateNoPlaceholderRowsOrEmptySections() throws {
        let detail = node(metadata: [
            "server": .null,
            "port": .string("  \n"),
            "cipher": .string(""),
            "plugin-opts": .object(["host": .null, "password": .string("")]),
            "unknown": .array([.null, .string(" ")]),
        ])
        let projection = ProxyProtocolInspectionProjection.project(detail: detail)
        #expect(projection.parameters.isEmpty)
        #expect(projection.additionalFields.isEmpty)
        let snapshot = try inspection(detail)
        #expect(snapshot.sections.map(\.id) == ["overview"])
        #expect(!snapshot.fields.contains { $0.value == "Not reported" })
        #expect(!snapshot.fields.contains { $0.isSensitive })
    }

    @Test func falseAndZeroRemainVisibleAndArraysKeepOriginalIndices() {
        let projection = ProxyProtocolInspectionProjection.project(detail: node(metadata: [
            "port": .number(0),
            "tls": .bool(false),
            "extra": .object([
                "active": .bool(false),
                "counter": .number(0),
                "items": .array([.null, .bool(false), .string(""), .number(0)]),
            ]),
        ]))
        #expect(projection.parameters.map(\.value) == ["0", "false"])
        #expect(projection.additionalFields.map(\.id) == [
            "metadata.extra/active", "metadata.extra/counter",
            "metadata.extra/items/[1]", "metadata.extra/items/[3]",
        ])
        #expect(projection.additionalFields.map(\.value) == ["false", "0", "false", "0"])
    }

    @Test func emptyHistorySamplesAreHiddenWhileAReportedZeroRemains() throws {
        let emptyDetail = ProxyNodeViewState(snapshot: ProxySnapshot(
            name: "SS Japan", type: "Shadowsocks",
            history: [ProxyDelayHistorySnapshot(time: " ", delay: nil)]
        ))
        let emptySnapshot = try inspection(emptyDetail)
        #expect(emptySnapshot.sections.map(\.id) == ["overview"])

        let measuredDetail = ProxyNodeViewState(snapshot: ProxySnapshot(
            name: "SS Japan", type: "Shadowsocks",
            history: [
                ProxyDelayHistorySnapshot(time: nil, delay: nil),
                ProxyDelayHistorySnapshot(time: nil, delay: 0),
            ]
        ))
        let measuredSnapshot = try inspection(measuredDetail)
        let testing = try #require(measuredSnapshot.sections.first { $0.id == "testing" })
        #expect(testing.fields.first { $0.id == "test-samples" }?.value == "1")
        #expect(testing.fields.contains { $0.id == "test-delay" })
        #expect(!testing.fields.contains { $0.id == "test-time" })
    }

    @Test func nestedCredentialsCanBeRevealedIndependentlyWithoutHidingPublicParameters() throws {
        let projection = ProxyProtocolInspectionProjection.project(detail: node(metadata: [
            "plugin-opts": .object([
                "host": .string("cdn.example.test"),
                "headers": .object([
                    "Authorization": .string("Bearer fixture-token"),
                    "User-Agent": .string("Fixture Agent"),
                ]),
                "private-key": .string("fixture-private-key"),
                "public-key": .string("fixture-public-key"),
            ]),
            "vendor": .object([
                "region": .string("JP"),
                "accounts": .array([.object([
                    "token": .string("fixture-vendor-token"),
                    "name": .string("account-a"),
                ])]),
            ]),
        ]))
        let fields = projection.parameters + projection.additionalFields
        let hidden = fields.filter(\.isSensitive)
        #expect(hidden.map(\.id).sorted() == [
            "metadata.plugin-opts/headers/Authorization",
            "metadata.plugin-opts/private-key",
            "metadata.vendor/accounts/[0]/token",
        ])
        #expect(hidden.allSatisfy { $0.displayValue() == "••••••••" })
        #expect(fields.first { $0.id == "metadata.plugin-opts/host" }?.displayValue() == "cdn.example.test")
        #expect(fields.first { $0.id == "metadata.plugin-opts/public-key" }?.displayValue() == "fixture-public-key")
        #expect(fields.first { $0.id == "metadata.vendor/region" }?.displayValue() == "JP")
        let token = try #require(hidden.first)
        #expect(token.displayValue(revealingSensitiveValue: true) == token.value)
        #expect(hidden.dropFirst().allSatisfy { $0.displayValue() == "••••••••" })
    }

    @Test func metadataPathsRemainUniqueForLiteralAndNestedKeys() {
        let projection = ProxyProtocolInspectionProjection.project(detail: node(metadata: [
            "a/b": .string("literal"),
            "a": .object(["b": .string("nested")]),
        ]))
        #expect(projection.additionalFields.map(\.id) == ["metadata.a/b", "metadata.a~1b"])
        #expect(Set(projection.additionalFields.map(\.id)).count == 2)
        #expect(projection.additionalFields.map(\.value) == ["nested", "literal"])
    }

    @Test func literalPunctuationCannotMasqueradeAsNestedPropertiesInTheInspector() {
        let projection = ProxyProtocolInspectionProjection.project(detail: node(metadata: [
            "a.b": .string("literal root"),
            "a": .object(["b": .string("nested root")]),
            "vendor": .object([
                "a.b": .string("literal child"),
                "a": .object(["b": .string("nested child")]),
                "items.[0]": .string("literal array spelling"),
                "items": .array([.string("array item")]),
                "\\.[]": .string("literal escape characters"),
            ]),
        ]))
        let fields = projection.additionalFields
        #expect(Dictionary(uniqueKeysWithValues: fields.compactMap { field in
            field.reportedKey.map { ($0, field.value) }
        }) == [
            "a\\.b": "literal root",
            "a.b": "nested root",
            "vendor.a\\.b": "literal child",
            "vendor.a.b": "nested child",
            "vendor.items\\.\\[0\\]": "literal array spelling",
            "vendor.items.[0]": "array item",
            "vendor.\\\\\\.\\[\\]": "literal escape characters",
        ])
        #expect(Set(fields.map(\.id)).count == fields.count)
        #expect(fields.allSatisfy { $0.label.resolved(language: .english) == $0.reportedKey })
    }

    @Test func objectKeysAndArrayIndicesCannotReuseARevealedCredentialIdentity() throws {
        let object = ProxyProtocolInspectionProjection.project(detail: node(metadata: [
            "password": .object(["[0]": .string("fixture-object-secret")]),
        ]))
        let array = ProxyProtocolInspectionProjection.project(detail: node(metadata: [
            "password": .array([.string("fixture-array-secret")]),
        ]))
        let objectField = try #require(object.parameters.first)
        let arrayField = try #require(array.parameters.first)
        #expect(objectField.id != arrayField.id)
        #expect(objectField.reportedKey == "password.\\[0\\]")
        #expect(arrayField.reportedKey == "password.[0]")
        #expect(objectField.isSensitive && arrayField.isSensitive)
        #expect(objectField.displayValue() == "••••••••")
        #expect(arrayField.displayValue() == "••••••••")

        let escaped = ProxyProtocolInspectionProjection.project(detail: node(metadata: [
            "password": .object([
                "[0]": .string("brackets"),
                "~20~3": .string("escape spelling"),
                "a/b": .string("slash"),
                "a~1b": .string("escaped slash spelling"),
            ]),
        ]))
        #expect(Set(escaped.parameters.map(\.id)).count == 4)
    }

    @Test func simultaneousAliasValuesStayDistinctAndStableAcrossMetadataOrder() {
        let pairs: [(String, MihomoJSONValue)] = [
            ("server", .string("primary.example.test")),
            ("server-address", .string("reported-alias.example.test")),
            ("port", .number(0)),
            ("server_port", .number(8443)),
            ("tls", .bool(false)),
            ("tls-options", .object(["enabled": .bool(true)])),
        ]
        let first = ProxyProtocolInspectionProjection.project(detail: node(
            metadata: Dictionary(uniqueKeysWithValues: pairs)
        ))
        let reordered = ProxyProtocolInspectionProjection.project(detail: node(
            metadata: Dictionary(uniqueKeysWithValues: pairs.reversed())
        ))
        #expect(first == reordered)
        #expect(first.additionalFields.isEmpty)
        #expect(first.parameters.map(\.value) == [
            "primary.example.test", "reported-alias.example.test", "0", "8443", "false", "true",
        ])
        #expect(Set(first.parameters.map(\.id)).count == pairs.count)
    }

    @Test func headerAndObfuscationCredentialAliasesAreMaskedAtEveryDepth() {
        let names = ["Proxy-Authorization", "Cookie", "Set-Cookie", "X-API-Key", "X-Auth-Token"]
        let projection = ProxyProtocolInspectionProjection.project(detail: node(metadata: [
            "obfs-password": .string("fixture-obfs-secret"),
            "ws-opts": .object([
                "headers": .object(Dictionary(uniqueKeysWithValues: names.map {
                    ($0, MihomoJSONValue.string("fixture-\($0)"))
                })),
                "path": .string("/socket"),
            ]),
        ]))
        let fields = projection.parameters + projection.additionalFields
        let protected = fields.filter(\.isSensitive)
        #expect(protected.count == names.count + 1)
        #expect(protected.allSatisfy { $0.displayValue() == "••••••••" })
        #expect(protected.allSatisfy { $0.displayValue(revealingSensitiveValue: true).hasPrefix("fixture-") })
        #expect(fields.first { $0.id == "metadata.ws-opts/path" }?.displayValue() == "/socket")
    }

    @Test func revealIdentityChangesWhenAGroupSelectsAnotherMemberEvenWithIdenticalValues() {
        let controllerID = UUID()
        let generation = UUID()
        let first = node(metadata: ["password": .string("same-fixture-secret")])
        let second = ProxyNodeViewState(snapshot: ProxySnapshot(
            name: "SS Singapore", type: "Shadowsocks",
            metadata: ["password": .string("same-fixture-secret")]
        ))
        func index(selected: String) -> OverviewPolicyInspectionIndex {
            OverviewPolicyInspectionIndex(catalog: PolicyGroupCatalogSnapshot(mode: "rule", groups: [
                ProxyGroupViewState(
                    id: "Manual", type: "Selector", selected: selected,
                    options: [first.name, second.name],
                    optionDetails: [first.name: first, second.name: second]
                ),
            ]))
        }
        let selection = WorkbenchInspectorSelection.proxyGroup(groupName: "Manual", groupOccurrenceID: nil)
        let firstIdentity = ProxyPolicyInspectionIdentity(
            selection: selection, controllerID: controllerID, generation: generation,
            policyIndex: index(selected: first.name)
        )
        let secondIdentity = ProxyPolicyInspectionIdentity(
            selection: selection, controllerID: controllerID, generation: generation,
            policyIndex: index(selected: second.name)
        )
        #expect(firstIdentity.resolvedMemberName == first.name)
        #expect(secondIdentity.resolvedMemberName == second.name)
        #expect(firstIdentity != secondIdentity)
        #expect(secondIdentity != ProxyPolicyInspectionIdentity(
            selection: selection, controllerID: controllerID, generation: UUID(),
            policyIndex: index(selected: second.name)
        ))
        #expect(secondIdentity != ProxyPolicyInspectionIdentity(
            selection: selection, controllerID: UUID(), generation: generation,
            policyIndex: index(selected: second.name)
        ))
    }

    @Test func aRetainedTopologyMemberCannotSupplyActionsToAnotherNodesInspector() throws {
        let detail = node(metadata: [:])
        let index = OverviewPolicyInspectionIndex(catalog: PolicyGroupCatalogSnapshot(mode: "rule", groups: [
            ProxyGroupViewState(
                id: "Manual", type: "Selector", selected: detail.name,
                options: [detail.name, "Other node"], optionDetails: [detail.name: detail]
            ),
        ]))
        guard case .member(let member) = index.resolve(name: detail.name) else {
            Issue.record("Expected the exact fixture member")
            return
        }
        let retainedResolution = index.resolve(name: detail.name)
        #expect(OverviewPolicyInspectionProjection.matches(
            selection: .proxyNode(groupName: "Manual", groupOccurrenceID: member.groupOccurrenceID, nodeName: detail.name),
            resolution: retainedResolution
        ))
        #expect(!OverviewPolicyInspectionProjection.matches(
            selection: .proxyNode(groupName: "Manual", groupOccurrenceID: member.groupOccurrenceID, nodeName: "Other node"),
            resolution: retainedResolution
        ))
        #expect(!OverviewPolicyInspectionProjection.matches(
            selection: .proxyNode(groupName: "Different group", groupOccurrenceID: member.groupOccurrenceID, nodeName: detail.name),
            resolution: retainedResolution
        ))
        #expect(!OverviewPolicyInspectionProjection.matches(
            selection: .proxyNode(groupName: "Manual", groupOccurrenceID: "another-occurrence", nodeName: detail.name),
            resolution: retainedResolution
        ))
        #expect(!OverviewPolicyInspectionProjection.matches(
            selection: .proxyGroup(groupName: "Manual", groupOccurrenceID: nil),
            resolution: .ambiguous
        ))
    }

    @Test func standardMihomoRuntimeResponseDoesNotPretendToContainProtocolConfiguration() throws {
        let response = try ProxiesResponse.decodePreservingProxyOrder(from: Data(#"""
        {"proxies":{"Runtime SS":{
          "name":"Runtime SS","type":"Shadowsocks","id":"node-runtime-id",
          "alive":true,"history":[{"time":"2026-09-01T12:00:00Z","delay":42}],
          "udp":true,"uot":false,"xudp":false,"tfo":false,"mptcp":false,"smux":false,
          "interface":"en0","provider-name":"Primary","routing-mark":0,"dialer-proxy":"Upstream",
          "extra":{"https://test.example.invalid/generate_204":{
            "alive":false,"history":[{"time":"2026-09-01T12:00:01Z","delay":0}]
          }}
        }}}
        """#.utf8))
        let detail = ProxyNodeViewState(snapshot: try #require(response.proxies["Runtime SS"]))
        let projection = ProxyProtocolInspectionProjection.project(detail: detail)
        let snapshot = try inspection(detail)

        #expect(snapshot.title == "Runtime SS")
        #expect(snapshot.subtitle == "Shadowsocks")
        #expect(projection.parameters.isEmpty)
        #expect(!snapshot.sections.contains { $0.id == "protocol" })
        #expect(projection.runtimeFields.map(\.reportedKey) == ["id", "routing-mark", "dialer-proxy"])
        #expect(projection.runtimeFields.map(\.value) == ["node-runtime-id", "0", "Upstream"])
        #expect(projection.testingFields.map(\.value) == ["false", "0", "2026-09-01T12:00:01Z"])
        #expect(projection.additionalFields.isEmpty)
        #expect(snapshot.sections.first { $0.id == "transport" }?.fields.count == 6)
        #expect(snapshot.sections.first { $0.id == "testing" }?.fields.suffix(3)
            == projection.testingFields[...])
        #expect(snapshot.fields.first { $0.id == "provider" }?.value == "Primary")
        #expect(snapshot.fields.first { $0.id == "interface" }?.value == "en0")
        #expect(Set(snapshot.fields.map(\.id)).count == snapshot.fields.count)
        #expect(!snapshot.fields.contains { field in
            field.reportedKey.map { ["server", "port", "cipher", "password"].contains($0) } == true
        })
    }

    @Test(arguments: [#"{}"#, #"{"type":null}"#, #"{"type":""}"#, #"{"type":"  "}"#])
    func missingDecodedNodeTypeNeverBorrowsProxyOrParentGroupType(json: String) throws {
        let response = try ProxiesResponse.decodePreservingProxyOrder(
            from: Data("{\"proxies\":{\"Node\":\(json)}}".utf8)
        )
        let detail = ProxyNodeViewState(snapshot: try #require(response.proxies["Node"]))
        let snapshot = try inspection(detail)
        #expect(snapshot.subtitle == nil)
        #expect(!snapshot.fields.contains { $0.id == "type" })
        // The parent group remains a separately labelled fact, never a node protocol.
        #expect(snapshot.fields.first { $0.id == "group-type" }?.value == "Selector")
        #expect(!snapshot.sections.contains { $0.id == "protocol" })
    }

    @Test func additionalExtraFieldsRetainSecretsAndDoNotMasqueradeAsTestStates() {
        let projection = ProxyProtocolInspectionProjection.project(detail: node(metadata: [
            "extra": .object([
                "password": .string("fixture-secret"),
                "auth": .object(["user": .string("fixture-credential")]),
                "vendor": .object(["enabled": .bool(false)]),
                "https://vendor.example.invalid": .object(["region": .string("JP")]),
            ]),
        ]))
        #expect(projection.parameters.isEmpty)
        #expect(projection.testingFields.isEmpty)
        #expect(projection.additionalFields.count == 4)
        let sensitive = projection.additionalFields.filter(\.isSensitive)
        #expect(Set(sensitive.compactMap(\.reportedKey)) == ["extra.password", "extra.auth.user"])
        #expect(sensitive.allSatisfy { $0.displayValue() == "••••••••" })
        #expect(Set(projection.additionalFields.filter { !$0.isSensitive }.map(\.value)) == ["false", "JP"])
    }

    private func node(metadata: [String: MihomoJSONValue]) -> ProxyNodeViewState {
        ProxyNodeViewState(snapshot: ProxySnapshot(name: "SS Japan", type: "Shadowsocks", metadata: metadata))
    }

    private func inspection(_ detail: ProxyNodeViewState) throws -> OverviewPolicyInspectionSnapshot {
        let catalog = PolicyGroupCatalogSnapshot(mode: "rule", groups: [
            ProxyGroupViewState(
                id: "Manual", type: "Selector", selected: detail.name,
                options: [detail.name], optionDetails: [detail.name: detail]
            ),
        ])
        return try #require(OverviewPolicyInspectionProjection.snapshot(
            name: detail.name,
            policyIndex: OverviewPolicyInspectionIndex(catalog: catalog),
            language: .english
        ))
    }
}

// Optional configuration metadata exercises the parser, not the standard
// Mihomo /proxies contract, which does not supply these configuration fields.
enum ProxyProtocolFixture: String, CaseIterable, Sendable {
    case vmess, vless, trojan, hysteria, hysteria2, tuic4, tuic5, wireguard, socks, http

    var json: String {
        switch self {
        case .vmess:
            #"{"type":"VMess","server":"vmess.example.test","port":443,"uuid":"fixture-vmess-uuid","alterId":0,"cipher":"auto","security":"auto","authenticated-length":false,"global-padding":false,"network":"ws","tls":true,"servername":"tls.example.test","ws-opts":{"path":"/vmess","headers":{"Host":"cdn.example.test"}}}"#
        case .vless:
            #"{"type":"VLESS","server":"vless.example.test","port":443,"uuid":"fixture-vless-uuid","flow":"xtls-rprx-vision","encryption":"none","tls":true,"servername":"tls.example.test","client-fingerprint":"chrome","reality-opts":{"public-key":"fixture-public-key","short-id":"abc123"},"packet-encoding":"xudp"}"#
        case .trojan:
            #"{"type":"Trojan","server":"trojan.example.test","port":443,"password":"fixture-trojan-password","sni":"tls.example.test","skip-cert-verify":false,"alpn":["h2","http/1.1"],"network":"grpc","grpc-opts":{"grpc-service-name":"tunnel"},"ss-opts":{"enabled":true,"method":"aes-128-gcm","password":"fixture-inner-password"}}"#
        case .hysteria:
            #"{"type":"Hysteria","server":"hy.example.test","port":443,"auth":"Zml4dHVyZQ==","auth-str":"fixture-auth","obfs":"fixture-xplus-key","up":20,"down":100,"protocol":"udp","sni":"tls.example.test","disable-mtu-discovery":false,"recv-window-conn":15728640,"recv-window":67108864}"#
        case .hysteria2:
            #"{"type":"Hysteria2","server":"hy2.example.test","port":443,"password":"fixture-hy2-password","obfs":"salamander","obfs-password":"fixture-obfs-password","up":"80 Mbps","down":"160 Mbps","sni":"tls.example.test","skip-cert-verify":false,"alpn":["h3"]}"#
        case .tuic4:
            #"{"type":"TUIC","server":"tuic4.example.test","port":443,"token":"fixture-tuic-token","congestion-controller":"bbr","udp-relay-mode":"quic","reduce-rtt":false,"request-timeout":8000}"#
        case .tuic5:
            #"{"type":"TUIC","server":"tuic5.example.test","port":443,"uuid":"fixture-tuic-uuid","password":"fixture-tuic-password","congestion-controller":"cubic","udp-relay-mode":"native","reduce-rtt":false,"heartbeat-interval":10000,"disable-sni":false,"alpn":["h3"]}"#
        case .wireguard:
            #"{"type":"WireGuard","private-key":"fixture-private-key","address":["10.0.0.2/32","fd00::2/128"],"mtu":1420,"peers":[{"server":"wg.example.test","port":51820,"public-key":"fixture-peer-public","pre-shared-key":"fixture-peer-secret","allowed-ips":["0.0.0.0/0","::/0"],"reserved":[0,1,2]}]}"#
        case .socks:
            #"{"type":"Socks5","server":"socks.example.test","port":1080,"username":"user-a","password":"fixture-socks-password","tls":false,"ip":"192.0.2.10"}"#
        case .http:
            #"{"type":"HTTP","server":"proxy.example.test","port":8443,"username":"user-b","password":"fixture-http-password","tls":true,"sni":"tls.example.test","headers":{"Proxy-Authorization":"Basic fixture-auth","User-Agent":"Fixture Agent"}}"#
        }
    }

    var expectedParameters: [String: String] {
        switch self {
        case .vmess:
            [
                "server": "vmess.example.test", "port": "443", "uuid": "fixture-vmess-uuid",
                "alterId": "0", "cipher": "auto", "security": "auto",
                "authenticated-length": "false", "global-padding": "false", "network": "ws",
                "tls": "true", "servername": "tls.example.test", "ws-opts.path": "/vmess",
                "ws-opts.headers.Host": "cdn.example.test",
            ]
        case .vless:
            [
                "server": "vless.example.test", "port": "443", "uuid": "fixture-vless-uuid",
                "flow": "xtls-rprx-vision", "encryption": "none", "tls": "true",
                "servername": "tls.example.test", "client-fingerprint": "chrome",
                "reality-opts.public-key": "fixture-public-key", "reality-opts.short-id": "abc123",
                "packet-encoding": "xudp",
            ]
        case .trojan:
            [
                "server": "trojan.example.test", "port": "443", "password": "fixture-trojan-password",
                "sni": "tls.example.test", "skip-cert-verify": "false", "alpn.[0]": "h2",
                "alpn.[1]": "http/1.1", "network": "grpc", "grpc-opts.grpc-service-name": "tunnel",
                "ss-opts.enabled": "true", "ss-opts.method": "aes-128-gcm", "ss-opts.password": "fixture-inner-password",
            ]
        case .hysteria:
            [
                "server": "hy.example.test", "port": "443", "auth": "Zml4dHVyZQ==",
                "auth-str": "fixture-auth", "obfs": "fixture-xplus-key", "up": "20", "down": "100",
                "protocol": "udp", "sni": "tls.example.test", "disable-mtu-discovery": "false",
                "recv-window-conn": "15728640", "recv-window": "67108864",
            ]
        case .hysteria2:
            [
                "server": "hy2.example.test", "port": "443", "password": "fixture-hy2-password",
                "obfs": "salamander", "obfs-password": "fixture-obfs-password", "up": "80 Mbps",
                "down": "160 Mbps", "sni": "tls.example.test", "skip-cert-verify": "false", "alpn.[0]": "h3",
            ]
        case .tuic4:
            [
                "server": "tuic4.example.test", "port": "443", "token": "fixture-tuic-token",
                "congestion-controller": "bbr", "udp-relay-mode": "quic", "reduce-rtt": "false",
                "request-timeout": "8000",
            ]
        case .tuic5:
            [
                "server": "tuic5.example.test", "port": "443", "uuid": "fixture-tuic-uuid",
                "password": "fixture-tuic-password", "congestion-controller": "cubic", "udp-relay-mode": "native",
                "reduce-rtt": "false", "heartbeat-interval": "10000", "disable-sni": "false", "alpn.[0]": "h3",
            ]
        case .wireguard:
            [
                "private-key": "fixture-private-key", "address.[0]": "10.0.0.2/32", "address.[1]": "fd00::2/128",
                "mtu": "1420", "peers.[0].server": "wg.example.test", "peers.[0].port": "51820",
                "peers.[0].public-key": "fixture-peer-public", "peers.[0].pre-shared-key": "fixture-peer-secret",
                "peers.[0].allowed-ips.[0]": "0.0.0.0/0", "peers.[0].allowed-ips.[1]": "::/0",
                "peers.[0].reserved.[0]": "0", "peers.[0].reserved.[1]": "1", "peers.[0].reserved.[2]": "2",
            ]
        case .socks:
            [
                "server": "socks.example.test", "port": "1080", "username": "user-a",
                "password": "fixture-socks-password", "tls": "false", "ip": "192.0.2.10",
            ]
        case .http:
            [
                "server": "proxy.example.test", "port": "8443", "username": "user-b",
                "password": "fixture-http-password", "tls": "true", "sni": "tls.example.test",
                "headers.Proxy-Authorization": "Basic fixture-auth", "headers.User-Agent": "Fixture Agent",
            ]
        }
    }

    var sensitivePaths: Set<String> {
        switch self {
        case .vmess, .vless: ["uuid"]
        case .trojan: ["password", "ss-opts.password"]
        case .hysteria: ["auth", "auth-str", "obfs"]
        case .hysteria2: ["password", "obfs-password"]
        case .tuic4: ["token"]
        case .tuic5: ["uuid", "password"]
        case .wireguard: ["private-key", "peers.[0].pre-shared-key"]
        case .socks: ["password"]
        case .http: ["password", "headers.Proxy-Authorization"]
        }
    }
}
