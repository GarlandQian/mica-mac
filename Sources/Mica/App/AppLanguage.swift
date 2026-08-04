import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    static func stored(_ rawValue: String?) -> AppLanguage {
        switch rawValue {
        case AppLanguage.english.rawValue, "english":
            .english
        case AppLanguage.simplifiedChinese.rawValue, "simplifiedChinese":
            .simplifiedChinese
        case AppLanguage.system.rawValue:
            .system
        default:
            .system
        }
    }

    var locale: Locale? {
        switch self {
        case .system:
            nil
        case .english:
            Locale(identifier: "en")
        case .simplifiedChinese:
            Locale(identifier: "zh-Hans")
        }
    }

    var resolvedLocale: Locale {
        locale ?? Self.systemLocale
    }

    var usesSystemLocale: Bool {
        locale == nil
    }

    static var systemLocale: Locale {
        for candidate in systemLocaleCandidates {
            if isSimplifiedChineseCandidate(candidate) {
                return Locale(identifier: AppLanguage.simplifiedChinese.rawValue)
            }

            if isEnglishCandidate(candidate) {
                return Locale(identifier: AppLanguage.english.rawValue)
            }
        }

        return Locale(identifier: AppLanguage.english.rawValue)
    }

    /// Standard AppKit menus use the localization selected for the executable
    /// bundle, which can differ from Mica's in-app content preference. Custom
    /// command groups must use the same language or the menu bar becomes mixed.
    static var menuBarLanguage: AppLanguage {
        let candidates = Bundle.main.preferredLocalizations
            + [Bundle.main.developmentLocalization].compactMap { $0 }

        for candidate in candidates {
            if isSimplifiedChineseCandidate(candidate) {
                return .simplifiedChinese
            }
            if isEnglishCandidate(candidate) {
                return .english
            }
        }

        return .english
    }

    private static var systemLocaleCandidates: [String] {
        var candidates = Locale.preferredLanguages
        if let appleLanguages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] {
            candidates.append(contentsOf: appleLanguages)
        }
        candidates.append(Locale.autoupdatingCurrent.identifier)
        candidates.append(Locale.current.identifier)

        if let autoupdatingLanguageCode = Locale.autoupdatingCurrent.language.languageCode?.identifier {
            candidates.append(autoupdatingLanguageCode)
        }

        if let currentLanguageCode = Locale.current.language.languageCode?.identifier {
            candidates.append(currentLanguageCode)
        }

        if let appleLocale = UserDefaults.standard.string(forKey: "AppleLocale") {
            candidates.append(appleLocale)
        }

        return candidates.reduce(into: []) { uniqueCandidates, candidate in
            let normalized = normalizeLocaleIdentifier(candidate)
            guard !normalized.isEmpty,
                  !uniqueCandidates.contains(where: { normalizeLocaleIdentifier($0) == normalized }) else {
                return
            }
            uniqueCandidates.append(candidate)
        }
    }

    private static func isSimplifiedChineseCandidate(_ identifier: String) -> Bool {
        let normalized = normalizeLocaleIdentifier(identifier)

        if normalized.hasPrefix("zh-hans")
            || normalized.hasPrefix("zh-cn")
            || normalized.hasPrefix("zh-sg")
            || normalized.hasPrefix("zh-")
            || normalized == "zh" {
            return true
        }

        return false
    }

    private static func isEnglishCandidate(_ identifier: String) -> Bool {
        let normalized = normalizeLocaleIdentifier(identifier)

        return normalized == "en" || normalized.hasPrefix("en-")
    }

    private static func normalizeLocaleIdentifier(_ identifier: String) -> String {
        identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    var titleKey: String {
        switch self {
        case .system:
            "settings.language_system"
        case .english:
            "settings.language_english"
        case .simplifiedChinese:
            "settings.language_simplified_chinese"
        }
    }

    var diagnosticsCode: String {
        switch self {
        case .system:
            "system"
        case .english:
            "en"
        case .simplifiedChinese:
            "zh-Hans"
        }
    }
}

enum MicaStrings {
    static var appLanguage: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        return AppLanguage.stored(rawValue)
    }

    static var locale: Locale {
        appLanguage.resolvedLocale
    }

    /// BCP-47 language code used to look up translations in the runtime
    /// `.xcstrings` catalog (e.g. "en", "zh-Hans"). Resolved from the user's
    /// language preference, never `nil`.
    static var resolvedLanguageCode: String {
        resolvedLanguageCode(for: appLanguage)
    }

    static func resolvedLanguageCode(for language: AppLanguage) -> String {
        switch language {
        case .english:
            AppLanguage.english.rawValue
        case .simplifiedChinese:
            AppLanguage.simplifiedChinese.rawValue
        case .system:
            normalizedLanguageCode(from: AppLanguage.systemLocale.identifier)
        }
    }

    private static func normalizedLanguageCode(from identifier: String) -> String {
        let normalized = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized.hasPrefix("zh") {
            return AppLanguage.simplifiedChinese.rawValue
        }

        return AppLanguage.english.rawValue
    }

    static func localized(_ key: String.LocalizationValue) -> String {
        localized(key, language: appLanguage)
    }

    static func localized(_ key: String.LocalizationValue, language: AppLanguage) -> String {
        let languageCode = resolvedLanguageCode(for: language)

        // Under SwiftPM, `Localizable.xcstrings` ships as a single JSON
        // document rather than compiled `.lproj` tables, so `Bundle.module`
        // only reports the source language (`en`). `String(localized:bundle:
        // locale:)` therefore cannot reach `zh-Hans` regardless of the
        // `locale:` argument. To honor the user's language preference, extract
        // the semantic catalog key (e.g. `operation.loaded_routers %lld`) and
        // its already-formatted arguments from the `String.LocalizationValue`
        // and resolve through the runtime string-catalog resolver — the same
        // reliable path used by dynamic-key lookups.
        let (catalogKey, stringArguments) = decompose(key)
        return XCStringsResolver.string(
            forKey: catalogKey,
            languageCode: languageCode,
            stringArguments: stringArguments
        )
    }

    /// Extracts the semantic key and pre-stringified positional arguments from
    /// a `String.LocalizationValue`. The standard library stores the format
    /// key (with `%@`/`%lld` specifiers intact) and the interpolated arguments
    /// separately; reflection is the only way to recover them without a public
    /// API. Falls back to the interpolated description if the internal layout
    /// ever changes.
    private static func decompose(_ value: String.LocalizationValue) -> (key: String, arguments: [String]) {
        var key: String?
        var arguments: [String] = []

        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            switch child.label {
            case "key":
                key = child.value as? String
            case "arguments":
                for argument in Mirror(reflecting: child.value).children {
                    // Each element is a `FormatArgument` wrapping a `Storage`
                    // enum; descend one more level to the associated value.
                    for storage in Mirror(reflecting: argument.value).children {
                        for associated in Mirror(reflecting: storage.value).children {
                            arguments.append(String(describing: associated.value))
                        }
                    }
                }
            default:
                break
            }
        }

        guard let key else {
            return (String(describing: value), [])
        }

        return (key, arguments)
    }

    static func localizedKey(_ key: String) -> String {
        localizedKey(key, language: appLanguage)
    }

    static func localizedKey(_ key: String, language: AppLanguage) -> String {
        let languageCode = resolvedLanguageCode(for: language)
        return XCStringsResolver.string(forKey: key, languageCode: languageCode)
    }

    static func relocalizedText(_ text: String) -> String {
        relocalizedText(text, language: appLanguage)
    }

    static func relocalizedText(_ text: String, language: AppLanguage) -> String {
        XCStringsResolver.relocalizedText(
            text,
            languageCode: resolvedLanguageCode(for: language)
        )
    }

    static func displayMode(_ mode: String) -> String {
        displayMode(mode, language: appLanguage)
    }

    static func displayMode(_ mode: String, language: AppLanguage) -> String {
        switch mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "rule", "规则":
            localized("mode.rule", language: language)
        case "global", "全局":
            localized("mode.global", language: language)
        case "direct", "直连":
            localized("mode.direct", language: language)
        case "unknown", "未知", "":
            localized("mode.unknown", language: language)
        case "not loaded", "未加载":
            localized("mode.not_loaded", language: language)
        default:
            localized("mode.custom \(mode)", language: language)
        }
    }

    static func displayRuleType(_ type: String) -> String {
        displayRuleType(type, language: appLanguage)
    }

    static func displayRuleType(_ type: String, language: AppLanguage) -> String {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "MATCH":
            localized("rule_type.match", language: language)
        case "DOMAIN":
            localized("rule_type.domain", language: language)
        case "DOMAIN-SUFFIX":
            localized("rule_type.domain_suffix", language: language)
        case "DOMAIN-KEYWORD":
            localized("rule_type.domain_keyword", language: language)
        case "GEOIP":
            localized("rule_type.geoip", language: language)
        case "IP-CIDR":
            localized("rule_type.ip_cidr", language: language)
        case "IP-CIDR6":
            localized("rule_type.ip_cidr6", language: language)
        case "SRC-IP-CIDR":
            localized("rule_type.src_ip_cidr", language: language)
        case "DST-PORT":
            localized("rule_type.dst_port", language: language)
        case "SRC-PORT":
            localized("rule_type.src_port", language: language)
        case "PROCESS-NAME":
            localized("rule_type.process_name", language: language)
        case "RULE-SET":
            localized("rule_type.rule_set", language: language)
        case "URL-REGEX":
            localized("rule_type.url_regex", language: language)
        case "FINAL":
            localized("rule_type.final", language: language)
        case "REJECT":
            localized("rule_type.reject", language: language)
        case "DIRECT":
            localized("mode.direct", language: language)
        case "RULE", "":
            localized("rule_type.rule", language: language)
        case "UNKNOWN":
            localized("mode.unknown", language: language)
        default:
            localized("rule_type.other \(type)", language: language)
        }
    }

    static func displayRuleProxyTarget(_ proxy: String?) -> String {
        displayRuleProxyTarget(proxy, language: appLanguage)
    }

    static func displayRuleProxyTarget(_ proxy: String?, language: AppLanguage) -> String {
        guard let proxy else {
            return localized("overview.config_not_reported", language: language)
        }

        let trimmed = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return localized("overview.config_not_reported", language: language)
        }

        switch trimmed.uppercased() {
        case "DIRECT":
            return localized("mode.direct", language: language)
        case "GLOBAL":
            return localized("mode.global", language: language)
        case "REJECT", "REJECT-DROP":
            return localized("rule_type.reject", language: language)
        case "PASS":
            return localized("rule_type.rule", language: language)
        default:
            return trimmed
        }
    }

    static func displayEndpointDetail(_ detail: String) -> String {
        displayEndpointDetail(detail, language: appLanguage)
    }

    static func displayEndpointDetail(_ detail: String, language: AppLanguage) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        switch lowered {
        case "ok", "正常":
            return localized("endpoint.ok", language: language)
        case "idle", "空闲":
            return localized("endpoint.idle", language: language)
        case "not checked", "未检查":
            return localized("endpoint.not_checked", language: language)
        case "probe pending", "探测待完成":
            return localized("endpoint.probe_pending", language: language)
        case "ready", "就绪":
            return localized("endpoint.ready", language: language)
        case "checking", "检查中":
            return localized("endpoint.checking", language: language)
        case "failed", "失败":
            return localized("endpoint.failed", language: language)
        default:
            break
        }

        if let count = integerPrefix(in: lowered, suffix: " groups") {
            return localized("endpoint.groups_count \(count)", language: language)
        }

        if let count = integerPrefix(in: trimmed, suffix: " 个组")
            ?? integerPrefix(in: trimmed, suffix: "个组") {
            return localized("endpoint.groups_count \(count)", language: language)
        }

        if let count = integerPrefix(in: lowered, suffix: " active") {
            return localized("endpoint.active_count \(count)", language: language)
        }

        if let count = integerPrefix(in: trimmed, suffix: " 个活动")
            ?? integerPrefix(in: trimmed, suffix: "个活动") {
            return localized("endpoint.active_count \(count)", language: language)
        }

        if let count = integerPrefix(in: lowered, suffix: " rules") {
            return localized("endpoint.rules_count \(count)", language: language)
        }

        if let count = integerPrefix(in: trimmed, suffix: " 条规则")
            ?? integerPrefix(in: trimmed, suffix: "条规则") {
            return localized("endpoint.rules_count \(count)", language: language)
        }

        if let count = integerPrefix(in: lowered, suffix: " providers") {
            return localized("endpoint.providers_count \(count)", language: language)
        }

        if let count = integerPrefix(in: trimmed, suffix: " 个来源")
            ?? integerPrefix(in: trimmed, suffix: "个来源")
            ?? integerPrefix(in: trimmed, suffix: " 个提供器")
            ?? integerPrefix(in: trimmed, suffix: "个提供器") {
            return localized("endpoint.providers_count \(count)", language: language)
        }

        if let count = integerPrefix(in: lowered, suffix: " policies") {
            return localized("endpoint.policies_count \(count)", language: language)
        }

        if let count = integerPrefix(in: trimmed, suffix: " 个策略")
            ?? integerPrefix(in: trimmed, suffix: "个策略") {
            return localized("endpoint.policies_count \(count)", language: language)
        }

        let relocalized = relocalizedText(trimmed)
        if language == appLanguage {
            return relocalized == trimmed ? trimmed : relocalized
        }

        let relocalizedForLanguage = relocalizedText(trimmed, language: language)
        return relocalizedForLanguage == trimmed ? trimmed : relocalizedForLanguage
    }

    static func displayTrafficMetric(_ label: String) -> String {
        displayTrafficMetric(label, language: appLanguage)
    }

    static func displayTrafficMetric(_ label: String, language: AppLanguage) -> String {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "upload":
            localized("dashboard.upload", language: language)
        case "download":
            localized("dashboard.download", language: language)
        default:
            displayRuleType(label, language: language)
        }
    }

    static func displayLogType(_ type: String) -> String {
        displayLogType(type, language: appLanguage)
    }

    static func displayLogType(_ type: String, language: AppLanguage) -> String {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "info", "information":
            localized("log_type.info", language: language)
        case "warning", "warn":
            localized("log_type.warning", language: language)
        case "error", "err":
            localized("log_type.error", language: language)
        case "debug":
            localized("log_type.debug", language: language)
        case "trace":
            localized("log_type.trace", language: language)
        default:
            localized("log_type.other \(type)", language: language)
        }
    }

    private static func integerPrefix(in value: String, suffix: String) -> Int? {
        guard value.hasSuffix(suffix) else {
            return nil
        }

        return Int(value.dropLast(suffix.count).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
