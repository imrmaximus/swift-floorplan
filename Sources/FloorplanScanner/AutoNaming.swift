import Foundation

/// Asks a language model one question and returns its text reply. The CLI plugs in `claude -p`; tests plug in a fake.
public typealias Ask = (String) throws -> String

private let maxTypesPerFolder = 40
private let maxFilesInFeaturePrompt = 200

private func folder(of path: String) -> String {
    path.contains("/") ? String(path[..<path.lastIndex(of: "/")!]) : "(top level)"
}

/// Folders that have files but no entry in the names file, sorted.
public func foldersWithoutName(_ result: ScanResult, names: [String: RoomName]) -> [String] {
    Set(result.files.map { folder(of: $0.path) }).subtracting(names.keys).sorted()
}

/// A short text summary of the given folders: file count, imports and type names.
public func namesDigest(_ result: ScanResult, folders: [String]) -> String {
    folders.map { name in
        let files = result.files.filter { folder(of: $0.path) == name }
        let imports = Set(files.flatMap(\.imports)).sorted().joined(separator: ",")
        let types = files.flatMap(\.types).prefix(maxTypesPerFolder).map(\.name).joined(separator: ", ")
        return "## \(name) [\(files.count) files] imports: \(imports)\n   \(types)"
    }.joined(separator: "\n")
}

/// Pulls the JSON out of a model reply that may have chatter or code fences around it.
public func parseModelJSON<T: Decodable>(_ type: T.Type, from reply: String) throws -> T {
    let opens = ["{", "["].compactMap { reply.firstIndex(of: Character($0)) }.min()
    let closes = ["}", "]"].compactMap { reply.lastIndex(of: Character($0)) }.max()
    guard let opens, let closes, opens < closes else { throw ScanError.modelReplyUnreadable(reply) }
    do {
        return try JSONDecoder().decode(T.self, from: Data(reply[opens...closes].utf8))
    } catch {
        throw ScanError.modelReplyUnreadable(String(describing: error))
    }
}

/// Names the folders that have no name yet. Existing names are never changed.
public func fillMissingNames(_ result: ScanResult, existing: [String: RoomName], ask: Ask) throws -> [String: RoomName] {
    let missing = foldersWithoutName(result, names: existing)
    if missing.isEmpty { return existing }
    let prompt = """
    Below are folders of a Swift app: file count, imports, type names.
    Reply with ONLY a JSON object. Keys are the folder paths exactly as written below.
    Each value is {"name": a 2 to 4 word plain-English name, "purpose": one plain sentence for a non-developer}.

    \(namesDigest(result, folders: missing))
    """
    let reply = try parseModelJSON([String: RoomName].self, from: try ask(prompt))
    return existing.merging(reply.filter { missing.contains($0.key) }) { old, _ in old }
}

/// Adds feature rules for files no rule matches. New rules go last, so existing rules keep winning.
public func fillMissingFeatures(_ result: ScanResult, existing: [FeatureRule], ask: Ask) throws -> [FeatureRule] {
    let assigned = assignFeatures(result.files, rules: existing, ignoringFolders: result.extraFolders)
    let loose = result.files.filter { assigned[$0.path] == nil }.prefix(maxFilesInFeaturePrompt)
    if loose.isEmpty { return existing }
    let lines = loose.map { "\($0.path): \($0.types.prefix(5).map(\.name).joined(separator: ", "))" }.joined(separator: "\n")
    let prompt = """
    A feature groups files across folders, for example Habits = its data, rules and screens.
    These files match no feature yet. Existing features: \(existing.map(\.name).joined(separator: ", ")).
    Reply with ONLY a JSON array like [{"name": "Habits", "purpose": "One plain sentence.", "match": ["habit", "streak"]}].
    "match" must always be an array of lowercase words that appear in the file paths, even for a single word.
    Reuse an existing name when a file belongs to it. Every file below should match at least one word.

    \(lines)
    """
    let reply = try parseModelJSON([FeatureRule].self, from: try ask(prompt))
    return existing + reply
}
