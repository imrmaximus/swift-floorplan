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

@Suite struct ExtensionScanTests {
    @Test func anExtensionBecomesItsOwnEntryWithItsReferences() throws {
        let file = scanSource("""
        struct NoteClient {}
        extension NoteClient: DependencyKey {
            static var liveValue: NoteClient { NoteRepository(context: NSManagedObjectContext()) }
        }
        """, path: "NoteClient.swift")
        let ext = try #require(file.types.first { $0.name == "NoteClient (extension)" })
        #expect(ext.kind == .extension)
        #expect(ext.inherits == ["DependencyKey"])
        #expect(ext.references.contains("NoteRepository"))
        #expect(ext.references.contains("NSManagedObjectContext"))
        #expect(file.types.first { $0.name == "NoteClient" }?.references == [])
    }

    @Test func typesNestedInAnExtensionKeepTheirPlainName() {
        // Reducer bodies refer to them without the parent name (`ColumnSync()`), so the link must match that.
        let file = scanSource("extension Feature { struct Helper {} }", path: "F.swift")
        #expect(file.types.map(\.name) == ["Feature (extension)", "Helper"])
    }

    @Test func anExtensionIsNeverAReducerAndDependencyValuesIsSkipped() {
        let file = scanSource("extension Feature: Reducer {}\nextension DependencyValues { var a: A { get set } }", path: "F.swift")
        #expect(file.types.map(\.name) == ["Feature (extension)"])
        #expect(file.types.allSatisfy { !$0.isReducer })
    }
}

@Suite struct TopLevelCodeScanTests {
    @Test func referencesInFreeFunctionsAreKeptOnATopLevelEntry() throws {
        let file = scanSource("""
        struct A {}
        private func openStore() -> HabitStore { HabitStore(context: NSManagedObjectContext()) }
        """, path: "A.swift")
        let top = try #require(file.types.first { $0.name == "(top level code)" })
        #expect(top.kind == .topLevel)
        #expect(top.references.contains("HabitStore"))
        #expect(top.references.contains("NSManagedObjectContext"))
    }

    @Test func noTopLevelEntryWhenThereIsNoTopLevelCode() {
        #expect(scanSource("struct A { var b: B }", path: "A.swift").types.map(\.name) == ["A"])
    }
}
