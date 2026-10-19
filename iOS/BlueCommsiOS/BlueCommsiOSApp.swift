//
//  BlueCommsiOSApp.swift
//
//  Why this file exists:
//    @main for the iPhone / iPad app. Same idea as the Mac's BlueCommsApp.swift:
//    build ChatStore before the first frame, start the radio once the UI is up.
//
//  What is different on iOS:
//    • The name peers see comes from Settings (DeviceName). iOS only gives
//      apps "iPhone" / "iPad", which is useless when two iPhones are nearby.
//    • iOS suspends the app in the background and Bonjour goes with it.
//      When we come back to the foreground we rebuild the listener + browser.
//

import BlueCommsChat
import SwiftUI
import UIKit

@main
struct BlueCommsiOSApp: App {
    /// Shared by every view via .environmentObject.
    @StateObject private var store: ChatStore
    /// Non-nil means we could not load identity/history. Window shows this text.
    private let launchError: String?

    @Environment(\.scenePhase) private var scenePhase
    /// Set when we go to the background so the next .active rebuilds Bonjour.
    @State private var wasBackgrounded = false

    init() {
        do {
            let created = try ChatStore(displayName: DeviceName.current)
            _store = StateObject(wrappedValue: created)
            launchError = nil
        } catch {
            _store = StateObject(wrappedValue: ChatStore.failed(error))
            launchError = String(describing: error)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let launchError {
                ContentUnavailableView(
                    "BlueComms Could Not Start",
                    systemImage: "exclamationmark.triangle",
                    description: Text(launchError)
                )
            } else {
                RootView()
                    .environmentObject(store)
                    // After the first frame so launch stays fast. start() is once-only.
                    .task { store.start() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                wasBackgrounded = true
            case .active where wasBackgrounded:
                wasBackgrounded = false
                store.resume()
            default:
                break
            }
        }
    }
}

/// The name nearby devices see. Stored in UserDefaults, edited in SettingsView.
enum DeviceName {
    static let defaultsKey = "displayName"

    @MainActor static var current: String {
        let saved = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? UIDevice.current.name : saved
    }
}
