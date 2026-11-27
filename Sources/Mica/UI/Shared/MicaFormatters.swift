import Foundation

/// Lightweight, allocation-free formatting utilities for live tables, cards, and telemetry.
enum MicaFormatters {
    private static let units = ["B", "KB", "MB", "GB", "TB"]
    private static let compactUnits = ["K", "M", "G", "T"]

    static func formatBytes(_ bytes: Int) -> String {
        let clamped = max(bytes, 0)
        if clamped < 1_000 {
            return "\(clamped) B"
        }
        var value = Double(clamped)
        var index = 0
        while value >= 999.5, index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        if value < 10 {
            return String(format: "%.2f %@", value, units[index])
        }
        if value < 100 {
            return String(format: "%.1f %@", value, units[index])
        }
        return String(format: "%.0f %@", value, units[index])
    }

    static func formatRate(_ bytesPerSecond: Int) -> String {
        "\(formatBytes(bytesPerSecond))/s"
    }

    static func compactRate(_ bytesPerSecond: Int) -> String {
        let value = max(bytesPerSecond, 0)
        guard value >= 1_000 else { return "\(value) B" }
        var scaled = Double(value) / 1_000
        var unitIndex = 0
        while scaled >= 999.5, unitIndex < compactUnits.count - 1 {
            scaled /= 1_000
            unitIndex += 1
        }
        let number = scaled < 9.95
            ? String(format: "%.1f", scaled)
            : String(Int(scaled.rounded()))
        return "\(number) \(compactUnits[unitIndex])"
    }

    static func formatLatency(_ delay: Int?, alive: Bool? = nil, language: AppLanguage) -> String {
        if alive == false {
            return L("routing.node_unavailable", language: language)
        }
        guard let delay else {
            return "-"
        }
        if delay <= 0 {
            return L("routing.node_unavailable", language: language)
        }
        return "\(delay) ms"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func formatDateTime(_ date: Date) -> String {
        shortDateTimeFormatter.string(from: date)
    }

    static func formatISO8601Short(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(raw), seconds > 1_000_000_000 {
            let normalized = seconds > 1_000_000_000_000 ? seconds / 1_000 : seconds
            return formatDateTime(Date(timeIntervalSince1970: normalized))
        }
        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = isoWithFractional.date(from: raw) {
            return formatDateTime(parsed)
        }
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        if let parsed = isoBasic.date(from: raw) {
            return formatDateTime(parsed)
        }
        return raw
    }

    static func formatDuration(from rawStart: String?, now: Date = Date()) -> String {
        guard let rawStart = rawStart?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawStart.isEmpty else {
            return "-"
        }
        let startDate: Date?
        if let numeric = TimeInterval(rawStart), numeric > 1_000_000_000 {
            let seconds = numeric > 1_000_000_000_000 ? numeric / 1_000 : numeric
            startDate = Date(timeIntervalSince1970: seconds)
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: rawStart) {
                startDate = d
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                startDate = formatter.date(from: rawStart)
            }
        }
        guard let startDate else { return "-" }
        let elapsed = max(Int(now.timeIntervalSince(startDate)), 0)
        if elapsed < 60 { return "\(elapsed)s" }
        if elapsed < 3_600 { return "\(elapsed / 60)m \(elapsed % 60)s" }
        return "\(elapsed / 3_600)h \((elapsed % 3_600) / 60)m"
    }
    static func formatMetadataNumber(_ value: Double) -> String {
        guard value.isFinite else {
            return String(value)
        }
        if let integer = Int64(exactly: value) {
            return String(integer)
        }
        return String(value)
    }
}

@inline(__always)
func L(_ key: String, language: AppLanguage) -> String {
    MicaStrings.localizedKey(key, language: language)
}
