import Foundation

/// One-time move from the app's earlier name (HueMenubar, bundle `local.HueMenubar`):
/// preferences, the Keychain pairing and the history folder, so nobody has to pair again.
enum LegacyMigration {
    static let oldDomain = "local.HueMenubar"
    static let keys = ["hue.host", "hue.bridgeID", "hue.name", "hue.favoriteScenes", "hue.syncGroup", "hue.syncMax", "hue.syncRestore", "hue.language"]

    static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "hue.migratedFromHueMenubar") else { return }
        defer { defaults.set(true, forKey: "hue.migratedFromHueMenubar") }

        if defaults.string(forKey: "hue.host") == nil, let old = UserDefaults(suiteName: oldDomain) {
            for key in keys { if let value = old.object(forKey: key) { defaults.set(value, forKey: key) } }
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldFolder = support.appendingPathComponent(oldDomain), newFolder = support.appendingPathComponent("Glowdesk")
        if FileManager.default.fileExists(atPath: oldFolder.path), !FileManager.default.fileExists(atPath: newFolder.path) {
            try? FileManager.default.moveItem(at: oldFolder, to: newFolder)
        }

        if let bridgeID = defaults.string(forKey: "hue.bridgeID") {
            for (item, legacyService) in [(KeychainItem.appKey, oldDomain), (.certificate, oldDomain + ".Certificate")] {
                if item.read(bridgeID) == nil, let value = KeychainItem.read(service: legacyService, account: bridgeID) {
                    try? item.save(value, account: bridgeID)
                }
            }
        }
    }
}
