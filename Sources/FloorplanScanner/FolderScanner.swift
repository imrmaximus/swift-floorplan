import Foundation

public enum ScanError: Error, Equatable {
    case folderNotFound(String)
    case unreadableFile(String)
    case invalidNamesFile(String)
    case invalidFeaturesFile(String)
    case modelReplyUnreadable(String)
}

/// Scans every .swift file under `folder` (recursively) and returns a summary per file, sorted by path.
/// Files of the `also` folders are added with their folder name as a path prefix, so paths of the main folder stay the same.
public func scanFolder(_ folder: URL, also extras: [URL] = []) throws -> ScanResult {
    let main = try summaries(in: folder, prefix: "")
    let more = try extras.flatMap { try summaries(in: $0, prefix: $0.lastPathComponent + "/") }
    return ScanResult(root: folder.path, files: resolveReducerLinks(main + more), extraFolders: extras.map(\.lastPathComponent))
}

private func summaries(in folder: URL, prefix: String) throws -> [FileSummary] {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw ScanError.folderNotFound(folder.path)
    }
    let relativePaths = try FileManager.default.subpathsOfDirectory(atPath: folder.path)
        .filter { $0.hasSuffix(".swift") }
        .sorted()
    return try relativePaths.map { relative in
        guard let source = try? String(contentsOf: folder.appendingPathComponent(relative), encoding: .utf8) else {
            throw ScanError.unreadableFile(relative)
        }
        return scanSource(source, path: prefix + relative)
    }
}

public func encodeJSON(_ result: ScanResult) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(result)
}
