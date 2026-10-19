//
//  SettingsView.swift
//
//  Why this file exists:
//    Your name (iOS will not tell apps the real device name), your key
//    fingerprint for verifying a friend in person, and where received files go.
//

import BlueCommsChat
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DeviceName.defaultsKey) private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(store.localName, text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text("Your Name")
                } footer: {
                    Text("Nearby Macs and iPhones see this name. Changes apply the next time you open BlueComms.")
                }

                Section {
                    LabeledContent("Fingerprint") {
                        Text(store.fingerprint)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Device ID") {
                        Text(store.shortID)
                            .font(.body.monospaced())
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("When you first connect, compare fingerprints with your friend in person. Messages are end-to-end encrypted.")
                }

                Section {
                    Label("Files → On My iPhone → BlueComms", systemImage: "folder")
                } header: {
                    Text("Received Files")
                }

                Section("Status") {
                    Text(friendlyStatus(store.statusLine))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
