import Foundation

public enum TypeKind: String, Codable, Sendable {
    case `struct`, `class`, `enum`, `protocol`, actor
    /// An `extension Foo { ... }` block, listed as "Foo (extension)" so its code is not lost.
    case `extension`
    /// Code outside any type (free functions, globals, previews), listed once per file as "(top level code)".
    case topLevel
}

/// How a reducer includes a child reducer.
public enum LinkKind: String, Codable, Sendable {
    /// `Scope(state:action:) { Child() }`
    case scope
    /// `.ifLet(...) { Child() }`, or `.ifLet(...)` alone, which means a nested `Destination`-style enum.
    case ifLet
    /// `.forEach(...) { Child() }`
    case forEach
    /// A child reducer listed directly in `body`.
    case body
    /// A case of a `@Reducer enum` that holds a child reducer.
    case enumCase
}

public struct ReducerLink: Codable, Equatable, Sendable {
    public let child: String
    public let via: LinkKind
}

public struct TypeInfo: Codable, Equatable, Sendable {
    /// Qualified with its parents, e.g. "InboxFeature.State".
    public let name: String
    public let kind: TypeKind
    public let line: Int
    /// Types after the colon: protocols and superclass.
    public let inherits: [String]
    /// Capitalised names used inside the body, sorted, without the type's own name.
    public let references: [String]
    /// True for `@Reducer` types and types that conform to `Reducer`.
    public let isReducer: Bool
    /// Child reducers this reducer includes. Only known reducers remain after a folder scan.
    public var composes: [ReducerLink]
    /// Reducers this type builds a `Store` for, e.g. a view with `Store(initialState: ...) { Feature() }`.
    public var createsStores: [String]
    /// Dependency keys this type reads with `@Dependency(\.name)`, sorted, e.g. "eventClient".
    public var dependencies: [String] = []
    /// Free functions this type calls by bare name, e.g. "linkEventToProject". After a folder scan only functions declared in the scan remain.
    public var calls: [String] = []
}

/// One line of `extension DependencyValues { var name: Type { get set } }`.
public struct DependencyKey: Codable, Equatable, Sendable {
    public let name: String
    public let type: String
}

public struct FileSummary: Codable, Equatable, Sendable {
    /// Path relative to the scanned folder.
    public let path: String
    public let imports: [String]
    public var types: [TypeInfo]
    /// Dependency keys declared in this file.
    public var dependencyKeys: [DependencyKey] = []
    /// Functions declared at the top level of this file (not methods, not nested functions).
    public var functions: [String] = []
}

public struct ScanResult: Codable, Equatable, Sendable {
    public let root: String
    public let files: [FileSummary]
    /// Names of the `--also` folders. They prefix some paths but are not part of what a file is about.
    public var extraFolders: [String] = []
}
