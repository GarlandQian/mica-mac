import Testing
@testable import Mica

struct XCStringsResolverTests {
    @Test func localizationContextMatchesDirectLookupAndKeepsItsResolvedLanguage() {
        let english = MicaStrings.localizationContext(for: .english)
        let simplifiedChinese = MicaStrings.localizationContext(for: .simplifiedChinese)
        let keys = [
            "traffic.connection_host",
            "traffic.log_received_time",
            "dashboard.col_status",
            "traffic.source_section_configuration",
            "endpoint.active_count %lld",
            "missing.accessibility.summary.key",
        ]

        for key in keys {
            #expect(
                english.localizedKey(key)
                    == MicaStrings.localizedKey(key, language: .english)
            )
            #expect(
                simplifiedChinese.localizedKey(key)
                    == MicaStrings.localizedKey(key, language: .simplifiedChinese)
            )
        }

        #expect(english.localizedKey("dashboard.col_status") == "STATUS")
        #expect(simplifiedChinese.localizedKey("dashboard.col_status") == "状态")
        #expect(
            english.localized(
                "routing.available_nodes_count %lld %lld",
                arguments: ["2", "3"]
            ) == "2 of 3 available"
        )
        #expect(
            simplifiedChinese.localized(
                "routing.available_nodes_count %lld %lld",
                arguments: ["2", "3"]
            ) == "可用 2 / 3"
        )
        #expect(
            english.localizedKey("missing.accessibility.summary.key")
                == "missing.accessibility.summary.key"
        )
    }

    @Test func diagnosticLabelsNeverExposeFormatTokens() {
        let keys = [
            "diagnostics.active_controller",
            "diagnostics.controller_health",
            "diagnostics.last_connected",
            "diagnostics.mode",
            "diagnostics.version",
            "diagnostics.capability_operations",
        ]

        for language in [AppLanguage.english, .simplifiedChinese] {
            for key in keys {
                let value = MicaStrings.localizedKey(key, language: language)
                #expect(!value.contains("%"))
                #expect(value != key)
            }
        }
    }

    @Test func staticPolicyCommandDoesNotRequireInterpolationArguments() {
        #expect(
            MicaStrings.localizedKey(
                "dashboard.switch_node",
                language: .english
            ) == "Switch Node"
        )
        #expect(
            MicaStrings.localizedKey(
                "dashboard.switch_node",
                language: .simplifiedChinese
            ) == "切换节点"
        )
    }

    @Test func dynamicKeyLookupNeverLeaksUnresolvedFormatSpecifiers() {
        for language in [AppLanguage.english, .simplifiedChinese] {
            for key in [
                "diagnostics.active_controller %@",
                "endpoint.active_count %lld",
                "log.loaded_policy_groups %lld %@",
            ] {
                let value = MicaStrings.localizedKey(key, language: language)
                #expect(!value.contains("%@"))
                #expect(!value.contains("%lld"))
                #expect(!value.contains("%d"))
            }
        }
    }

    @Test func diagnosticStringAndIntegerArgumentsResolveThroughExactCatalogKeys() {
        let controllerName = "Local Bettbox"
        let groupCount = 7

        #expect(
            MicaStrings.localized(
                "diagnostics.active_controller \(controllerName)",
                language: .english
            ) == "Active Controller: Local Bettbox"
        )
        #expect(
            MicaStrings.localized(
                "diagnostics.active_controller \(controllerName)",
                language: .simplifiedChinese
            ) == "当前控制器：Local Bettbox"
        )
        #expect(
            MicaStrings.localized(
                "diagnostics.policy_groups \(groupCount)",
                language: .english
            ) == "Policy Groups: 7"
        )
        #expect(
            MicaStrings.localized(
                "diagnostics.policy_groups \(groupCount)",
                language: .simplifiedChinese
            ) == "策略组：7"
        )
    }

    @Test func localizedTemplatesCanReorderArgumentsExplicitly() {
        let groupCount = 7
        let source = "remote"

        #expect(
            MicaStrings.localized(
                "log.loaded_policy_groups \(groupCount) \(source)",
                language: .english
            ) == "Loaded 7 policy groups from remote."
        )
        #expect(
            MicaStrings.localized(
                "log.loaded_policy_groups \(groupCount) \(source)",
                language: .simplifiedChinese
            ) == "已从 remote 加载 7 个策略组。"
        )
    }

    @Test func reorderedRenderedTextRelocalizesByArgumentPosition() {
        let chinese = XCStringsResolver.string(
            forKey: "log.loaded_policy_groups %lld %@",
            languageCode: "zh-Hans",
            stringArguments: ["7", "remote"]
        )

        #expect(chinese == "已从 remote 加载 7 个策略组。")
        #expect(
            XCStringsResolver.relocalizedText(
                chinese,
                languageCode: "en"
            ) == "Loaded 7 policy groups from remote."
        )
    }

    @Test func diagnosticMessageRelocalizesWithoutLeakingItsSemanticKey() {
        let english = XCStringsResolver.string(
            forKey: "diagnostics.active_controller %@",
            languageCode: "en",
            stringArguments: ["Local Bettbox"]
        )

        #expect(
            XCStringsResolver.relocalizedText(
                english,
                languageCode: "zh-Hans"
            ) == "当前控制器：Local Bettbox"
        )
    }

    @Test func exactRenderedTextRelocalizesThroughReverseIndex() {
        let chinese = XCStringsResolver.string(
            forKey: "settings.appearance",
            languageCode: "zh-Hans"
        )
        let english = XCStringsResolver.string(
            forKey: "settings.appearance",
            languageCode: "en"
        )

        #expect(XCStringsResolver.relocalizedText(chinese, languageCode: "en") == english)
    }

    @Test func interpolatedRenderedTextUsesPrecompiledTemplateMatcher() {
        let key = "endpoint.active_count %lld"
        let chinese = XCStringsResolver.string(
            forKey: key,
            languageCode: "zh-Hans",
            stringArguments: ["17"]
        )
        let english = XCStringsResolver.string(
            forKey: key,
            languageCode: "en",
            stringArguments: ["17"]
        )

        #expect(XCStringsResolver.relocalizedText(chinese, languageCode: "en") == english)
    }

    @Test func ambiguousRenderedTextIsNotRelocalizedToAnArbitraryMeaning() {
        #expect(
            XCStringsResolver.relocalizedText("Overview", languageCode: "zh-Hans")
                == "Overview"
        )
        #expect(
            XCStringsResolver.relocalizedText("17 active", languageCode: "zh-Hans")
                == "17 active"
        )
    }
}
