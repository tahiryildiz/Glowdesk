import Foundation
import CryptoKit

/// Pins the bridge's TLS certificate on first pairing (trust on first use).
/// Hue bridges use a certificate macOS does not trust, so the fingerprint is the identity check.
final class CertificatePinner: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var pinned: String?
    private let allowFirstUse: Bool
    private var observedValue: String?
    private var rejectedValue = false
    init(pinned: String?, allowFirstUse: Bool) { self.pinned = pinned; self.allowFirstUse = allowFirstUse }
    var observed: String? { lock.withLock { observedValue } }
    var rejected: Bool { lock.withLock { rejectedValue } }

    static func fingerprint(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        evaluate(challenge, completionHandler: completionHandler)
    }

    /// Streaming tasks (`bytes(for:)`) deliver the server-trust challenge at task level;
    /// without this the event stream fell back to the system check and was rejected.
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        evaluate(challenge, completionHandler: completionHandler)
    }

    private func evaluate(_ challenge: URLAuthenticationChallenge,
                          completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            completionHandler(.performDefaultHandling, nil); return
        }
        let fingerprint = Self.fingerprint(SecCertificateCopyData(leaf) as Data)
        let accepted: Bool = lock.withLock {
            observedValue = fingerprint
            if let pinned { rejectedValue = pinned != fingerprint; return !rejectedValue }
            if allowFirstUse { pinned = fingerprint; return true }
            rejectedValue = true
            return false
        }
        if accepted { completionHandler(.useCredential, URLCredential(trust: trust)) }
        else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}

struct HueEventBatch: @unchecked Sendable {
    let kind: String
    let items: [[String: Any]]
}

/// Thin wrapper over the bridge's local CLIP v2 API.
final class HueClient: @unchecked Sendable {
    let host: String
    let appKey: String?
    let pinner: CertificatePinner
    private let session: URLSession
    private let streamSession: URLSession
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()

    init(host: String, appKey: String?, pinner: CertificatePinner) {
        self.host = host; self.appKey = appKey; self.pinner = pinner
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: pinner, delegateQueue: nil)
        let stream = URLSessionConfiguration.ephemeral
        // The event stream can be silent for a long time; reconnecting after an idle spell is harmless.
        stream.timeoutIntervalForRequest = 300
        stream.timeoutIntervalForResource = 7 * 86400
        streamSession = URLSession(configuration: stream, delegate: pinner, delegateQueue: nil)
    }
    func close() { session.invalidateAndCancel(); streamSession.invalidateAndCancel() }

    /// Accepts dotted IPv4 addresses on private ranges, or `.local` hostnames.
    static func isLocalHost(_ host: String) -> Bool {
        if host.hasSuffix(".local"), host.count > 6, host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }) { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 != nil && (0...255).contains($0!) }) else { return false }
        let p = parts.map { $0! }
        return p[0] == 10 || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 192 && p[1] == 168) || (p[0] == 169 && p[1] == 254)
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://\(host)\(path)")!)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let appKey { request.setValue(appKey, forHTTPHeaderField: "hue-application-key") }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw translate(error) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw HueError.unauthorized }
        if status == 429 { throw HueError.message(t("The bridge is getting commands too fast. Slow down a little.")) }
        guard (200..<300).contains(status) else {
            let detail = (try? Self.decoder.decode(HueEnvelope<EmptyResource>.self, from: data))?.errors.first?.description
            throw HueError.message(detail ?? t("The bridge returned HTTP %d.", status))
        }
        return data
    }
    private func translate(_ error: Error) -> Error {
        if pinner.rejected { return HueError.certificateChanged }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost:
                return HueError.unreachable(host)
            default: break
            }
        }
        return error
    }

    func config() async throws -> BridgeConfig {
        try Self.decoder.decode(BridgeConfig.self, from: try await perform(request("/api/0/config")))
    }

    /// Asks the bridge for an application key. Throws `.linkButtonNotPressed` until the button is pressed.
    func pair(deviceType: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["devicetype": deviceType, "generateclientkey": true])
        let data = try await perform(request("/api", method: "POST", body: body))
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = array.first else {
            throw HueError.message(t("The bridge sent an unexpected reply."))
        }
        if let success = first["success"] as? [String: Any], let key = success["username"] as? String { return key }
        if let error = first["error"] as? [String: Any] {
            if error["type"] as? Int == 101 { throw HueError.linkButtonNotPressed }
            throw HueError.message(error["description"] as? String ?? t("The bridge refused pairing."))
        }
        throw HueError.message(t("The bridge sent an unexpected reply."))
    }

    func resources<T: Decodable>(_ type: String, as: T.Type) async throws -> [T] {
        let envelope = try Self.decoder.decode(HueEnvelope<T>.self, from: try await perform(request("/clip/v2/resource/\(type)")))
        if envelope.data.isEmpty, let error = envelope.errors.first { throw HueError.message(error.description) }
        return envelope.data
    }

    func update(_ type: String, id: String, body: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: body)
        DebugLog.write("PUT \(type)/\(id) \(DebugLog.json(body))")
        do {
            let reply = try await perform(request("/clip/v2/resource/\(type)/\(id)", method: "PUT", body: data))
            DebugLog.write("  ok \(String(decoding: reply.prefix(300), as: UTF8.self))")
        } catch {
            DebugLog.write("  failed \(error.localizedDescription)")
            throw error
        }
    }

    /// Server-sent events from `/eventstream/clip/v2`, one batch per bridge event.
    func events() -> AsyncThrowingStream<HueEventBatch, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = self.request("/eventstream/clip/v2")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await self.streamSession.bytes(for: request, delegate: self.pinner)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let http = response as? HTTPURLResponse
                    DebugLog.write("events open HTTP \(status) \(http?.value(forHTTPHeaderField: "Content-Type") ?? "-")")
                    if status == 401 || status == 403 { throw HueError.unauthorized }
                    guard status == 200 else { throw HueError.message(t("Couldn't open the live update stream (HTTP %d).", status)) }
                    for try await line in bytes.lines {
                        DebugLog.write("events line \(line.prefix(400))")
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let events = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [[String: Any]] else { continue }
                        for event in events {
                            guard let kind = event["type"] as? String, let items = event["data"] as? [[String: Any]] else { continue }
                            continuation.yield(HueEventBatch(kind: kind, items: items))
                        }
                    }
                    DebugLog.write("events ended")
                    continuation.finish()
                } catch {
                    DebugLog.write("events error \(error.localizedDescription)")
                    continuation.finish(throwing: self.translate(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct EmptyResource: Decodable {}
