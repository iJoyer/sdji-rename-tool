import Foundation

enum ConfigStore {
    static let configURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SDJI Rename Tool").appendingPathComponent("config.json")
    }()

    static func loadRules() -> RenameRules {
        guard let data = try? Data(contentsOf: configURL),
              let saved = try? JSONDecoder().decode(RenameRules.self, from: data) else {
            return RenameRules()
        }
        return saved
    }

    static func saveRules(_ rules: RenameRules) throws {
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(rules).write(to: configURL)
    }
}
