import Foundation

/// The app writes display preferences; the keyboard only reads them.
/// Input history and learned words remain in the keyboard's private container.
struct SKKeyboardPreferences: Codable, Equatable {
    var shuangpinLearningMode = true

    static var sharedDirectory: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "ShikaAppGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static func load(from directory: URL? = sharedDirectory) -> Self {
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent("keyboard-preferences.json")),
              let preferences = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return preferences
    }

    func save(to directory: URL? = Self.sharedDirectory) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent("keyboard-preferences.json"), options: .atomic)
    }
}
