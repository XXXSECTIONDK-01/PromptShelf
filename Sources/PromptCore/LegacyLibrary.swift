import Foundation

enum LegacyLibrary {
    static func adapt(_ data: Data, root: [String: Any]?) throws -> Data {
        guard var root, root["version"] == nil, let version = root["schemaVersion"] as? Int else { return data }
        guard version == 1 else { throw LibraryError.invalid("此旧版资料库尚不受支持，原文件已保留。") }
        var categories = root["categories"] as? [[String: Any]] ?? []
        var prompts = root["prompts"] as? [[String: Any]] ?? []
        for i in categories.indices { categories[i]["color"] = categories[i]["color"] ?? categories[i]["accent"] ?? "blue" }
        let general = PromptCategory.generalID.uuidString
        if !categories.contains(where: { ($0["id"] as? String)?.uppercased() == general }) {
            if let i = categories.firstIndex(where: { ($0["name"] as? String) == "通用" }) {
                let old = categories[i]["id"] as? String; categories[i]["id"] = general
                for p in prompts.indices where prompts[p]["categoryID"] as? String == old { prompts[p]["categoryID"] = general }
            } else { categories.insert(["id":general,"name":"通用","symbol":"square.grid.2x2","color":"blue"], at: 0) }
        }
        var settings = root["settings"] as? [String: Any] ?? [:]
        let defaults = try JSONSerialization.jsonObject(with: LibraryFile.encoder().encode(Preferences())) as! [String: Any]
        for (key,value) in defaults where settings[key] == nil { settings[key] = value }
        if let font = settings["fontSize"] as? String { settings["fontSize"] = ["small":13,"medium":15,"large":17][font] ?? 15 }
        if let key = settings["hotkey"] as? String { settings["hotkey"] = try parseHotkey(key) }
        settings["styleRevision"] = 2
        root["version"] = 3; root["categories"] = categories; root["prompts"] = prompts; root["preferences"] = settings
        return try JSONSerialization.data(withJSONObject: root)
    }
    private static func parseHotkey(_ value: String) throws -> [String: UInt32] {
        let parts = value.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        let modifiers: [String: UInt32] = ["control":4096,"ctrl":4096,"option":2048,"alt":2048,"shift":512,"command":256,"cmd":256]
        let keys: [String: UInt32] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46,"space":49,"return":36,"tab":48]
        guard let last = parts.last, let key = keys[last], parts.dropLast().allSatisfy({ modifiers[$0] != nil }) else { throw LibraryError.invalid("旧版快捷键无法解析，原资料库已保留。") }
        return ["keyCode":key,"modifiers":parts.dropLast().reduce(0) { $0 | modifiers[$1]! }]
    }
}
