import FloorplanScanner
import Foundation

// Usage: swift-floorplan <folder> [-o out.json] [--html map.html] [--names names.json] [--features features.json] [--auto-name] [--also <folder>]...   (JSON goes to stdout without -o or --html)
let args = Array(CommandLine.arguments.dropFirst())
guard let folderArg = args.first else {
    FileHandle.standardError.write(Data("usage: swift-floorplan <folder> [-o out.json] [--html map.html] [--names names.json] [--features features.json] [--auto-name] [--also <folder>]...\n".utf8))
    exit(64)
}
func value(after flag: String) -> String? {
    args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
}
let outputPath = value(after: "-o")
let htmlPath = value(after: "--html")
let namesPath = value(after: "--names")
let featuresPath = value(after: "--features")
let autoName = args.contains("--auto-name")
let extraFolders = args.indices.filter { args[$0] == "--also" && args.indices.contains($0 + 1) }.map { URL(fileURLWithPath: args[$0 + 1]) }

/// Sends the prompt to `claude -p` on stdin and returns what it prints.
func askClaude(_ prompt: String) throws -> String {
    let process = Process(), input = Pipe(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["claude", "-p"]
    process.standardInput = input
    process.standardOutput = output
    try process.run()
    input.fileHandleForWriting.write(Data(prompt.utf8))
    try input.fileHandleForWriting.close()
    let reply = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ScanError.modelReplyUnreadable("claude exited with \(process.terminationStatus)") }
    return String(decoding: reply, as: UTF8.self)
}

func readIfPresent(_ path: String) -> Data? { try? Data(contentsOf: URL(fileURLWithPath: path)) }
func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(value).write(to: URL(fileURLWithPath: path))
}

do {
    let result = try scanFolder(URL(fileURLWithPath: folderArg), also: extraFolders)
    let data = try encodeJSON(result)
    var names = try namesPath.flatMap(readIfPresent).map(decodeRoomNames) ?? [:]
    var features = try featuresPath.flatMap(readIfPresent).map(decodeFeatureRules) ?? []
    if autoName {
        // Only gaps are filled: folders without a name, files without a feature. Hand-written entries stay.
        if let namesPath { names = try fillMissingNames(result, existing: names, ask: askClaude); try writeJSON(names, to: namesPath) }
        if let featuresPath { features = try fillMissingFeatures(result, existing: features, ask: askClaude); try writeJSON(features, to: featuresPath) }
    }
    if let htmlPath {
        try Data(try renderHTML(result, names: names, features: features).utf8).write(to: URL(fileURLWithPath: htmlPath))
    }
    if let outputPath {
        try data.write(to: URL(fileURLWithPath: outputPath))
    } else if htmlPath == nil {
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
