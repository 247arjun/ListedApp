import SwiftUI
import ListedCore

/// Lightweight design tokens shared across the app.
///
/// Expanded with a full ambient color system, generous spacing grid,
/// and signature accent palette.
public enum DesignTokens {

    // MARK: - Spacing (8pt grid)

    public static let spacingXS: CGFloat = 4
    public static let spacingSM: CGFloat = 8
    public static let spacingMD: CGFloat = 12
    public static let spacingLG: CGFloat = 16
    public static let spacingXL: CGFloat = 20
    public static let spacingXXL: CGFloat = 24
    public static let spacingSection: CGFloat = 32

    // MARK: - Corners

    public static let cornerRadius: CGFloat = 14
    public static let cornerRadiusLG: CGFloat = 18
    public static let chipCornerRadius: CGFloat = 8
    public static let cardCornerRadius: CGFloat = 16

    // MARK: - Layout

    public static let rowSpacing: CGFloat = 12
    public static let groupHeaderInset: CGFloat = 8
    public static let cardRowGap: CGFloat = 6
    public static let sidebarIconSize: CGFloat = 28
    public static let priorityBarWidth: CGFloat = 3

    // MARK: - Signature accent color

    /// The app's brand accent — a warm teal that echoes through selected states,
    /// primary actions, and progress indicators.
    public static let accent = Color.teal

    // MARK: - Priority

    /// Priority letters offered in user-facing pickers, in canonical todo.txt
    /// order (A is highest). The `priorityColor(_:)` switch below covers each.
    public static let pickerPriorities: [Character] = ["A", "B", "C", "D", "E", "F", "G", "H"]

    public static func priorityColor(_ priority: Character) -> Color {
        switch priority {
        case "A": return .red
        case "B": return .orange
        case "C": return .yellow
        case "D": return .green
        case "E": return .teal
        case "F": return .blue
        case "G": return .indigo
        case "H": return .purple
        default: return .secondary
        }
    }

    // MARK: - Due date

    public static func dueColor(for date: LocalDate, today: LocalDate = LocalDate.today()) -> Color {
        if date < today { return .red }
        if date == today { return .orange }
        if date <= today.adding(days: 1) { return .yellow }
        return .blue
    }

    public static func dueLabel(for date: LocalDate, today: LocalDate = LocalDate.today()) -> String {
        if date == today { return "Today" }
        if date == today.adding(days: 1) { return "Tomorrow" }
        if date == today.adding(days: -1) { return "Yesterday" }
        let diff = today.daysBetween(date)
        if diff < 0 && diff >= -7 { return "\(-diff) days ago" }
        if diff > 0 && diff <= 7 { return "In \(diff) days" }
        return date.iso8601
    }

    // MARK: - Sidebar section tints

    /// Ambient tint colors for sidebar sections, used as subtle background washes
    /// and selection highlights to create visual regions.
    public static func sidebarTint(for selection: SidebarSelection) -> Color {
        switch selection {
        case .smartList(let kind):
            switch kind {
            case .today:     return .orange
            case .upcoming:  return .blue
            case .all:       return .teal
            case .inbox:     return .gray
            case .completed: return .green
            }
        case .file:          return .gray
        case .project:       return .blue
        case .context:       return .purple
        case .priority(let p): return priorityColor(p)
        }
    }

    /// Icon for each smart list type, used in sidebar icon badges.
    public static func smartListIcon(for kind: TaskQuery.SmartList) -> String {
        switch kind {
        case .today:     return "sun.max.fill"
        case .upcoming:  return "calendar"
        case .all:       return "tray.full.fill"
        case .inbox:     return "tray.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    /// Section tint for sidebar icon badges and background washes.
    public static func smartListColor(for kind: TaskQuery.SmartList) -> Color {
        switch kind {
        case .today:     return .orange
        case .upcoming:  return .blue
        case .all:       return .teal
        case .inbox:     return .gray
        case .completed: return .green
        }
    }

    // MARK: - Empty state messages

    public static func emptyIcon(for selection: SidebarSelection) -> String {
        switch selection {
        case .smartList(let kind):
            switch kind {
            case .today:     return "checkmark.seal.fill"
            case .upcoming:  return "calendar.badge.checkmark"
            case .all:       return "sparkles"
            case .inbox:     return "tray.fill"
            case .completed: return "star.fill"
            }
        default: return "magnifyingglass"
        }
    }

    public static func emptyTitle(for selection: SidebarSelection) -> String {
        switch selection {
        case .smartList(let kind):
            switch kind {
            case .today:     return "Clear schedule"
            case .upcoming:  return "Nothing on the horizon"
            case .all:       return "No tasks yet"
            case .inbox:     return "Inbox zero"
            case .completed: return "Nothing completed yet"
            }
        default: return "No tasks"
        }
    }

    public static func emptySubtitle(for selection: SidebarSelection) -> String {
        switch selection {
        case .smartList(let kind):
            switch kind {
            case .today:     return "Time to breathe — or add something new."
            case .upcoming:  return "No future due dates. Enjoy the calm."
            case .all:       return "Add a task to get started."
            case .inbox:     return "Nice. Every task has a home."
            case .completed: return "You've got this — start checking things off."
            }
        default: return "Add a task to get started."
        }
    }

    public static func emptyGradient(for selection: SidebarSelection) -> [Color] {
        let tint = sidebarTint(for: selection)
        return [tint.opacity(0.08), .clear]
    }

    // MARK: - Time-of-day greeting

    public static var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:      return "Good night"
        }
    }

    public static var timeOfDayIcon: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "sun.max.fill"
        case 12..<17: return "cup.and.saucer.fill"
        case 17..<21: return "sunset.fill"
        default:      return "moon.stars.fill"
        }
    }
}
