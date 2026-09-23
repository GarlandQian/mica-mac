import Foundation
import MicaCore
import Testing
@testable import Mica

struct WorkbenchSourceTimestampCacheTests {
    @Test func repeatedDatesParseOnceAndCountOnlyRefreshesDoNotParseAgain() {
        var sources = (0..<500).map { index in
            source("source-\(index)", updatedAt: timestamp(minute: index % 60), count: index)
        }
        var cache = WorkbenchSourceProjectionCache()
        project(sources, into: &cache)
        let initialIDs = cache.allRows.map(\.id)
        #expect(cache.timestampParseCount == 60)
        #expect(cache.retainedTimestampCount == 60)
        #expect(cache.allRows.map(\.source) == sources)

        for index in sources.indices { sources[index].itemCount += 100 }
        project(sources, into: &cache)
        #expect(cache.timestampParseCount == 60)
        #expect(cache.allRows.map(\.id) == initialIDs)
        #expect(cache.allRows.map(\.source) == sources)
        #expect(cache.allRows.map(\.itemCountText) == sources.map { String($0.itemCount) })

        sources[0].updatedAt = "2026-08-01T09:00:00Z"
        sources[1].updatedAt = "2026-08-02T09:00:00Z"
        sources[2].updatedAt = sources[0].updatedAt
        project(sources, into: &cache)
        #expect(cache.timestampParseCount == 62)
        #expect(cache.retainedTimestampCount == 62)
        #expect(cache.allRows[0].updatedText == originalDisplay(sources[0].updatedAt, language: .english))
        #expect(cache.allRows[2].updatedText == cache.allRows[0].updatedText)
    }

    @Test func missingSentinelInvalidAndOffsetDatesKeepTheOriginalPresentation() {
        let timestamps: [String?] = [
            nil, "", " \n", "0001-01-01T00:00:00Z", "1970-01-01T00:00:00Z",
            "not-a-date", "  not-a-date \n", "2026-08-01T09:00:00Z",
            "2026-08-01T17:00:00+08:00", "2026-08-01T09:00:00.125Z",
        ]
        let sources = timestamps.enumerated().map { source("source-\($0.offset)", updatedAt: $0.element) }
        var cache = WorkbenchSourceProjectionCache()
        project(sources, into: &cache)
        #expect(cache.timestampParseCount == 4)
        #expect(cache.retainedTimestampCount == 4)
        for (row, raw) in zip(cache.allRows, timestamps) {
            let expected = originalDisplay(raw, language: .english)
            #expect(WorkbenchDataFormat.providerUpdatedAt(raw, language: .english) == expected)
            #expect(row.updatedText == (expected ?? "Not reported"))
        }
        #expect(cache.allRows[5].updatedText == "not-a-date")
        #expect(cache.allRows[5].updatedText == cache.allRows[6].updatedText)
        #expect(cache.allRows[7].updatedText == cache.allRows[8].updatedText)
        project(sources, into: &cache)
        #expect(cache.timestampParseCount == 4)
    }

    @Test func languageChangesReformatRetainedDatesAndRefreshAllLocalizedFields() {
        var sources = [source("dated", updatedAt: timestamp(minute: 10)), source("missing", updatedAt: nil)]
        sources[1].type = " "
        sources[1].updatable = false
        var cache = WorkbenchSourceProjectionCache()
        project(sources, into: &cache)
        let english = cache.allRows
        project(sources, into: &cache, language: .simplifiedChinese)
        #expect(cache.timestampParseCount == 1)
        #expect(cache.retainedTimestampCount == 1)
        #expect(cache.allRows.map(\.id) == english.map(\.id))
        #expect(cache.allRows.map(\.source) == sources)
        #expect(cache.allRows[0].updatedText == originalDisplay(sources[0].updatedAt, language: .simplifiedChinese))
        #expect(cache.allRows[0].updatedText != english[0].updatedText)
        #expect(cache.allRows[0].kindText == MicaStrings.localizedKey("traffic.provider_kind_proxy", language: .simplifiedChinese))
        #expect(cache.allRows[0].updatableText == MicaStrings.localizedKey("traffic.provider_updatable_yes", language: .simplifiedChinese))
        #expect(cache.allRows[1].updatedText == MicaStrings.localizedKey("overview.config_not_reported", language: .simplifiedChinese))
        #expect(cache.allRows[1].typeText == cache.allRows[1].updatedText)
        #expect(cache.allRows[1].updatableText == MicaStrings.localizedKey("traffic.provider_updatable_no", language: .simplifiedChinese))

        project(sources, into: &cache, language: .system)
        #expect(cache.timestampParseCount == 1)
        #expect(cache.allRows[0].updatedText == originalDisplay(sources[0].updatedAt, language: .system))
    }

    @Test func parsedDateCanRenderInAnotherTimeZoneWithoutRetainingOldDisplayText() {
        let parsed = WorkbenchDataFormat.parseProviderTimestamp("2026-08-01T09:00:00Z")
        var utc = WorkbenchDataFormat.providerTimestampStyle(language: .english)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var shanghai = utc
        shanghai.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        #expect(parsed.formatted(using: utc) != parsed.formatted(using: shanghai))
        let invalid = WorkbenchDataFormat.parseProviderTimestamp("controller-specific timestamp")
        #expect(invalid.formatted(using: utc) == "controller-specific timestamp")
        #expect(invalid.formatted(using: shanghai) == "controller-specific timestamp")
    }

    @Test func sourceOrderAndDuplicateIdentitiesSurviveReuseAndUnusedDatesArePruned() {
        let duplicateOne = source("duplicate", updatedAt: timestamp(minute: 1), count: 1)
        let duplicateTwo = source("duplicate", updatedAt: timestamp(minute: 2), count: 2)
        let unique = source("unique", updatedAt: timestamp(minute: 3), count: 3)
        var cache = WorkbenchSourceProjectionCache()
        project([duplicateOne, duplicateTwo, unique], into: &cache)
        let ids = cache.allRows.map(\.id)
        #expect(Set(ids).count == 3)
        #expect(cache.retainedTimestampCount == 3)

        project([unique, duplicateOne, duplicateTwo], into: &cache)
        #expect(cache.allRows.map(\.source) == [unique, duplicateOne, duplicateTwo])
        #expect(cache.allRows.map(\.sourceIndex) == [0, 1, 2])
        #expect(cache.allRows.map(\.id) == [ids[2], ids[0], ids[1]])
        #expect(cache.timestampParseCount == 3)

        project([duplicateOne], into: &cache)
        #expect(cache.retainedTimestampCount == 1)
        #expect(cache.timestampParseCount == 3)
        project([duplicateOne, unique], into: &cache)
        #expect(cache.retainedTimestampCount == 2)
        #expect(cache.timestampParseCount == 4)
        project([], into: &cache)
        #expect(cache.retainedTimestampCount == 0)
        #expect(cache.allRows.isEmpty)
        cache.reset()
        #expect(cache.timestampParseCount == 0)
        #expect(cache.retainedTimestampCount == 0)
    }

    private func project(
        _ sources: [ProxyProviderViewState],
        into cache: inout WorkbenchSourceProjectionCache,
        language: AppLanguage = .english
    ) {
        cache.project(update: .source, sources: sources, kind: .all, query: "", sortOrder: [], language: language)
    }

    private func source(_ name: String, updatedAt: String?, count: Int = 1) -> ProxyProviderViewState {
        .init(kind: .proxy, name: name, type: "HTTP", updatedAt: updatedAt, updatable: true, itemCount: count)
    }

    private func timestamp(minute: Int) -> String {
        "2026-07-29T08:\(String(format: "%02d", minute)):00Z"
    }

    /// Independent reference for the previous interface, including its raw
    /// fallback and sentinel filtering. Do not use the optimized parser here.
    private func originalDisplay(_ raw: String?, language: AppLanguage) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              !raw.hasPrefix("0001-"), !raw.hasPrefix("1970-") else { return nil }
        guard let date = ISO8601DateFormatter().date(from: raw) else { return raw }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(language.resolvedLocale))
    }
}
