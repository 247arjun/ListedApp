import Foundation
import UserNotifications

/// Schedules and manages local notifications for tasks with due dates.
///
/// Stateless from a persistence perspective — every call to `syncNotifications`
/// computes the desired set of notifications from the current tasks + settings,
/// diffs against what `UNUserNotificationCenter` reports as pending, and reconciles.
/// This means external edits, iCloud sync, completing tasks, and changing the
/// reminder time all "just work" without special-case logic.
public final class ReminderScheduler: @unchecked Sendable {

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: - Permission

    /// Request notification authorization. Returns `true` if granted.
    public func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// Whether the user has granted notification permission.
    public func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - Sync

    /// Reconcile pending notifications with the current state of tasks and settings.
    ///
    /// - Cancels notifications for completed/deleted tasks or changed due dates
    /// - Schedules new notifications for upcoming tasks
    /// - Respects the iOS 64-notification cap by prioritizing nearest due dates
    public func syncNotifications(
        tasks: [TodoTask],
        settings: AppSettings
    ) async {
        guard settings.remindersEnabled else {
            await cancelAll()
            return
        }

        // Build the desired set
        let desired = buildDesired(from: tasks, settings: settings)

        // Fetch what's currently scheduled
        let pending = await center.pendingNotificationRequests()
        let existingIDs = Set(pending.map(\.identifier).filter { $0.hasPrefix("listed-reminder-") })

        // Cancel stale (no longer desired)
        let desiredIDs = Set(desired.map(\.identifier))
        let toCancel = existingIDs.subtracting(desiredIDs)
        if !toCancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toCancel))
        }

        // Schedule new (not already pending). Skip already-scheduled to avoid
        // unnecessary churn.
        let toSchedule = desired.filter { !existingIDs.contains($0.identifier) }
        for request in toSchedule {
            try? await center.add(request)
        }
    }

    /// Remove all Listed-managed notifications.
    public func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let listedIDs = pending.map(\.identifier).filter { $0.hasPrefix("listed-reminder-") }
        if !listedIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: listedIDs)
        }
    }

    // MARK: - Build desired notifications

    private func buildDesired(
        from tasks: [TodoTask],
        settings: AppSettings
    ) -> [UNNotificationRequest] {
        let today = LocalDate.today()
        var candidates: [(LocalDate, UNNotificationRequest)] = []

        for task in tasks {
            guard !task.isCompleted, let due = task.dueDate else { continue }

            let fireDate = due.adding(days: -settings.reminderDaysBefore)

            // Skip if fire date is in the past
            guard fireDate >= today else { continue }

            let id = notificationID(for: task)

            var components = DateComponents()
            let calendarDate = fireDate.date(in: .current)
            let calendar = Calendar.current
            components.year = calendar.component(.year, from: calendarDate)
            components.month = calendar.component(.month, from: calendarDate)
            components.day = calendar.component(.day, from: calendarDate)
            components.hour = settings.reminderHour
            components.minute = settings.reminderMinute

            // If firing today but the time has already passed, skip
            if fireDate == today {
                let now = Date()
                if let triggerDate = calendar.date(from: components), triggerDate <= now {
                    continue
                }
            }

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )

            let content = UNMutableNotificationContent()
            content.title = task.cleanTitle.isEmpty ? "Task due" : task.cleanTitle
            if settings.reminderDaysBefore == 0 {
                content.body = "Due today"
            } else if settings.reminderDaysBefore == 1 {
                content.body = "Due tomorrow"
            } else {
                content.body = "Due in \(settings.reminderDaysBefore) days"
            }
            content.sound = .default
            // Deep-link payload for navigating to the task on tap
            content.userInfo = ["taskRawLine": task.rawLine, "sourceFileID": task.sourceFileID.uuidString]

            let request = UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: trigger
            )
            candidates.append((fireDate, request))
        }

        // iOS caps pending notifications at 64. Prioritize nearest due dates.
        let sorted = candidates.sorted { $0.0 < $1.0 }
        let maxNotifications = 60 // Leave headroom for other notification types
        return Array(sorted.prefix(maxNotifications).map(\.1))
    }

    // MARK: - Helpers

    /// Stable notification ID per task. Uses UID if available, falls back to
    /// a hash of the raw line + source file so it's deterministic across
    /// app launches without requiring persistent task IDs.
    private func notificationID(for task: TodoTask) -> String {
        if let uid = task.uid, !uid.isEmpty {
            return "listed-reminder-\(uid)"
        }
        // Fallback: hash the raw line + source for a stable-ish ID
        let combined = "\(task.sourceFileID.uuidString)-\(task.rawLine)"
        let hash = combined.hash
        return "listed-reminder-\(abs(hash))"
    }
}
