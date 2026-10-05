import Foundation
import Combine
import AppKit

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

    private let settings: FloBlurSettings
    private var timer: Timer?

    var timeRemaining: TimeInterval {
        guard let ends = phaseEndsAt else { return 0 }
        return max(0, ends.timeIntervalSinceNow)
    }

    var sessionLabel: String? {
        switch phase {
        case .idle: return nil
        case .focus: return "Focusing · \(Int(timeRemaining / 60)) min left"
        case .pauseBreak: return "On a break · \(Int(timeRemaining / 60)) min left"
        case .longBreak: return "Long break · \(Int(timeRemaining / 60)) min left"
        }
    }

    init(settings: FloBlurSettings) {
        self.settings = settings
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tickSchedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Pomodoro

    func startSession() {
        completedRounds = 0
        beginFocus()
    }

    func stopSession() {
        phase = .idle
        phaseEndsAt = nil
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

    private func tick() {
        if phase != .idle, let ends = phaseEndsAt, Date() >= ends {
            advance()
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
        let inHours = settings.scheduleWeekdays.contains(weekday)
            && minutes >= settings.scheduleStartMinutes
            && minutes < settings.scheduleEndMinutes
        guard inHours != scheduleActive else { return }
        scheduleActive = inHours
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
        let note = NSUserNotification()
        note.title = title
        note.informativeText = body
        NSUserNotificationCenter.default.deliver(note)
    }
}
