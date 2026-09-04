import XCTest
@testable import MicaCore

final class MihomoModelsTests: XCTestCase {
    func testConfigDecodesKebabCaseKeys() throws {
        let data = Data("""
        {
          "mode": "Rule",
          "mode-options": ["Rule", "Global", "Direct"],
          "allow-lan": true,
          "log-level": "info",
          "mixed-port": 7890,
          "socks-port": 7891,
          "redir-port": 7892,
          "ipv6": false,
          "tcp-concurrent": true,
          "tun": { "enable": true }
        }
        """.utf8)

        let config = try JSONDecoder().decode(ConfigResponse.self, from: data)

        XCTAssertEqual(config.mode, "Rule")
        XCTAssertEqual(config.modeOptions, ["Rule", "Global", "Direct"])
        XCTAssertEqual(config.allowLan, true)
        XCTAssertEqual(config.logLevel, "info")
        XCTAssertEqual(config.mixedPort, 7890)
        XCTAssertEqual(config.socksPort, 7891)
        XCTAssertEqual(config.redirPort, 7892)
        XCTAssertEqual(config.ipv6, false)
        XCTAssertEqual(config.tcpConcurrent, true)
        XCTAssertEqual(config.tun?.enable, true)
    }

    func testConfigPatchEncodesOfficialRuntimeKeysAndNestedTUN() throws {
        let patch = MihomoConfigPatch(
            logLevel: "warning",
            allowLan: true,
            ipv6: false,
            tcpConcurrent: true,
            tunEnabled: true,
            port: 7890,
            socksPort: 7891,
            redirPort: 7892,
            mixedPort: 7893
        )
        let data = try JSONEncoder().encode(patch)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tun = try XCTUnwrap(object["tun"] as? [String: Any])

        XCTAssertEqual(object["log-level"] as? String, "warning")
        XCTAssertEqual(object["allow-lan"] as? Bool, true)
        XCTAssertEqual(object["ipv6"] as? Bool, false)
        XCTAssertEqual(object["tcp-concurrent"] as? Bool, true)
        XCTAssertEqual(tun["enable"] as? Bool, true)
        XCTAssertEqual(object["port"] as? Int, 7890)
        XCTAssertEqual(object["socks-port"] as? Int, 7891)
        XCTAssertEqual(object["redir-port"] as? Int, 7892)
        XCTAssertEqual(object["mixed-port"] as? Int, 7893)

        let endpoint = MihomoEndpoint.updateConfigs()
        XCTAssertEqual(endpoint.method, .patch)
        XCTAssertEqual(endpoint.pathDescription, "/configs")
    }

    func testConfigurationReloadAndGeoDataUseOfficialRemoteEndpoints() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://controller.example:9090"))
        let reload = MihomoEndpoint.reloadConfigs(force: true)
        let reloadComponents = try XCTUnwrap(
            URLComponents(url: reload.url(relativeTo: baseURL), resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(reload.method, .put)
        XCTAssertEqual(reload.pathDescription, "/configs")
        XCTAssertEqual(reloadComponents.path, "/configs")
        XCTAssertEqual(reloadComponents.queryItems, [URLQueryItem(name: "force", value: "true")])

        XCTAssertEqual(MihomoEndpoint.updateGeoData.method, .post)
        XCTAssertEqual(MihomoEndpoint.updateGeoData.pathDescription, "/configs/geo")
        XCTAssertEqual(
            try MihomoEndpoint.updateGeoData.url(relativeTo: baseURL).absoluteString,
            "http://controller.example:9090/configs/geo"
        )
    }

    func testProxiesDecodesDictionaryIntoNamedSnapshots() throws {
        let data = Data("""
        {
          "proxies": {
            "Proxy": {
              "type": "Selector",
              "now": "Option A",
              "all": ["Option A", "Option B", "DIRECT"],
              "hidden": true
            },
            "Option A": {
              "type": "Shadowsocks",
              "udp": true
            }
          }
        }
        """.utf8)

        let response = try ProxiesResponse.decodePreservingProxyOrder(from: data)

        XCTAssertEqual(response.proxies["Proxy"]?.name, "Proxy")
        XCTAssertEqual(response.proxies["Proxy"]?.now, "Option A")
        XCTAssertEqual(response.proxies["Proxy"]?.all, ["Option A", "Option B", "DIRECT"])
        XCTAssertEqual(response.proxies["Proxy"]?.hidden, true)
        XCTAssertEqual(response.proxyOrder, ["Proxy", "Option A"])
        XCTAssertEqual(response.policyGroups.map(\.name), ["Proxy"])
    }

    func testClearFixedSelectionUsesOfficialProxyDeleteEndpoint() throws {
        let endpoint = MihomoEndpoint.clearFixedProxy(group: "Auto / Fallback")
        let baseURL = try XCTUnwrap(URL(string: "http://controller.example:9090"))

        XCTAssertEqual(endpoint.method, .delete)
        XCTAssertEqual(endpoint.pathDescription, "/proxies/Auto / Fallback")
        XCTAssertEqual(
            try endpoint.url(relativeTo: baseURL).absoluteString,
            "http://controller.example:9090/proxies/Auto%20/%20Fallback"
        )
    }

    func testSmartWeightEndpointsUseOfficialPaths() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://controller.example:9090"))
        let legacy = MihomoEndpoint.smartGroupWeights(group: "Smart / Select")

        XCTAssertEqual(MihomoEndpoint.smartWeights.method, .get)
        XCTAssertEqual(MihomoEndpoint.smartWeights.pathDescription, "/group/weights")
        XCTAssertEqual(
            try MihomoEndpoint.smartWeights.url(relativeTo: baseURL).absoluteString,
            "http://controller.example:9090/group/weights"
        )
        XCTAssertEqual(legacy.method, .get)
        XCTAssertEqual(legacy.pathDescription, "/group/Smart / Select/weights")
        XCTAssertEqual(
            try legacy.url(relativeTo: baseURL).absoluteString,
            "http://controller.example:9090/group/Smart%20/%20Select/weights"
        )
    }

    func testPolicyGroupsPreserveControllerOrder() throws {
        let data = Data("""
        {
          "proxies": {
            "GLOBAL": {
              "type": "Selector",
              "now": "US",
              "all": ["US", "JP", "DIRECT"]
            },
            "Proxy": {
              "type": "Selector",
              "now": "JP",
              "all": ["JP", "US", "DIRECT"]
            },
            "DIRECT": {
              "type": "Direct"
            },
            "Apple": {
              "type": "Selector",
              "now": "DIRECT",
              "all": ["DIRECT", "Proxy"]
            }
          }
        }
        """.utf8)

        let response = try ProxiesResponse.decodePreservingProxyOrder(from: data)

        XCTAssertEqual(response.proxyOrder, ["GLOBAL", "Proxy", "DIRECT", "Apple"])
        XCTAssertEqual(response.policyGroups.map(\.name), ["GLOBAL", "Proxy", "Apple"])
        XCTAssertEqual(response.policyGroups.first?.all, ["US", "JP", "DIRECT"])
    }

    func testPolicyGroupsPreserveControllerOrderWhenGlobalCatalogIsPresent() throws {
        let data = Data("""
        {
          "proxies": {
            "GLOBAL": {
              "type": "Selector",
              "now": "Apple",
              "all": ["Apple", "Proxy", "Fallback", "DIRECT"]
            },
            "DIRECT": {
              "type": "Direct"
            },
            "Proxy": {
              "type": "Selector",
              "now": "JP",
              "all": ["JP", "US", "DIRECT"]
            },
            "Fallback": {
              "type": "Fallback",
              "now": "US",
              "all": ["US", "DIRECT"]
            },
            "Apple": {
              "type": "Selector",
              "now": "DIRECT",
              "all": ["DIRECT", "Proxy"]
            }
          }
        }
        """.utf8)

        let response = try ProxiesResponse.decodePreservingProxyOrder(from: data)

        XCTAssertEqual(response.policyGroups.map(\.name), ["GLOBAL", "Proxy", "Fallback", "Apple"])
        XCTAssertEqual(response.policyGroups.first?.all, ["Apple", "Proxy", "Fallback", "DIRECT"])
    }

    func testPolicyGroupsPreserveEscapedUnicodeKeyOrder() throws {
        let data = Data(#"""
        {
          "proxies": {
            "\uD83C\uDF38 First": {
              "type": "Selector",
              "now": "A",
              "all": ["A", "B"]
            },
            "Quote \" Group": {
              "type": "Selector",
              "now": "C",
              "all": ["C"],
              "metadata": { "note": "nested value" }
            },
            "Plain": {
              "type": "Fallback",
              "now": "D",
              "all": ["D"]
            }
          }
        }
        """#.utf8)

        let response = try ProxiesResponse.decodePreservingProxyOrder(from: data)

        XCTAssertEqual(response.proxyOrder, ["🌸 First", "Quote \" Group", "Plain"])
        XCTAssertEqual(response.policyGroups.map(\.name), ["🌸 First", "Quote \" Group", "Plain"])
    }

    func testProxiesPreserveCompleteGroupAndNodeMetadata() throws {
        let data = Data(#"""
        {
          "proxies": {
            "Proxy": {
              "type": "Selector",
              "now": "Node A",
              "all": ["Node A"],
              "alive": true,
              "icon": "https://controller.example/icons/proxy.png",
              "testUrl": "https://www.gstatic.com/generate_204",
              "fixed": "Node A",
              "interface": "en0",
              "udp": true,
              "uot": true,
              "xudp": true,
              "custom-field": { "mode": "strict" },
              "history": [
                { "time": "2026-07-18T09:00:00Z", "delay": 47, "meanDelay": 51 }
              ]
            },
            "Node A": {
              "type": "Shadowsocks",
              "alive": false,
              "provider-name": "Remote Nodes",
              "interface": "utun7",
              "udp": true,
              "tfo": true,
              "mptcp": true,
              "smux": true,
              "history": [
                { "time": "2026-07-18T08:59:00Z", "delay": 88 }
              ]
            }
          }
        }
        """#.utf8)

        let response = try ProxiesResponse.decodePreservingProxyOrder(from: data)
        let group = try XCTUnwrap(response.proxies["Proxy"])
        let node = try XCTUnwrap(response.proxies["Node A"])

        XCTAssertEqual(group.alive, true)
        XCTAssertEqual(group.icon, "https://controller.example/icons/proxy.png")
        XCTAssertEqual(group.testURL, "https://www.gstatic.com/generate_204")
        XCTAssertEqual(group.fixed, "Node A")
        XCTAssertEqual(group.interfaceName, "en0")
        XCTAssertEqual(group.latestDelay, 47)
        XCTAssertEqual(group.history.first?.meanDelay, 51)
        XCTAssertEqual(group.enabledTransportNames, ["UDP", "UOT", "XUDP"])
        XCTAssertEqual(group.metadata["custom-field"], .object(["mode": .string("strict")]))

        XCTAssertEqual(node.alive, false)
        XCTAssertEqual(node.providerName, "Remote Nodes")
        XCTAssertEqual(node.interfaceName, "utun7")
        XCTAssertEqual(node.latestDelay, 88)
        XCTAssertEqual(node.enabledTransportNames, ["UDP", "TFO", "MPTCP", "SMUX"])
    }

    func testSpecializedProxyDecodePreservesKnownFieldsAndCompleteMetadata() throws {
        let data = Data(#"""
        {
          "proxies": {
            "\uD83C\uDF38 Group \"A\"": {
              "type": "Selector",
              "now": "节点一",
              "all": ["节点一", "DIRECT"],
              "alive": true,
              "history": [
                {
                  "time": "2026-09-02T12:00:00Z",
                  "delay": 47,
                  "mean-delay": "51",
                  "detail": { "samples": [1, true, null] }
                }
              ],
              "icon": "https://controller.example/icon.png",
              "tester": "https://controller.example/generate_204",
              "provider-name": "机场 A",
              "fixed": "节点一",
              "interface": "utun7",
              "udp": true,
              "uot": false,
              "xudp": true,
              "tfo": false,
              "mptcp": true,
              "smux": false,
              "hidden": true,
              "unknown-object": {
                "nested": [1, true, null, { "name": "值" }]
              },
              "unknown-number": 42,
              "unknown-bool": false,
              "unknown-null": null
            },
            "Second \\ Path": {
              "type": "Direct"
            }
          }
        }
        """#.utf8)

        let response = try ProxiesResponse.decodePreservingProxyOrder(from: data)
        let groupName = "🌸 Group \"A\""
        let group = try XCTUnwrap(response.proxies[groupName])

        XCTAssertEqual(response.proxyOrder, [groupName, "Second \\ Path"])
        XCTAssertEqual(group.type, "Selector")
        XCTAssertEqual(group.now, "节点一")
        XCTAssertEqual(group.all, ["节点一", "DIRECT"])
        XCTAssertEqual(group.alive, true)
        XCTAssertEqual(
            group.history,
            [
                ProxyDelayHistorySnapshot(
                    time: "2026-09-02T12:00:00Z",
                    delay: 47,
                    meanDelay: 51
                ),
            ]
        )
        XCTAssertEqual(group.icon, "https://controller.example/icon.png")
        XCTAssertEqual(group.testURL, "https://controller.example/generate_204")
        XCTAssertEqual(group.providerName, "机场 A")
        XCTAssertEqual(group.fixed, "节点一")
        XCTAssertEqual(group.interfaceName, "utun7")
        XCTAssertEqual(group.enabledTransportNames, ["UDP", "XUDP", "MPTCP"])
        XCTAssertEqual(group.hidden, true)
        XCTAssertEqual(
            group.metadata,
            [
                "type": .string("Selector"),
                "now": .string("节点一"),
                "all": .array([.string("节点一"), .string("DIRECT")]),
                "alive": .bool(true),
                "history": .array([
                    .object([
                        "time": .string("2026-09-02T12:00:00Z"),
                        "delay": .number(47),
                        "mean-delay": .string("51"),
                        "detail": .object([
                            "samples": .array([.number(1), .bool(true), .null]),
                        ]),
                    ]),
                ]),
                "icon": .string("https://controller.example/icon.png"),
                "tester": .string("https://controller.example/generate_204"),
                "provider-name": .string("机场 A"),
                "fixed": .string("节点一"),
                "interface": .string("utun7"),
                "udp": .bool(true),
                "uot": .bool(false),
                "xudp": .bool(true),
                "tfo": .bool(false),
                "mptcp": .bool(true),
                "smux": .bool(false),
                "hidden": .bool(true),
                "unknown-object": .object([
                    "nested": .array([
                        .number(1),
                        .bool(true),
                        .null,
                        .object(["name": .string("值")]),
                    ]),
                ]),
                "unknown-number": .number(42),
                "unknown-bool": .bool(false),
                "unknown-null": .null,
            ]
        )
    }

    func testSpecializedProxyDecodePreservesTestURLPrecedenceAndLegacyFallback() throws {
        let data = Data(#"""
        {
          "proxies": {
            "Preferred": {
              "testUrl": "https://controller.example/preferred",
              "tester": "https://controller.example/legacy"
            },
            "Legacy": {
              "tester": "https://controller.example/legacy-only"
            },
            "Null Preferred": {
              "testUrl": null,
              "tester": "https://controller.example/null-fallback"
            }
          }
        }
        """#.utf8)

        let response = try ProxiesResponse.decodePreservingProxyOrder(from: data)

        XCTAssertEqual(
            response.proxies["Preferred"]?.testURL,
            "https://controller.example/preferred"
        )
        XCTAssertEqual(
            response.proxies["Legacy"]?.testURL,
            "https://controller.example/legacy-only"
        )
        XCTAssertEqual(
            response.proxies["Null Preferred"]?.testURL,
            "https://controller.example/null-fallback"
        )
        XCTAssertEqual(
            response.proxies["Preferred"]?.metadata["tester"],
            .string("https://controller.example/legacy")
        )
        XCTAssertEqual(
            response.proxies["Null Preferred"]?.metadata["testUrl"],
            .null
        )
    }

    func testSpecializedProxyDecodeRetainsPermissiveKnownFieldFallbacks() throws {
        let data = Data(#"""
        {
          "proxies": {
            "Mixed": {
              "type": 7,
              "now": false,
              "all": ["Node", 9, true, null],
              "alive": 1,
              "history": [
                null,
                { "delay": "42", "meanDelay": 5.4 },
                "ignored"
              ],
              "udp": 0
            }
          }
        }
        """#.utf8)

        let proxy = try XCTUnwrap(
            ProxiesResponse.decodePreservingProxyOrder(from: data).proxies["Mixed"]
        )

        XCTAssertEqual(proxy.type, "Proxy")
        XCTAssertNil(proxy.now)
        XCTAssertEqual(proxy.all, ["Node"])
        XCTAssertNil(proxy.alive)
        XCTAssertEqual(
            proxy.history,
            [ProxyDelayHistorySnapshot(delay: 42, meanDelay: 5)]
        )
        XCTAssertNil(proxy.udp)
        XCTAssertEqual(proxy.metadata["type"], .number(7))
        XCTAssertEqual(proxy.metadata["now"], .bool(false))
        XCTAssertEqual(
            proxy.metadata["all"],
            .array([.string("Node"), .number(9), .bool(true), .null])
        )
        XCTAssertEqual(proxy.metadata["alive"], .number(1))
        XCTAssertEqual(proxy.metadata["udp"], .number(0))

        XCTAssertThrowsError(
            try ProxiesResponse.decodePreservingProxyOrder(
                from: Data(#"{"proxies":{"Broken":{"type":"Direct"}"#.utf8)
            )
        )
    }

    func testMemoryDecodesAggregateFields() throws {
        let data = Data("""
        {
          "inuse": 24576,
          "oslimit": 1048576
        }
        """.utf8)

        let response = try JSONDecoder().decode(MemoryResponse.self, from: data)

        XCTAssertEqual(response.inuse, 24576)
        XCTAssertEqual(response.oslimit, 1048576)
    }

    func testStructuredLogPreservesControllerFieldsAndLegacyProjection() throws {
        let data = Data(#"""
        {
          "time": "12:34:56",
          "level": "warning",
          "message": "connection retry",
          "fields": ["host", "attempt=2"]
        }
        """#.utf8)

        let response = try JSONDecoder().decode(LogMessage.self, from: data)

        XCTAssertEqual(response.type, "warning")
        XCTAssertEqual(response.payload, "connection retry")
        XCTAssertEqual(response.time, "12:34:56")
        XCTAssertEqual(response.level, "warning")
        XCTAssertEqual(response.message, "connection retry")
        XCTAssertEqual(response.fields, .array([.string("host"), .string("attempt=2")]))
    }

    func testLegacyLogShapeStillDecodes() throws {
        let data = Data(#"{"type":"info","payload":"ready"}"#.utf8)

        let response = try JSONDecoder().decode(LogMessage.self, from: data)

        XCTAssertEqual(response.type, "info")
        XCTAssertEqual(response.payload, "ready")
        XCTAssertNil(response.time)
        XCTAssertNil(response.fields)
    }

    func testGroupDelayDecodesOfficialTopLevelNodeMap() throws {
        let data = Data("""
        {
          "JP-01": 42,
          "US-02": 0
        }
        """.utf8)

        let response = try JSONDecoder().decode(GroupDelayResponse.self, from: data)

        XCTAssertEqual(response.delay, ["JP-01": 42, "US-02": 0])
        XCTAssertNil(response.delay["Missing Node"])
    }

    func testGroupDelayRejectsWrappedOrNonIntegerValues() {
        let wrapped = Data(#"{"delay":{"JP-01":42}}"#.utf8)
        let invalidValue = Data(#"{"JP-01":"timeout"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(GroupDelayResponse.self, from: wrapped))
        XCTAssertThrowsError(try JSONDecoder().decode(GroupDelayResponse.self, from: invalidValue))
    }

    func testRulesPreserveIndexMutableExtraCountersTimestampsAndUnknownFields() throws {
        let data = Data(#"""
        {
          "rules": [
            {
              "index": 7,
              "type": "DOMAIN-SUFFIX",
              "payload": "example.com",
              "proxy": "Proxy",
              "size": -1,
              "provider": "remote-rules",
              "extra": {
                "disabled": true,
                "hitCount": 12,
                "hitAt": "2026-07-18T10:00:00Z",
                "missCount": 3,
                "missAt": "2026-07-18T09:59:00Z",
                "custom": "controller-value"
              }
            }
          ]
        }
        """#.utf8)

        let response = try JSONDecoder().decode(RulesResponse.self, from: data)
        let rule = try XCTUnwrap(response.rules.first)

        XCTAssertEqual(rule.index, 7)
        XCTAssertEqual(rule.size, -1)
        XCTAssertEqual(rule.disabled, true)
        XCTAssertEqual(rule.hitCount, 12)
        XCTAssertEqual(rule.hitAt, "2026-07-18T10:00:00Z")
        XCTAssertEqual(rule.missCount, 3)
        XCTAssertEqual(rule.missAt, "2026-07-18T09:59:00Z")
        XCTAssertTrue(rule.hasMutableExtra)
        XCTAssertEqual(rule.extra?.metadata["custom"], .string("controller-value"))
        XCTAssertEqual(rule.additionalMetadata["provider"], .string("remote-rules"))
    }

    func testRuleDisableUsesOfficialPatchEndpoint() throws {
        let endpoint = MihomoEndpoint.setRuleDisabled()
        let baseURL = try XCTUnwrap(URL(string: "http://controller.example:9090"))

        XCTAssertEqual(endpoint.method, .patch)
        XCTAssertEqual(endpoint.pathDescription, "/rules/disable")
        XCTAssertEqual(
            try endpoint.url(relativeTo: baseURL).absoluteString,
            "http://controller.example:9090/rules/disable"
        )
    }

    func testConnectionsPreserveCompleteControllerFields() throws {
        let data = Data("""
        {
          "uploadTotal": 4096,
          "downloadTotal": 8192,
          "memory": 1048576,
          "connections": [
            {
              "id": "connection-visible-id",
              "upload": { "total": 1024 },
              "download": 2048,
              "uploadSpeed": 128,
              "download-speed": 256,
              "start": "2026-06-30T06:00:00Z",
              "chains": ["Proxy"],
              "providerChains": ["Remote Nodes", "Fallback"],
              "rule": "MATCH",
              "rulePayload": "sensitive.example",
              "controller-note": { "source": "mihomo" },
              "metadata": {
                "network": "tcp",
                "type": "HTTP",
                "host": "sensitive.example",
                "sourceIP": "198.51.100.8",
                "destinationIP": "203.0.113.1",
                "sourcePort": 53124,
                "destinationPort": "443",
                "process": "Safari",
                "processPath": "/Applications/Safari.app/Contents/MacOS/Safari",
                "inboundName": "mixed",
                "dnsMode": "normal",
                "sniffHost": "sni.example",
                "specialProxy": "DIRECT",
                "specialRules": "PROCESS-NAME",
                "remoteDestination": "remote.example:443",
                "log": ["opened", 2, true],
                "uid": "501",
                "controller-field": { "routing-mark": 255 }
              }
            }
          ]
        }
        """.utf8)

        let response = try JSONDecoder().decode(ConnectionsResponse.self, from: data)
        let connection = try XCTUnwrap(response.connections.first)

        XCTAssertEqual(response.uploadTotal, 4096)
        XCTAssertEqual(response.downloadTotal, 8192)
        XCTAssertEqual(response.memory, 1048576)
        XCTAssertEqual(connection.upload, 1024)
        XCTAssertEqual(connection.download, 2048)
        XCTAssertEqual(connection.uploadSpeed, 128)
        XCTAssertEqual(connection.downloadSpeed, 256)
        XCTAssertEqual(connection.start, "2026-06-30T06:00:00Z")
        XCTAssertEqual(connection.providerChains, ["Remote Nodes", "Fallback"])
        XCTAssertEqual(connection.metadata?.network, "tcp")
        XCTAssertEqual(connection.metadata?.type, "HTTP")
        XCTAssertEqual(connection.metadata?.host, "sensitive.example")
        XCTAssertEqual(connection.metadata?.sourceIP, "198.51.100.8")
        XCTAssertEqual(connection.metadata?.destinationIP, "203.0.113.1")
        XCTAssertEqual(connection.metadata?.sourcePort, "53124")
        XCTAssertEqual(connection.metadata?.destinationPort, "443")
        XCTAssertEqual(connection.metadata?.process, "Safari")
        XCTAssertEqual(connection.metadata?.processPath, "/Applications/Safari.app/Contents/MacOS/Safari")
        XCTAssertEqual(connection.metadata?.inboundName, "mixed")
        XCTAssertEqual(connection.metadata?.dnsMode, "normal")
        XCTAssertEqual(connection.metadata?.sniffHost, "sni.example")
        XCTAssertEqual(connection.metadata?.specialProxy, "DIRECT")
        XCTAssertEqual(connection.metadata?.specialRules, "PROCESS-NAME")
        XCTAssertEqual(connection.metadata?.remoteDestination, "remote.example:443")
        XCTAssertEqual(connection.metadata?.connectionLogs, ["opened", "2", "true"])
        XCTAssertEqual(connection.metadata?.uid, 501)
        XCTAssertEqual(
            connection.metadata?.additionalFields["controller-field"],
            .object(["routing-mark": .number(255)])
        )
        XCTAssertEqual(
            connection.additionalFields["controller-note"],
            .object(["source": .string("mihomo")])
        )
    }

    func testCoreLifecycleEndpointsUseRemoteControllerAPI() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://controller.example:9090"))

        XCTAssertEqual(MihomoEndpoint.restart.method, .post)
        XCTAssertEqual(MihomoEndpoint.restart.pathDescription, "/restart")
        XCTAssertEqual(try MihomoEndpoint.restart.url(relativeTo: baseURL).absoluteString, "http://controller.example:9090/restart")

        let upgrade = MihomoEndpoint.upgradeCore(channel: "alpha", force: true)
        XCTAssertEqual(upgrade.method, .post)
        XCTAssertEqual(upgrade.pathDescription, "/upgrade")

        let components = try XCTUnwrap(URLComponents(url: upgrade.url(relativeTo: baseURL), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/upgrade")
        XCTAssertEqual(components.queryItems?.contains(URLQueryItem(name: "channel", value: "alpha")), true)
        XCTAssertEqual(components.queryItems?.contains(URLQueryItem(name: "force", value: "true")), true)
    }

    func testStructuredLogEndpointCarriesUpstreamLevel() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://controller.example:9090"))
        let endpoint = MihomoEndpoint.logsEndpoint(level: "debug", structured: true)
        let components = try XCTUnwrap(
            URLComponents(url: endpoint.url(relativeTo: baseURL), resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(components.path, "/logs")
        XCTAssertEqual(components.queryItems?.contains(URLQueryItem(name: "level", value: "debug")), true)
        XCTAssertEqual(components.queryItems?.contains(URLQueryItem(name: "format", value: "structured")), true)
    }

    func testRuleProviderEndpointsUseRemoteControllerAPI() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://controller.example:9090"))

        XCTAssertEqual(MihomoEndpoint.ruleProviders.method, .get)
        XCTAssertEqual(MihomoEndpoint.ruleProviders.pathDescription, "/providers/rules")
        XCTAssertEqual(try MihomoEndpoint.ruleProviders.url(relativeTo: baseURL).absoluteString, "http://controller.example:9090/providers/rules")

        let update = MihomoEndpoint.updateRuleProvider(name: "privacy-rules")
        XCTAssertEqual(update.method, .put)
        XCTAssertEqual(update.pathDescription, "/providers/rules/privacy-rules")
        XCTAssertEqual(try update.url(relativeTo: baseURL).absoluteString, "http://controller.example:9090/providers/rules/privacy-rules")
    }

    func testProxyProviderHealthCheckUsesOfficialRemoteEndpoint() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://controller.example:9090"))
        let endpoint = MihomoEndpoint.healthCheckProxyProvider(name: "Airport A")

        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.pathDescription, "/providers/proxies/Airport A/healthcheck")
        XCTAssertEqual(
            try endpoint.url(relativeTo: baseURL).absoluteString,
            "http://controller.example:9090/providers/proxies/Airport%20A/healthcheck"
        )
    }

    func testRuleProvidersDecodeAggregateSnapshotsWithoutRetainingRules() throws {
        let data = Data("""
        {
          "providers": {
            "privacy-rules": {
              "type": "Rule",
              "behavior": "domain",
              "format": "mrs",
              "vehicleType": "HTTP",
              "updatedAt": "2026-06-30T06:00:00Z",
              "updatable": false,
              "healthCheck": { "enable": true, "url": "https://cp.cloudflare.com" },
              "rules": [
                { "type": "DOMAIN-SUFFIX", "payload": "sensitive.example", "proxy": "Proxy" },
                { "type": "DOMAIN", "payload": "private.example", "proxy": "DIRECT" }
              ]
            },
            "geo-rules": {
              "name": "geo-rules",
              "type": "Rule",
              "behavior": "classical",
              "vehicleType": "File",
              "rule-count": 42
            }
          }
        }
        """.utf8)

        let response = try RuleProvidersResponse.decodePreservingProviderOrder(from: data)

        XCTAssertEqual(response.providerList.map(\.name), ["privacy-rules", "geo-rules"])
        XCTAssertEqual(response.providers["privacy-rules"]?.behavior, "domain")
        XCTAssertEqual(response.providers["privacy-rules"]?.format, "mrs")
        XCTAssertEqual(response.providers["privacy-rules"]?.vehicleType, "HTTP")
        XCTAssertEqual(response.providers["privacy-rules"]?.updatedAt, "2026-06-30T06:00:00Z")
        XCTAssertEqual(response.providers["privacy-rules"]?.updatable, false)
        XCTAssertEqual(
            response.providers["privacy-rules"]?.healthCheck,
            .object(["enable": .bool(true), "url": .string("https://cp.cloudflare.com")])
        )
        XCTAssertEqual(response.providers["privacy-rules"]?.ruleCount, 2)
        XCTAssertEqual(response.providers["geo-rules"]?.updatable, false)
        XCTAssertEqual(response.providers["geo-rules"]?.ruleCount, 42)
    }

    func testProxyProvidersPreserveUpdateAndHealthMetadata() throws {
        let data = Data("""
        {
          "providers": {
            "remote-nodes": {
              "type": "Proxy",
              "vehicleType": "HTTP",
              "format": "yaml",
              "testUrl": "https://www.gstatic.com/generate_204",
              "updatedAt": "2026-07-18T08:00:00Z",
              "healthCheck": { "enable": true, "interval": 300 },
              "subscriptionInfo": { "total": 1073741824 },
              "proxies": [{ "name": "Node A", "type": "Shadowsocks" }]
            },
            "local-nodes": {
              "type": "Proxy",
              "vehicleType": "File",
              "updatable": true,
              "proxies": []
            }
          }
        }
        """.utf8)

        let response = try ProxyProvidersResponse.decodePreservingProviderOrder(from: data)
        let remote = try XCTUnwrap(response.providers["remote-nodes"])
        let local = try XCTUnwrap(response.providers["local-nodes"])

        XCTAssertEqual(response.providerList.map(\.name), ["remote-nodes", "local-nodes"])
        XCTAssertEqual(remote.format, "yaml")
        XCTAssertEqual(remote.testURL, "https://www.gstatic.com/generate_204")
        XCTAssertEqual(remote.updatedAt, "2026-07-18T08:00:00Z")
        XCTAssertEqual(remote.updatable, true)
        XCTAssertEqual(remote.healthCheck, .object(["enable": .bool(true), "interval": .number(300)]))
        XCTAssertEqual(remote.subscriptionInfo, .object(["total": .number(1_073_741_824)]))
        XCTAssertEqual(remote.proxyCount, 1)
        XCTAssertEqual(local.updatable, true)
    }
}
