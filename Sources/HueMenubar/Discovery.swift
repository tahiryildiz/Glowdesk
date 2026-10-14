import Foundation
import Network

struct DiscoveredBridge: Identifiable, Hashable {
    var id: String { bridgeID.isEmpty ? host : bridgeID }
    let name: String
    let host: String
    let bridgeID: String
}

/// Finds bridges that announce `_hue._tcp` over Bonjour on the local network. Nothing leaves the LAN.
enum BridgeDiscovery {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var results: [NWBrowser.Result] = []
        var finished = false
    }

    static func search(seconds: Double = 3) async -> [DiscoveredBridge] {
        let queue = DispatchQueue(label: "hue.discovery")
        let state = State()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_hue._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { results, _ in state.lock.withLock { state.results = Array(results) } }
        browser.start(queue: queue)
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        browser.cancel()
        let results = state.lock.withLock { state.results }

        var bridges: [DiscoveredBridge] = []
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint, let host = await resolveIPv4(result.endpoint, queue: queue) else { continue }
            var bridgeID = ""
            if case let .bonjour(txt) = result.metadata { bridgeID = txt["bridgeid"] ?? "" }
            bridges.append(DiscoveredBridge(name: name, host: host, bridgeID: bridgeID))
        }
        return bridges.sorted { $0.name < $1.name }
    }

    private static func resolveIPv4(_ endpoint: NWEndpoint, queue: DispatchQueue) async -> String? {
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: endpoint, using: parameters)
        let state = State()
        return await withCheckedContinuation { continuation in
            @Sendable func finish(_ value: String?) {
                let first = state.lock.withLock { () -> Bool in
                    if state.finished { return false }
                    state.finished = true; return true
                }
                guard first else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint, case let .ipv4(address) = host {
                        finish("\(address)".components(separatedBy: "%").first)
                    } else { finish(nil) }
                case .failed, .cancelled: finish(nil)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }
}
