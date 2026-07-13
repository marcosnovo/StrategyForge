//
//  LoopNotifier.swift
//  StrategyForge
//
//  Local (system) notifications for loop runs — so a long / background loop tells
//  you when it's done even if Coral isn't the frontmost app. Non-sandboxed macOS
//  apps can post user notifications without a special entitlement. Authorization is
//  requested lazily on the first post; macOS suppresses the banner while the app is
//  frontmost (the in-app banner covers that case), so posting unconditionally is safe.
//

import Foundation
import UserNotifications

enum LoopNotifier {
    /// Post a local notification, requesting permission the first time if needed.
    static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let post = {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                                 content: content, trigger: nil))
            }
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                post()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { post() }
                }
            default:
                break   // denied — respect the user's choice, stay silent
            }
        }
    }
}
