import Foundation
import Testing
@testable import FloorplanScanner

@Suite struct AutoNamingTests {
    private let scan = ScanResult(root: "/tmp/x", files: [
        scanSource("struct Home {}", path: "Features/Home/Home.swift"),
        scanSource("struct Tag {}", path: "Features/Tags/Tag.swift"),
        scanSource("struct Top {}", path: "Top.swift"),
    ])
    private let known = ["Features/Home": RoomName(name: "Home screen", purpose: "Hand written.")]

    @Test func listsOnlyFoldersWithoutAName() {
        #expect(foldersWithoutName(scan, names: known) == ["(top level)", "Features/Tags"])
    }

    @Test func digestShowsFolderAndTypeNames() {
        let digest = namesDigest(scan, folders: ["Features/Tags"])
        #expect(digest.contains("Features/Tags"))
        #expect(digest.contains("Tag"))
        #expect(!digest.contains("Home"))
    }

    @Test func parsesJSONWrappedInFencesAndChatter() throws {
        let reply = "Sure!\n```json\n{\"Features/Tags\": {\"name\": \"Tags\", \"purpose\": \"Labels.\"}}\n```\nDone."
        let names = try parseModelJSON([String: RoomName].self, from: reply)
        #expect(names["Features/Tags"]?.name == "Tags")
    }

    @Test func throwsWhenTheReplyHasNoJSON() {
        #expect(throws: ScanError.self) { try parseModelJSON([String: RoomName].self, from: "no json here") }
    }

    @Test func fillKeepsExistingNamesAndAddsNewOnes() throws {
        let reply = #"{"Features/Tags": {"name": "Tags", "purpose": "Labels."}, "Features/Home": {"name": "WRONG", "purpose": "x"}}"#
        let merged = try fillMissingNames(scan, existing: known) { _ in reply }
        #expect(merged["Features/Home"]?.name == "Home screen")
        #expect(merged["Features/Tags"]?.name == "Tags")
    }

    @Test func fillDoesNotCallTheModelWhenNothingIsMissing() throws {
        let all = ["(top level)": known.values.first!, "Features/Home": known.values.first!, "Features/Tags": known.values.first!]
        let merged = try fillMissingNames(scan, existing: all) { _ in throw ScanError.unreadableFile("model was called") }
        #expect(merged == all)
    }

    @Test func fillMissingFeaturesAppendsRulesAfterTheExistingOnes() throws {
        let rules = [FeatureRule(name: "Home", purpose: "p", match: ["home"])]
        let reply = #"[{"name": "Tags", "purpose": "Labels.", "match": ["tag"]}]"#
        var prompt = ""
        let merged = try fillMissingFeatures(scan, existing: rules) { prompt = $0; return reply }
        #expect(merged.map(\.name) == ["Home", "Tags"])
        #expect(prompt.contains("Features/Tags/Tag.swift"))
        #expect(!prompt.contains("Features/Home/Home.swift"))
    }
}
