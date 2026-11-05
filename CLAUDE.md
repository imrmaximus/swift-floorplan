# swift-floorplan

## Goal
A local developer tool (not an app) that reads a Swift/iOS codebase and produces an interactive,
plain-English map of it. It ports the idea of Floorplan (https://github.com/haydenschmitty/floorplan, MIT),
which only supports web stacks. First real target: a private TCA + SwiftUI + Core Data + EventKit app (~1148 Swift files,
its path is in STATUS.md, which stays local). That repo is read-only for us: never modify it.

## Target
Swift 6, macOS 14+, Swift Package Manager, SwiftSyntax for parsing. Tests use Swift Testing.

## Rules
- Tests first, 80% coverage minimum on our own code (`Sources/`).
- No commit and no GitHub remote without asking the user first.
- Simplest solution first. No abstraction without two real uses.
- Files 200 to 400 lines (800 max), functions under 50 lines.
- Docs and code comments in English, plain words.

## Current scope
Done: scanner (JSON), static HTML map, folder names file (`--names`), cross-folder features file (`--features`).
Also done: TCA reducer tree (`isReducer` + `composes` on each type; "Reducer tree" view = root cards with a tile grid of children).
Also done: several folders in one scan (`--also`, extra files get their folder name as path prefix). Also done: automatic naming. `--auto-name` asks `claude -p` for names of folders and rules for files that have none yet; hand-written entries are never changed.

## Commands
- `swift test` runs the tests.
- `swift run swift-floorplan <folder> [-o out/result.json] [--html out/map.html] [--names names.json] [--features features.json] [--auto-name] [--also <folder>]...` (create `out/` first).
