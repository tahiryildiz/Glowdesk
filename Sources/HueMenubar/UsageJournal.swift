import Foundation

struct UsageTotal: Identifiable {
    let id: String
    let name: String
    let seconds: TimeInterval
}

/// Seconds each room spent with at least one light on, per local day. Only time this Mac observed counts.
final class UsageJournal {
    private struct Storage: Codable { var days: [String: [String: Double]] = [:]; var names: [String: String] = [:] }
    private var storage: Storage
    private let url: URL
    private static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    init(url: URL) {
        self.url = url
        storage = (try? JSONDecoder().decode(Storage.self, from: Data(contentsOf: url))) ?? Storage()
    }
    func record(rooms: [(id: String, name: String)], seconds: Double, at date: Date = Date()) {
        guard seconds > 0 else { return }
        let key = Self.dayFormat.string(from: date)
        for room in rooms {
            storage.days[key, default: [:]][room.id, default: 0] += seconds
            storage.names[room.id] = room.name
        }
        let cutoff = Self.dayFormat.string(from: date.addingTimeInterval(-90 * 86400))
        storage.days = storage.days.filter { $0.key >= cutoff }
    }
    func totals(days: Int, now: Date = Date()) -> [UsageTotal] {
        let start = Calendar.current.startOfDay(for: now.addingTimeInterval(-Double(days - 1) * 86400))
        let first = Self.dayFormat.string(from: start)
        var sums: [String: Double] = [:]
        for (day, rooms) in storage.days where day >= first {
            for (id, seconds) in rooms { sums[id, default: 0] += seconds }
        }
        return sums.map { UsageTotal(id: $0.key, name: storage.names[$0.key] ?? "Room", seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }
    func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(storage).write(to: url, options: .atomic)
    }
}
