import Foundation
import Testing
@testable import FloorplanScanner

@Suite struct ReducerDetectionTests {
    private func firstType(_ source: String) -> TypeInfo {
        scanSource(source, path: "A.swift").types[0]
    }

    @Test func flagsReducerAttribute() {
        #expect(firstType("@Reducer struct F {}").isReducer)
    }

    @Test func flagsReducerAttributeWithArguments() {
        #expect(firstType("@Reducer(state: .equatable) enum D {}").isReducer)
    }

    @Test func flagsReducerConformance() {
        #expect(firstType("struct F: Reducer {}").isReducer)
    }

    @Test func doesNotFlagPlainTypes() {
        #expect(!firstType("struct V: View {}").isReducer)
    }
}

@Suite struct ReducerLinkTests {
    private func links(_ body: String, name: String = "P") -> [ReducerLink] {
        let source = "@Reducer struct \(name) { var body: some ReducerOf<Self> { \(body) } }"
        return scanSource(source, path: "A.swift").types[0].composes
    }

    @Test func findsScopeChild() {
        let found = links("Scope(state: \\.a, action: \\.a) { AFeature() }")
        #expect(found == [ReducerLink(child: "AFeature", via: .scope)])
    }

    @Test func findsIfLetChildWithClosure() {
        let found = links("Reduce { _, _ in .none }.ifLet(\\.$sheet, action: \\.sheet) { SheetFeature() }")
        #expect(found == [ReducerLink(child: "SheetFeature", via: .ifLet)])
    }

    @Test func findsForEachChild() {
        let found = links("Reduce { _, _ in .none }.forEach(\\.rows, action: \\.rows) { RowFeature() }")
        #expect(found == [ReducerLink(child: "RowFeature", via: .forEach)])
    }

    @Test func ifLetWithoutClosureLinksToNestedEnumNamedAfterTheKey() {
        let found = links("Reduce { _, _ in .none }.ifLet(\\.$destination, action: \\.destination)")
        #expect(found == [ReducerLink(child: "P.Destination", via: .ifLet)])
    }

    @Test func ifLetWithoutClosureLinksToThePresentedType() {
        let source = """
        @Reducer struct P {
            struct State { @Presents var itemDetail: ItemDetail.State? }
            var body: some ReducerOf<Self> { Reduce { _, _ in .none }.ifLet(\\.$itemDetail, action: \\.itemDetail) }
        }
        """
        let found = scanSource(source, path: "A.swift").types[0].composes
        #expect(found == [ReducerLink(child: "ItemDetail", via: .ifLet)])
    }

    @Test func presentedDestinationKeepsTheNestedEnumName() {
        let source = """
        @Reducer struct P {
            @Reducer enum Destination {}
            struct State { @Presents var destination: Destination.State? }
            var body: some ReducerOf<Self> { Reduce { _, _ in .none }.ifLet(\\.$destination, action: \\.destination) }
        }
        """
        let found = scanSource(source, path: "A.swift").types[0].composes
        #expect(found == [ReducerLink(child: "P.Destination", via: .ifLet)])
    }

    @Test func unwrapsReduceAroundTheChildInsideScope() {
        let found = links("Scope(state: \\.a, action: \\.a) { Reduce(AFeature()) }")
        #expect(found == [ReducerLink(child: "AFeature", via: .scope)])
    }

    @Test func forEachWithAnInlineReduceFallsBackToTheNestedEnum() {
        let found = links("Reduce { _, _ in .none }.forEach(\\.path, action: \\.path) { Reduce { _, _ in .none } }")
        #expect(found == [ReducerLink(child: "P.Path", via: .forEach)])
    }

    @Test func readsHelperPropertiesThatReturnAReducer() {
        let source = """
        @Reducer struct P {
            var body: some ReducerOf<Self> { mainReducer }
            private var mainReducer: some ReducerOf<Self> { CombineReducers { ChromeReducer() } }
            var title: String { Label() }
        }
        """
        let found = scanSource(source, path: "A.swift").types[0].composes
        #expect(found == [ReducerLink(child: "ChromeReducer", via: .body)])
    }

    @Test func readsAStaticBodyReferenceAsTheClosureChild() {
        let found = links("Reduce { _, _ in .none }.ifLet(\\.$detail, action: \\.detail) { ItemDetail.body }")
        #expect(found == [ReducerLink(child: "ItemDetail", via: .ifLet)])
    }

    @Test func readsAStaticBodyReferenceListedInBody() {
        let found = links("Reduce { _, _ in .none }\nItemDetail.body")
        #expect(found == [ReducerLink(child: "ItemDetail", via: .body)])
    }

    @Test func findsBareChildInBody() {
        let found = links("ChromeReducer()\nReduce { _, _ in .none }")
        #expect(found == [ReducerLink(child: "ChromeReducer", via: .body)])
    }

    @Test func prefersScopeOverBareBodyForTheSameChild() {
        let found = links("Scope(state: \\.a, action: \\.a) { AFeature() }")
        #expect(found.count == 1)
    }

    @Test func ignoresReduceAndScopeThemselves() {
        #expect(links("Reduce { _, _ in .none }").isEmpty)
    }

    @Test func findsChildrenOfReducerEnumCases() {
        let source = "@Reducer enum Destination { case edit(EditFeature)\n case alert(AlertState<Int>) }"
        let found = scanSource(source, path: "A.swift").types[0].composes
        #expect(found.contains(ReducerLink(child: "EditFeature", via: .enumCase)))
    }

    @Test func keepsNestedTypeLinksOnTheNestedType() {
        let source = """
        @Reducer struct Outer {
            @Reducer struct Inner { var body: some ReducerOf<Self> { InnerChild() } }
            var body: some ReducerOf<Self> { OuterChild() }
        }
        """
        let types = scanSource(source, path: "A.swift").types
        #expect(types[0].composes.map(\.child) == ["OuterChild"])
        #expect(types[1].composes.map(\.child) == ["InnerChild"])
    }
}

@Suite struct ReducerResolveTests {
    @Test func dropsLinksToUnknownTypes() {
        let source = """
        @Reducer struct Parent { var body: some ReducerOf<Self> { Reduce { _, _ in _ = Date(); .none }; Known() } }
        @Reducer struct Known {}
        """
        let file = scanSource(source, path: "A.swift")
        let resolved = resolveReducerLinks([file])
        #expect(resolved[0].types[0].composes == [ReducerLink(child: "Known", via: .body)])
    }

    @Test func folderScanLinksReducersAcrossFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "@Reducer struct Parent { var body: some ReducerOf<Self> { Scope(state: \\.c, action: \\.c) { Child() } } }"
            .write(to: dir.appendingPathComponent("P.swift"), atomically: true, encoding: .utf8)
        try "@Reducer struct Child {}".write(to: dir.appendingPathComponent("C.swift"), atomically: true, encoding: .utf8)

        let result = try scanFolder(dir)

        let parent = try #require(result.files.flatMap(\.types).first { $0.name == "Parent" })
        #expect(parent.composes == [ReducerLink(child: "Child", via: .scope)])
    }

    @Test func pageOffersAReducerTreeView() throws {
        let html = try renderHTML(ScanResult(root: "/tmp/x", files: []))
        #expect(html.contains("Reducer tree"))
    }
}

@Suite struct StoreCreationTests {
    private func creates(_ source: String) -> [[String]] {
        scanSource(source, path: "A.swift").types.filter { $0.kind != .topLevel }.map(\.createsStores)
    }

    @Test func recordsAReducerThatAViewBuildsAStoreFor() {
        let source = "struct V: View { @State private var store = Store(initialState: F.State()) { F() } }"
        #expect(creates(source) == [["F"]])
    }

    @Test func recordsStoresBuiltInInitializers() {
        let source = "struct V: View { init() { _store = State(initialValue: Store(initialState: F.State()) { F() }) } }"
        #expect(creates(source) == [["F"]])
    }

    @Test func attributesTheStoreToTheInnermostType() {
        let source = "struct Outer { struct Inner { let s = Store(initialState: F.State()) { F() } } }"
        #expect(creates(source) == [[], ["F"]])
    }

    @Test func ignoresStoresOutsideAnyType() {
        #expect(creates("let s = Store(initialState: F.State()) { F() }\nstruct V {}") == [[]])
    }

    @Test func ignoresStoreCallsWithoutAReducerClosure() {
        #expect(creates("struct V { let s = Store(initialState: 1) }") == [[]])
    }

    @Test func folderScanKeepsOnlyKnownReducers() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "struct V: View { let a = Store(initialState: F.State()) { F() }; let b = Store(initialState: 1) { Other() } }"
            .write(to: dir.appendingPathComponent("V.swift"), atomically: true, encoding: .utf8)
        try "@Reducer struct F {}".write(to: dir.appendingPathComponent("F.swift"), atomically: true, encoding: .utf8)

        let view = try #require(try scanFolder(dir).files.flatMap(\.types).first { $0.name == "V" })

        #expect(view.createsStores == ["F"])
    }

    @Test func pageShowsWhichViewCreatesAStore() throws {
        let html = try renderHTML(ScanResult(root: "/tmp/x", files: []))
        #expect(html.contains("created by"))
    }
}
