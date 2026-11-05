import Foundation
import Testing
@testable import FloorplanScanner

@Suite struct FeatureTests {
    private let rules = [
        FeatureRule(name: "Habits", purpose: "Daily habits.", match: ["habit"]),
        FeatureRule(name: "Inbox", purpose: "Unfiled items.", match: ["inbox", "unfiled"]),
    ]

    @Test func ignoresTheExtraFolderNameWhenMatching() {
        // "HabitTests/" is only the folder the file came from; it must not count as the word "habit".
        let result = ScanResult(root: "/tmp/x", files: [scanSource("struct A {}", path: "HabitTests/Core/CacheTests.swift")], extraFolders: ["HabitTests"])
        #expect(assignFeatures(result.files, rules: rules, ignoringFolders: result.extraFolders).isEmpty)
    }

    @Test func stillMatchesWordsAfterTheExtraFolderName() {
        let result = ScanResult(root: "/tmp/x", files: [scanSource("struct A {}", path: "HabitTests/Streaks/HabitStreakTests.swift")], extraFolders: ["HabitTests"])
        #expect(assignFeatures(result.files, rules: rules, ignoringFolders: result.extraFolders).values.first == "Habits")
    }

    private func scan(_ paths: [String]) -> ScanResult {
        ScanResult(root: "/tmp/x", files: paths.map { scanSource("struct A {}", path: $0) })
    }

    @Test func matchesFileNameIgnoringCase() {
        let map = assignFeatures(scan(["Data/Stores/HabitStore.swift"]).files, rules: rules)
        #expect(map["Data/Stores/HabitStore.swift"] == "Habits")
    }

    @Test func matchesFolderNameInPath() {
        let map = assignFeatures(scan(["Features/Inbox/View.swift"]).files, rules: rules)
        #expect(map["Features/Inbox/View.swift"] == "Inbox")
    }

    @Test func firstRuleWins() {
        let map = assignFeatures(scan(["Habit/InboxHabit.swift"]).files, rules: rules)
        #expect(map["Habit/InboxHabit.swift"] == "Habits")
    }

    @Test func leavesUnmatchedFilesOut() {
        let map = assignFeatures(scan(["Core/Utils/Cache.swift"]).files, rules: rules)
        #expect(map.isEmpty)
    }

    @Test func decodesRulesFile() throws {
        let json = #"[{"name":"Habits","purpose":"Daily habits.","match":["habit"]}]"#
        #expect(try decodeFeatureRules(Data(json.utf8)) == [rules[0]])
    }

    @Test func throwsOnMalformedRulesFile() {
        #expect(throws: ScanError.self) { try decodeFeatureRules(Data("{}".utf8)) }
    }

    @Test func embedsFeaturesInThePage() throws {
        let html = try renderHTML(scan(["HabitStore.swift"]), features: rules)
        #expect(html.contains("Daily habits."))
        #expect(html.contains("\"HabitStore.swift\":\"Habits\""))
        #expect(!html.contains("__FEATURES__"))
    }

    @Test func defaultsToNoFeatures() throws {
        let html = try renderHTML(scan(["A.swift"]))
        #expect(html.contains("const FEATURE_OF = {}"))
        #expect(html.contains("const FEATURES = []"))
    }
}
