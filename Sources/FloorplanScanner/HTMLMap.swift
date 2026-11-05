import Foundation

/// A plain-English label for one folder. Written by Claude (or by hand) into a names file.
public struct RoomName: Codable, Equatable, Sendable {
    public let name: String
    public let purpose: String

    public init(name: String, purpose: String) {
        self.name = name
        self.purpose = purpose
    }
}

/// Reads a names file: `{ "Features/Inbox": { "name": "...", "purpose": "..." } }`.
public func decodeRoomNames(_ data: Data) throws -> [String: RoomName] {
    do {
        return try JSONDecoder().decode([String: RoomName].self, from: data)
    } catch {
        throw ScanError.invalidNamesFile(String(describing: error))
    }
}

/// Builds one self-contained HTML page (data inlined, no network) that draws the scan as a map of file cards.
public func renderHTML(_ result: ScanResult, names: [String: RoomName] = [:], features: [FeatureRule] = []) throws -> String {
    let namesJSON = names.isEmpty ? "{}" : String(decoding: try sortedJSON(names), as: UTF8.self)
    let featureOf = assignFeatures(result.files, rules: features, ignoringFolders: result.extraFolders)
    return mapTemplate
        .replacingOccurrences(of: "__GRAPH_SCRIPT__", with: graphScript)
        .replacingOccurrences(of: "__SCAN_DATA__", with: safeInScript(String(decoding: try encodeJSON(result), as: UTF8.self)))
        .replacingOccurrences(of: "__ROOM_NAMES__", with: safeInScript(namesJSON))
        .replacingOccurrences(of: "__FEATURE_OF__", with: safeInScript(String(decoding: try sortedJSON(featureOf), as: UTF8.self)))
        .replacingOccurrences(of: "__FEATURES__", with: safeInScript(String(decoding: try sortedJSON(features), as: UTF8.self)))
}

// "</" in the data would end the script tag early.
private func safeInScript(_ json: String) -> String {
    json.replacingOccurrences(of: "</", with: "<\\/")
}

private func sortedJSON<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}
