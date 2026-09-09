// NotificationManager.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import Foundation
import UserNotifications
import os

/// Manages scheduling and cancellation of task reminder notifications.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.bingowu.polaris", category: "notifications")

    override init() {
        super.init()
        center.delegate = self
    }

    /// Request notification permission and, once the user answers, reconcile
    /// scheduled reminders against the current Store. Any arbitrary launch
    /// delay is removed — the system already presents the permission prompt
    /// out-of-line, so gating it behind a timer only invited authorization
    /// races where a task added on launch would be added *before* we asked
    /// and therefore never scheduled.
    func requestPermission() {
        guard !DocketRuntime.isPreview else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            guard let self else { return }
            if let error { self.logger.error("Auth error: \(error.localizedDescription)") }
            if !granted {
                self.logger.warning("Permission denied")
                return
            }
            // Reconcile: without this, tasks created before the user granted
            // permission would have silently failed to schedule.
            DispatchQueue.main.async { self.reconcileFromStore() }
        }
    }

    /// (Re-)schedule notifications for every uncompleted task in the Store.
    /// Safe to call repeatedly — `scheduleReminder(for:)` cancels any prior
    /// pending request for the same task id before adding a new one.
    func reconcileFromStore() {
        for item in Store.shared.items where !item.isCompleted {
            scheduleReminder(for: item)
        }
    }

    func scheduleReminder(for item: TodoItem) {
        guard !DocketRuntime.isPreview else { return }
        cancelReminder(for: item)

        guard let dueDate = item.dueDate,
              item.reminderOffset != .none,
              item.completedAt == nil else { return }

        let anchor = item.hasDueTime ? dueDate : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate)!
        let fireDate = anchor.addingTimeInterval(-item.reminderOffset.timeInterval)
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.appName
        content.body = item.reminderOffset == .atTime
            ? L10n.notifDueNow(item.title)
            : L10n.notifReminder(item.title, item.reminderOffset.displayName)

        let soundPref = UserDefaults.standard.string(forKey: "notifSound") ?? "default"
        switch soundPref {
        case "none": content.sound = nil
        case "default": content.sound = .default
        default: content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(soundPref).aiff"))
        }

        // Absolute-duration trigger — resilient to timezone shifts, DST
        // transitions, and system-clock adjustments. A calendar trigger with
        // fixed components would re-fire (or move) if the system entered a
        // different zone/offset between scheduling and firing time.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { self.logger.error("Schedule failed: \(error.localizedDescription)") }
        }
    }

    func cancelReminder(for item: TodoItem) {
        center.removePendingNotificationRequests(withIdentifiers: [item.id.uuidString])
    }

    // MARK: - Delegate — show notifications even when app is in foreground

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
