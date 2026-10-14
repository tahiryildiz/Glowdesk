import Foundation

/// Coalesces rapid updates (slider drags) per resource. The first update goes out at once,
/// later ones merge into a single trailing update, so the bridge stays under its rate limit.
@MainActor final class SendThrottle {
    private var pending: [String: [String: Any]] = [:]
    private var last: [String: Date] = [:]
    private var timers: [String: Task<Void, Never>] = [:]

    func submit(_ key: String, _ body: [String: Any], interval: TimeInterval, send: @escaping @MainActor ([String: Any]) -> Void) {
        var merged = pending[key] ?? [:]
        // A color and a color temperature cannot both apply; the newest one wins.
        if body["color"] != nil { merged["color_temperature"] = nil }
        if body["color_temperature"] != nil { merged["color"] = nil }
        merged.merge(body) { _, new in new }
        let elapsed = Date().timeIntervalSince(last[key] ?? .distantPast)
        if timers[key] == nil, elapsed >= interval {
            last[key] = Date(); pending[key] = nil
            send(merged)
            return
        }
        pending[key] = merged
        guard timers[key] == nil else { return }
        let delay = max(0.01, interval - elapsed)
        timers[key] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.timers[key] = nil
            if let body = self.pending.removeValue(forKey: key) { self.last[key] = Date(); send(body) }
        }
    }
    func cancelAll() {
        timers.values.forEach { $0.cancel() }
        timers.removeAll(); pending.removeAll()
    }
}
