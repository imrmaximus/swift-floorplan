import Foundation
import Testing
@testable import FloorplanScanner

@Suite struct HTMLMapTests {
    private func sample(path: String = "A.swift") -> ScanResult {
        let file = scanSource("import SwiftUI\nstruct Home: View {}", path: path)
        return ScanResult(root: "/tmp/x", files: [file])
    }

    @Test func embedsTheScanDataAndLeavesNoPlaceholder() throws {
        let html = try renderHTML(sample())
        #expect(html.contains("\"Home\""))
        #expect(!html.contains("__SCAN_DATA__"))
    }

    @Test func producesOneSelfContainedDocument() throws {
        let html = try renderHTML(sample())
        #expect(html.hasPrefix("<!doctype html>"))
        #expect(!html.contains("src=\"http"))
        #expect(!html.contains("href=\"http"))
    }

    @Test func escapesScriptClosingTagsInsideData() throws {
        let result = sample(path: "</script><b>.swift")
        let html = try renderHTML(result)
        // The only closing script tag must be the template's own.
        #expect(html.components(separatedBy: "</script>").count == 2)
    }
}

@Suite struct ReducerTreePageTests {
    @Test func pageHasTheRootListAndChildTiles() throws {
        let html = try renderHTML(ScanResult(root: "/tmp/x", files: []))
        // Roots stack in one column; children are a grid of tiles colored by how they are included.
        #expect(html.contains(".roots {"))
        #expect(html.contains(".coll {"))
        #expect(html.contains(".tile.enumCase"))
        #expect(html.contains("subcoll"))
        #expect(!html.contains("<details"))
    }
}

@Suite struct DependencyPageTests {
    @Test func pageHasADependenciesViewAndEmbedsTheScannedData() throws {
        let file = scanSource("extension DependencyValues { var eventClient: EventClient { get set } }\nstruct Home { @Dependency(\\.eventClient) var e }", path: "Home.swift")
        let html = try renderHTML(ScanResult(root: "/tmp/x", files: [file]))
        #expect(html.contains("value=\"deps\""))
        #expect(html.contains(".depcard"))
        #expect(html.contains("\"dependencyKeys\""))
        #expect(html.contains("\"eventClient\""))
    }
}

@Suite struct EntityPageTests {
    @Test func pageHasACoreDataViewListingRecordClasses() throws {
        let record = scanSource("class TaskRecord: NSManagedObject {}", path: "TaskRecord.swift")
        let user = scanSource("struct Home { let r: TaskRecord }", path: "Home.swift")
        let html = try renderHTML(ScanResult(root: "/tmp/x", files: [record, user]))
        #expect(html.contains("value=\"entities\""))
        #expect(html.contains("function drawEntities"))
        #expect(html.contains("\"NSManagedObject\""))
        // A dependency is credited through its own client type, not through every type in its files.
        #expect(html.contains("relatedOf(d).named"))
        // A call to a free function that touches Core Data counts as one hop.
        #expect(html.contains("functionFiles"))
    }
}

@Suite struct RoomNamesTests {
    private let scan = ScanResult(root: "/tmp/x", files: [scanSource("struct A {}", path: "Features/Inbox/A.swift")])

    @Test func decodesNamesFile() throws {
        let json = #"{"Features/Inbox": {"name": "Inbox", "purpose": "Where new items land."}}"#
        let names = try decodeRoomNames(Data(json.utf8))
        #expect(names["Features/Inbox"] == RoomName(name: "Inbox", purpose: "Where new items land."))
    }

    @Test func throwsOnMalformedNamesFile() {
        #expect(throws: ScanError.self) { try decodeRoomNames(Data("not json".utf8)) }
    }

    @Test func embedsNamesInThePage() throws {
        let names = ["Features/Inbox": RoomName(name: "Inbox", purpose: "Where new items land.")]
        let html = try renderHTML(scan, names: names)
        #expect(html.contains("Where new items land."))
        #expect(!html.contains("__ROOM_NAMES__"))
    }

    @Test func escapesScriptClosingTagInNames() throws {
        let names = ["x": RoomName(name: "</script>", purpose: "p")]
        let html = try renderHTML(scan, names: names)
        #expect(html.components(separatedBy: "</script>").count == 2)
    }

    @Test func defaultsToNoNames() throws {
        let html = try renderHTML(scan)
        #expect(html.contains("const NAMES = {}"))
    }
}

@Suite struct GraphPanelTests {
    @Test func fileAndReducerPanelsDrawTheNeighbourGraph() throws {
        let file = scanSource("struct A { let b: B }", path: "A.swift")
        let html = try renderHTML(ScanResult(root: "/tmp/x", files: [file]))
        #expect(html.contains("function neighbourGraph"))
        // One drawing function serves both panels, and each click hands a key back.
        #expect(html.contains("neighbourGraph(r.name"))
        #expect(html.contains("g[data-p]"))
        // Deselecting and cutting long lists are part of the contract.
        #expect(html.contains("GRAPH_MAX"))
    }
}

@Suite struct GraphOptionTests {
    @Test func pageCanDrawEveryViewAsOneGraphWithoutAnyOutsideCode() throws {
        let file = scanSource("struct A { let b: B }", path: "A.swift")
        let html = try renderHTML(ScanResult(root: "/tmp/x", files: [file]))
        #expect(html.contains("id=\"graphToggle\""))
        #expect(html.contains("function drawGraph"))
        #expect(!html.contains("__GRAPH_SCRIPT__"))
        // The page must stay offline and self-contained: no script, style or request to another host.
        #expect(!html.contains("<script src"))
        #expect(!html.contains("http://") && !html.contains("https://"))
        #expect(!html.contains("fetch(") && !html.contains("XMLHttpRequest"))
    }

    @Test func graphHasAGroupFilterWithBulkActionsAndLinkedGroups() throws {
        let file = scanSource("struct A { let b: B }", path: "A.swift")
        let html = try renderHTML(ScanResult(root: "/tmp/x", files: [file]))
        #expect(html.contains("function groupSelection"))
        #expect(html.contains("data-all=\"1\"") && html.contains("data-all=\"0\""))
        #expect(html.contains("Linked to the shown "))
        #expect(html.contains("graph.onClear"))
        #expect(html.contains("id=\"groups\""))
    }

    @Test func cardViewsCanShowOnlyOrphanFiles() throws {
        let file = scanSource("struct A {}", path: "A.swift")
        let html = try renderHTML(ScanResult(root: "/tmp/x", files: [file]))
        #expect(html.contains("id=\"orphanToggle\""))
        #expect(html.contains("const isOrphan"))
        #expect(html.contains("files.filter(isOrphan)"))
        #expect(html.contains("not used by any file and not using any other file"))
    }
}
