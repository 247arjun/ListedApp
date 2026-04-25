import Foundation
import ListedCore

/// Minimal natural-language helpers used by the inline composer.
///
/// V1 is intentionally tiny: we recognise `due:today`, `due:tomorrow`, `due:next week`
/// and `due:YYYY-MM-DD`. Anything else is left in the description verbatim.
public enum SmartInputParser {

    public static func extractDueDate(from text: String, today: LocalDate = LocalDate.today()) -> LocalDate? {
        let lowered = text.lowercased()
        if let range = lowered.range(of: #"due:\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            let token = String(lowered[range])
            return LocalDate.parse(String(token.dropFirst("due:".count)))
        }
        if lowered.contains("due:today") { return today }
        if lowered.contains("due:tomorrow") { return today.adding(days: 1) }
        if lowered.contains("due:next-week") || lowered.contains("due:nextweek") { return today.adding(days: 7) }
        return nil
    }
}
