import Foundation

/// When to ask, gently, whether the master password is still remembered (DESIGN.md §5). With
/// Face ID or Touch ID on, the password may go unused for months, yet it's the only way into the
/// vault on a new device and can't be recovered. The reminder can always be skipped.
public enum PasswordReminder {
    /// How long after the password was last typed the reminder comes.
    public static let interval: TimeInterval = 30 * 24 * 60 * 60
    /// How long "Not Now" puts it off.
    public static let snooze: TimeInterval = 7 * 24 * 60 * 60

    public static func next(afterConfirmingAt date: Date) -> Date {
        date.addingTimeInterval(interval)
    }

    public static func next(afterSnoozingAt date: Date) -> Date {
        date.addingTimeInterval(snooze)
    }

    /// Whether the reminder should show now. Without a date it isn't due; the caller sets one.
    public static func isDue(next: Date?, now: Date) -> Bool {
        guard let next else { return false }
        return now >= next
    }
}
