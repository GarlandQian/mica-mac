import Darwin
import Foundation

enum IPAddressClassification {
    static func isIPAddress(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return parseIPv4(value) != nil || parseIPv6(value) != nil
    }

    static func isNonPublic(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        if let ipv4 = parseIPv4(value) { return isNonPublicIPv4(ipv4) }
        if let ipv6 = parseIPv6(value) { return isNonPublicIPv6(ipv6) }
        return true
    }

    private static func parseIPv4(_ value: String) -> [UInt8]? {
        var address = in_addr()
        guard value.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else {
            return nil
        }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func isNonPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return true }
        let a = bytes[0]
        let b = bytes[1]
        if a == 0 || a == 10 || a == 127 { return true }
        if a == 100, (64...127).contains(b) { return true }
        if a == 169, b == 254 { return true }
        if a == 172, (16...31).contains(b) { return true }
        if a == 192, b == 168 { return true }
        if a == 192, b == 0, (bytes[2] == 0 || bytes[2] == 2) { return true }
        if a == 198, (18...19).contains(b) { return true }
        if a == 198, b == 51, bytes[2] == 100 { return true }
        if a == 203, b == 0, bytes[2] == 113 { return true }
        return a >= 224
    }

    private static func parseIPv6(_ value: String) -> [UInt8]? {
        var address = in6_addr()
        guard value.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else {
            return nil
        }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func isNonPublicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }
        if bytes.allSatisfy({ $0 == 0 }) { return true }
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes.last == 1 { return true }
        if bytes[0] & 0xFE == 0xFC { return true }
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return true }
        if bytes[0] == 0xFF { return true }
        if bytes[0] == 0x20,
           bytes[1] == 0x01,
           bytes[2] == 0x0D,
           bytes[3] == 0xB8 {
            return true
        }
        let isIPv4Mapped = bytes.prefix(10).allSatisfy { $0 == 0 }
            && bytes[10] == 0xFF
            && bytes[11] == 0xFF
        if isIPv4Mapped {
            return isNonPublicIPv4(Array(bytes.suffix(4)))
        }
        return false
    }
}

// MARK: - Result model

enum GeoIPLookupStatus: Equatable, Sendable {
    case resolved
    case pending
    case unavailable
    case disabled
}

struct GeoIPLookupResult: Equatable, Sendable {
    var status: GeoIPLookupStatus
    var ip: String
    var country: String?
    var city: String?
    var asn: String?
    var organization: String?

    static func pending(ip: String) -> GeoIPLookupResult {
        GeoIPLookupResult(status: .pending, ip: ip)
    }

    static func unavailable(ip: String) -> GeoIPLookupResult {
        GeoIPLookupResult(status: .unavailable, ip: ip)
    }

    static func disabled(ip: String) -> GeoIPLookupResult {
        GeoIPLookupResult(status: .disabled, ip: ip)
    }

    static func resolved(
        ip: String,
        country: String? = nil,
        city: String? = nil,
        asn: String? = nil,
        organization: String? = nil
    ) -> GeoIPLookupResult {
        GeoIPLookupResult(
            status: .resolved,
            ip: ip,
            country: country,
            city: city,
            asn: asn,
            organization: organization
        )
    }

    /// True when geo enrichment produced usable fields (never invents values).
    var hasEnrichment: Bool {
        status == .resolved
            && (country != nil || city != nil || asn != nil || organization != nil)
    }
}

// MARK: - Protocol

/// Offline/local GeoIP lookup. Implementations must not perform online HTTP.
protocol GeoIPResolving: Sendable {
    @concurrent
    func resolve(_ ip: String, language: AppLanguage) async -> GeoIPLookupResult
}

extension GeoIPResolving {
    func resolve(_ ip: String) async -> GeoIPLookupResult {
        await resolve(ip, language: .english)
    }
}

// MARK: - Disabled / fixture / offline path

/// Always returns `disabled` — used when no local DB is configured.
struct DisabledGeoIPResolver: GeoIPResolving {
    @concurrent
    func resolve(_ ip: String, language _: AppLanguage) async -> GeoIPLookupResult {
        if IPAddressClassification.isNonPublic(ip) {
            return .unavailable(ip: ip)
        }
        return .disabled(ip: ip)
    }
}

/// Map-backed resolver for unit tests and offline fixtures. No network I/O.
struct FixtureGeoIPResolver: GeoIPResolving {
    struct Record: Equatable, Sendable {
        var country: String?
        var city: String?
        var asn: String?
        var organization: String?
        var localizedCityNames: [String: String]

        init(
            country: String? = nil,
            city: String? = nil,
            asn: String? = nil,
            organization: String? = nil,
            localizedCityNames: [String: String] = [:]
        ) {
            self.country = country
            self.city = city
            self.asn = asn
            self.organization = organization
            self.localizedCityNames = localizedCityNames
        }
    }

    private let records: [String: Record]
    /// When the IP is public but missing from the fixture map.
    private let missingStatus: GeoIPLookupStatus

    init(records: [String: Record] = [:], missingStatus: GeoIPLookupStatus = .unavailable) {
        self.records = records
        self.missingStatus = missingStatus
    }

    @concurrent
    func resolve(_ ip: String, language: AppLanguage) async -> GeoIPLookupResult {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || IPAddressClassification.isNonPublic(trimmed) {
            return .unavailable(ip: trimmed)
        }
        guard let record = records[trimmed] else {
            return GeoIPLookupResult(status: missingStatus, ip: trimmed)
        }
        return .resolved(
            ip: trimmed,
            country: record.country,
            city: record.localizedCityNames[geoIPLanguageCode(for: language)] ?? record.city,
            asn: record.asn,
            organization: record.organization
        )
    }
}

/// G1 offline path: reads one or more local MaxMind DB files when present.
/// City/Country and ASN databases may be supplied together; fields are merged
/// without online requests or invented fallback values.
struct OfflineLocalGeoIPResolver: GeoIPResolving {
    /// Pluggable local lookup. Return `nil` for miss. Must stay offline.
    private let localLookup: (@Sendable (String) -> GeoIPLookupResult?)?
    /// Status used when the database is missing or unreadable.
    private let missingDatabaseStatus: GeoIPLookupStatus
    private let databaseStore: OfflineMaxMindDatabaseStore

    init(
        databasePath: String? = nil,
        localLookup: (@Sendable (String) -> GeoIPLookupResult?)? = nil,
        missingDatabaseStatus: GeoIPLookupStatus = .disabled
    ) {
        let paths = databasePath.map { [$0] } ?? Self.defaultDatabasePaths()
        self.init(
            databasePaths: paths,
            localLookup: localLookup,
            missingDatabaseStatus: missingDatabaseStatus
        )
    }

    init(
        databasePaths: [String],
        localLookup: (@Sendable (String) -> GeoIPLookupResult?)? = nil,
        missingDatabaseStatus: GeoIPLookupStatus = .disabled
    ) {
        self.localLookup = localLookup
        self.missingDatabaseStatus = missingDatabaseStatus
        databaseStore = OfflineMaxMindDatabaseStore(paths: databasePaths)
    }

    @concurrent
    func resolve(_ ip: String, language: AppLanguage) async -> GeoIPLookupResult {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || IPAddressClassification.isNonPublic(trimmed) {
            return .unavailable(ip: trimmed)
        }

        if let localLookup {
            if let hit = localLookup(trimmed) {
                return hit
            }
            return .unavailable(ip: trimmed)
        }

        switch await databaseStore.lookup(trimmed, language: language) {
        case .missingDatabase:
            return GeoIPLookupResult(status: missingDatabaseStatus, ip: trimmed)
        case .unreadableDatabase, .miss:
            return .unavailable(ip: trimmed)
        case let .resolved(record):
            return .resolved(
                ip: trimmed,
                country: record.country,
                city: record.city,
                asn: record.asn,
                organization: record.organization
            )
        }
    }

    private static func defaultDatabasePaths() -> [String] {
        var paths: [String] = []

        if let configured = ProcessInfo.processInfo.environment["MICA_GEOIP_MMDB"] {
            paths.append(contentsOf: configured.split(separator: ":").map(String.init))
        }

        for name in ["GeoLite2-City", "GeoLite2-Country", "GeoLite2-ASN"] {
            if let bundled = Bundle.main.url(forResource: name, withExtension: "mmdb") {
                paths.append(bundled.path)
            }
        }

        if let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            let micaDirectory = applicationSupport.appending(path: "Mica", directoryHint: .isDirectory)
            paths.append(micaDirectory.appending(path: "GeoLite2-City.mmdb").path)
            paths.append(micaDirectory.appending(path: "GeoLite2-Country.mmdb").path)
            paths.append(micaDirectory.appending(path: "GeoLite2-ASN.mmdb").path)
        }

        var seen = Set<String>()
        return paths.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

private enum OfflineMaxMindLookup: Sendable {
    case missingDatabase
    case unreadableDatabase
    case miss
    case resolved(MaxMindGeoRecord)
}

private actor OfflineMaxMindDatabaseStore {
    private struct LoadedDatabases: Sendable {
        var hasExistingFile: Bool
        var databases: [MaxMindDatabase]
    }

    private let paths: [String]
    private var loadedDatabases: LoadedDatabases?

    init(paths: [String]) {
        self.paths = paths
    }

    func lookup(_ ip: String, language: AppLanguage) -> OfflineMaxMindLookup {
        guard !Task.isCancelled else { return .miss }
        let loaded = loadIfNeeded()
        guard !loaded.databases.isEmpty else {
            return loaded.hasExistingFile ? .unreadableDatabase : .missingDatabase
        }

        var merged = MaxMindGeoRecord()
        var foundRecord = false
        for database in loaded.databases {
            guard !Task.isCancelled else { return .miss }
            guard let value = try? database.lookup(ip) else { continue }
            foundRecord = true
            merged.merge(MaxMindGeoRecord(value: value, language: language))
        }

        guard foundRecord, !merged.isEmpty else { return .miss }
        return .resolved(merged)
    }

    private func loadIfNeeded() -> LoadedDatabases {
        if let loadedDatabases {
            return loadedDatabases
        }

        let existingURLs = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let loaded = LoadedDatabases(
            hasExistingFile: !existingURLs.isEmpty,
            databases: existingURLs.compactMap { try? MaxMindDatabase(contentsOf: $0) }
        )
        loadedDatabases = loaded
        return loaded
    }
}

private func geoIPLanguageCode(for language: AppLanguage) -> String {
    MicaStrings.resolvedLanguageCode(for: language)
}

private func resolvedGeoIPLanguage(_ language: AppLanguage) -> AppLanguage {
    geoIPLanguageCode(for: language) == AppLanguage.simplifiedChinese.rawValue
        ? .simplifiedChinese
        : .english
}

// MARK: - Session cache

/// Generation-scoped IP → result cache for Overview network enrichment.
struct GeoIPSessionCache: Equatable, Sendable {
    private(set) var generation: UUID?
    private var results: [CacheKey: GeoIPLookupResult] = [:]

    mutating func bind(generation: UUID) {
        if self.generation != generation {
            self.generation = generation
            results.removeAll(keepingCapacity: true)
        }
    }

    mutating func invalidate() {
        generation = nil
        results.removeAll(keepingCapacity: true)
    }

    subscript(ip: String) -> GeoIPLookupResult? {
        get { results[CacheKey(ip: ip, languageCode: AppLanguage.english.rawValue)] }
        set {
            let key = CacheKey(ip: ip, languageCode: AppLanguage.english.rawValue)
            if let newValue {
                results[key] = newValue
            } else {
                results.removeValue(forKey: key)
            }
        }
    }

    mutating func store(
        _ result: GeoIPLookupResult,
        generation: UUID,
        language: AppLanguage = .english
    ) {
        bind(generation: generation)
        results[CacheKey(ip: result.ip, languageCode: geoIPLanguageCode(for: language))] = result
    }

    func result(
        for ip: String,
        generation: UUID,
        language: AppLanguage = .english
    ) -> GeoIPLookupResult? {
        guard self.generation == generation else { return nil }
        return results[CacheKey(ip: ip, languageCode: geoIPLanguageCode(for: language))]
    }

    private struct CacheKey: Hashable, Sendable {
        var ip: String
        var languageCode: String
    }
}

/// Coordinates offline GeoIP lookups with a generation-scoped session cache.
@MainActor
final class GeoIPSessionCoordinator {
    private let resolver: any GeoIPResolving
    private(set) var cache = GeoIPSessionCache()
    private var inFlight: [LookupKey: InFlightLookup] = [:]
    private var nextLookupToken: UInt64 = 0

    init(resolver: any GeoIPResolving = OfflineLocalGeoIPResolver()) {
        self.resolver = resolver
    }

    func invalidate() {
        cancelInFlightLookups()
        cache.invalidate()
    }

    func bind(generation: UUID) {
        if cache.generation != generation {
            cancelInFlightLookups()
        }
        cache.bind(generation: generation)
    }

    func cachedResult(
        for ip: String,
        generation: UUID,
        language: AppLanguage = MicaStrings.appLanguage
    ) -> GeoIPLookupResult? {
        cache.result(
            for: ip,
            generation: generation,
            language: resolvedGeoIPLanguage(language)
        )
    }

    /// Best-effort offline lookup. Duplicate requests await one shared task.
    func lookup(
        ip: String,
        generation: UUID,
        language: AppLanguage = MicaStrings.appLanguage
    ) async -> GeoIPLookupResult {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLanguage = resolvedGeoIPLanguage(language)
        guard cache.generation == generation else {
            return .unavailable(ip: trimmed)
        }

        if trimmed.isEmpty || IPAddressClassification.isNonPublic(trimmed) {
            let result = GeoIPLookupResult.unavailable(ip: trimmed)
            cache.store(result, generation: generation, language: resolvedLanguage)
            return result
        }

        if let cached = cache.result(
            for: trimmed,
            generation: generation,
            language: resolvedLanguage
        ),
           cached.status != .pending {
            return cached
        }

        let lookupKey = LookupKey(
            generation: generation,
            ip: trimmed,
            languageCode: geoIPLanguageCode(for: resolvedLanguage)
        )
        let lookup: InFlightLookup
        if let existing = inFlight[lookupKey] {
            lookup = existing
        } else {
            let pending = GeoIPLookupResult.pending(ip: trimmed)
            cache.store(pending, generation: generation, language: resolvedLanguage)

            let resolver = resolver
            let task = Task(priority: .utility) { @concurrent in
                await resolver.resolve(trimmed, language: resolvedLanguage)
            }
            nextLookupToken &+= 1
            lookup = InFlightLookup(token: nextLookupToken, task: task)
            inFlight[lookupKey] = lookup
        }

        let resolved = await lookup.task.value

        guard inFlight[lookupKey]?.token == lookup.token else {
            if let cached = cache.result(
                for: trimmed,
                generation: generation,
                language: resolvedLanguage
            ), cached.status != .pending {
                return cached
            }
            return .unavailable(ip: trimmed)
        }
        inFlight.removeValue(forKey: lookupKey)

        guard cache.generation == generation else { return .unavailable(ip: trimmed) }
        let terminalResult = resolved.status == .pending
            ? GeoIPLookupResult.unavailable(ip: trimmed)
            : resolved
        cache.store(terminalResult, generation: generation, language: resolvedLanguage)
        return terminalResult
    }

    private func cancelInFlightLookups() {
        for lookup in inFlight.values {
            lookup.task.cancel()
        }
        inFlight.removeAll()
    }

    private struct LookupKey: Hashable {
        var generation: UUID
        var ip: String
        var languageCode: String
    }

    private struct InFlightLookup {
        var token: UInt64
        var task: Task<GeoIPLookupResult, Never>
    }
}
