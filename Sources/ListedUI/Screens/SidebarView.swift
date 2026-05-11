import SwiftUI
import ListedCore

/// Three-column-aware sidebar shared by macOS and iPad. iPhone presents this as a
/// stand-alone screen.
///
/// Refreshed with tinted icon badges, section color washes, and richer visual hierarchy.
public struct SidebarView: View {
    @Environment(AppModel.self) private var model

    /// When `true`, taps push onto a `NavigationStack` via `NavigationLink(value:)`
    /// (iPhone). When `false`, taps update the `List(selection:)` binding to drive
    /// the next column of a `NavigationSplitView` (iPad / macOS).
    ///
    /// **Why explicit?** Inside a `NavigationSplitView`'s sidebar column,
    /// `horizontalSizeClass` reports `.compact` (relative to the column width) even
    /// on iPad's full-window regular layout — so detecting mode locally is unreliable.
    /// The parent (`RootView`) knows the correct mode and passes it down.
    private let usesPushNavigation: Bool

    public init(usesPushNavigation: Bool = false) {
        self.usesPushNavigation = usesPushNavigation
    }

    public var body: some View {
        if usesPushNavigation {
            plainSidebarList
                .navigationTitle("Listed")
        } else {
            #if os(macOS)
            selectionSidebarList
                .navigationTitle("Listed")
                .frame(minWidth: 240)
            #else
            selectionSidebarList
                .navigationTitle("Listed")
            #endif
        }
    }

    // MARK: - List variants

    private var selectionSidebarList: some View {
        List(selection: Binding(
            get: { Optional(model.selection) },
            set: { newValue in
                if let newValue {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.selection = newValue
                    }
                }
            }
        )) {
            sidebarSections
        }
        .listStyle(.sidebar)
    }

    private var plainSidebarList: some View {
        List {
            sidebarSections
        }
        .listStyle(.sidebar)
    }

    // MARK: - Sections

    @ViewBuilder
    private var sidebarSections: some View {
        Section {
            ForEach(TaskQuery.SmartList.allCases, id: \.self) { kind in
                sidebarRow(selection: .smartList(kind)) {
                    smartListRow(kind)
                }
            }
        } header: {
            Text("Smart Lists")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, DesignTokens.spacingSM)
        }

        if !model.usedPriorities.isEmpty {
            Section {
                ForEach(model.usedPriorities, id: \.self) { priority in
                    sidebarRow(selection: .priority(priority)) {
                        HStack(spacing: DesignTokens.spacingMD) {
                            sidebarIconBadge(
                                systemImage: "flag.fill",
                                color: DesignTokens.priorityColor(priority)
                            )
                            Text("Priority \(String(priority))")
                                .font(.body)
                        }
                    }
                }
            } header: {
                Text("Priorities")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, DesignTokens.spacingSM)
            }
        }

        if !model.allProjects.isEmpty {
            Section {
                ForEach(model.allProjects, id: \.self) { project in
                    sidebarRow(selection: .project(project)) {
                        HStack(spacing: DesignTokens.spacingMD) {
                            sidebarIconBadge(systemImage: "number", color: .blue)
                            Text(project)
                                .font(.body)
                            Spacer()
                            countBadge(model.taskCount(for: .project(project)))
                        }
                    }
                }
            } header: {
                Text("Projects")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, DesignTokens.spacingSM)
            }
        }

        if !model.allContexts.isEmpty {
            Section {
                ForEach(model.allContexts, id: \.self) { context in
                    sidebarRow(selection: .context(context)) {
                        HStack(spacing: DesignTokens.spacingMD) {
                            sidebarIconBadge(systemImage: "at", color: .purple)
                            Text(context)
                                .font(.body)
                            Spacer()
                            countBadge(model.taskCount(for: .context(context)))
                        }
                    }
                }
            } header: {
                Text("Contexts")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, DesignTokens.spacingSM)
            }
        }

        if model.activeTaskFiles.count > 1 {
            Section {
                ForEach(model.activeTaskFiles) { file in
                    sidebarRow(selection: .file(file.id)) {
                        HStack(spacing: DesignTokens.spacingMD) {
                            sidebarIconBadge(systemImage: "doc.text.fill", color: .gray)
                            Text(file.displayName)
                                .font(.body)
                            Spacer()
                            countBadge(model.taskCount(for: .file(file.id)))
                        }
                    }
                }
            } header: {
                Text("Files")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, DesignTokens.spacingSM)
            }
        }
    }

    // MARK: - Smart list row with tinted icon badge

    /// One sidebar row that adapts to push (NavigationStack) vs selection
    /// (NavigationSplitView) navigation modes.
    ///
    /// - **Push** mode (iPhone): wraps the label in a `NavigationLink(value:)`
    ///   so taps push onto the surrounding `NavigationStack`.
    /// - **Selection** mode (iPad / macOS): tags the label with the
    ///   `SidebarSelection` so the surrounding `List(selection:)` picks up taps
    ///   and updates the binding directly. Wrapping in `NavigationLink` here
    ///   would intercept the tap on iPad and prevent selection from updating
    ///   (the visible "Today only" bug pre-fix).
    @ViewBuilder
    private func sidebarRow<Content: View>(
        selection: SidebarSelection,
        @ViewBuilder label: () -> Content
    ) -> some View {
        if usesPushNavigation {
            NavigationLink(value: selection) {
                label()
            }
        } else {
            label()
                .tag(selection)
        }
    }

    private func smartListRow(_ kind: TaskQuery.SmartList) -> some View {
        let color = DesignTokens.smartListColor(for: kind)
        let count = model.taskCount(for: .smartList(kind))

        return HStack(spacing: DesignTokens.spacingMD) {
            sidebarIconBadge(
                systemImage: DesignTokens.smartListIcon(for: kind),
                color: color
            )

            Text(label(for: kind))
                .font(.body.weight(.medium))

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    // MARK: - Tinted icon badge (iOS Settings style)

    /// A small rounded square with a tinted fill and white icon inside,
    /// giving each sidebar item a distinct visual anchor.
    private func sidebarIconBadge(systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: DesignTokens.sidebarIconSize, height: DesignTokens.sidebarIconSize)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.gradient)
            )
    }

    /// Subtle inline count badge for non-smart-list items.
    @ViewBuilder
    private func countBadge(_ count: Int) -> some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    // MARK: - Labels

    private func label(for kind: TaskQuery.SmartList) -> String {
        switch kind {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .all: return "All"
        case .inbox: return "Inbox"
        case .completed: return "Completed"
        }
    }
}
