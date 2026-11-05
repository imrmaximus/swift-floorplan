import Foundation
import Testing
@testable import FloorplanScanner

@Suite struct DependencyUseTests {
    @Test func recordsKeyPathDependenciesOnTheInnermostType() {
        let file = scanSource("""
        struct Home {
            @Dependency(\\.eventClient) var eventClient
            @Dependency(\\.projectClient) private var projects
            struct State { @Dependency(\\.uuid) var uuid }
        }
        """, path: "Home.swift")
        #expect(file.types.first { $0.name == "Home" }?.dependencies == ["eventClient", "projectClient"])
        #expect(file.types.first { $0.name == "Home.State" }?.dependencies == ["uuid"])
    }

    @Test func ignoresOtherPropertyWrappers() {
        let file = scanSource("struct A { @State var x = 1\n @Dependency(Foo.self) var foo }", path: "A.swift")
        #expect(file.types.first?.dependencies == [])
    }

    @Test func typesWithoutDependenciesHaveNone() {
        #expect(scanSource("struct A {}", path: "A.swift").types.first?.dependencies == [])
    }
}

@Suite struct DependencyDeclarationTests {
    @Test func readsKeysDeclaredInADependencyValuesExtension() {
        let file = scanSource("""
        extension DependencyValues {
            var eventClient: EventClient {
                get { self[EventClientKey.self] }
                set { self[EventClientKey.self] = newValue }
            }
            var fetchSpaces: FetchSpacesUseCase { get { self[K.self] } set { self[K.self] = newValue } }
        }
        """, path: "EventClient.swift")
        #expect(file.dependencyKeys == [DependencyKey(name: "eventClient", type: "EventClient"), DependencyKey(name: "fetchSpaces", type: "FetchSpacesUseCase")])
    }

    @Test func ignoresVariablesInOtherExtensions() {
        let file = scanSource("extension String { var shout: String { self } }", path: "S.swift")
        #expect(file.dependencyKeys.isEmpty)
    }
}

@Suite struct DependencyFolderScanTests {
    @Test func folderScanKeepsDependencyDataAfterReducerLinking() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "extension DependencyValues { var eventClient: EventClient { get set } }".write(to: dir.appendingPathComponent("K.swift"), atomically: true, encoding: .utf8)
        try "@Reducer struct Home { @Dependency(\\.eventClient) var e }".write(to: dir.appendingPathComponent("H.swift"), atomically: true, encoding: .utf8)

        let files = try scanFolder(dir).files

        #expect(files.flatMap(\.dependencyKeys) == [DependencyKey(name: "eventClient", type: "EventClient")])
        #expect(files.flatMap(\.types).first { $0.name == "Home" }?.dependencies == ["eventClient"])
    }
}
