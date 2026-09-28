import Foundation

@main struct KeyboardPreferencesChecks {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let mode = CommandLine.arguments[2]
        if mode == "write" {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            precondition(SKKeyboardPreferences.load(from: directory).shuangpinLearningMode)
            try SKKeyboardPreferences(shuangpinLearningMode: false).save(to: directory)
        } else {
            precondition(!SKKeyboardPreferences.load(from: directory).shuangpinLearningMode,
                         "A new process must read the disabled learning mode")
            try SKKeyboardPreferences(shuangpinLearningMode: true).save(to: directory)
            precondition(SKKeyboardPreferences.load(from: directory).shuangpinLearningMode)
            try Data("{broken".utf8).write(to: directory.appendingPathComponent("keyboard-preferences.json"))
            precondition(SKKeyboardPreferences.load(from: directory).shuangpinLearningMode)
            precondition(SKKeyboardPreferences.load(from: nil).shuangpinLearningMode)
            do {
                try SKKeyboardPreferences().save(to: nil)
                fatalError("Unavailable shared storage must not silently claim success")
            } catch { }
        }
        print("PASS: keyboard display preferences \(mode)")
    }
}
