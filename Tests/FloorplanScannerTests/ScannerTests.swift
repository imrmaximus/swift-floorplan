import Foundation
import Testing
@testable import FloorplanScanner

@Suite struct SourceScanTests {
    @Test func extractsImports() {
        let file = scanSource("import SwiftUI\nimport struct Foundation.Date\nimport ComposableArchitecture\n", path: "A.swift")
        #expect(file.imports == ["ComposableArchitecture", "Foundation", "SwiftUI"])
    }

    @Test func extractsAllFiveTypeKinds() {
        let source = """
        struct S {}
        class C {}
        enum E {}
        protocol P {}
        actor A {}
        """
        let file = scanSource(source, path: "A.swift")
        #expect(file.types.map(\.kind) == [.struct, .class, .enum, .protocol, .actor])
        #expect(file.types.map(\.name) == ["S", "C", "E", "P", "A"])
    }

    @Test func recordsLineNumber() {
        let file = scanSource("\n\nstruct S {}\n", path: "A.swift")
        #expect(file.types.first?.line == 3)
    }

    @Test func qualifiesNestedTypes() {
        let source = """
        struct Feature {
            struct State {}
            enum Action {}
        }
        """
        let names = scanSource(source, path: "A.swift").types.map(\.name)
        #expect(names == ["Feature", "Feature.State", "Feature.Action"])
    }

    @Test func recordsInheritedTypes() {
        let file = scanSource("struct V: View, Equatable {}", path: "A.swift")
        #expect(file.types.first?.inherits == ["View", "Equatable"])
    }

    @Test func collectsReferencedTypeNames() {
        let source = """
        struct Home {
            var store: StoreOf<InboxFeature>
            func load() { _ = TaskRepository.shared.fetch() }
        }
        """
        let refs = scanSource(source, path: "A.swift").types[0].references
        #expect(refs.contains("StoreOf"))
        #expect(refs.contains("InboxFeature"))
        #expect(refs.contains("TaskRepository"))
    }

    @Test func ignoresLowercaseValuesAndSelfReference() {
        let source = "struct Home { var title: String; func f() { _ = title; _ = Home.self } }"
        let refs = scanSource(source, path: "A.swift").types[0].references
        #expect(!refs.contains("title"))
        #expect(!refs.contains("Home"))
    }

    @Test func attributesReferencesToInnermostType() {
        let source = """
        struct Outer {
            var a: Alpha
            struct Inner { var b: Beta }
        }
        """
        let types = scanSource(source, path: "A.swift").types
        #expect(types[0].references == ["Alpha"])
        #expect(types[1].references == ["Beta"])
    }

    @Test func returnsEmptyTypesForFileWithoutDeclarations() {
        let file = scanSource("import Foundation\nlet x = 1\n", path: "A.swift")
        #expect(file.types.isEmpty)
    }
}

@Suite struct FolderScanTests {
    private func makeTempFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        return dir
    }

    @Test func listsOnlySwiftFilesRecursivelyWithRelativePaths() throws {
        let dir = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "struct A {}".write(to: dir.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "struct B {}".write(to: dir.appendingPathComponent("Sub/B.swift"), atomically: true, encoding: .utf8)
        try "not swift".write(to: dir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let result = try scanFolder(dir)

        #expect(result.files.map(\.path) == ["A.swift", "Sub/B.swift"])
    }

    @Test func extraFoldersAreScannedWithTheirNameAsPrefix() throws {
        let main = try makeTempFolder(), extra = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: main); try? FileManager.default.removeItem(at: extra) }
        try "struct A {}".write(to: main.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "struct B {}".write(to: extra.appendingPathComponent("Sub/B.swift"), atomically: true, encoding: .utf8)

        let result = try scanFolder(main, also: [extra])

        #expect(result.files.map(\.path) == ["A.swift", "\(extra.lastPathComponent)/Sub/B.swift"])
        #expect(result.root == main.path)
    }

    @Test func throwsWhenAnExtraFolderDoesNotExist() throws {
        let main = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: main) }
        #expect(throws: ScanError.self) { try scanFolder(main, also: [URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")]) }
    }

    @Test func throwsWhenFolderDoesNotExist() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(throws: ScanError.self) { try scanFolder(missing) }
    }

    @Test func encodesToStableJSON() throws {
        let dir = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "import SwiftUI\nstruct A: View {}".write(to: dir.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)

        let data = try encodeJSON(try scanFolder(dir))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let files = try #require(json["files"] as? [[String: Any]])

        #expect(files.count == 1)
        #expect(files[0]["imports"] as? [String] == ["SwiftUI"])
    }
}
