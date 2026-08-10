import Foundation
import MicaCore
import Synchronization

// MARK: - Shared data-page presentation

enum WorkbenchDataState: Equatable {
    case noController
    case loading
    case unsupported
    case empty
    case filterEmpty(staleMessage: String?)
    case failed(String)
    case content(staleMessage: String?)

    var staleMessage: String? {
        switch self {
        case .filterEmpty(let message), .content(let message):
            message
        case .noController, .loading, .unsupported, .empty, .failed:
            nil
        }
    }
}

enum WorkbenchDataStateResolver {
    static func endpoint(
        hasController: Bool,
        isSupported: Bool,
        sourceCount: Int,
        visibleCount: Int,
        isFiltering: Bool,
        endpointStatus: ControllerEndpointStatus?,
        snapshotState: EnhancedSnapshotState? = nil,
        sessionState: LiveSessionState? = nil,
        language: AppLanguage = .english
    ) -> WorkbenchDataState {
        guard hasController else { return .noController }

        let endpointFailure = failureMessage(
            endpointStatus: endpointStatus,
            snapshotState: snapshotState
        )
        let sessionMessage = sessionStaleMessage(
            sessionState,
            language: language
        )
        let staleMessage = sessionMessage ?? endpointFailure
        let loading = endpointStatus?.isChecking == true
            || snapshotState?.isLoading == true
            || sessionState == .connecting

        if sourceCount == 0 {
            if !isSupported { return .unsupported }
            if loading { return .loading }
            if let staleMessage { return .failed(staleMessage) }
            return .empty
        }

        if visibleCount == 0, isFiltering {
            return .filterEmpty(staleMessage: staleMessage)
        }

        return .content(staleMessage: staleMessage)
    }

    static func logs(
        hasController: Bool,
        isSupported: Bool,
        sourceCount: Int,
        visibleCount: Int,
        isFiltering: Bool,
        streamState: LiveStreamState,
        sessionState: LiveSessionState? = nil,
        language: AppLanguage = .english
    ) -> WorkbenchDataState {
        guard hasController else { return .noController }

        let sessionMessage = sessionStaleMessage(
            sessionState,
            language: language
        )
        let staleMessage = sessionMessage
            ?? streamStaleMessage(streamState, language: language)

        if sourceCount == 0 {
            if !isSupported { return .unsupported }
            if sessionState == .connecting {
                return .loading
            }
            switch streamState {
            case .idle, .connecting: return .loading
            default: break
            }
            if let staleMessage { return .failed(staleMessage) }
            return .empty
        }

        if visibleCount == 0, isFiltering {
            return .filterEmpty(staleMessage: staleMessage)
        }

        return .content(staleMessage: staleMessage)
    }

    private static func sessionStaleMessage(
        _ state: LiveSessionState?,
        language: AppLanguage
    ) -> String? {
        guard let state else { return nil }
        switch state {
        case .live:
            return nil
        case .idle:
            return MicaStrings.localizedKey("connection.disconnected", language: language)
        case .connecting:
            return state.label(language: language)
        case .staleReconnecting(let message), .partial(let message),
             .failedBeforeFirstSnapshot(let message), .failed(let message):
            return message.dataNonEmpty ?? state.label(language: language)
        case .stopped:
            return MicaStrings.localizedKey("live.detail_stopped", language: language)
        }
    }

    private static func streamStaleMessage(
        _ state: LiveStreamState,
        language: AppLanguage
    ) -> String? {
        switch state {
        case .live, .nearLive:
            return nil
        case .idle:
            return MicaStrings.localizedKey("live.detail_idle", language: language)
        case .connecting:
            return MicaStrings.localizedKey("live.detail_connecting", language: language)
        case .partial(let message), .failed(let message), .unavailable(let message):
            return message.dataNonEmpty ?? state.label(language: language)
        case .stopped:
            return MicaStrings.localizedKey("live.detail_stopped", language: language)
        }
    }

    private static func failureMessage(
        endpointStatus: ControllerEndpointStatus?,
        snapshotState: EnhancedSnapshotState?
    ) -> String? {
        if case .some(.unavailable(let message)) = snapshotState {
            return message
        }
        if case .some(.failed(let message)) = endpointStatus {
            return message
        }
        return nil
    }
}

struct WorkbenchDataInspectorValue: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let value: String?
    var monospaced = false
}

enum WorkbenchDataInspectorProjection {
    static func value(
        _ id: String,
        _ titleKey: String,
        _ value: String?,
        monospaced: Bool = false
    ) -> WorkbenchDataInspectorValue {
        WorkbenchDataInspectorValue(
            id: id,
            titleKey: titleKey,
            value: value,
            monospaced: monospaced
        )
    }
}

enum WorkbenchDataFormat {
    private static let iso8601DateFormatter = Mutex(ISO8601DateFormatter())

    struct MetricsFormatter {
        let language: AppLanguage
        private let rateSuffix: String

        init(language: AppLanguage) {
            self.language = language
            rateSuffix = MicaStrings.resolvedLanguageCode(for: language)
                == AppLanguage.simplifiedChinese.rawValue ? "/秒" : "/s"
        }

        func bytes(_ value: Int?) -> String? {
            guard let value else { return nil }
            return WorkbenchDataFormat.compactBytes(Int64(value))
        }

        func bytes(_ value: Int64?) -> String? {
            guard let value else { return nil }
            return WorkbenchDataFormat.compactBytes(value)
        }

        func rate(_ value: Int?) -> String? {
            guard let value else { return nil }
            guard value > 0 else { return "0 B/s" }
            guard let bytes = bytes(value) else { return nil }
            return bytes + rateSuffix
        }
    }

    static func bytes(_ value: Int?) -> String? {
        MetricsFormatter(language: .english).bytes(value)
    }

    static func bytes(_ value: Int64?) -> String? {
        MetricsFormatter(language: .english).bytes(value)
    }

    static func rate(_ value: Int?, language: AppLanguage) -> String? {
        MetricsFormatter(language: language).rate(value)
    }

    private static func compactBytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 B" }

        let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
        guard value >= 1_024 else { return "\(value) B" }

        let rawValue = Double(value)
        var divisor = 1_024.0
        var unitIndex = 1
        while unitIndex < units.count - 1, rawValue >= divisor * 1_024 {
            divisor *= 1_024
            unitIndex += 1
        }

        let scaled = rawValue / divisor
        if unitIndex == 1 {
            return "\(Int(scaled.rounded())) \(units[unitIndex])"
        }

        let tenths = Int((scaled * 10).rounded())
        let whole = tenths / 10
        let decimal = tenths % 10
        let number = decimal == 0 ? "\(whole)" : "\(whole).\(decimal)"
        return "\(number) \(units[unitIndex])"
    }

    static func address(_ host: String?, port: String?) -> String? {
        let host = host?.dataNonEmpty
        let port = port?.dataNonEmpty
        switch (host, port) {
        case let (.some(host), .some(port)):
            return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
        case let (.some(host), .none):
            return host
        case let (.none, .some(port)):
            return port
        case (.none, .none):
            return nil
        }
    }

    static func chain(_ values: [String]?) -> String? {
        values?
            .compactMap(\.dataNonEmpty)
            .joined(separator: " → ")
            .dataNonEmpty
    }

    static func json(_ values: [String: MihomoJSONValue]) -> String? {
        guard !values.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(values) else { return nil }
        return String(data: data, encoding: .utf8)?.dataNonEmpty
    }

    static func receivedTime(_ date: Date, language: AppLanguage) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .standard)
                .locale(language.resolvedLocale)
        )
    }

    static func receivedDateTime(_ date: Date, language: AppLanguage) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .standard)
                .locale(language.resolvedLocale)
        )
    }

    static func providerUpdatedAt(_ raw: String?, language: AppLanguage) -> String? {
        guard let raw = reportedTimestamp(raw) else { return nil }
        let date = iso8601DateFormatter.withLock {
            $0.date(from: raw)
        }
        if let date {
            return date.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened)
                    .locale(language.resolvedLocale)
            )
        }
        return raw
    }

    static func reportedTimestamp(_ raw: String?) -> String? {
        guard let raw = raw?.dataNonEmpty else { return nil }
        guard !raw.hasPrefix("0001-"), !raw.hasPrefix("1970-") else { return nil }
        return raw
    }

    static func reported(_ value: String?, language: AppLanguage) -> String {
        value?.dataNonEmpty
            ?? MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            )
    }

    static func joined(
        _ values: [String?],
        separator: String = " · "
    ) -> String? {
        values
            .compactMap { $0?.dataNonEmpty }
            .joined(separator: separator)
            .dataNonEmpty
    }
}

enum WorkbenchDataSearch {
    static func contains(_ query: String, in searchText: String) -> Bool {
        (searchText as NSString).range(
            of: query,
            options: [.caseInsensitive]
        ).location != NSNotFound
    }
}

extension String {
    var dataNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct WorkbenchStableRowIdentity: Equatable {
    let id: String
    let family: String
}

enum WorkbenchStableIdentityToken {
    static func make(_ components: [String]) -> String {
        let value = components
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

struct WorkbenchStableRowIdentityBuilder {
    private let duplicateReportedIDs: Set<String>
    private var occurrences: [String: Int] = [:]
    private var used: Set<String> = []

    init(reportedIDs: [String], reserving reservedIDs: Set<String> = []) {
        var counts: [String: Int] = [:]
        for reportedID in reportedIDs.compactMap(\.dataNonEmpty) {
            counts[reportedID, default: 0] += 1
        }
        duplicateReportedIDs = Set(counts.compactMap { key, value in
            value > 1 ? key : nil
        })
        used = reservedIDs
    }

    mutating func make(
        reportedID: String?,
        fallbackComponents: [String]
    ) -> WorkbenchStableRowIdentity {
        let reportedID = reportedID?.dataNonEmpty
        let family: String
        if let reportedID, !duplicateReportedIDs.contains(reportedID) {
            family = reportedID
        } else if let reportedID {
            let fallback = WorkbenchStableIdentityToken.make(fallbackComponents)
            family = "\(reportedID)#\(fallback)"
        } else {
            let fallback = WorkbenchStableIdentityToken.make(fallbackComponents)
            family = "unreported#\(fallback)"
        }

        var occurrence = occurrences[family, default: 0]
        var candidate = occurrence == 0 ? family : "\(family)#\(occurrence + 1)"

        while used.contains(candidate) {
            occurrence += 1
            candidate = "\(family)#\(occurrence + 1)"
        }

        occurrences[family] = occurrence + 1
        used.insert(candidate)
        return WorkbenchStableRowIdentity(id: candidate, family: family)
    }
}

enum WorkbenchDataSelection {
    static func reconciled<Row: Identifiable & Equatable>(
        _ selection: String?,
        previousRows: [Row],
        nextVisibleRows: [Row],
        identityFamily: (Row) -> String
    ) -> String? where Row.ID == String {
        guard let selection else {
            return nil
        }
        guard let previous = previousRows.first(where: { $0.id == selection }) else {
            return nextVisibleRows.contains(where: { $0.id == selection }) ? selection : nil
        }

        let family = identityFamily(previous)
        let previousFamilyRows = previousRows.filter { identityFamily($0) == family }
        let nextFamilyRows = nextVisibleRows.filter { identityFamily($0) == family }

        guard !nextFamilyRows.isEmpty else { return nil }
        if previousFamilyRows.count == 1, nextFamilyRows.count == 1 {
            return nextFamilyRows[0].id
        }

        let previousIDs = previousFamilyRows.map(\.id)
        let nextIDs = nextFamilyRows.map(\.id)
        guard previousIDs == nextIDs,
              let exact = nextFamilyRows.first(where: { $0.id == selection }),
              exact == previous else {
            return nil
        }
        return selection
    }
}
