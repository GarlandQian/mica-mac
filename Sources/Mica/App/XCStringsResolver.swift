import Foundation

/// Runtime resolver for Mica's string catalog across SwiftPM and Xcode
/// resource layouts.
///
/// Under Swift Package Manager builds, `Localizable.xcstrings` is copied into
/// `Bundle.module` as a single JSON document rather than being compiled into
/// per-language `.lproj` directories. Xcode builds compile the same catalog
/// into `en.lproj` / `zh-Hans.lproj` `Localizable.strings` files instead. This
/// resolver merges both shapes when available and returns the string for the
/// requested language code, falling back to the source language (`en`) and then
/// the key itself.
enum XCStringsResolver {
    /// Languages tried, in order, when a key has no entry for the requested
    /// language. The source language is the final fallback before the key.
    static let sourceLanguage = "en"

    /// Languages with compiled `.lproj/Localizable.strings` tables in the
    /// Xcode-built resource bundle. The raw `.xcstrings` path can still carry
    /// additional languages if the catalog grows later.
    private static let compiledLanguageCodes = [sourceLanguage, "zh-Hans"]

    /// Cached decoded catalog. Available compiled `.strings` tables and the
    /// raw `.xcstrings` document are loaded once and reused; language switches
    /// do not require a reload because all languages are merged into the same
    /// in-memory catalog.
    private struct Catalog {
        let strings: [String: [String: String]]
        let exactKeyByRenderedText: [String: String]
        let templateMatchers: [TemplateMatcher]
    }

    private struct TemplateMatcher: @unchecked Sendable {
        let key: String
        let regex: NSRegularExpression
        let captureArgumentPositions: [Int]
        let literalCharacterCount: Int

        func arguments(in text: String) -> [String]? {
            guard let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
            ), match.numberOfRanges == captureArgumentPositions.count + 1,
               let maximumPosition = captureArgumentPositions.max() else {
                return nil
            }

            var arguments = Array<String?>(
                repeating: nil,
                count: maximumPosition + 1
            )
            for rangeIndex in 1..<match.numberOfRanges {
                guard let range = Range(match.range(at: rangeIndex), in: text) else {
                    return nil
                }
                let value = String(text[range])
                let argumentPosition = captureArgumentPositions[rangeIndex - 1]
                if let existing = arguments[argumentPosition], existing != value {
                    return nil
                }
                arguments[argumentPosition] = value
            }

            guard arguments.allSatisfy({ $0 != nil }) else {
                return nil
            }
            return arguments.compactMap { $0 }
        }
    }

    private static let catalog: Catalog = loadCatalog()
    private static let unresolvedFormatSpecifierRegex = try? NSRegularExpression(
        pattern: #"%(?:\d+\$)?[-+#0 ']*\d*(?:\.\d+)?(?:hh|h|ll|l|L|z|j|t|q)?[@dDuUxXoifeEgGsScp]"#
    )

    /// Returns the localized string for `key` in `languageCode` (e.g. "en",
    /// "zh-Hans"). Interpolation arguments are substituted into the format
    /// template after lookup, mirroring `String(localized:)` for the positional
    /// `%@`/`%d` placeholders used by Mica's string catalog.
    static func string(
        forKey key: String,
        languageCode: String,
        arguments: [CVarArg] = []
    ) -> String {
        let resolved = resolvedTemplate(forKey: key, languageCode: languageCode)

        if resolved == key,
           arguments.isEmpty,
           let looseResolution = looseInterpolatedResolution(forKey: key, languageCode: languageCode) {
            return substituteFormatSpecifiers(looseResolution.template, arguments: looseResolution.arguments)
        }

        guard !arguments.isEmpty else {
            return removingUnresolvedFormatSpecifiers(resolved)
        }

        return format(resolved, arguments: arguments)
    }

    /// Resolves a template string (before argument substitution) for `key`.
    /// Exposed so callers that perform their own formatting can reuse the
    /// same fallback chain.
    static func template(forKey key: String, languageCode: String) -> String {
        resolvedTemplate(forKey: key, languageCode: languageCode)
    }

    /// Returns the localized string for `key` in `languageCode`, substituting
    /// pre-stringified positional arguments into the format template. Used by
    /// the `String.LocalizationValue` bridge, which extracts the semantic key
    /// (e.g. `operation.loaded_routers %lld`) and its already-formatted
    /// arguments (e.g. `["7"]`) via reflection. Format specifiers (`%@`,
    /// `%lld`, `%d`, `%1$@`, …) are replaced positionally with the provided
    /// string values, mirroring `String(localized:)` for Mica's catalog.
    static func string(
        forKey key: String,
        languageCode: String,
        stringArguments: [String]
    ) -> String {
        let resolved = resolvedTemplate(forKey: key, languageCode: languageCode)
        if resolved == key,
           let looseResolution = looseInterpolatedResolution(forKey: key, languageCode: languageCode) {
            let arguments = stringArguments.isEmpty ? looseResolution.arguments : stringArguments
            return substituteFormatSpecifiers(looseResolution.template, arguments: arguments)
        }

        guard !stringArguments.isEmpty else {
            return removingUnresolvedFormatSpecifiers(resolved)
        }

        return substituteFormatSpecifiers(resolved, arguments: stringArguments)
    }

    /// Re-resolves a previously rendered localized string into `languageCode`.
    /// This is used for short-lived presentation state that was intentionally
    /// stored as concrete `String`s (operation banners, endpoint details, and
    /// snapshot messages) before the user switched the app language.
    static func relocalizedText(_ text: String, languageCode: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return text
        }

        if let key = catalog.exactKeyByRenderedText[trimmed] {
            return resolvedTemplate(forKey: key, languageCode: languageCode)
        }

        for matcher in catalog.templateMatchers {
            guard let arguments = matcher.arguments(in: trimmed) else { continue }
            let targetTemplate = resolvedTemplate(forKey: matcher.key, languageCode: languageCode)
            return substituteFormatSpecifiers(targetTemplate, arguments: arguments)
        }

        if let looseResolution = looseInterpolatedResolution(forKey: trimmed, languageCode: languageCode) {
            return substituteFormatSpecifiers(looseResolution.template, arguments: looseResolution.arguments)
        }

        return text
    }

    /// Replaces C-style positional format specifiers with pre-stringified
    /// argument values. Supports both implicit ordering (`%@`, `%lld`) and
    /// explicit positional forms (`%1$@`, `%2$lld`). Because the arguments are
    /// already strings, the specifier's numeric/textual type is irrelevant —
    /// each specifier is replaced by the next (or explicitly indexed) value.
    private static func substituteFormatSpecifiers(_ template: String, arguments: [String]) -> String {
        var result = ""
        result.reserveCapacity(template.count)

        let characters = Array(template)
        var index = 0
        var nextImplicitArgument = 0

        while index < characters.count {
            let character = characters[index]

            guard character == "%" else {
                result.append(character)
                index += 1
                continue
            }

            // Lookahead past `%`.
            var cursor = index + 1
            guard cursor < characters.count else {
                result.append(character)
                index += 1
                continue
            }

            // Escaped percent.
            if characters[cursor] == "%" {
                result.append("%")
                index = cursor + 1
                continue
            }

            // Optional explicit position: digits followed by `$`.
            var explicitPosition: Int?
            var digits = ""
            var scan = cursor
            while scan < characters.count, characters[scan].isNumber {
                digits.append(characters[scan])
                scan += 1
            }
            if !digits.isEmpty, scan < characters.count, characters[scan] == "$" {
                explicitPosition = Int(digits)
                cursor = scan + 1
            }

            // Consume flags/width/length modifiers up to the conversion letter.
            let conversionLetters = Set("@dDuUxXoifeEgGsScp")
            while cursor < characters.count, !conversionLetters.contains(characters[cursor]) {
                cursor += 1
            }
            guard cursor < characters.count else {
                // Malformed specifier: emit verbatim.
                result.append(contentsOf: characters[index...])
                index = characters.count
                break
            }

            let argumentIndex: Int
            if let explicitPosition {
                argumentIndex = explicitPosition - 1
            } else {
                argumentIndex = nextImplicitArgument
                nextImplicitArgument += 1
            }

            if argumentIndex >= 0, argumentIndex < arguments.count {
                result.append(arguments[argumentIndex])
            }

            index = cursor + 1
        }

        return result
    }

    /// Dynamic-key lookup has no argument channel. Treat a format template
    /// passed through that API as a caller bug, but never expose its raw C
    /// placeholder to the interface. The typed/interpolated lookup paths keep
    /// using the original template and substitute every argument normally.
    private static func removingUnresolvedFormatSpecifiers(_ template: String) -> String {
        guard template.contains("%"), let regex = unresolvedFormatSpecifierRegex else {
            return template
        }

        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        return regex
            .stringByReplacingMatches(
                in: template,
                range: range,
                withTemplate: ""
            )
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looseInterpolatedResolution(
        forKey key: String,
        languageCode: String
    ) -> (template: String, arguments: [String])? {
        let parts = key
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count > 1 else {
            return nil
        }

        for argumentStart in stride(from: parts.count - 1, through: 1, by: -1) {
            let head = parts[..<argumentStart].joined(separator: " ")
            let arguments = Array(parts[argumentStart...])
            let specifiers = arguments.map { isIntegerLiteral($0) ? "%lld" : "%@" }
            let candidateKey = ([head] + specifiers).joined(separator: " ")

            guard catalog.strings[candidateKey] != nil else {
                continue
            }

            return (
                resolvedTemplate(forKey: candidateKey, languageCode: languageCode),
                arguments
            )
        }

        return nil
    }

    private static func templateMatcher(
        key: String,
        template: String
    ) -> TemplateMatcher? {
        var pattern = "^"
        var captureArgumentPositions: [Int] = []
        var literalCharacterCount = 0
        let characters = Array(template)
        var index = 0
        var nextImplicitArgument = 0

        while index < characters.count {
            let character = characters[index]
            guard character == "%" else {
                pattern += NSRegularExpression.escapedPattern(for: String(character))
                literalCharacterCount += 1
                index += 1
                continue
            }

            var cursor = index + 1
            guard cursor < characters.count else {
                pattern += NSRegularExpression.escapedPattern(for: String(character))
                index += 1
                continue
            }

            if characters[cursor] == "%" {
                pattern += "%"
                literalCharacterCount += 1
                index = cursor + 1
                continue
            }

            var explicitPosition: Int?
            var digits = ""
            var scan = cursor
            while scan < characters.count, characters[scan].isNumber {
                digits.append(characters[scan])
                scan += 1
            }
            if !digits.isEmpty, scan < characters.count, characters[scan] == "$" {
                explicitPosition = Int(digits)
                cursor = scan + 1
            }

            let conversionLetters = Set("@dDuUxXoifeEgGsScp")
            while cursor < characters.count, !conversionLetters.contains(characters[cursor]) {
                cursor += 1
            }
            guard cursor < characters.count else {
                return nil
            }

            let conversion = characters[cursor]
            pattern += conversion == "@" ? "(.+?)" : "(-?\\d+(?:\\.\\d+)?)"
            let argumentPosition: Int
            if let explicitPosition, explicitPosition > 0 {
                argumentPosition = explicitPosition - 1
            } else if explicitPosition != nil {
                return nil
            } else {
                argumentPosition = nextImplicitArgument
                nextImplicitArgument += 1
            }
            captureArgumentPositions.append(argumentPosition)
            index = cursor + 1
        }

        pattern += "$"

        guard !captureArgumentPositions.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        return TemplateMatcher(
            key: key,
            regex: regex,
            captureArgumentPositions: captureArgumentPositions,
            literalCharacterCount: literalCharacterCount
        )
    }

    private static func isIntegerLiteral(_ value: String) -> Bool {
        Int64(value) != nil
    }

    private static func resolvedTemplate(forKey key: String, languageCode: String) -> String {
        let entries = catalog.strings[key]

        if let entries,
           let value = entries[languageCode],
           !value.isEmpty {
            return value
        }

        if let entries,
           let source = entries[sourceLanguage],
           !source.isEmpty {
            return source
        }

        // `xcstrings` may store the source-language value as the key's own
        // extraction when no explicit localization entry exists. Fall back to
        // the key so missing strings remain visible during development.
        return key
    }

    private static func format(_ template: String, arguments: [CVarArg]) -> String {
        // `String(localized:)` uses positional `String.LocalizationValue`
        // interpolation. The catalog templates use `%@`, `%d`, etc. Mirror the
        // standard behavior by using `String(format:)` with the arguments in
        // declaration order.
        String(format: template, arguments: arguments)
    }

    private static func loadCatalog() -> Catalog {
        var catalog: [String: [String: String]] = [:]

        for languageCode in compiledLanguageCodes {
            let translations = loadCompiledStrings(forLocalization: languageCode)
            mergeTranslations(translations, languageCode: languageCode, into: &catalog)
        }

        mergeRawStringCatalog(into: &catalog)

        var keysByRenderedText: [String: Set<String>] = [:]
        for key in catalog.keys.sorted() {
            let templates = Set(catalog[key, default: [:]].values).sorted()
            for template in templates where !template.isEmpty {
                keysByRenderedText[template, default: []].insert(key)
            }
        }

        let languageCodes = Set(catalog.values.flatMap(\.keys)).union([sourceLanguage])
        var exactKeyByRenderedText: [String: String] = [:]
        var templateMatchers: [TemplateMatcher] = []
        for template in keysByRenderedText.keys.sorted() {
            let keys = keysByRenderedText[template, default: []].sorted()
            guard let key = keys.first,
                  keys.dropFirst().allSatisfy({ candidate in
                      languageCodes.allSatisfy { languageCode in
                          resolvedTemplate(
                              forKey: candidate,
                              languageCode: languageCode,
                              catalog: catalog
                          ) == resolvedTemplate(
                              forKey: key,
                              languageCode: languageCode,
                              catalog: catalog
                          )
                      }
                  }) else {
                continue
            }

            exactKeyByRenderedText[template] = key
            if let matcher = templateMatcher(key: key, template: template) {
                templateMatchers.append(matcher)
            }
        }
        templateMatchers.sort {
            if $0.literalCharacterCount != $1.literalCharacterCount {
                return $0.literalCharacterCount > $1.literalCharacterCount
            }
            if $0.captureArgumentPositions.count != $1.captureArgumentPositions.count {
                return $0.captureArgumentPositions.count < $1.captureArgumentPositions.count
            }
            return $0.key < $1.key
        }

        return Catalog(
            strings: catalog,
            exactKeyByRenderedText: exactKeyByRenderedText,
            templateMatchers: templateMatchers
        )
    }

    private static func loadCompiledStrings(forLocalization languageCode: String) -> [String: String] {
        guard let url = Bundle.module.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: languageCode
        ),
            let data = try? Data(contentsOf: url),
            let plist = (try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )) as? [String: Any] else {
            return [:]
        }

        return plist.reduce(into: [:]) { result, entry in
            guard let text = entry.value as? String,
                  !text.isEmpty else {
                return
            }

            result[entry.key] = text
        }
    }

    private static func mergeRawStringCatalog(into catalog: inout [String: [String: String]]) {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = document["strings"] as? [String: Any] else {
            return
        }

        for (key, entry) in strings {
            guard let entryDict = entry as? [String: Any] else {
                continue
            }

            var translations: [String: String] = [:]

            if let localizations = entryDict["localizations"] as? [String: Any] {
                for (language, value) in localizations {
                    guard let valueDict = value as? [String: Any],
                          let stringUnit = valueDict["stringUnit"] as? [String: Any],
                          let state = stringUnit["state"] as? String,
                          state == "translated" || state == "new",
                          let text = stringUnit["value"] as? String else {
                        continue
                    }

                    translations[language] = text
                }
            }

            catalog[key, default: [:]].merge(translations) { _, new in new }
        }
    }

    private static func mergeTranslations(
        _ translations: [String: String],
        languageCode: String,
        into catalog: inout [String: [String: String]]
    ) {
        for (key, text) in translations where !text.isEmpty {
            catalog[key, default: [:]][languageCode] = text
        }
    }

    private static func resolvedTemplate(
        forKey key: String,
        languageCode: String,
        catalog: [String: [String: String]]
    ) -> String {
        if let value = catalog[key]?[languageCode], !value.isEmpty {
            return value
        }
        if let source = catalog[key]?[sourceLanguage], !source.isEmpty {
            return source
        }
        return key
    }
}
