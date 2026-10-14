#if DEBUG
import AppKit
import SwiftUI

/// Renders each panel tab with demo data to PNG files, for checking the design without a bridge.
@MainActor enum Snapshot {
    static func demoStore() -> HueStore {
        let suite = "hue.snapshot"
        let store = HueStore(defaults: UserDefaults(suiteName: suite)!, dataDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        func light(_ id: String, _ device: String, _ name: String, _ archetype: String, on: Bool, bri: Double, xy: XY? = nil, mirek: Int? = nil) -> HueLight {
            HueLight(id: id, owner: ResourceRef(rid: device, rtype: "device"), metadata: .init(name: name, archetype: archetype), on: .init(on: on),
                     dimming: .init(brightness: bri, minDimLevel: 0.2),
                     colorTemperature: .init(mirek: mirek, mirekValid: mirek != nil, mirekSchema: .init(mirekMinimum: 153, mirekMaximum: 500)),
                     color: xy.map { .init(xy: $0, gamutType: "C") })
        }
        let lights = [
            light("l1", "d1", "Hue Go", "hue_go", on: true, bri: 72, xy: XY(x: 0.18, y: 0.08)),
            light("l2", "d2", "Lightstrip", "hue_lightstrip_tv", on: true, bri: 55, xy: XY(x: 0.45, y: 0.2)),
            light("l3", "d3", "Ceiling", "ceiling_round", on: true, bri: 80, mirek: 370),
            light("l4", "d4", "Reading lamp", "table_shade", on: false, bri: 40, xy: XY(x: 0.5, y: 0.41)),
            light("l5", "d5", "Kitchen spot 1", "spot_bulb", on: false, bri: 100, mirek: 250),
            light("l6", "d6", "Kitchen spot 2", "spot_bulb", on: false, bri: 100, mirek: 250),
            light("l7", "d7", "Bedside", "table_shade", on: true, bri: 20, mirek: 454),
        ]
        store.lights = Dictionary(uniqueKeysWithValues: lights.map { ($0.id, $0) })
        func group(_ id: String, _ name: String, _ archetype: String, _ devices: [String]) -> HueGroup {
            HueGroup(id: id, type: "room", children: devices.map { ResourceRef(rid: $0, rtype: "device") },
                     services: [ResourceRef(rid: "g" + id, rtype: "grouped_light")], metadata: .init(name: name, archetype: archetype))
        }
        store.rooms = [group("r1", "Living room", "living_room", ["d1", "d2", "d3", "d4"]), group("r2", "Kitchen", "kitchen", ["d5", "d6"]), group("r3", "Bedroom", "bedroom", ["d7"])]
        store.home = HueGroup(id: "home", type: "bridge_home", children: [], services: [ResourceRef(rid: "ghome", rtype: "grouped_light")], metadata: nil)
        store.grouped = Dictionary(uniqueKeysWithValues: (store.rooms + [store.home!]).map { g in
            (g.groupedLightID!, HueGroupedLight(id: g.groupedLightID!, owner: ResourceRef(rid: g.id, rtype: g.type), on: .init(on: store.lights(in: g).contains(where: \.on.on)), dimming: .init(brightness: 60)))
        })
        func scene(_ id: String, _ name: String, _ room: String, _ xys: [XY], active: Bool = false) -> HueScene {
            HueScene(id: id, metadata: .init(name: name), group: ResourceRef(rid: room, rtype: "room"), actions: [],
                     palette: .init(color: xys.map { .init(color: .init(xy: $0)) }, colorTemperature: nil), status: .init(active: active ? "static" : "inactive"))
        }
        store.scenes = [
            scene("s1", "Tokyo", "r1", [XY(x: 0.18, y: 0.08), XY(x: 0.45, y: 0.2), XY(x: 0.15, y: 0.3)], active: true),
            scene("s2", "Sunset", "r1", [XY(x: 0.6, y: 0.38), XY(x: 0.52, y: 0.41), XY(x: 0.45, y: 0.25)]),
            scene("s3", "Ocean", "r1", [XY(x: 0.16, y: 0.2), XY(x: 0.2, y: 0.35)]),
            scene("s4", "Northern lights", "r1", [XY(x: 0.2, y: 0.55), XY(x: 0.25, y: 0.12)]),
            scene("s5", "Concentrate", "r2", [XY(x: 0.31, y: 0.33)]),
            scene("s6", "Relax", "r3", [XY(x: 0.52, y: 0.41)]),
        ]
        store.favoriteScenes = ["s1", "s2"]
        store.connected = true
        store.status = "Connected"
        store.bridgeName = "Hue Bridge"
        store.modelID = "BSB002"
        store.syncGroupID = "r1"
        store.journal.record(rooms: [(id: "r1", name: "Living room")], seconds: 3 * 3600 + 25 * 60)
        store.journal.record(rooms: [(id: "r3", name: "Bedroom")], seconds: 52 * 60)
        store.journal.record(rooms: [(id: "r2", name: "Kitchen")], seconds: 18 * 60)
        return store
    }

    /// The status item at 6x, on a light and a dark menu bar.
    static func renderIcon(store: HueStore, to url: URL) {
        let icons = [MenuBarIcon.image(on: false, syncing: false), MenuBarIcon.image(on: true, syncing: false)]
        let scale: CGFloat = 6, pad: CGFloat = 6
        let cell = NSSize(width: (22 + pad * 2) * scale, height: (22 + pad * 2) * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cell.width * 4), pixelsHigh: Int(cell.height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (index, name) in [NSAppearance.Name.aqua, .aqua, .darkAqua, .darkAqua].enumerated() {
            let icon = icons[index % 2]
            let origin = CGFloat(index) * cell.width
            (index < 2 ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.16, alpha: 1)).setFill()
            NSRect(x: origin, y: 0, width: cell.width, height: cell.height).fill()
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                let rect = NSRect(x: origin + (cell.width - icon.size.width * scale) / 2, y: (cell.height - icon.size.height * scale) / 2,
                                  width: icon.size.width * scale, height: icon.size.height * scale)
                if icon.isTemplate {
                    // Menu bars tint template images with their text color.
                    let tinted = NSImage(size: icon.size, flipped: false) { r in
                        icon.draw(in: r); NSColor.labelColor.set(); r.fill(using: .sourceAtop); return true
                    }
                    tinted.draw(in: rect)
                } else { icon.draw(in: rect) }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print(url.path)
    }

    static func render(to directory: URL) {
        for language in [AppLanguage.en, .tr] {
            let folder = directory.appendingPathComponent(language.rawValue)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let store = demoStore()
            store.language = language
            if language == .en { renderIcon(store: store, to: directory.appendingPathComponent("0-menubar.png")) }
            let shots: [(String, () -> PanelView)] = [
                ("1-rooms", { PanelView(store: store, startTab: 0, revealed: true) }),
                ("2-lights", { PanelView(store: store, startTab: 1, expanded: ["l1"]) }),
                ("3-scenes", { PanelView(store: store, startTab: 2) }),
                ("4-sync", { PanelView(store: store, startTab: 3) }),
                ("5-history", { PanelView(store: store, startTab: 4) }),
                ("6-settings", { PanelView(store: store, showSettings: true) }),
                ("7-found", {
                    store.discovered = [DiscoveredBridge(name: "Hue Bridge - ABC123", host: "192.168.1.20", bridgeID: "demo")]
                    return PanelView(store: store, showSettings: true)
                }),
            ]
            for (name, make) in shots {
                // First pass measures the panel's natural height, second pass renders at that height.
                store.preferredPanelHeight = 0
                _ = capture(make(), height: 900)
                let height = max(200, store.preferredPanelHeight - PanelView.arrowHeight)
                guard let png = capture(make(), height: height) else { continue }
                let url = folder.appendingPathComponent("\(name).png")
                try? png.write(to: url)
                print(url.path)
            }
        }
        if !L10n.missing.isEmpty { print("Untranslated:", L10n.missing.sorted()) }
    }

    private static func capture(_ view: PanelView, height: CGFloat) -> Data? {
        let size = NSSize(width: 360, height: height)
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
