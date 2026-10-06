import Foundation
import Combine
import AppKit
import UserNotifications

/// Pomodoro session state, mirroring the original's Timing → Focus sessions.
enum PomodoroPhase: String {
    case idle
    case focus
    case pauseBreak
    case longBreak

    var isBreak: Bool { self == .pauseBreak || self == .longBreak }
}

/// Working-hours schedule + pomodoro sessions. Drives `isEnabled` and applies
/// the configured presets, like the original:
///
/// - Entering working hours turns the effect on (with the schedule preset
///   unless "Keep the current look"); leaving turns it off.
/// - Focus phases apply the focus preset; breaks switch the effect off so
///   stepping away actually looks like a break.
final class FocusScheduler: ObservableObject {
    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var phaseEndsAt: Date?
    @Published private(set) var completedRounds = 0
    @Published private(set) var scheduleActive = false
    /// Ticks every second while a session runs so countdown labels stay live.
    @Published private(set) var heartbeat = 0

    private let settings: FloBlurSettings
    private var timer: Timer?

    var timeRemaining: TimeInterval {
        guard let ends = phaseEndsAt else { return 0 }
        return max(0, ends.timeIntervalSinceNow)
    }

    var sessionLabel: String? {
        let remaining = Int(timeRemaining.rounded(.up))
        let clock = String(format: "%d:%02d", remaining / 60, remaining % 60)
        switch phase {
        case .idle: return nil
        case .focus: return "Focusing · \(clock) left"
        case .pauseBreak: return "On a break · \(clock) left"
        case .longBreak: return "Long break · \(clock) left"
        }
    }

    init(settings: FloBlurSettings) {
        self.settings = settings
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tickSchedule()
    }

    deinit {
        stop()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Pomodoro

    func startSession() {
        completedRounds = 0
        // One-time permission for phase-change notices; the system only
        // ever prompts once and stays silent if declined.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        beginFocus()
    }

    func stopSession() {
        phase = .idle
        phaseEndsAt = nil
        restoreScheduleState()
    }

    func skipPhase() {
        advance()
    }

    private func beginFocus() {
        phase = .focus
        phaseEndsAt = Date().addingTimeInterval(TimeInterval(settings.pomodoroFocusMinutes * 60))
        if let preset = settings.preset(id: settings.pomodoroPresetID) {
            settings.applyPreset(preset)
        }
        settings.isEnabled = true
        notify("Focus round started", "Stay sharp for \(settings.pomodoroFocusMinutes) minutes.")
    }

    private func beginBreak(long: Bool) {
        phase = long ? .longBreak : .pauseBreak
        let minutes = long ? settings.pomodoroLongBreakMinutes : settings.pomodoroBreakMinutes
        phaseEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        settings.isEnabled = false // breaks look like breaks
        notify(long ? "Long break" : "Break", "Step away for \(minutes) minutes.")
    }

    private func advance() {
        switch phase {
        case .idle:
            break
        case .focus:
            completedRounds += 1
            let long = completedRounds % max(1, settings.pomodoroRounds) == 0
            if settings.pomodoroContinuesAutomatically {
                beginBreak(long: long)
            } else {
                stopSession()
            }
        case .pauseBreak, .longBreak:
            if settings.pomodoroContinuesAutomatically {
                beginFocus()
            } else {
                stopSession()
            }
        }
    }

    // MARK: - Schedule

    /// Re-applies working-hours state after a session ends (the session
    /// owned the switch while running — see tickSchedule guard).
    private func restoreScheduleState() {
        guard settings.scheduleEnabled else { return }
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let inHours: Bool
        if settings.scheduleEndMinutes <= settings.scheduleStartMinutes {
            inHours = settings.scheduleWeekdays.contains(weekday)
                && (minutes >= settings.scheduleStartMinutes || minutes < settings.scheduleEndMinutes)
        } else {
            inHours = settings.scheduleWeekdays.contains(weekday)
                && minutes >= settings.scheduleStartMinutes
                && minutes < settings.scheduleEndMinutes
        }
        scheduleActive = inHours
        // Keep the session's look — only the switch follows the schedule.
        settings.isEnabled = inHours
    }

    private func tick() {
        if phase != .idle {
            heartbeat += 1
            if let ends = phaseEndsAt, Date() >= ends {
                advance()
            }
        }
        tickSchedule()
    }

    private func tickSchedule() {
        guard settings.scheduleEnabled else {
            if scheduleActive {
                scheduleActive = false
            }
            return
        }
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now) // 1 = Sunday
        let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let inHours: Bool
        if settings.scheduleEndMinutes <= settings.scheduleStartMinutes {
            // Overnight window (e.g. 22:00 → 06:00).
            inHours = settings.scheduleWeekdays.contains(weekday)
                && (minutes >= settings.scheduleStartMinutes || minutes < settings.scheduleEndMinutes)
        } else {
            inHours = settings.scheduleWeekdays.contains(weekday)
                && minutes >= settings.scheduleStartMinutes
                && minutes < settings.scheduleEndMinutes
        }
        guard inHours != scheduleActive else { return }
        scheduleActive = inHours
        // An active pomodoro session owns the switch: schedule state still
        // tracks for display, but must not stomp focus/break. The next tick
        // after the session stops (phase == .idle) restores schedule state.
        guard phase == .idle else { return }
        if inHours {
            if let id = settings.schedulePresetID, let preset = settings.preset(id: id) {
                settings.applyPreset(preset)
            }
            settings.isEnabled = true
        } else {
            settings.isEnabled = false
        }
    }

    private func notify(_ title: String, _ body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
