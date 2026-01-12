import Foundation

class ReplacementManager {

    static let shared = ReplacementManager()

    private var rules: [String: String] = [:]
    private let rulesFileURL: URL

    private init() {
        // Store rules in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("TextReplacer")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        rulesFileURL = appFolder.appendingPathComponent("rules.json")

        loadRules()

        // Add default rule if no rules exist
        if rules.isEmpty {
            addRule(trigger: ";wkaeupon", replacement: "sudo pmset disablesleep 1")
        }
    }

    func addRule(trigger: String, replacement: String) {
        rules[trigger] = replacement
        saveRules()
    }

    func removeRule(trigger: String) {
        rules.removeValue(forKey: trigger)
        saveRules()
    }

    func getRules() -> [String: String] {
        return rules
    }

    func clearAllRules() {
        rules.removeAll()
        saveRules()
    }

    func findMatch(in text: String) -> (trigger: String, replacement: String)? {
        // Check if any trigger matches the end of the typed text
        for (trigger, replacement) in rules {
            if text.hasSuffix(trigger) {
                return (trigger, replacement)
            }
        }
        return nil
    }

    private func saveRules() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(rules)
            try data.write(to: rulesFileURL)
            print("Rules saved to: \(rulesFileURL.path)")
        } catch {
            print("Failed to save rules: \(error)")
        }
    }

    private func loadRules() {
        guard FileManager.default.fileExists(atPath: rulesFileURL.path) else {
            print("No rules file found at: \(rulesFileURL.path)")
            return
        }

        do {
            let data = try Data(contentsOf: rulesFileURL)
            let decoder = JSONDecoder()
            rules = try decoder.decode([String: String].self, from: data)
            print("Loaded \(rules.count) rules from: \(rulesFileURL.path)")
        } catch {
            print("Failed to load rules: \(error)")
        }
    }
}
