import SwiftUI
import ListedCore

/// Lightweight design tokens shared across the app.
public enum DesignTokens {
    public static let cornerRadius: CGFloat = 14
    public static let chipCornerRadius: CGFloat = 8
    public static let rowSpacing: CGFloat = 12
    public static let groupHeaderInset: CGFloat = 8

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
}
