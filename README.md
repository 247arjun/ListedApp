# Listed

A native, plain-text-first task manager for **macOS 26** and **iOS / iPadOS 26**, built in SwiftUI with the Liquid Glass design system. Your tasks live as ordinary `todo.txt` files in iCloud Drive (or anywhere else you choose) — Listed never holds them hostage.

> Specification: see [`plan.md`](./plan.md).

---

## Highlights

- **Plain-text source of truth.** Every task is one line in a `.txt` file. Delete Listed and your data is still readable in any editor.
- **todo.txt compatible.** Priorities `(A)`, projects `+Work`, contexts `@phone`, creation/completion dates, and `key:value` metadata (`due:`, `t:`, `rec:`, `uid:`, `parent:`, `pri:`).
- **iCloud-first storage.** Default tasks live in `iCloud Drive/Listed/todo.txt`. Switch to local-only at any time.
- **Multi-file, multi-location.** Track many `.txt` files across iCloud, the local container, and any user-selected folder via security-scoped bookmarks.
- **Atomic, conflict-aware writes.** All saves go through `NSFileCoordinator` + atomic `.write(to:options:.atomic)`. External edits are detected and reloaded.
- **Liquid Glass UI.** Chips, cards, the inline composer, and onboarding all use `.glassEffect(_:in:)`. macOS gets a three-column `NavigationSplitView`; iPhone gets a stack with a glass tab bar.
- **Shared core.** macOS, iPad, and iPhone share `ListedCore` and `ListedUI`.

## Project layout

```
Listed/
├── Package.swift             # SwiftPM workspace (macOS 26, iOS 26)
├── project.yml               # XcodeGen spec for the App target
├── plan.md                   # Original product spec
├── App/
│   └── ListedApp/            # @main entry point + Info.plist + entitlements
├── Sources/
│   ├── ListedCore/           # Models, parser, serializer, storage, query
│   │   ├── Models/
│   │   ├── TodoTxt/
│   │   ├── Storage/
│   │   └── Search/
│   └── ListedUI/             # Shared SwiftUI views + view models
│       ├── Components/
│       ├── Screens/
│       └── ViewModels/
└── Tests/
    └── ListedCoreTests/      # Parser, serializer, operations, storage, query
```

## Building

### Library (Swift Package Manager)

The core libraries build directly with `swift`:

```sh
swift build
swift test
```

48 unit tests cover parsing, serialization, completion/reopen rules, multi-line files, the query engine, and the file repository.

### App (Xcode)

The Xcode project is generated from `project.yml` so the repo doesn't track a `.xcodeproj`:

```sh
brew install xcodegen          # one-time
xcodegen generate
open Listed.xcodeproj
```

Two schemes are produced:

| Scheme           | Destination                |
|------------------|----------------------------|
| `Listed (macOS)` | macOS 26 (Apple silicon)   |
| `Listed (iOS)`   | iPhone / iPad (iOS 26)     |

Both targets share the `App/ListedApp` sources and link the same `ListedCore` + `ListedUI` package products. Update the `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` (or override per-target in Xcode) before signing for distribution.

### Entitlements

| Entitlement                                                | Why                                                 |
|------------------------------------------------------------|-----------------------------------------------------|
| `com.apple.security.app-sandbox`                           | macOS sandbox                                       |
| `com.apple.security.files.user-selected.read-write`        | "Add file…" / "Add folder…" pickers                 |
| `com.apple.security.files.bookmarks.app-scope`             | Persisting access to user-picked locations          |
| `com.apple.developer.icloud-services = CloudDocuments`     | Default `iCloud Drive/Listed` storage               |
| `com.apple.developer.ubiquity-container-identifiers`       | Same                                                |

## Architecture overview

```
┌──────────────────────────────────────────────────────────────┐
│ App target                                                   │
│  - SwiftUI scenes, Settings, commands, keyboard shortcuts    │
│  - Wires AppModel into the view tree                         │
└────────────────────────┬─────────────────────────────────────┘
                         ▼
┌──────────────────────────────────────────────────────────────┐
│ ListedUI (@MainActor @Observable AppModel)                   │
│  - SidebarView, TaskListView, TaskDetailView, OnboardingView │
│  - Drives TaskRepository through async helpers               │
└────────────────────────┬─────────────────────────────────────┘
                         ▼
┌──────────────────────────────────────────────────────────────┐
│ ListedCore                                                   │
│  - TodoTask, LocalDate, FileSource, TaskFile, Workspace      │
│  - TodoTxtParser / TodoTxtSerializer / TaskOperations        │
│  - TaskRepository (actor): atomic writes, conflict detection │
│  - QueryEngine: smart lists, projects, contexts, search      │
│  - FileURLResolver: iCloud / local / security-scoped         │
└──────────────────────────────────────────────────────────────┘
```

The repository is an actor that serializes all I/O for a workspace. Every write reads the file again first, compares a SHA-256 of the on-disk text against the in-memory hash, and either saves through `NSFileCoordinator` atomically or surfaces a `WriteConflictResolution` to the caller.

## todo.txt support

| Feature                | Status |
|------------------------|--------|
| `x YYYY-MM-DD` completion marker          | ✅ |
| `(A)` … `(Z)` priorities                  | ✅ |
| Creation / completion dates               | ✅ |
| `+Project`, `@Context`                    | ✅ |
| `due:`, `t:`, `rec:`, `uid:`, `parent:`, `pri:`, `order:` | ✅ |
| Unknown `key:value` metadata preserved    | ✅ |
| URLs left untouched                       | ✅ |
| Blank lines preserved                     | ✅ |
| CRLF / LF line endings preserved          | ✅ |
| Trailing newline preserved                | ✅ |

ULIDs are minted automatically (`uid:`) for any task created inside Listed so the structured editor can find a stable target after external edits.

## What's next (post-V1)

- Sidecar Markdown notes (`note:<uid>` → `Listed.notes/<uid>.md`).
- Recurrence engine (consume `rec:` and roll due dates).
- Sub-task hierarchy view (collapsible parent/child).
- Apple Watch companion + Shortcuts support.
- Optional encrypted vault storage.

## License

TBD.
