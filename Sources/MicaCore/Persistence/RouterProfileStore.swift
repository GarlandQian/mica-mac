import Foundation

public protocol RouterProfileStore: Sendable {
    func loadProfiles() async throws -> [RouterProfile]
    func saveProfiles(_ profiles: [RouterProfile]) async throws
}

public actor JSONRouterProfileStore: RouterProfileStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadProfiles() async throws -> [RouterProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([RouterProfile].self, from: data)
    }

    public func saveProfiles(_ profiles: [RouterProfile]) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(profiles)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return appSupport
            .appendingPathComponent("Mica", isDirectory: true)
            .appendingPathComponent("routers.json")
    }
}

public actor InMemoryRouterProfileStore: RouterProfileStore {
    private var profiles: [RouterProfile]

    public init(profiles: [RouterProfile] = []) {
        self.profiles = profiles
    }

    public func loadProfiles() async throws -> [RouterProfile] {
        profiles
    }

    public func saveProfiles(_ profiles: [RouterProfile]) async throws {
        self.profiles = profiles
    }
}
