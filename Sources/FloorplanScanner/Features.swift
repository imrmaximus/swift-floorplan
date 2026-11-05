import Foundation

/// A feature cuts across folders, e.g. "Habits" = its data, rules and screens.
/// A file belongs to the first rule with a `match` word found in its path (case-insensitive).
public struct FeatureRule: Codable, Equatable, Sendable {
    public let name: String
    public let purpose: String
    public let match: [String]

    public init(name: String, purpose: String, match: [String]) {
        self.name = name
        self.purpose = purpose
        self.match = match
    }
}

/// Reads a features file: `[ { "name": "...", "purpose": "...", "match": ["habit"] } ]`.
public func decodeFeatureRules(_ data: Data) throws -> [FeatureRule] {
    do {
        return try JSONDecoder().decode([FeatureRule].self, from: data)
    } catch {
        throw ScanError.invalidFeaturesFile(String(describing: error))
    }
}

/// Maps file path to feature name. Files that match no rule are left out.
/// A leading folder named in `ignoringFolders` is skipped, so `AppTests/` does not match the word "app".
public func assignFeatures(_ files: [FileSummary], rules: [FeatureRule], ignoringFolders: [String] = []) -> [String: String] {
    var assigned: [String: String] = [:]
    for file in files {
        let skipped = ignoringFolders.first { file.path.hasPrefix($0 + "/") }.map { $0.count + 1 } ?? 0
        let path = String(file.path.dropFirst(skipped)).lowercased()
        let rule = rules.first { $0.match.contains { path.contains($0.lowercased()) } }
        if let rule { assigned[file.path] = rule.name }
    }
    return assigned
}
