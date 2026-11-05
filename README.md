# swift-floorplan

A local tool that reads a Swift / iOS codebase and writes an interactive, plain-English map of it as one HTML file. It ports the idea of [Floorplan](https://github.com/haydenschmitty/floorplan) (MIT), which only supports web stacks.

Everything runs on your machine. The map is a single static HTML page with the data inlined, so it needs no server and makes no network calls.

## What you get
- **File cards** grouped by folder or by feature. Click a card to see the types inside, the files it uses and the files that use it.
- **Names and purposes** for folders and features, in plain English.
- **Reducer tree** for [TCA](https://github.com/pointfreeco/swift-composable-architecture) apps: root reducers as cards, child reducers as tiles colored by how they are included (scope, ifLet, forEach, body, enumCase), plus the view that creates each root store.
- **Dependencies view** for TCA apps: every `@Dependency(\.name)` as a card with its type, the frameworks its file imports (EventKit, CoreData...) and the types that use it. Filter by "eventkit" to see what touches the calendar.
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

## How it works and its limits
It parses each file with SwiftSyntax and records types, what they inherit and which capitalised names they mention. This is a heuristic: a name links to a file only if exactly one scanned file defines it. Reducer detection is syntax only, so reducers built by functions are missed. See [DESIGN.md](DESIGN.md) for the details.

## Develop
```sh
swift test
```
