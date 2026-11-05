import Foundation
import Testing
@testable import FloorplanScanner

@Suite struct ParseOptionsTests {
    @Test func readsEveryFlag() {
        let o = parseOptions(["App", "-o", "o.json", "--html", "m.html", "--names", "n.json", "--features", "f.json", "--auto-name", "--also", "A", "--also", "B"])
        #expect(o == Options(folder: "App", also: ["A", "B"], output: "o.json", html: "m.html", names: "n.json", features: "f.json", autoName: true))
    }

    @Test func aFolderAloneUsesDefaults() {
        #expect(parseOptions(["App"]) == Options(folder: "App"))
    }

    @Test func noArgumentsMeansUsage() {
        #expect(parseOptions([]) == nil)
    }

    @Test func aFlagWithoutAValueIsIgnored() {
        let o = parseOptions(["App", "--html"])
        #expect(o?.html == nil)
        #expect(o?.also == [])
    }
}

@Suite struct RunCommandTests {
    private func makeProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Features/Tags"), withIntermediateDirectories: true)
        try "struct Tag {}".write(to: dir.appendingPathComponent("Features/Tags/Tag.swift"), atomically: true, encoding: .utf8)
        return dir
    }
    private let noModel: Ask = { _ in throw ScanError.modelReplyUnreadable("the model must not be called") }

    @Test func printsJSONWhenThereIsNoOutputFile() throws {
        let dir = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = try runCommand(Options(folder: dir.path), ask: noModel)
        #expect(String(decoding: try #require(out), as: UTF8.self).contains("\"Tag\""))
    }

    @Test func writesTheFilesAndPrintsNothing() throws {
        let dir = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = dir.appendingPathComponent("o.json").path, html = dir.appendingPathComponent("m.html").path
        let out = try runCommand(Options(folder: dir.path, output: json, html: html), ask: noModel)
        #expect(out == nil)
        #expect(try String(contentsOfFile: json, encoding: .utf8).contains("\"Tag\""))
        #expect(try String(contentsOfFile: html, encoding: .utf8).hasPrefix("<!doctype html>"))
    }

    @Test func htmlOnlyDoesNotPrintJSON() throws {
        let dir = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = try runCommand(Options(folder: dir.path, html: dir.appendingPathComponent("m.html").path), ask: noModel)
        #expect(out == nil)
    }

    @Test func autoNameCreatesAndFillsTheNamesFile() throws {
        let dir = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = dir.appendingPathComponent("names.json").path
        let ask: Ask = { _ in #"{"Features/Tags": {"name": "Tags", "purpose": "Labels."}}"# }
        _ = try runCommand(Options(folder: dir.path, output: dir.appendingPathComponent("o.json").path, names: names, autoName: true), ask: ask)
        let saved = try decodeRoomNames(Data(contentsOf: URL(fileURLWithPath: names)))
        #expect(saved["Features/Tags"]?.name == "Tags")
    }

    @Test func autoNameFillsTheFeaturesFile() throws {
        let dir = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }
        let features = dir.appendingPathComponent("features.json").path
        let ask: Ask = { _ in #"[{"name": "Tags", "purpose": "Labels.", "match": ["tag"]}]"# }
        _ = try runCommand(Options(folder: dir.path, output: dir.appendingPathComponent("o.json").path, features: features, autoName: true), ask: ask)
        #expect(try decodeFeatureRules(Data(contentsOf: URL(fileURLWithPath: features))).map(\.name) == ["Tags"])
    }

    @Test func withoutAutoNameTheModelIsNeverCalledAndNamesAreRead() throws {
        let dir = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = dir.appendingPathComponent("names.json")
        try #"{"Features/Tags": {"name": "Tags", "purpose": "Hand written."}}"#.write(to: names, atomically: true, encoding: .utf8)
        let html = dir.appendingPathComponent("m.html").path
        _ = try runCommand(Options(folder: dir.path, html: html, names: names.path), ask: noModel)
        #expect(try String(contentsOfFile: html, encoding: .utf8).contains("Hand written."))
    }

    @Test func aBrokenNamesFileIsAnError() throws {
        let dir = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = dir.appendingPathComponent("names.json")
        try "not json".write(to: names, atomically: true, encoding: .utf8)
        #expect(throws: ScanError.self) { try runCommand(Options(folder: dir.path, names: names.path), ask: noModel) }
    }

    @Test func aMissingFolderIsAnError() {
        #expect(throws: ScanError.self) { try runCommand(Options(folder: "/nonexistent-\(UUID().uuidString)"), ask: noModel) }
    }
}
