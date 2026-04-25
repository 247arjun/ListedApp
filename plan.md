Listed — Cross-Platform macOS/iOS todo.txt Task App Specification

1. Product Summary

Listed is a native SwiftUI task app for macOS, iPhone, and iPad. It presents a modern task-management UI while storing the user’s tasks as plain-text todo.txt files on the filesystem.

The app must prioritize:

1. Plain-text ownership: user data remains readable and editable without Listed.
2. todo.txt compatibility: tasks use the todo.txt convention: one task per line, optional priority, optional creation/completion dates, projects, contexts, and extensible key:value metadata. The official todo.txt primer defines one line as one task and supports priorities, projects, contexts, dates, and key:value extensions.  ￼
3. iCloud-first storage: default storage should live in iCloud Drive under an app folder named Listed.
4. Flexible storage: users may add multiple task files from multiple locations, including iCloud Drive, local app storage, external folders, and other Files-provider locations.
5. Shared SwiftUI implementation: most models, parsing, state, and views should be reusable across macOS and iOS.

⸻

2. Target Platforms

Platform	Minimum target	UI style
macOS	macOS 15+ preferred	Three-column productivity layout
iPhone	iOS 18+ preferred	Stacked navigation, bottom toolbar
iPad	iPadOS 18+ preferred	Three-column layout similar to macOS

SwiftUI should be the primary UI framework. SwiftUI WindowGroup works across Apple platforms, and DocumentGroup supports document-based workflows on iOS and macOS.  ￼

⸻

3. High-Level Goals

Goal	Requirement
Plain-text-first	The canonical task data must be in .txt files, not a database.
todo.txt compatible	Existing todo.txt users should be able to open existing files with minimal surprises.
Multi-file support	A user can manage many files at once.
Multi-location support	Files may live in iCloud Drive, local app storage, user-selected folders, or Files-provider locations.
Cross-platform	macOS, iPhone, and iPad must share most code.
Offline-first	App must work without network connectivity.
Safe file writes	Writes must be atomic and resilient to concurrent external edits.
External editor friendly	If the user edits the file in another app, Listed should detect and reload changes.
Minimal vendor lock-in	Deleting Listed should not make the task data unreadable.

⸻

4. Non-Goals for V1

Non-goal	Rationale
Google Tasks sync	This app uses todo.txt storage, not Google Tasks.
CloudKit task database	iCloud Drive file sync is enough for V1.
Rich-text notes	todo.txt is plain text. Rich text would require non-standard sidecar storage.
Collaboration	File-level iCloud sync is acceptable; multi-user collaboration is out of scope.
Full natural language parsing	V1 can support simple date shortcuts like today, tomorrow, and next week, but not complex NLP.
Encrypted vault	Plain files are the source of truth. Encryption can be added later as a separate storage mode.

⸻

5. Core Architecture

5.1 Recommended Package Layout

Listed/
  ListedApp/
    ListedApp.swift
    Platform/
      macOS/
      iOS/
  ListedCore/
    Models/
    TodoTxt/
    Storage/
    Sync/
    Search/
    Settings/
  ListedUI/
    Components/
    Screens/
    ViewModels/
  ListedTests/
    TodoTxtParserTests/
    StorageTests/
    ViewModelTests/
    UITests/

5.2 Module Responsibilities

Module	Responsibility	Shared across platforms?
ListedCore	Models, parser, serializer, file repository, storage configuration, task operations	✅
ListedUI	Shared SwiftUI views: rows, chips, editors, filter UI, empty states	✅
ListedApp	App entry point, platform-specific scenes, commands, window behavior	⚠️ Partly
Platform/macOS	macOS menu commands, keyboard shortcuts, window sizing	❌
Platform/iOS	iPhone/iPad file picker wrappers, share sheet, touch-specific behavior	❌

⸻

6. Storage Model

6.1 Storage Principles

Listed must treat the filesystem as the source of truth.

Principle	Requirement
Source of truth	.txt files are canonical.
Cache allowed	The app may maintain an index/cache for performance.
Cache disposable	Deleting the cache must not lose user data.
External edits supported	Manual edits in another app should be detected and loaded.
Atomic writes	App writes should not corrupt files if interrupted.
Multi-file aware	The same UI can display tasks from many files.

⸻

6.2 Default iCloud Storage

Default storage should be:

iCloud Drive/
  Listed/
    todo.txt
    done.txt

Implementation notes:

Item	Requirement
iCloud capability	Enable iCloud Documents entitlement. Apple notes that apps enabling iCloud Documents need the iCloud capability and selected containers in Xcode.  ￼
Container name	Configure the app’s visible iCloud Drive container/folder name as Listed where possible.
Initial file	Create todo.txt on first launch if it does not exist.
Completed archive	Create done.txt only when first needed.
App-local fallback	If iCloud is unavailable, offer local app container storage.
User prompt	On first launch, ask whether to use iCloud Drive or local-only storage.

First-Launch Flow

1. App starts.
2. Check whether iCloud Drive is available.
3. If available:
    * Show onboarding screen: “Store tasks in iCloud Drive?”
    * Default option: Use iCloud Drive.
    * Secondary option: Use Local Storage.
4. If iCloud is unavailable:
    * Create local Listed/todo.txt.
    * Show warning banner: “iCloud Drive is unavailable. You can change storage later.”
5. Create default workspace.
6. Open main UI.

⸻

6.3 Flexible File Storage

Users must be able to add arbitrary todo files and folders.

Storage type	Example	V1 support
Default iCloud app folder	iCloud Drive/Listed/todo.txt	✅
Local app container	On My iPhone/Listed/todo.txt	✅
User-selected iCloud folder	iCloud Drive/Tasks/work.txt	✅
User-selected external file	~/Documents/todo.txt on macOS	✅
User-selected folder with many files	~/Dropbox/todo/*.txt	✅
Files-provider folder	Dropbox, OneDrive, etc. via Files app	✅ where provider supports security-scoped access
Network mounts	SMB folder on macOS	⚠️ best-effort
Git repository folder	Any folder containing .txt files	✅ as regular files

For iOS/iPadOS folder access, use the system document picker. Apple’s directory-access guidance states that the document picker returns a security-scoped URL for directories outside the app container.  ￼ For external files, the document picker provides security-scoped URLs and the app must call startAccessingSecurityScopedResource() before using them.  ￼

⸻

6.4 File Source Model

A File Source is a user-approved storage location.

struct FileSource: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var kind: FileSourceKind
    var rootBookmarkData: Data?
    var rootURLString: String?
    var isDefault: Bool
    var isEnabled: Bool
    var createdAt: Date
    var lastAccessedAt: Date?
}
enum FileSourceKind: String, Codable {
    case appICloudContainer
    case appLocalContainer
    case securityScopedFolder
    case securityScopedFile
}

File Source Requirements

Requirement	Description
Stable identity	Each source gets a UUID.
Bookmark persistence	External URLs must be persisted using security-scoped bookmarks where applicable.
Health check	App should show whether each source is reachable.
Reconnect flow	If a bookmark is stale or permission is lost, prompt user to reselect the location.
Disable source	User can temporarily disable a source without deleting its data.
Remove source	Removing a source removes only the app reference, never the file itself unless user explicitly chooses delete.

⸻

6.5 Task File Model

A Task File is a single .txt file that contains tasks.

struct TaskFile: Identifiable, Codable, Hashable {
    let id: UUID
    var sourceID: UUID
    var displayName: String
    var relativePath: String
    var role: TaskFileRole
    var isEnabled: Bool
    var sortOrder: Int
    var lastKnownContentHash: String?
    var lastLoadedAt: Date?
}
enum TaskFileRole: String, Codable {
    case activeTodo
    case completedArchive
    case reference
}

Task File Examples

File	Role	Behavior
todo.txt	activeTodo	Primary active tasks
work.txt	activeTodo	Separate work list
personal.txt	activeTodo	Separate personal list
done.txt	completedArchive	Completed task archive
archive-2026.txt	completedArchive	Historical completed tasks
ideas.txt	reference	Parsed optionally, hidden from default views

⸻

6.6 Multiple Files Behavior

The app must support both file-centric and metadata-centric views.

View type	Example	Behavior
All	Shows tasks from every enabled active file	Default aggregate view
Today	Shows all due today or overdue tasks across files	Aggregated
Upcoming	Shows future due dates across files	Aggregated
File	Shows tasks from one file	Equivalent to a list
Project	Shows all tasks containing +ProjectName	Cross-file
Context	Shows all tasks containing @context	Cross-file
Priority	Shows all tasks with priority (A), (B), etc.	Cross-file
Completed	Shows completed tasks from active and archive files	Optional

Every visible task row must show enough context to avoid ambiguity when multiple files are loaded. For example:

Write unit tests for payment module
Work Projects · work.txt · due tomorrow

⸻

7. todo.txt Data Format

7.1 Supported Standard Fields

Field	Syntax	Example	V1 support
Completion marker	x at start	x 2026-04-25 Task	✅
Completion date	YYYY-MM-DD after x	x 2026-04-25 Task	✅
Priority	(A) to (Z) at start	(A) Call bank	✅
Creation date	YYYY-MM-DD after priority or at start	(A) 2026-04-25 Call bank	✅
Project	+Name	Fix bug +Work	✅
Context	@Name	Call bank @phone	✅
Extra metadata	key:value	due:2026-04-30	✅

⸻

7.2 Listed-Supported Extensions

todo.txt allows additional metadata using key:value. Listed should use this extension mechanism for app-specific metadata. The official todo.txt primer explicitly allows developers to define additional metadata using key:value, including examples such as due:2010-01-02.  ￼

Metadata	Syntax	Example	Purpose
Due date	due:YYYY-MM-DD	due:2026-04-30	Task deadline
Threshold/start date	t:YYYY-MM-DD	t:2026-05-01	Hide until date
Recurrence	rec:<rule>	rec:1w	Future enhancement
Preserved priority	pri:A	pri:A	Preserve priority after completion
Stable task ID	uid:<id>	uid:01JXYZ...	Stable identity
Display order	order:<int>	order:1200	Manual ordering
List alias	list:<name>	list:Home	Optional virtual list
Parent task	parent:<uid>	parent:01JXYZ...	Subtask relationship

⸻

7.3 Canonical Task Examples

Basic Task

Buy milk

Priority

(A) Pay electricity bill

Creation Date

2026-04-25 Read chapter 5 of Swift book

Priority + Creation Date

(A) 2026-04-25 Write unit tests for payment module +Work @mac due:2026-04-27

Completed Task

x 2026-04-25 Write unit tests for payment module +Work @mac due:2026-04-27

Completed Task Preserving Original Priority

x 2026-04-25 2026-04-20 Write unit tests for payment module +Work @mac due:2026-04-27 pri:A

Subtask

Check expired cards +Work @mac parent:01JABCDEF1234567890 uid:01JXYZ1234567890

⸻

7.4 Task Completion Rules

When a user completes an active task:

Step	Behavior
1	Prefix the line with x YYYY-MM-DD.
2	If task had creation date, preserve it after completion date.
3	If task had priority (A), remove the leading priority and append pri:A.
4	Preserve projects, contexts, due date, threshold date, recurrence, uid, parent, and unknown metadata.
5	Keep the task in the same file unless user has enabled auto-archive.

Example:

Before:

(A) 2026-04-20 Write unit tests +Work @mac due:2026-04-27 uid:01JABC

After:

x 2026-04-25 2026-04-20 Write unit tests +Work @mac due:2026-04-27 uid:01JABC pri:A

⸻

7.5 Task Reopening Rules

When a user reopens a completed task:

Step	Behavior
1	Remove leading x YYYY-MM-DD.
2	If pri:A exists, restore leading (A) and remove pri:A.
3	Preserve creation date if present.
4	Preserve projects, contexts, due date, uid, and unknown metadata.

Example:

Before:

x 2026-04-25 2026-04-20 Write unit tests +Work @mac due:2026-04-27 uid:01JABC pri:A

After:

(A) 2026-04-20 Write unit tests +Work @mac due:2026-04-27 uid:01JABC

⸻

7.6 Notes and Descriptions

todo.txt is line-oriented. Therefore, V1 must support single-line task notes/descriptions only.

UI concept	Storage mapping
Task title	Main task description text
Notes field	Additional plain text appended to the same line
Projects	+ProjectName tokens
Contexts	@context tokens
Due date	due:YYYY-MM-DD
Subtasks	Separate task lines with parent:<uid>

V1 Notes Rule

The task detail pane may show a “Notes” field, but it must be backed by the task’s plain-text description. For V1, the developer should not create hidden databases or rich-text sidecars.

Example:

Write unit tests for payment module. Cover expired cards, retries, and invalid state transitions. +Work @mac due:2026-04-27

Future Long-Notes Option

A later version may support sidecar Markdown notes:

Write unit tests for payment module +Work @mac note:01JABC

With:

Listed.notes/
  01JABC.md

This is explicitly not V1 unless separately approved.

⸻

8. Parser and Serializer

8.1 Parser Requirements

Create a parser that converts raw lines into structured tasks.

struct TodoTask: Identifiable, Hashable {
    var id: TodoTaskID
    var sourceFileID: UUID
    var lineNumber: Int
    var rawLine: String
    var isCompleted: Bool
    var completionDate: LocalDate?
    var priority: Character?
    var preservedPriority: Character?
    var creationDate: LocalDate?
    var description: String
    var projects: [String]
    var contexts: [String]
    var metadata: [String: String]
    var uid: String?
    var dueDate: LocalDate?
    var thresholdDate: LocalDate?
    var recurrence: String?
    var parentUID: String?
    var parseWarnings: [TodoParseWarning]
}

8.2 Parsing Order

For each line:

1. Preserve raw line exactly.
2. Detect blank line.
3. Detect completed marker:
    * Must start with lowercase x .
    * Uppercase X is not completion.
4. Detect completion date after x.
5. Detect priority:
    * Only valid if it appears at the beginning of an active task.
    * Pattern: ^\([A-Z]\) .
6. Detect creation date:
    * Active task: after priority or at beginning.
    * Completed task: after completion date.
7. Parse remaining text.
8. Extract projects:
    * Tokens starting with +.
9. Extract contexts:
    * Tokens starting with @.
10. Extract metadata:

* Tokens matching key:value.

11. Preserve unknown metadata.
12. Compute stable display fields.

⸻

8.3 Serializer Requirements

The serializer must turn a TodoTask back into a todo.txt line.

Serializer Rules

Rule	Requirement
Avoid unnecessary rewrites	Do not reformat untouched lines.
Preserve unknown metadata	Unknown key:value pairs must not be dropped.
Preserve ordering where possible	User-authored text should remain recognizable.
Write valid todo.txt	Priority first, then creation date, then description/metadata.
Stable IDs	New tasks created by Listed should get uid:<ULID> by default.
No hidden data loss	If parser sees unknown syntax, serializer must preserve it unless user edits that exact field.

⸻

8.4 Raw Line Preservation Strategy

Each task should retain:

Field	Purpose
rawLine	Preserve original user-authored text.
lineNumber	Map back to file position.
contentHash	Detect stale writes.
parsedFields	Power UI and filters.

When the user edits only one field, the app may minimally rewrite that line. Other lines must remain byte-for-byte unchanged.

⸻

9. File I/O and Data Integrity

9.1 File Loading

For every enabled task file:

1. Resolve file URL.
2. Start security-scoped access if needed.
3. Read file as UTF-8.
4. If UTF-8 fails, try UTF-8 with BOM.
5. If still failing, show import error.
6. Split lines preserving line endings.
7. Parse each line.
8. Update in-memory store.
9. Update search index/cache.

⸻

9.2 File Writing

All writes must be atomic.

Required sequence:

1. Acquire storage actor lock.
2. Resolve security-scoped URL if needed.
3. Read latest file content from disk.
4. Compare latest hash to last known hash.
5. If unchanged:
    * Apply mutation.
    * Write temp file.
    * Replace original atomically.
6. If changed:
    * Reparse latest content.
    * Attempt operation replay.
    * If replay succeeds, write merged content.
    * If replay fails, show conflict UI.
7. Stop security-scoped access.

⸻

9.3 File Coordination

Use file coordination for external/iCloud files.

API	Purpose
NSFileCoordinator	Coordinate reads/writes with iCloud and external editors.
NSFilePresenter	Observe changes to files/directories.
Security-scoped bookmarks	Persist access to user-selected files/folders.
FileManager	Basic file operations inside app-controlled containers.

Apple describes NSFileCoordinator as coordinating reads and writes of files and directories among file presenters.  ￼

⸻

9.4 Conflict Handling

Conflict types:

Conflict	Example	Handling
Same task edited externally	User edits line in TextEdit while Listed edits due date	Try merge by uid; otherwise show conflict
Task deleted externally	Listed tries to complete deleted line	Show “Task no longer exists”
File deleted	External folder removed	Mark source unavailable
File moved	Bookmark stale	Prompt user to reconnect
Duplicate UID	Two tasks share same uid	Show warning and offer repair
Invalid syntax	User writes malformed metadata	Keep line visible and editable as raw text

Conflict UI must show:

This task changed outside Listed.
Version in Listed:
...
Version on disk:
...
Choose:
[Keep Disk Version] [Use Listed Version] [Edit Raw Line]

⸻

10. App Data Model

10.1 Workspace

A workspace is the app’s saved configuration.

struct Workspace: Codable {
    var id: UUID
    var name: String
    var fileSources: [FileSource]
    var taskFiles: [TaskFile]
    var defaultTaskFileID: UUID?
    var sidebarConfiguration: SidebarConfiguration
    var sortConfiguration: SortConfiguration
    var filterPresets: [SavedFilter]
}

V1 may only support one workspace internally, named Default.

⸻

10.2 Task Identity

Use this identity priority:

Priority	Identity source
1	uid:<id> metadata
2	File ID + line number + content hash
3	Temporary UUID for unsaved new task

New tasks created by Listed should include uid:<ULID>.

Example:

Schedule dentist appointment +Home @phone due:2026-04-30 uid:01J6W7KM2Y9VJ9N4WY9J9YF5TN

⸻

10.3 Date Model

Use a date-only type, not Date, for todo.txt dates.

struct LocalDate: Codable, Hashable, Comparable {
    var year: Int
    var month: Int
    var day: Int
}

Reason: todo.txt dates are calendar dates, not instants. Time zones should not accidentally shift a due date.

⸻

11. UI Specification

11.1 Shared UI Concepts

UI element	macOS	iPad	iPhone
Sidebar	Persistent	Persistent or collapsible	Separate screen
Task list	Center column	Center column	Main screen
Detail pane	Right column	Right column	Pushed detail screen
Toolbar	Window toolbar	Navigation toolbar	Navigation toolbar
Add task	Inline row + keyboard shortcut	Inline row + floating button	Floating button / bottom button
Search	Toolbar search	Toolbar search	Searchable list
File source switcher	Sidebar section	Sidebar section	Settings / filter screen

⸻

11.2 macOS Layout

Use NavigationSplitView with three columns.

┌────────────────────┬────────────────────────────┬────────────────────────────┐
│ Sidebar            │ Task List                  │ Detail Pane                │
│                    │                            │                            │
│ Today              │ My Tasks                   │ Write unit tests           │
│ Upcoming           │   ○ Pay electricity bill   │ due: 2026-04-27            │
│ All                │   ○ Review goals           │ +Work @mac                 │
│                    │                            │                            │
│ Files              │ Work Projects              │ Subtasks                   │
│   todo.txt         │   ○ Fix login timeout      │   ✓ Expired cards          │
│   work.txt         │   ○ Write unit tests       │   ○ Retry logic            │
│                    │                            │                            │
│ Projects           │                            │                            │
│ Contexts           │                            │                            │
└────────────────────┴────────────────────────────┴────────────────────────────┘

macOS Requirements

Requirement	Detail
Sidebar width	Minimum 220 pt, default 260 pt
Task list width	Minimum 360 pt
Detail width	Minimum 360 pt
Keyboard navigation	Arrow keys move selection
Complete shortcut	⌘↩ toggles completion
New task	⌘N
Search	⌘F
Raw edit	⌘E
Settings	⌘,
Multi-window	Support multiple windows showing the same workspace
Menu commands	File, Edit, View, Task, Window

⸻

11.3 iPad Layout

iPad should use the same conceptual three-column layout where space allows.

Size class	Layout
Regular width	Sidebar + list + detail
Compact width	Sidebar collapses; list/detail use navigation stack
Stage Manager	Behave like macOS-style resizable window
External keyboard	Support macOS-like shortcuts

⸻

11.4 iPhone Layout

Use stacked navigation.

Tab / root:
  Today
  Upcoming
  All
  Files
  Search
  Settings
Flow:
  Sidebar/Filter screen -> Task list -> Task detail

iPhone Requirements

Requirement	Detail
Add task	Bottom-right floating button or bottom toolbar
Complete task	Tap circle or swipe action
Edit task	Tap row
Move task	Long press or detail menu
Search	.searchable on task list
Filters	Presented as sheet
File source status	Show in Settings

⸻

12. Sidebar Specification

12.1 Default Sidebar Sections

Smart Lists
  Today
  Upcoming
  All
  Inbox
  Completed
Files
  todo.txt
  work.txt
  personal.txt
Projects
  +Work
  +Home
  +Shopping
Contexts
  @phone
  @mac
  @errands
Priorities
  A
  B
  C
Storage
  iCloud Listed
  Local
  External Folder

12.2 Sidebar Row Requirements

Field	Requirement
Icon	SF Symbol
Title	Human-readable
Count	Active task count
Error state	Show warning icon if source unavailable
Selection	Drives task-list query
Context menu	Rename, hide, reveal in Finder/Files, remove source

⸻

13. Task List Specification

13.1 Task Row

Each task row should show:

Element	Requirement
Completion control	Hollow circle for active, checkmark for completed
Priority	Colored (A) badge or subtle indicator
Title	Main description without metadata noise
Due chip	Today, Tomorrow, Overdue, or date
Project/context chips	Optional compact display
Source file	Show when in aggregated views
Subtask indicator	Show count if task has children
Raw syntax warning	Show warning icon if parse issue exists

⸻

13.2 Sorting

Default sort for active tasks:

1. Overdue due date.
2. Due today.
3. Priority A-Z.
4. Due date ascending.
5. Manual order:<int>.
6. Creation date ascending.
7. File order.
8. Line order.

User-configurable sort options:

Sort option	Description
Manual	Uses order:<int> where available
File order	Preserve todo.txt line order
Due date	Earliest due first
Priority	A first, then B, etc.
Project	Group by project
Context	Group by context
Creation date	Oldest/newest
Source file	Group by file

⸻

13.3 Grouping

Supported groupings:

Group	Example
None	Flat task list
File	todo.txt, work.txt
Project	+Work, +Home
Context	@phone, @mac
Due date	Overdue, Today, Tomorrow, Later
Priority	A, B, C, None
Completion	Active, Completed

⸻

14. Task Detail Pane

14.1 Fields

Field	UI control	Storage
Completed	Toggle/check circle	x YYYY-MM-DD prefix
Title/description	Text field/editor	Main text
Priority	Picker A-Z/None	(A) prefix or pri:A if completed
Creation date	Date picker	YYYY-MM-DD
Completion date	Date picker	Completion date after x
Due date	Date picker	due:YYYY-MM-DD
Threshold date	Date picker	t:YYYY-MM-DD
Projects	Token field	+Project
Contexts	Token field	@context
Source file	Picker	Move task between files
Parent task	Picker	parent:<uid>
Raw line	Expandable raw editor	Entire line

⸻

14.2 Raw Line Editor

The raw editor is important because the app must not hide todo.txt from power users.

Requirements:

Requirement	Description
Expandable section	Collapsed by default
Syntax highlighting	Highlight priority, dates, projects, contexts, metadata
Validation	Show warnings but allow saving
Round-trip	Save exactly what user types
Escape hatch	If structured editor fails, raw editor still works

⸻

15. Subtasks

todo.txt does not define native subtasks. Listed will support subtasks using parent:<uid>.

15.1 Parent Task

Write unit tests for payment module +Work @mac due:2026-04-27 uid:01JPARENT

15.2 Child Tasks

Cover expired cards +Work @mac parent:01JPARENT uid:01JCHILD1
Cover retry logic +Work @mac parent:01JPARENT uid:01JCHILD2
Cover invalid state transitions +Work @mac parent:01JPARENT uid:01JCHILD3

15.3 Subtask Rules

Rule	Requirement
Parent must have UID	If user adds a subtask to a task without uid, add one.
Child must have UID	All subtasks created by Listed get UID.
Child inherits defaults	New subtask inherits parent project/context unless user disables this.
Completing parent	Prompt: complete subtasks too, leave as-is, or cancel.
Moving parent	Prompt whether to move subtasks to same file.
Deleting parent	Prompt whether to delete subtasks or promote them.

⸻

16. Task Operations

16.1 Add Task

Inputs

Input	Required?
Description	✅
Target file	✅
Priority	❌
Due date	❌
Project	❌
Context	❌
Creation date	Configurable
UID	Auto-generated

Output Example

(A) 2026-04-25 Pay electricity bill +Home @online due:2026-04-26 uid:01JNEW

⸻

16.2 Edit Task

Edits should be field-level when possible.

Edit	Behavior
Change due date	Replace or add due:YYYY-MM-DD
Remove due date	Remove due:* token
Change priority	Rewrite leading priority
Add project	Append +Project
Remove project	Remove token
Change source file	Remove line from old file, append to new file
Edit raw line	Replace full line

⸻

16.3 Complete Task

See section 7.4.

⸻

16.4 Delete Task

Deletion behavior should be configurable:

Mode	Behavior
Soft delete	Move to trash file, e.g. deleted.txt
Hard delete	Remove line from file
Ask every time	Prompt user

Default for V1: Ask every time, with “Move to deleted.txt” as the safer default.

⸻

16.5 Archive Completed Tasks

User can archive completed tasks from active files into done.txt.

Before:

todo.txt
  x 2026-04-25 2026-04-20 Pay bill +Home

After:

todo.txt
  ...
done.txt
  x 2026-04-25 2026-04-20 Pay bill +Home

Rules:

Rule	Requirement
Preserve line	Move exact completed line.
Same source folder	Default archive file lives next to active file.
Multiple active files	Each folder may have its own done.txt.
Undo	Keep undo stack for current session.

⸻

17. Search and Filtering

17.1 Search Syntax

Support simple search first:

Query	Behavior
payment	Full-text contains
+Work	Project filter
@phone	Context filter
(A)	Priority filter
due:today	Due today
due:2026-04-30	Due on date
file:work.txt	Source file filter
is:done	Completed tasks
is:active	Active tasks

17.2 Search UI

Platform	UI
macOS	Toolbar search field
iPad	Toolbar search field
iPhone	Search bar above list

⸻

18. Settings

18.1 General

Setting	Default
Default storage	iCloud if available
Default task file	todo.txt
Add creation date to new tasks	On
Add UID to new tasks	On
Preserve priority on completion	On
Auto-archive completed tasks	Off
Show completed in lists	Off
Show raw metadata in rows	Off

⸻

18.2 Storage Settings

Setting	Requirement
Add file	Select a .txt file
Add folder	Select a folder and discover .txt files
Create new file	Create new todo file in selected source
Remove file	Stop tracking file
Reveal file	Open Finder on macOS; show Files location on iOS where possible
Reconnect source	Re-pick location if permission lost
Default new-task file	Choose target file

⸻

19. Security and Privacy

Requirement	Description
No telemetry by default	Do not send task names or metadata anywhere.
No account required	iCloud Drive is optional and OS-managed.
Local cache only	Any cache/index remains on device.
Respect sandbox	Use security-scoped access for external files.
No hidden cloud database	Do not mirror tasks to CloudKit in V1.
File permissions	Only access files/folders explicitly selected by user or app container.

⸻

20. Error Handling

20.1 Error Types

Error	User-facing message	Recovery
iCloud unavailable	“iCloud Drive is unavailable.”	Use local storage or retry
File missing	“This task file could not be found.”	Reconnect or remove
Permission lost	“Listed no longer has access to this location.”	Re-select file/folder
Parse warning	“Some lines contain unsupported syntax.”	Show raw editor
Write conflict	“This task changed outside Listed.”	Conflict resolution UI
Encoding error	“This file is not valid UTF-8.”	Open as read-only or choose encoding later
Disk full	“Changes could not be saved because storage is full.”	Retry after freeing space

⸻

21. Testing Requirements

21.1 Parser Tests

Test	Input	Expected
Basic task	Buy milk	Description = Buy milk
Priority	(A) Buy milk	Priority = A
Invalid priority	(a) Buy milk	No priority
Creation date	2026-04-25 Buy milk	Creation date parsed
Project	Buy milk +Home	Project = Home
Context	Call mom @phone	Context = phone
Due date	Task due:2026-04-30	Due date parsed
Completed	x 2026-04-25 Task	Completed true
Completion + creation	x 2026-04-25 2026-04-20 Task	Both dates parsed
Unknown metadata	Task foo:bar	Preserved
URL	Read https://example.com/a:b	Must not corrupt URL
Multiple projects	Task +A +B	Both parsed
Empty line	``	Preserved as blank

⸻

21.2 Serializer Tests

Test	Requirement
Round-trip unchanged	Parse + serialize untouched line returns identical string.
Add due date	Adds due:YYYY-MM-DD once.
Remove due date	Removes only due token.
Change priority	Rewrites leading priority correctly.
Complete task	Adds x YYYY-MM-DD.
Reopen task	Removes completion marker.
Preserve unknown metadata	Keeps unknown tokens.
Preserve line endings	CRLF files remain CRLF.
Preserve final newline	If file had final newline, keep it.

⸻

21.3 Storage Tests

Test	Requirement
Create default iCloud file	Creates todo.txt if missing.
Create local fallback	Works when iCloud unavailable.
Add external file	Persists bookmark.
Reload external edit	Detects file change and updates UI.
Atomic write	Simulate crash during write; original file remains valid.
Conflict detection	External edit between read/write triggers merge or conflict.
Move task between files	Removes from source and appends to destination.
Archive completed	Moves exact line to done.txt.

⸻

21.4 UI Tests

Test	Platform
Add task from Today	macOS/iOS
Complete task from list	macOS/iOS
Edit due date	macOS/iOS
Add project/context	macOS/iOS
Search +Work	macOS/iOS
Add external file	macOS/iOS
Reconnect missing source	macOS/iOS
iPhone navigation flow	iOS
macOS keyboard shortcuts	macOS
iPad split view	iPadOS

⸻

22. Implementation Milestones

Milestone 1 — Core todo.txt Engine

Deliverables:

* LocalDate
* TodoTask
* Parser
* Serializer
* Unit tests
* Basic task operations

Acceptance criteria:

* Parser handles all standard todo.txt examples.
* Serializer round-trips untouched lines.
* Completion/reopen behavior works.
* Unknown metadata is preserved.

⸻

Milestone 2 — Storage Engine

Deliverables:

* File source model
* Task file model
* Default local storage
* Default iCloud storage
* Atomic read/write
* External file import
* File change detection

Acceptance criteria:

* App can create and edit todo.txt.
* App can open an existing file.
* External edits appear after reload.
* Writes do not destroy unknown lines.

⸻

Milestone 3 — Shared SwiftUI Task UI

Deliverables:

* Task row
* Task list
* Task detail pane
* Add task UI
* Project/context chips
* Due-date chips
* Raw line editor

Acceptance criteria:

* User can add, edit, complete, reopen, and delete tasks.
* UI reflects todo.txt metadata.
* Raw editor can save arbitrary valid line text.

⸻

Milestone 4 — macOS App Shell

Deliverables:

* Three-column layout
* Sidebar
* Toolbar
* Menus
* Keyboard shortcuts
* Settings window

Acceptance criteria:

* macOS app feels native.
* User can manage multiple files.
* User can reveal files in Finder.
* Keyboard-first usage works.

⸻

Milestone 5 — iOS/iPadOS App Shell

Deliverables:

* iPhone stacked navigation
* iPad split navigation
* File picker integration
* Touch gestures
* Settings screen

Acceptance criteria:

* iPhone task flow works one-handed.
* iPad layout adapts to window size.
* User can select files/folders via Files app.
* External iCloud files remain accessible after app restart where permissions allow.

⸻

Milestone 6 — Multi-File and Smart Views

Deliverables:

* Aggregated All view
* Today view
* Upcoming view
* File views
* Project views
* Context views
* Priority views
* Search

Acceptance criteria:

* Tasks from multiple files appear correctly.
* Rows indicate source file when needed.
* Filters work across files.
* Moving tasks between files works.

⸻

23. Recommended Technical Decisions

Decision	Recommendation
UI framework	SwiftUI-first
Persistence source of truth	Plain .txt files
Cache	Optional local index in app support directory
Date handling	Custom LocalDate
Task IDs	uid:<ULID> for Listed-created tasks
Default storage	iCloud Documents app folder named Listed
External storage	Security-scoped files/folders
Parser	Custom parser; do not depend on fragile regex-only implementation
Sync	Rely on filesystem/iCloud Drive for V1
Conflict handling	Hash + reparse + operation replay
Notes	Single-line plain text in V1
Subtasks	parent:<uid> extension

⸻

24. Definition of Done for V1

V1 is complete when:

1. A new user can launch Listed and create iCloud Drive/Listed/todo.txt.
2. A user can add, edit, complete, reopen, delete, and archive tasks.
3. A user can use priorities, projects, contexts, due dates, and creation dates.
4. A user can open existing todo.txt files.
5. A user can track multiple task files from multiple locations.
6. macOS, iPhone, and iPad all share the same core parser/storage logic.
7. The app preserves unknown todo.txt metadata.
8. The app does not corrupt files during normal writes.
9. External edits are detected and reflected.
10. The app remains usable offline.
11. The raw todo.txt file remains human-readable and editable in any text editor.