//
//  PeerListView.swift
//
//  Why this file exists:
//    The first screen: everyone nearby, Messages-style rows with the last
//    message as a preview. Settings (your name, fingerprint) is the gear.
//

import BlueCommsChat
import BlueCommsCore
import SwiftUI
import UIKit

struct PeerListView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var showingSettings = false

    private var nearby: [NearbyPeer] { store.peers.filter(\.isOnline) }
    private var earlier: [NearbyPeer] { store.peers.filter { !$0.isOnline } }

    var body: some View {
        List(selection: $store.selectedPeerID) {
            if !nearby.isEmpty {
                Section("Nearby") {
                    ForEach(nearby) { row(for: $0) }
                }
            }
            if !earlier.isEmpty {
                Section("Earlier") {
                    ForEach(earlier) { row(for: $0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("BlueComms")
        .overlay {
            if store.peers.isEmpty {
                ContentUnavailableView {
                    Label("Looking for Devices", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Keep Wi-Fi on (no network needed) and allow Local Network for BlueComms in Settings → Privacy & Security.")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text(friendlyStatus(store.statusLine))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal)
                .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private func row(for peer: NearbyPeer) -> some View {
        PeerRow(peer: peer, lastMessage: store.conversations[peer.id]?.last)
            .tag(peer.id as String?)
    }
}

/// Avatar, name, last message, time. Lock = secure session open.
private struct PeerRow: View {
    let peer: NearbyPeer
    let lastMessage: ChatMessage?

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: peer.displayName, size: 44)
                .overlay(alignment: .bottomTrailing) {
                    if peer.isOnline {
                        Circle()
                            .fill(.green)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(peer.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if peer.isSessionOpen {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .accessibilityLabel("Secure session open")
                    }
                    Spacer(minLength: 4)
                    if let lastMessage {
                        Text(lastMessage.sentAt, format: .relative(presentation: .named))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var preview: String {
        guard let lastMessage else {
            if peer.isSessionOpen { return "Connected" }
            if peer.isOnline { return "Nearby" }
            return "Seen \(peer.lastSeen.formatted(.relative(presentation: .named)))"
        }
        if lastMessage.kind == .file {
            return "Attachment: \(lastMessage.fileName ?? lastMessage.text)"
        }
        return lastMessage.isLocal ? "You: \(lastMessage.text)" : lastMessage.text
    }
}

/// Initials in a gray circle, like Contacts / Messages.
struct Avatar: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.66), Color(white: 0.52)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

/// Radio logs arrive as "[BROWSER] …". Drop the tag for display.
func friendlyStatus(_ line: String) -> String {
    guard line.hasPrefix("["), let end = line.firstIndex(of: "]") else { return line }
    return line[line.index(after: end)...].trimmingCharacters(in: .whitespaces)
}
