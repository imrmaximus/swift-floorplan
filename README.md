# swift-floorplan

A local tool that reads a Swift / iOS codebase and writes an interactive, plain-English map of it as one HTML file. It ports the idea of [Floorplan](https://github.com/haydenschmitty/floorplan) (MIT), which only supports web stacks.

Everything runs on your machine. The map is a single static HTML page with the data inlined, so it needs no server and makes no network calls.

## What you get
- **File cards** grouped by folder or by feature. Click a card to see the types inside, the files it uses and the files that use it.
- **Names and purposes** for folders and features, in plain English.
- **Reducer tree** for [TCA](https://github.com/pointfreeco/swift-composable-architecture) apps: root reducers as cards, child reducers as tiles colored by how they are included (scope, ifLet, forEach, body, enumCase), plus the view that creates each root store.
- **Dependencies view** for TCA apps: every `@Dependency(\.name)` as a card with its type, the frameworks its file imports (EventKit, CoreData...) and the types that use it. Filter by "eventkit" to see what touches the calendar, or `!coredata` to see what does not touch the database.
- **Core Data view**: one card per record class (a subclass of `NSManagedObject`), with the dependencies and types that mention it.
- A filter box that works in every view.

## Requirements
Swift 6 toolchain, macOS 14 or later. The scanner uses [SwiftSyntax](https://github.com/swiftlang/swift-syntax). `--auto-name` also needs the [`claude` CLI](https://docs.claude.com/en/docs/claude-code) on your PATH.

## Use
```sh
mkdir -p out
swift run swift-floorplan <folder> -o out/scan.json --html out/map.html
```
Open `out/map.html` in a browser.

| Flag | What it does |
|------|--------------|
| `-o file.json` | Write the raw scan (types, references, reducers) as JSON. |
| `--html file.html` | Write the interactive map. |
| `--names names.json` | Folder names and purposes: `{ "Features/Inbox": { "name": "...", "purpose": "..." } }`. |
| `--features features.json` | Cross-folder features: `[ { "name": "...", "purpose": "...", "match": ["word"] } ]`. First matching rule wins. |
| `--auto-name` | Ask `claude -p` to fill only the missing names and feature rules. Hand-written entries are never changed. |
| `--also <folder>` | Scan another folder too (repeatable). Its files get the folder name as a path prefix. |

Without `-o` and `--html`, the JSON goes to stdout.

## First run
1. Clone this repo and build it once: `swift build` (the first build compiles SwiftSyntax and takes a few minutes).
2. Scan the folder that holds your app's Swift sources. If the code is split over several folders (a design system, tests, widgets), add `--also <folder>` for each one:
   ```sh
   mkdir -p out
   swift run swift-floorplan ~/Dev/MyApp/Sources --also ~/Dev/MyApp/Tests -o out/scan.json --html out/map.html
   ```
3. Open `out/map.html`. Start with "Group by folder". The "Reducer tree", "Dependencies" and "Core Data" views appear only when the scan finds reducers, `@Dependency` uses or `NSManagedObject` subclasses.
4. Optional: add `--auto-name` to get plain-English folder names and feature groups from `claude -p`. It writes `names.json` and `features.json` next to your outputs when you pass `--names` and `--features`. Edit those files by hand and rerun: your entries are kept.

Scan results and maps describe your code, so keep `out/` out of version control (it is in this repo's `.gitignore`).

## How it works and its limits
It parses each file with SwiftSyntax and records types, what they inherit and which capitalised names they mention. This is a heuristic: a name links to a file only if exactly one scanned file defines it. Reducer detection is syntax only, so reducers built by functions are missed. Types are found by capitalised names; a bare call to a free function (`purgeOldRecords()`) is followed one hop when exactly one file declares that function. Methods called on a value (`store.purge()`) are not tracked. See [DESIGN.md](DESIGN.md) for the details.

## Develop
```sh
swift test
```
The command line is thin: `Command.swift` parses the flags and runs the job, so tests cover it. Only `main.swift` (usage message, exit codes, the `claude -p` runner) is untested.
