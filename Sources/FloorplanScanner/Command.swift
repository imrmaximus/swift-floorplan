import Foundation

public let usage = "usage: swift-floorplan <folder> [-o out.json] [--html map.html] [--names names.json] [--features features.json] [--auto-name] [--also <folder>]..."

/// What the command line asked for.
public struct Options: Equatable, Sendable {
    public var folder: String
    public var also: [String] = []
    public var output: String?
    public var html: String?
    public var names: String?
    public var features: String?
    public var autoName = false
}

/// Reads the arguments (without the program name). Returns nil when there is no folder, which means: show the usage.
/// A flag with no value after it is ignored.
public func parseOptions(_ args: [String]) -> Options? {
    guard let folder = args.first else { return nil }
    func value(at index: Int) -> String? { args.indices.contains(index + 1) ? args[index + 1] : nil }
    var options = Options(folder: folder)
    for (index, arg) in args.enumerated() {
        switch arg {
        case "-o": options.output = value(at: index)
        case "--html": options.html = value(at: index)
        case "--names": options.names = value(at: index)
        case "--features": options.features = value(at: index)
        case "--also": if let folder = value(at: index) { options.also.append(folder) }
        case "--auto-name": options.autoName = true
        default: break
        }
    }
    return options
}

/// Does the whole job. Returns the JSON to print when neither `-o` nor `--html` was given, otherwise nil.
public func runCommand(_ options: Options, ask: Ask) throws -> Data? {
    let result = try scanFolder(URL(fileURLWithPath: options.folder), also: options.also.map { URL(fileURLWithPath: $0) })
    var names = try options.names.flatMap(readIfPresent).map(decodeRoomNames) ?? [:]
    var features = try options.features.flatMap(readIfPresent).map(decodeFeatureRules) ?? []
    if options.autoName {
        // Only gaps are filled: folders without a name, files without a feature. Hand-written entries stay.
        if let path = options.names { names = try fillMissingNames(result, existing: names, ask: ask); try writeJSON(names, to: path) }
        if let path = options.features { features = try fillMissingFeatures(result, existing: features, ask: ask); try writeJSON(features, to: path) }
    }
    let json = try encodeJSON(result)
    if let path = options.html {
        try Data(try renderHTML(result, names: names, features: features).utf8).write(to: URL(fileURLWithPath: path))
    }
    if let path = options.output { try json.write(to: URL(fileURLWithPath: path)) }
    return options.output == nil && options.html == nil ? json : nil
}

// A names or features file that does not exist yet is fine (auto-name creates it); one that exists must parse.
private func readIfPresent(_ path: String) -> Data? { try? Data(contentsOf: URL(fileURLWithPath: path)) }

private func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(value).write(to: URL(fileURLWithPath: path))
}
