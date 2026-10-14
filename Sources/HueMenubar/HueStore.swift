import SwiftUI
import AppKit
import ServiceManagement

@MainActor final class HueStore: ObservableObject {
    // Saved bridge
    @Published var host: String { didSet { defaults.set(host, forKey: "hue.host") } }
    @Published var bridgeID: String { didSet { defaults.set(bridgeID, forKey: "hue.bridgeID") } }
    @Published var bridgeName: String { didSet { defaults.set(bridgeName, forKey: "hue.name") } }
    @Published var modelID = ""
    @Published var swVersion = ""
    @Published var apiVersion = ""
    // Connection
    @Published var connected = false
    @Published var connecting = false
    @Published var pairing = false
    @Published var status = "Not connected"
    @Published var error: String?
    @Published var notice: String?
    // Bridge data
    @Published var lights: [String: HueLight] = [:]
    @Published var rooms: [HueGroup] = []
    @Published var zones: [HueGroup] = []
    @Published var home: HueGroup?
    @Published var grouped: [String: HueGroupedLight] = [:]
    @Published var devices: [String: HueDevice] = [:]
    @Published var scenes: [HueScene] = []
    // Discovery
    @Published var discovering = false
    @Published var discovered: [DiscoveredBridge] = []
    // Panel
    @Published var preferredPanelHeight: CGFloat = 700
    /// Set by the app delegate; the panel replays its opening moment each time this turns true.
    @Published var panelVisible = false
    /// Tallest the panel can be on the current screen; set by the app delegate.
    @Published var maxPanelHeight: CGFloat = 800
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "hue.language"); L10n.language = L10n.resolve(language) } }
    @Published var favoriteScenes: Set<String> { didSet { defaults.set(Array(favoriteScenes), forKey: "hue.favoriteScenes") } }
    @Published var usageRevision = 0
    // Screen sync
    @Published var syncGroupID: String? { didSet { defaults.set(syncGroupID, forKey: "hue.syncGroup") } }
    @Published var syncing = false
    @Published var syncColor: RGB?
    @Published var syncMaxBrightness: Double { didSet { defaults.set(syncMaxBrightness, forKey: "hue.syncMax") } }
    @Published var syncRestore: Bool { didSet { defaults.set(syncRestore, forKey: "hue.syncRestore") } }

    private let defaults: UserDefaults
    private var client: HueClient?
    private var connectTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var pairTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var usageTimer: Timer?
    private var lastUsageTick: Date?
    private var syncSnapshot: [String: [String: Any]] = [:]
    private var touched: [String: Date] = [:]
    private var pendingNudge = 0.0
    private var nudgeTask: Task<Void, Never>?
    private let throttle = SendThrottle()
    let journal: UsageJournal
    private var observers: [NSObjectProtocol] = []
    static let defaultAccent = RGB(r: 1, g: 0.70, b: 0.32)

    init(defaults: UserDefaults = .standard, dataDirectory: URL? = nil) {
        self.defaults = defaults
        host = defaults.string(forKey: "hue.host") ?? ""
        bridgeID = defaults.string(forKey: "hue.bridgeID") ?? ""
        bridgeName = defaults.string(forKey: "hue.name") ?? "Hue Bridge"
        favoriteScenes = Set(defaults.stringArray(forKey: "hue.favoriteScenes") ?? [])
        syncGroupID = defaults.string(forKey: "hue.syncGroup")
        syncMaxBrightness = defaults.object(forKey: "hue.syncMax") as? Double ?? 80
        syncRestore = defaults.object(forKey: "hue.syncRestore") as? Bool ?? true
        let savedLanguage = AppLanguage(rawValue: defaults.string(forKey: "hue.language") ?? "") ?? .system
        language = savedLanguage
        L10n.language = L10n.resolve(savedLanguage)
        let directory = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("local.HueMenubar")
        journal = UsageJournal(url: directory.appendingPathComponent("usage.json"))
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickUsage(); self?.lastUsageTick = nil; self?.stopSync() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPaired == true { self?.connect() } }
        })
        usageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tickUsage() } }
        if isPaired { connect() }
    }

    // MARK: Derived state

    var isPaired: Bool { !host.isEmpty && !bridgeID.isEmpty && KeychainItem.appKey.read(bridgeID) != nil }
    var allLights: [HueLight] { lights.values.sorted { $0.metadata.name.localizedStandardCompare($1.metadata.name) == .orderedAscending } }
    var litLights: [HueLight] { allLights.filter(\.on.on) }
    var anyOn: Bool { lights.values.contains { $0.on.on } }
    var accent: RGB { ColorMath.accent(for: litLights.map(\.displayRGB)) ?? Self.defaultAccent }
    var groups: [HueGroup] { rooms + zones }
    var activeScene: HueScene? { scenes.first { $0.isActive } }

    func lights(in group: HueGroup) -> [HueLight] {
        let ids: Set<String>
        switch group.type {
        case "bridge_home": return allLights
        case "zone": ids = Set(group.children.filter { $0.rtype == "light" }.map(\.rid))
        default:
            let deviceIDs = Set(group.children.filter { $0.rtype == "device" }.map(\.rid))
            ids = Set(lights.values.filter { deviceIDs.contains($0.owner.rid) }.map(\.id))
        }
        return allLights.filter { ids.contains($0.id) }
    }
    /// Lights are the source of truth: a room's grouped_light cache can lag behind
    /// commands sent to the whole home, so it is only a fallback for empty groups.
    func isOn(_ group: HueGroup) -> Bool {
        let members = lights(in: group)
        if !members.isEmpty { return members.contains { $0.on.on } }
        return grouped[group.groupedLightID ?? ""]?.on?.on ?? false
    }
    func brightness(_ group: HueGroup) -> Double {
        let lit = lights(in: group).filter(\.on.on)
        guard !lit.isEmpty else { return grouped[group.groupedLightID ?? ""]?.dimming?.brightness ?? 0 }
        return lit.map(\.brightness).reduce(0, +) / Double(lit.count)
    }
    func color(_ group: HueGroup) -> RGB { ColorMath.accent(for: lights(in: group).filter(\.on.on).map(\.displayRGB)) ?? RGB(r: 0.45, g: 0.45, b: 0.47) }
    func scenes(for groupID: String) -> [HueScene] {
        scenes.filter { $0.group.rid == groupID }.sorted { $0.metadata.name.localizedStandardCompare($1.metadata.name) == .orderedAscending }
    }
    func group(for scene: HueScene) -> HueGroup? { groups.first { $0.id == scene.group.rid } }
    func room(of light: HueLight) -> HueGroup? { rooms.first { $0.children.contains { $0.rid == light.owner.rid } } }
    var favoriteSceneList: [HueScene] { scenes.filter { favoriteScenes.contains($0.id) }.sorted { $0.metadata.name < $1.metadata.name } }
    var unassignedLights: [HueLight] { allLights.filter { room(of: $0) == nil } }

    // MARK: Connection

    func connect() {
        guard !host.isEmpty, !bridgeID.isEmpty, let key = KeychainItem.appKey.read(bridgeID) else {
            status = "Pairing needed"; return
        }
        reconnectTask?.cancel(); connectTask?.cancel(); eventTask?.cancel()
        client?.close()
        let pin = KeychainItem.certificate.read(bridgeID)
        let client = HueClient(host: host, appKey: key, pinner: CertificatePinner(pinned: pin, allowFirstUse: pin == nil))
        self.client = client
        connecting = true; status = "Connecting…"
        connectTask = Task {
            do {
                let config = try await client.config()
                guard config.bridgeid.lowercased() == bridgeID.lowercased() else {
                    throw HueError.message(t("A different bridge (%@) answers at %@. Choose the right bridge in Settings.", config.name, host))
                }
                if pin == nil, let fingerprint = client.pinner.observed { try KeychainItem.certificate.save(fingerprint, account: bridgeID) }
                apply(config)
                try await load(client)
                guard !Task.isCancelled else { return }
                connected = true; connecting = false; error = nil
                status = "Connected"
                lastUsageTick = Date()
                startEvents(client)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                connecting = false; connected = false
                handle(error)
                scheduleReconnect(after: 15)
            }
        }
    }

    func disconnect() {
        connectTask?.cancel(); eventTask?.cancel(); reconnectTask?.cancel(); pairTask?.cancel()
        stopSync()
        throttle.cancelAll()
        tickUsage(); lastUsageTick = nil
        client?.close(); client = nil
        connected = false; connecting = false; pairing = false
        status = isPaired ? "Disconnected" : "Not connected"
    }

    private func scheduleReconnect(after seconds: Double) {
        reconnectTask?.cancel()
        guard isPaired else { return }
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, !connected, !connecting else { return }
            connect()
        }
    }

    private func apply(_ config: BridgeConfig) {
        bridgeName = config.name
        modelID = config.modelid
        swVersion = config.swversion ?? ""
        apiVersion = config.apiversion ?? ""
    }

    private func load(_ client: HueClient) async throws {
        async let lightList = client.resources("light", as: HueLight.self)
        async let roomList = client.resources("room", as: HueGroup.self)
        async let zoneList = client.resources("zone", as: HueGroup.self)
        async let homeList = client.resources("bridge_home", as: HueGroup.self)
        async let groupedList = client.resources("grouped_light", as: HueGroupedLight.self)
        async let deviceList = client.resources("device", as: HueDevice.self)
        async let sceneList = client.resources("scene", as: HueScene.self)
        let (l, r, z, h, g, d, s) = try await (lightList, roomList, zoneList, homeList, groupedList, deviceList, sceneList)
        lights = Dictionary(uniqueKeysWithValues: l.map { ($0.id, $0) })
        rooms = r.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        zones = z.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        home = h.first
        grouped = Dictionary(uniqueKeysWithValues: g.map { ($0.id, $0) })
        devices = Dictionary(uniqueKeysWithValues: d.map { ($0.id, $0) })
        scenes = s
        if syncGroupID == nil || !groups.contains(where: { $0.id == syncGroupID }) { syncGroupID = rooms.first?.id }
    }

    func refresh() async {
        guard let client else { return }
        do { try await load(client); if !connected { connected = true; status = "Connected" } }
        catch { handle(error) }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func startEvents(_ client: HueClient) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                do {
                    for try await batch in client.events() {
                        failures = 0
                        self?.apply(batch)
                    }
                } catch {
                    if case HueError.unauthorized = error { self?.handle(error); return }
                    if case HueError.certificateChanged = error { self?.handle(error); return }
                    failures += 1
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: UInt64(min(30, 1 + failures * 3)) * 1_000_000_000)
                // Catch up on anything missed while the stream was down.
                await self?.refresh()
            }
        }
    }

    // MARK: Pairing

    func pair(host rawHost: String) {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HueClient.isLocalHost(host) else { error = t("Enter the bridge's local IP address, like 192.168.1.20."); return }
        disconnect()
        error = nil; notice = nil
        pairing = true; status = "Waiting for the bridge button…"
        let pinner = CertificatePinner(pinned: nil, allowFirstUse: true)
        let client = HueClient(host: host, appKey: nil, pinner: pinner)
        pairTask = Task {
            defer { client.close() }
            do {
                let config = try await client.config()
                let deviceType = "hue_menubar#" + (Host.current().localizedName ?? "mac").prefix(19)
                let deadline = Date().addingTimeInterval(45)
                while Date() < deadline {
                    try Task.checkCancellation()
                    do {
                        let key = try await client.pair(deviceType: String(deviceType))
                        try KeychainItem.appKey.save(key, account: config.bridgeid)
                        if let fingerprint = pinner.observed { try KeychainItem.certificate.save(fingerprint, account: config.bridgeid) }
                        self.host = host; bridgeID = config.bridgeid.lowercased(); apply(config)
                        pairing = false
                        notice = t("Paired with %@.", config.name)
                        connect()
                        return
                    } catch HueError.linkButtonNotPressed {
                        try await Task.sleep(nanoseconds: 1_500_000_000)
                    }
                }
                throw HueError.message(t("The bridge button wasn't pressed within 45 seconds. Try again."))
            } catch is CancellationError {
                pairing = false
            } catch {
                pairing = false; status = "Pairing failed"
                handle(error)
            }
        }
    }

    func cancelPairing() { pairTask?.cancel(); pairing = false; status = isPaired ? "Disconnected" : "Not connected" }

    func forgetPairing() {
        let id = bridgeID
        disconnect()
        do { try KeychainItem.appKey.delete(id); try KeychainItem.certificate.delete(id) } catch { handle(error) }
        bridgeID = ""
        lights = [:]; rooms = []; zones = []; home = nil; grouped = [:]; devices = [:]; scenes = []
        status = "Not connected"
        notice = t("Pairing removed. You can also revoke this Mac's access in the Hue app.")
    }

    func discover() {
        discovering = true
        Task {
            discovered = await BridgeDiscovery.search()
            discovering = false
            if discovered.isEmpty { notice = nil }
        }
    }

    var certificateFingerprint: String? { bridgeID.isEmpty ? nil : KeychainItem.certificate.read(bridgeID) }

    // MARK: Events

    func apply(_ batch: HueEventBatch) {
        DebugLog.write("apply \(batch.kind) \(batch.items.map { "\($0["type"] ?? "?")/\($0["id"] ?? "?")" }.joined(separator: ","))")
        if batch.kind == "add" || batch.kind == "delete" { scheduleRefresh(); return }
        let now = Date()
        for item in batch.items {
            guard let id = item["id"] as? String, let type = item["type"] as? String else { continue }
            if let at = touched[id], now.timeIntervalSince(at) < 1.5 { continue }
            switch type {
            case "light":
                guard var light = lights[id] else { scheduleRefresh(); continue }
                if let on = (item["on"] as? [String: Any])?["on"] as? Bool { light.on.on = on }
                if let value = (item["dimming"] as? [String: Any])?["brightness"] as? Double { light.dimming?.brightness = value }
                let temperature = item["color_temperature"] as? [String: Any]
                if let temperature {
                    if let mirek = temperature["mirek"] as? Int { light.colorTemperature?.mirek = mirek }
                    if let valid = temperature["mirek_valid"] as? Bool { light.colorTemperature?.mirekValid = valid }
                }
                if let xy = (item["color"] as? [String: Any])?["xy"] as? [String: Any], let x = xy["x"] as? Double, let y = xy["y"] as? Double {
                    light.color?.xy = XY(x: x, y: y)
                    if temperature == nil { light.colorTemperature?.mirekValid = false }
                }
                if light != lights[id] { lights[id] = light }
            case "grouped_light":
                guard var group = grouped[id] else { continue }
                if let on = (item["on"] as? [String: Any])?["on"] as? Bool { group.on = .init(on: on) }
                if let value = (item["dimming"] as? [String: Any])?["brightness"] as? Double { group.dimming = .init(brightness: value) }
                if group != grouped[id] { grouped[id] = group }
            case "scene":
                if let active = (item["status"] as? [String: Any])?["active"] as? String, let index = scenes.firstIndex(where: { $0.id == id }) {
                    scenes[index].status = .init(active: active)
                } else if item["metadata"] != nil { scheduleRefresh() }
            case "room", "zone", "device":
                if item["metadata"] != nil || item["children"] != nil || item["services"] != nil { scheduleRefresh() }
            default: break
            }
        }
    }

    // MARK: Commands

    private func send(_ type: String, _ id: String, _ body: [String: Any], interval: TimeInterval) {
        guard let client else { return }
        touched[id] = Date()
        throttle.submit("\(type)/\(id)", body, interval: interval) { [weak self] merged in
            Task {
                do { try await client.update(type, id: id, body: merged) }
                catch { self?.handle(error) }
            }
        }
    }

    private func mutateLight(_ id: String, _ change: (inout HueLight) -> Void) {
        guard var light = lights[id] else { return }
        change(&light); lights[id] = light; touched[id] = Date()
    }
    private func mutateGroup(_ group: HueGroup, on: Bool? = nil, brightness: Double? = nil) {
        guard let gid = group.groupedLightID else { return }
        var state = grouped[gid]
        if let on { state?.on = .init(on: on) }
        if let brightness { state?.dimming = .init(brightness: brightness) }
        grouped[gid] = state; touched[gid] = Date()
        // Keep the caches of rooms and zones that share these lights in step.
        if let on {
            let ids = Set(lights(in: group).map(\.id))
            for other in groups where other.id != group.id {
                guard let otherID = other.groupedLightID, lights(in: other).contains(where: { ids.contains($0.id) }) else { continue }
                grouped[otherID]?.on = .init(on: on || lights(in: other).contains { !ids.contains($0.id) && $0.on.on })
            }
        }
        for light in lights(in: group) {
            mutateLight(light.id) { l in
                if let on { l.on.on = on }
                if let brightness { l.dimming?.brightness = brightness; l.on.on = true }
            }
        }
    }

    func setLight(_ id: String, on: Bool) {
        mutateLight(id) { $0.on.on = on }
        send("light", id, ["on": ["on": on]], interval: 0.1)
    }
    func setLight(_ id: String, brightness: Double) {
        mutateLight(id) { $0.dimming?.brightness = brightness; $0.on.on = true }
        send("light", id, ["on": ["on": true], "dimming": ["brightness": brightness.rounded()]], interval: 0.12)
    }
    func setLight(_ id: String, color rgb: RGB) {
        let xy = ColorMath.rgbToXY(rgb)
        mutateLight(id) { $0.color?.xy = xy; $0.colorTemperature?.mirekValid = false; $0.on.on = true }
        send("light", id, ["on": ["on": true], "color": ["xy": ["x": xy.x, "y": xy.y]]], interval: 0.12)
    }
    func setLight(_ id: String, mirek: Int) {
        mutateLight(id) { $0.colorTemperature?.mirek = mirek; $0.colorTemperature?.mirekValid = true; $0.on.on = true }
        send("light", id, ["on": ["on": true], "color_temperature": ["mirek": mirek]], interval: 0.12)
    }
    func setGroup(_ group: HueGroup, on: Bool) {
        guard let gid = group.groupedLightID else { return }
        mutateGroup(group, on: on)
        send("grouped_light", gid, ["on": ["on": on]], interval: 0.4)
    }
    func setGroup(_ group: HueGroup, brightness: Double) {
        guard let gid = group.groupedLightID else { return }
        mutateGroup(group, brightness: brightness)
        send("grouped_light", gid, ["on": ["on": true], "dimming": ["brightness": brightness.rounded()]], interval: 0.4)
    }
    /// Color changes go to each light so mixed rooms (color and white bulbs) still respond sensibly.
    func setGroup(_ group: HueGroup, color rgb: RGB? = nil, mirek: Int? = nil) {
        let members = lights(in: group)
        let spacing = max(0.12, Double(members.count) * 0.1)
        for light in members {
            if let rgb, light.supportsColor {
                let xy = ColorMath.rgbToXY(rgb)
                mutateLight(light.id) { $0.color?.xy = xy; $0.colorTemperature?.mirekValid = false; $0.on.on = true }
                send("light", light.id, ["on": ["on": true], "color": ["xy": ["x": xy.x, "y": xy.y]]], interval: spacing)
            } else if let mirek, light.supportsTemperature {
                let value = Int(min(light.mirekRange.upperBound, max(light.mirekRange.lowerBound, Double(mirek))))
                mutateLight(light.id) { $0.colorTemperature?.mirek = value; $0.colorTemperature?.mirekValid = true; $0.on.on = true }
                send("light", light.id, ["on": ["on": true], "color_temperature": ["mirek": value]], interval: spacing)
            }
        }
    }
    func setAll(on: Bool) {
        if let home { setGroup(home, on: on) }
    }
    func toggleAll() { setAll(on: !anyOn) }

    /// Scrolling over the menu bar icon: brighten or dim every lit light by the same amount,
    /// keeping each room's own level. Scrolling up with everything off turns the lights on.
    func nudgeAll(by delta: Double) {
        guard connected, let gid = home?.groupedLightID else { return }
        guard anyOn else { if delta > 0 { setAll(on: true) }; return }
        for light in litLights {
            let next = min(100, max(1, light.brightness + delta))
            mutateLight(light.id) { $0.dimming?.brightness = next }
        }
        pendingNudge += delta
        guard nudgeTask == nil else { return }
        // One relative command per 0.4 s keeps the home group under the bridge's rate limit.
        nudgeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self else { return }
            let amount = pendingNudge
            pendingNudge = 0; nudgeTask = nil
            guard abs(amount) >= 0.5, let client else { return }
            touched[gid] = Date()
            do {
                try await client.update("grouped_light", id: gid, body: ["dimming_delta": ["action": amount > 0 ? "up" : "down", "brightness_delta": min(100, abs(amount).rounded())]])
            } catch { handle(error) }
        }
    }

    func recall(_ scene: HueScene) {
        guard let client else { return }
        for index in scenes.indices where scenes[index].group.rid == scene.group.rid { scenes[index].status = .init(active: "inactive") }
        if let index = scenes.firstIndex(where: { $0.id == scene.id }) { scenes[index].status = .init(active: "static") }
        Task {
            do {
                try await client.update("scene", id: scene.id, body: ["recall": ["action": "active"]])
                // Read the lights back once the scene's transition is done, so the panel
                // shows the new colors even if a live update is missed.
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await refresh()
            } catch { handle(error) }
        }
    }
    func toggleFavorite(_ scene: HueScene) {
        if favoriteScenes.contains(scene.id) { favoriteScenes.remove(scene.id) } else { favoriteScenes.insert(scene.id) }
    }

    // MARK: Screen sync

    func startSync() {
        guard !syncing, let groupID = syncGroupID, let group = groups.first(where: { $0.id == groupID }), let client else { return }
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            error = t("Screen sync needs Screen Recording access. Allow HueMenubar in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen the app.")
            return
        }
        let targets = lights(in: group).filter(\.supportsColor)
        guard !targets.isEmpty else { error = t("%@ has no color lights.", group.name); return }
        syncSnapshot = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, Self.restoreBody($0)) })
        error = nil
        syncing = true
        syncTask = Task { [weak self] in
            let sampler = ScreenSampler()
            var lastColor: RGB?
            var lastLuminance = -1.0
            // Each light accepts about ten commands per second in total; stay well under that.
            let interval = max(0.3, Double(targets.count) / 6)
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let sample = try await sampler.sample()
                    let changed = lastColor.map { $0.distance(to: sample.rgb) > 0.05 } ?? true || abs(sample.luminance - lastLuminance) > 0.04
                    if changed {
                        lastColor = sample.rgb; lastLuminance = sample.luminance
                        self.syncColor = sample.rgb
                        let xy = ColorMath.rgbToXY(sample.rgb)
                        let brightness = max(2, (pow(sample.luminance, 0.7) * self.syncMaxBrightness).rounded())
                        let body: [String: Any] = ["on": ["on": true], "color": ["xy": ["x": xy.x, "y": xy.y]],
                                                   "dimming": ["brightness": brightness], "dynamics": ["duration": Int(interval * 1000)]]
                        for light in targets {
                            self.mutateLight(light.id) { $0.color?.xy = xy; $0.colorTemperature?.mirekValid = false; $0.dimming?.brightness = brightness; $0.on.on = true }
                            Task { try? await client.update("light", id: light.id, body: body) }
                        }
                    }
                } catch {
                    if !Task.isCancelled { self.error = t("Couldn't read the screen: %@", error.localizedDescription); self.stopSync() }
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopSync() {
        guard syncing else { return }
        syncTask?.cancel(); syncTask = nil
        syncing = false; syncColor = nil
        if syncRestore, let client {
            for (id, body) in syncSnapshot { Task { try? await client.update("light", id: id, body: body) } }
            scheduleRefresh()
        }
        syncSnapshot = [:]
    }

    private static func restoreBody(_ light: HueLight) -> [String: Any] {
        var body: [String: Any] = ["on": ["on": light.on.on], "dynamics": ["duration": 400]]
        if light.on.on {
            if let value = light.dimming?.brightness { body["dimming"] = ["brightness": value] }
            if light.colorTemperature?.mirekValid == true, let mirek = light.colorTemperature?.mirek { body["color_temperature"] = ["mirek": mirek] }
            else if let xy = light.color?.xy { body["color"] = ["xy": ["x": xy.x, "y": xy.y]] }
        }
        return body
    }

    // MARK: Activity

    func tickUsage(now: Date = Date()) {
        defer { lastUsageTick = connected ? now : nil }
        guard connected, let last = lastUsageTick else { return }
        let elapsed = now.timeIntervalSince(last)
        // A long gap means the Mac slept or lost the bridge; that time is not counted.
        guard elapsed > 0, elapsed <= 45 else { return }
        let lit = rooms.filter { room in lights(in: room).contains { $0.on.on } }.map { (id: $0.id, name: $0.name) }
        journal.record(rooms: lit, seconds: elapsed, at: now)
        try? journal.save()
        usageRevision += 1
    }
    func usage(days: Int) -> [UsageTotal] { _ = usageRevision; return journal.totals(days: days) }

    // MARK: App

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { self.error = t("Couldn't change Open at Login: %@", error.localizedDescription) }
            objectWillChange.send()
        }
    }

    func handle(_ error: Error) {
        switch error {
        case HueError.unauthorized, HueError.certificateChanged:
            eventTask?.cancel(); connected = false; connecting = false
            status = "Pair again"
        default: break
        }
        if (error as? URLError)?.code == .cancelled { return }
        self.error = error.localizedDescription
    }
}
