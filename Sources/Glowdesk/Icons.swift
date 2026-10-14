import AppKit

/// Maps the icons chosen in the Hue app (CLIP v2 "archetype") to SF Symbols.
/// Signify's own icon artwork isn't public, so each archetype gets the closest system symbol.
/// Any symbol missing on this macOS version falls back to a plain one.
enum HueIcons {
    static let lights: [String: String] = [
        "classic_bulb": "lightbulb", "sultan_bulb": "lightbulb", "ellipse_bulb": "lightbulb",
        "triangle_bulb": "lightbulb", "small_globe_bulb": "lightbulb.circle", "large_globe_bulb": "lightbulb.circle",
        "edison_bulb": "lightbulb.max", "vintage_bulb": "lightbulb.max", "flood_bulb": "light.beacon.max",
        "spot_bulb": "light.recessed", "candle_bulb": "flame", "vintage_candle_bulb": "flame", "luster_bulb": "flame",
        "pendant_round": "lamp.ceiling", "pendant_long": "light.cylindrical.ceiling", "pendant_spot": "light.cylindrical.ceiling",
        "ceiling_round": "light.recessed.inverse", "ceiling_square": "light.panel", "ceiling_horizontal": "light.panel",
        "ceiling_tube": "light.panel", "recessed_ceiling": "light.recessed", "recessed_floor": "light.recessed.inverse",
        "floor_shade": "lamp.floor", "floor_lantern": "lamp.floor", "hue_signe": "lamp.floor",
        "table_shade": "lamp.table", "table_wash": "lamp.desk", "flexible_lamp": "lamp.desk",
        "single_spot": "light.recessed", "double_spot": "light.recessed.3", "wall_spot": "light.recessed",
        "ground_spot": "light.beacon.min", "bollard": "light.beacon.min",
        "wall_lantern": "light.beacon.min", "wall_shade": "lamp.table", "wall_washer": "light.beacon.max",
        "up_and_down": "light.beacon.max", "up_and_down_up": "light.beacon.max", "up_and_down_down": "light.beacon.max",
        "hue_play_wallwasher": "light.beacon.max", "hue_bloom": "light.beacon.max",
        "plug": "poweroutlet.type.f", "hue_go": "circle.bottomhalf.filled", "hue_iris": "circle.circle",
        "hue_play": "rectangle.portrait", "hue_centris": "light.recessed.3", "hue_tube": "light.panel",
        "hue_lightstrip": "light.strip.2", "hue_omniglow": "light.strip.2", "hue_neon": "light.ribbon",
        "hue_lightstrip_tv": "tv", "hue_lightstrip_pc": "display",
        "christmas_tree": "tree", "string_light": "sparkles", "string_globe": "sparkles", "string_permanent": "sparkles",
        "hue_floodlight_camera": "video", "twilight": "sunrise", "twilight_front": "sunrise", "twilight_back": "sunrise",
    ]

    static let rooms: [String: String] = [
        "living_room": "sofa", "lounge": "sofa", "kitchen": "refrigerator", "dining": "fork.knife",
        "bedroom": "bed.double", "guest_room": "bed.double", "kids_bedroom": "teddybear", "nursery": "stroller",
        "bathroom": "shower", "toilet": "toilet", "office": "briefcase", "computer": "desktopcomputer",
        "studio": "paintbrush", "music": "music.note", "tv": "tv", "reading": "book",
        "gym": "dumbbell", "recreation": "gamecontroller", "man_cave": "gamecontroller",
        "hallway": "door.left.hand.open", "front_door": "door.left.hand.closed", "staircase": "stairs",
        "garage": "car", "carport": "car", "driveway": "road.lanes",
        "terrace": "sun.max", "balcony": "sun.max", "porch": "sun.max", "garden": "leaf",
        "barbecue": "flame", "pool": "figure.pool.swim", "closet": "hanger", "storage": "shippingbox",
        "laundry_room": "washer", "attic": "arrow.up.square", "top_floor": "arrow.up.square",
        "upstairs": "arrow.up.square", "downstairs": "arrow.down.square", "home": "house",
    ]

    private static var available: [String: Bool] = [:]
    private static func exists(_ symbol: String) -> Bool {
        if let known = available[symbol] { return known }
        let found = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        available[symbol] = found
        return found
    }

    static func light(_ archetype: String?) -> String {
        guard let symbol = lights[archetype ?? ""], exists(symbol) else { return "lightbulb" }
        return symbol
    }
    static func room(_ archetype: String?) -> String {
        guard let symbol = rooms[archetype ?? ""], exists(symbol) else { return "square.split.bottomrightquarter" }
        return symbol
    }
    /// Symbols this macOS doesn't have; used by the self-check.
    static var missing: [String] { Set(lights.values).union(rooms.values).filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }.sorted() }
}
