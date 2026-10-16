import Foundation
import CoreGraphics

/// Offline checks: no bridge, no Keychain, no saved preferences.
@MainActor enum FeatureChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
        print("ok  \(message)")
    }

    static let sampleLights = """
    {"errors":[],"data":[
     {"id":"l1","type":"light","owner":{"rid":"d1","rtype":"device"},"metadata":{"name":"Desk","archetype":"table_shade"},
      "on":{"on":true},"dimming":{"brightness":60.5,"min_dim_level":0.2},
      "color_temperature":{"mirek":null,"mirek_valid":false,"mirek_schema":{"mirek_minimum":153,"mirek_maximum":500}},
      "color":{"xy":{"x":0.675,"y":0.322},"gamut":{"red":{"x":0.6915,"y":0.3083},"green":{"x":0.17,"y":0.7},"blue":{"x":0.1532,"y":0.0475}},"gamut_type":"C"},
      "mode":"normal"},
     {"id":"l2","type":"light","owner":{"rid":"d2","rtype":"device"},"metadata":{"name":"Ceiling","archetype":"ceiling_round"},
      "on":{"on":false},"dimming":{"brightness":100},
      "color_temperature":{"mirek":366,"mirek_valid":true,"mirek_schema":{"mirek_minimum":153,"mirek_maximum":454}}}
    ]}
    """
    static let sampleRooms = """
    {"errors":[],"data":[{"id":"r1","type":"room","children":[{"rid":"d1","rtype":"device"},{"rid":"d2","rtype":"device"}],
     "services":[{"rid":"g1","rtype":"grouped_light"}],"metadata":{"name":"Den","archetype":"living_room"}}]}
    """
    static let sampleScenes = """
    {"errors":[],"data":[{"id":"s1","type":"scene","metadata":{"name":"Sunset"},"group":{"rid":"r1","rtype":"room"},
     "actions":[{"target":{"rid":"l1","rtype":"light"},"action":{"on":{"on":true},"dimming":{"brightness":80},"color":{"xy":{"x":0.55,"y":0.4}}}}],
     "palette":{"color":[{"color":{"xy":{"x":0.6,"y":0.35}},"dimming":{"brightness":70}},{"color":{"xy":{"x":0.2,"y":0.1}},"dimming":{"brightness":70}}],
     "dimming":[],"color_temperature":[]},"speed":0.6,"status":{"active":"static"}}]}
    """

    static func run() async throws {
        // Decoding
        let lights = try HueClient.decoder.decode(HueEnvelope<HueLight>.self, from: Data(sampleLights.utf8)).data
        try expect(lights.count == 2 && lights[0].metadata.name == "Desk", "lights decode")
        try expect(lights[0].supportsColor && lights[0].colorTemperature?.mirekValid == false, "color light is in xy mode")
        try expect(!lights[1].supportsColor && lights[1].supportsTemperature && lights[1].mirekRange.upperBound == 454, "white light temperature range")
        let rooms = try HueClient.decoder.decode(HueEnvelope<HueGroup>.self, from: Data(sampleRooms.utf8)).data
        try expect(rooms.first?.groupedLightID == "g1", "room finds its grouped_light")
        let scenes = try HueClient.decoder.decode(HueEnvelope<HueScene>.self, from: Data(sampleScenes.utf8)).data
        try expect(scenes.first?.isActive == true && scenes.first?.swatches.count == 2, "scene palette and status")

        // Color math
        let red = ColorMath.rgbToXY(RGB(r: 1, g: 0, b: 0))
        try expect(abs(red.x - 0.7006) < 0.01 && abs(red.y - 0.2993) < 0.01, "red → xy (\(red.x), \(red.y))")
        for hue in stride(from: 0.0, to: 1.0, by: 0.1) {
            let original = RGB.hsb(hue, 1, 1)
            let back = ColorMath.xyToRGB(ColorMath.rgbToXY(original))
            let delta = abs(back.hueSaturation.hue - original.hueSaturation.hue)
            try expect(min(delta, 1 - delta) < 0.03, "color round trip keeps hue (hue \(String(format: "%.1f", hue)))")
        }
        let warm = ColorMath.mirekToRGB(500), cool = ColorMath.mirekToRGB(153)
        try expect(warm.r > warm.b + 0.4 && cool.b > 0.9, "mirek colors warm and cool")
        try expect(ColorMath.kelvin(370) == 2700, "mirek → kelvin")

        // Store wiring on top of decoded resources
        let suite = "hue.selfcheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = HueStore(defaults: defaults, dataDirectory: temp)
        store.lights = Dictionary(uniqueKeysWithValues: lights.map { ($0.id, $0) })
        store.rooms = rooms
        store.grouped = ["g1": HueGroupedLight(id: "g1", owner: ResourceRef(rid: "r1", rtype: "room"), on: .init(on: true), dimming: .init(brightness: 60))]
        try expect(store.lights(in: rooms[0]).count == 2, "room lights resolve through devices")
        try expect(store.isOn(rooms[0]) && store.litLights.count == 1, "room state and lit count")
        store.apply(HueEventBatch(kind: "update", items: [["id": "l2", "type": "light", "on": ["on": true], "dimming": ["brightness": 42.0]]]))
        try expect(store.lights["l2"]?.on.on == true && store.lights["l2"]?.brightness == 42, "event stream updates a light")
        store.apply(HueEventBatch(kind: "update", items: [["id": "l1", "type": "light", "color": ["xy": ["x": 0.17, "y": 0.7]]]]))
        try expect(store.lights["l1"]?.color?.xy.y == 0.7, "event stream updates color")
        try expect(store.accent != HueStore.defaultAccent, "accent comes from lit lights")
        // "All on" goes through the home group; a room's own grouped_light cache can stay stale.
        store.grouped["g1"]?.on = .init(on: false)
        try expect(store.isOn(rooms[0]) && store.brightness(rooms[0]) > 0, "room state follows lights, not a stale group cache")
        store.home = HueGroup(id: "h", type: "bridge_home", children: [], services: [ResourceRef(rid: "gh", rtype: "grouped_light")], metadata: nil)
        store.grouped["gh"] = HueGroupedLight(id: "gh", owner: ResourceRef(rid: "h", rtype: "bridge_home"), on: .init(on: true), dimming: nil)
        store.setAll(on: false)
        try expect(!store.isOn(rooms[0]) && !store.anyOn, "all off turns rooms off")
        store.setAll(on: true)
        try expect(store.isOn(rooms[0]) && store.lights(in: rooms[0]).allSatisfy(\.on.on), "room channel shows on after all on")

        // Activity journal
        store.connected = true
        store.tickUsage(now: Date())
        store.tickUsage(now: Date().addingTimeInterval(30))
        let usage = store.usage(days: 1)
        try expect(usage.first?.id == "r1" && Int(usage.first?.seconds ?? 0) == 30, "history records time")
        store.tickUsage(now: Date().addingTimeInterval(400))
        try expect(Int(store.usage(days: 1).first?.seconds ?? 0) == 30, "sleep gaps are not counted")

        // Throttle: one immediate send, then one merged trailing send.
        let throttle = SendThrottle()
        var sent: [[String: Any]] = []
        throttle.submit("light/x", ["on": ["on": true]], interval: 0.2) { sent.append($0) }
        throttle.submit("light/x", ["dimming": ["brightness": 10]], interval: 0.2) { sent.append($0) }
        throttle.submit("light/x", ["color": ["xy": ["x": 0.3, "y": 0.3]]], interval: 0.2) { sent.append($0) }
        throttle.submit("light/x", ["color_temperature": ["mirek": 300]], interval: 0.2) { sent.append($0) }
        try expect(sent.count == 1, "first command goes out at once")
        try await Task.sleep(nanoseconds: 350_000_000)
        try expect(sent.count == 2 && sent[1]["dimming"] != nil && sent[1]["color_temperature"] != nil && sent[1]["color"] == nil, "rapid commands merge")

        // Fader detents sit at 25, 50 and 75.
        try expect(Detent.band(24.9) == 0 && Detent.band(25) == 1 && Detent.band(74) == 2 && Detent.band(100) == 3, "fader detents at 25/50/75")
        try expect(!MenuBarIcon.image(on: true, syncing: false).isTemplate && MenuBarIcon.image(on: false, syncing: false).isTemplate,
                   "menu icon is yellow when on, system color when off")

        // Scrolling over the menu bar icon shifts every lit light by the same amount.
        store.connected = true
        store.setAll(on: false)
        store.nudgeAll(by: -10)
        try expect(!store.anyOn, "scrolling down with all off does nothing")
        store.nudgeAll(by: 5)
        try expect(store.anyOn, "scrolling up with all off turns lights on")
        let before = store.litLights.map(\.brightness)
        store.nudgeAll(by: 10)
        try expect(zip(before, store.litLights.map(\.brightness)).allSatisfy { abs($1 - min(100, $0 + 10)) < 0.001 }, "scrolling shifts every lit light equally")
        store.nudgeAll(by: -500)
        try expect(store.litLights.allSatisfy { $0.brightness == 1 } && store.anyOn, "scrolling down dims to minimum without turning off")

        // An unreachable bridge takes the panel offline instead of showing unconfirmed lights.
        store.connected = true
        store.handle(HueError.unreachable("192.168.1.20"))
        try expect(!store.connected && store.status == "Offline" && store.error?.contains("192.168.1.20") == true,
                   "unreachable bridge goes offline with a clear message")
        store.error = nil

        // Icons chosen in the Hue app map to symbols that exist on this Mac.
        try expect(HueIcons.missing.isEmpty, "all mapped icons exist (missing: \(HueIcons.missing))")
        try expect(HueIcons.light("table_shade") == "lamp.table" && HueIcons.light("made_up") == "lightbulb" && HueIcons.room("kitchen") == "refrigerator",
                   "archetypes map to icons, unknown ones fall back")

        // Language switches live and falls back to English for unknown keys.
        let savedLanguage = L10n.language
        L10n.language = L10n.resolve(.tr)
        try expect(t("Rooms") == "Odalar" && t("%d lights on", 3) == "3 ışık açık" && t("%d of %d lights on", 3, 4) == "4 lambadan 3 tanesi açık",
                   "Turkish strings, plural and positional formats")
        L10n.language = L10n.resolve(.en)
        try expect(t("Rooms") == "Rooms" && durationText(3725) == "1 h 2 min", "English strings and durations")
        L10n.language = savedLanguage

        // Host validation
        try expect(HueClient.isLocalHost("192.168.1.20") && HueClient.isLocalHost("001788abcdef.local"), "local addresses accepted")
        try expect(!HueClient.isLocalHost("8.8.8.8") && !HueClient.isLocalHost("example.com") && !HueClient.isLocalHost("192.168.1"), "outside addresses rejected")

        // Screen reduction picks the saturated subject over a gray background.
        if let image = makeTestImage() {
            let sample = ScreenSampler.reduce(image)
            try expect(sample.rgb.b > sample.rgb.r && sample.rgb.b > 0.8, "screen sample picks the dominant color")
        }
        print("All checks passed.")
    }

    private static func makeTestImage() -> CGImage? {
        guard let context = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.3, blue: 1, alpha: 1)); context.fill(CGRect(x: 20, y: 10, width: 20, height: 14))
        return context.makeImage()
    }
}
