import Foundation

/// Opt-in troubleshooting log, enabled by launching with `--log`.
/// Records commands, replies and live events; never the app key.
enum DebugLog {
    static let enabled = CommandLine.arguments.contains("--log")
    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Glowdesk/debug.log")
    private static let queue = DispatchQueue(label: "hue.debuglog")
    private static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    static func write(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(stamp.string(from: Date())) \(message())\n"
        queue.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "\(object)" }
        return String(decoding: data.prefix(600), as: UTF8.self)
    }
}
