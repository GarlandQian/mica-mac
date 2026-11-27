import Foundation
import MicaCore

enum LogLevelFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case error
    case warning
    case info
    case debug

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .all: "traffic.log_level_all"
        case .error: "log_type.error"
        case .warning: "log_type.warning"
        case .info: "log_type.info"
        case .debug: "log_type.debug"
        }
    }

    func matches(_ normalizedLevel: String) -> Bool {
        switch self {
        case .all: true
        case .error: normalizedLevel == "error" || normalizedLevel == "err" || normalizedLevel == "fatal" || normalizedLevel == "panic"
        case .warning: normalizedLevel == "warning" || normalizedLevel == "warn"
        case .info: normalizedLevel == "info"
        case .debug: normalizedLevel == "debug" || normalizedLevel == "trace"
        }
    }
}

struct LogRowItem: Identifiable, Equatable, Sendable {
    let id: String
    let timeText: String
    let level: String
    let message: String
    let entry: ControllerLogEntry

    var normalizedLevel: String {
        level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Lean store for Logs: filters only on revision/filter changes and limits work.
@MainActor
@Observable
final class LogsStore {
    private(set) var rows: [LogRowItem] = []
    private(set) var errorCount = 0
    private(set) var warningCount = 0

    var levelFilter: LogLevelFilter = .all {
        didSet {
            guard oldValue != levelFilter else { return }
            rebuildRows()
        }
    }

    var searchQuery: String = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            rebuildRows()
        }
    }

    @ObservationIgnored private var allEntries: [ControllerLogEntry] = []
    @ObservationIgnored private var lastRevision: UInt64?

    func sync(catalog: LogsCatalogSnapshot) {
        guard lastRevision != catalog.entriesRevision else { return }
        lastRevision = catalog.entriesRevision
        allEntries = catalog.entries

        var errors = 0
        var warnings = 0
        for entry in allEntries {
            let level = Self.levelText(for: entry).lowercased()
            if LogLevelFilter.error.matches(level) {
                errors += 1
            } else if LogLevelFilter.warning.matches(level) {
                warnings += 1
            }
        }
        errorCount = errors
        warningCount = warnings
        rebuildRows()
    }

    func entry(id: String) -> ControllerLogEntry? {
        allEntries.first { $0.id == id }
    }

    private func rebuildRows() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var next: [LogRowItem] = []
        next.reserveCapacity(allEntries.count)

        for entry in allEntries {
            let rawLevel = Self.levelText(for: entry)
            let normalized = rawLevel.lowercased()
            guard levelFilter.matches(normalized) else { continue }
            let message = Self.payloadText(for: entry)
            if !query.isEmpty {
                let matched = message.lowercased().contains(query) || normalized.contains(query)
                if !matched { continue }
            }
            next.append(
                LogRowItem(
                    id: entry.id,
                    timeText: MicaFormatters.formatTime(entry.receivedAt),
                    level: rawLevel.uppercased(),
                    message: message,
                    entry: entry
                )
            )
        }

        if next != rows {
            rows = next
        }
    }

    private static func levelText(for entry: ControllerLogEntry) -> String {
        let level = (entry.message.level ?? entry.message.type)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return level.isEmpty ? "info" : level
    }

    private static func payloadText(for entry: ControllerLogEntry) -> String {
        let text = entry.message.message ?? entry.message.payload
        return text.trimmingCharacters(in: .newlines)
    }
}
