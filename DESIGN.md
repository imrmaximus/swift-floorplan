# Design

## Steps
1. **Scanner** (done): folder in, per-file facts out (types, imports, referenced names).
2. **Data file** (done, plain JSON): `files[] -> {path, imports, types[] -> {name, kind, line, inherits, references}}`.
3. **HTML map** (done): one static page with the JSON inlined. File cards by folder; click one to see what it uses and what uses it. No server.
4. **Claude naming step** (done by hand-in-session): Claude reads a digest of each folder (type names, imports) and writes `names.json`: `{ "Folder/Path": { name, purpose } }`. The map shows it as the room title. Names are per folder only; the scanner JSON is never changed.

Flow is the same as Floorplan's skill: scan, name, map.

## What we removed
- No graph model, no database, no cache: the JSON file is the only state.
- No TCA reducer-tree detection yet (tca-graph does this). Add it once the plain scan proves useful on the target.
- No `extension` handling, no functions or properties: types are enough to draw a first map.
- No type resolution. "Referenced names" are capitalised identifiers found in the type body.
- No CLI argument library. Two arguments, parsed by hand.
- No separate `Scanner` protocol or `Reporter` layer: two free functions and one visitor.

## Parser
SwiftSyntax, not regex: it understands nesting, attributes and macros, and it is Apple's own parser, so new Swift syntax keeps working.

## Known limits (accepted for now)
- References include stdlib and framework names (`String`, `Date`, `Self`) and unqualified `State` / `Action`. Filtering is a map-step concern.
- A reference is guessed from capitalisation; it can include enum-like constants and miss lowercase types.
- A reference is attributed to the innermost type only.
- Cross-file linking (which file defines `LifeItem`) is not done in the scanner; the map step can join on type names.

## Features (cross-folder grouping)
`features.json` is an ordered list of `{ name, purpose, match: [words] }`. A file joins the first feature whose word appears in its path (case-insensitive). Files that match nothing show under "Unassigned". The map has a "Group by folder / feature" switch. Matching is a plain substring on the path, so a word like `tag` can catch unrelated names; check the Unassigned list and the biggest groups after editing the rules.

## TCA reducer tree
A type is a reducer if it has `@Reducer` or conforms to `Reducer`. For each reducer we read `body` and any helper property that returns a reducer, and record children as `{child, via}`:
`scope` (`Scope { Child() }`, also `Scope { Reduce(Child()) }`), `ifLet` and `forEach` (closure child, or the nested `Destination`/`Path` enum when there is no usable closure), `body` (a child listed directly or inside `CombineReducers`), `enumCase` (cases of a `@Reducer enum`). After the whole folder is scanned, links to names that are not reducers (`Date()`, `UUID()`) are dropped.
Limits: purely syntactic. Reducers built by functions, extensions in other modules, or `Scope(child:)` forms are missed. Root reducers in the page are reducers nobody includes that have children.
Also read: a reducer used through its static body (`{ ItemDetail.body }` inside `.ifLet`, or `ItemDetail.body` listed in `body`), and `Store(initialState:) { Feature() }` inside any type, recorded as `createsStores` on that type (the page shows it as "created by" on root reducers).

### How the tree is drawn
Each root reducer is one full-width card in a single column. Its children are a grid of tiles (min 270 px, name on one line, full file name below). The left edge color shows how the child is included: scope green, ifLet blue, forEach purple, body gray, enumCase orange. The dot is the feature. A tile with "N ›" opens its own children in a tinted block right below it. Any tile opens the side panel (included by, includes, store created by). The filter box hides roots with no match and outlines matching tiles. We chose this after comparing cards, columns and an outline; a plain expandable list looked too flat.

## Automatic naming (`--auto-name`)
With `--names` and/or `--features` files, the tool finds folders with no name and files no feature rule matches, sends a short digest (folder, file count, imports, type names) to `claude -p`, and writes the answers back to those files. Existing entries are never changed. New feature rules go last, so old rules keep winning. The model call is a plain function, so tests use a fake. Limits: names come from type names, not from reading the code; it needs the `claude` CLI on the PATH; one call per file (about 30 to 60 seconds each); a malformed reply stops the run with an error and writes nothing.

## Several folders in one scan (`--also`)
`swift-floorplan <main> --also <folder> --also <folder>`. Paths of the main folder stay as they are, so existing names and feature rules keep working. Files of an `--also` folder get that folder's name in front (`AppTests/Features/...`). Reducer links are resolved across all folders. The scan result lists these folder names (`extraFolders`), and feature matching skips that leading name: otherwise `AppTests/` matched the word "project" and 198 files landed in the wrong feature. Limit: two `--also` folders with the same last name would mix their paths.

## Dependencies view
A type that has `@Dependency(\.name) var ...` records `name` in `dependencies`. A file with `extension DependencyValues { var name: Type { get set } }` records `{name, type}` in `dependencyKeys`. The page joins the two: one card per key, sorted by number of users. Keys declared in the scan come first; keys from libraries (`uuid`, `continuousClock`) go in a second section. The card also shows frameworks. EventKit, CloudKit and UserNotifications come from imports plus type names (`EKEventStore` and friends) in the key's file and in types named after it (`LiveReminderClient` for `ReminderClient`, test types skipped), because `LiveReminderClient.swift` uses EventKit without importing it. Boring frameworks (SwiftUI, Foundation, ComposableArchitecture, AppKit, UIKit...) are left out.
CoreData is not taken from imports: 130 of 190 keys sit in files that import it out of habit. A key shows CoreData when its code uses `NSManagedObject`, `NSFetchRequest`, `NSPersistent*` or a record class (a subclass of `NSManagedObject`), directly, or through one hop to another type, or through a dependency it reads (`FetchGroupesUseCase` reads `groupeStoreClient`). In the target app about 90% of keys reach Core Data, so the filter is most useful inverted: a leading `!` hides matches, and `!coredata` lists the dependencies that do not touch the database.
Limits: only the key-path form `@Dependency(\.name)` is read, not `@Dependency(Foo.self)`. Dependencies read through `withDependencies` or a `DependencyValues` parameter are not seen. Types are related by name and by file, so a file that declares many keys can credit all of them with one key's Core Data use. Two hops through types are not followed. A struct and its extensions count as one type for the hop; a name declared twice (`State`, `Action`) is skipped. Clients passed as function arguments (`input.eventClient`) are not seen, only `@Dependency` reads. Only keys used by at least one type get a card.

## What the scanner keeps outside types
`extension Foo { ... }` is listed as `Foo (extension)` (kind `extension`) and code outside any type (free functions, globals, previews) as `(top level code)` (kind `topLevel`), once per file. Both carry the references they make, so the file-to-file links no longer lose what extensions and helper functions use. Types declared inside an extension keep their plain name (`ColumnSync`, not `AppReducer.ColumnSync`), because reducer bodies refer to them that way; qualifying them dropped 5 reducer links. Extensions never count as reducers, and `extension DependencyValues` is read for keys only.
