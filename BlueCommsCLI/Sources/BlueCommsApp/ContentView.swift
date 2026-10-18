//
//  ContentView.swift
//
//  Why this file exists:
//    Draws the Mac window. No networking here — it only reads/writes ChatStore.
//
//  What it does:
//    Sidebar = nearby Macs + you. Detail = thread + composer, with
//    Connect/Disconnect in the window toolbar (Messages-style).
//    Attach / Screenshot / drag-and-drop all call ChatStore.sendFile.
//
//  Uses system colors, materials and SF Symbols so it follows Light/Dark mode
//  and the user's accent color. NavigationSplitView is safe again because
//  ChatStore.start() is once-only (PR #6 froze when the column toggle
//  re-started the radio).
//

import AppKit
import BlueCommsCore
import SwiftUI
import UniformTypeIdentifiers

/// Root of the window: sidebar | chat. Lives inside BlueCommsMacApp.
struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            ChatView()
        }
    }
}

// MARK: - Sidebar

/// Nearby list on top, you + status pinned to the bottom.
private struct SidebarView: View {
    @EnvironmentObject private var store: ChatStore

    private var selection: Binding<String?> {
        Binding(
            get: { store.selectedPeerID },
            set: { if let id = $0 { store.select(peerID: id) } }
        )
    }

    private var nearby: [NearbyPeer] { store.peers.filter(\.isOnline) }
    private var earlier: [NearbyPeer] { store.peers.filter { !$0.isOnline } }

    var body: some View {
        List(selection: selection) {
            if !nearby.isEmpty {
                Section("Nearby") {
                    ForEach(nearby) { PeerRow(peer: $0).tag($0.id) }
                }
            }
            if !earlier.isEmpty {
                Section("Earlier") {
                    ForEach(earlier) { PeerRow(peer: $0).tag($0.id) }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.peers.isEmpty {
                ContentUnavailableView {
                    Label("Looking for Macs", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Keep Wi-Fi on and allow Local Network in System Settings → Privacy & Security.")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IdentityFooter()
        }
    }
}

/// One Mac in the sidebar. Green dot = Bonjour still sees them. Lock = handshake is up.
private struct PeerRow: View {
    let peer: NearbyPeer

    var body: some View {
        HStack(spacing: 10) {
            Avatar(name: peer.displayName, size: 28)
                .overlay(alignment: .bottomTrailing) {
                    if peer.isOnline {
                        Circle()
                            .fill(.green)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.background, lineWidth: 1.5))
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(peer.displayName)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if peer.isSessionOpen {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .help("Secure session open")
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if peer.isSessionOpen { return "Connected" }
        if peer.isOnline { return "Nearby" }
        return "Seen \(peer.lastSeen.formatted(.relative(presentation: .named)))"
    }
}

/// "This Mac" card at the bottom of the sidebar, with the latest status line.
private struct IdentityFooter: View {
    @EnvironmentObject private var store: ChatStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 10) {
                Avatar(name: store.localName, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.localName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(store.fingerprint)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .help("Your key fingerprint. Compare it with your friend's screen to verify.")
                }
            }
            .padding(.horizontal, 12)
            Text(friendlyStatus)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .help(store.statusLine)
                .padding(.horizontal, 12)
        }
        .padding(.bottom, 10)
        .background(.bar)
    }

    /// Radio logs arrive as "[BROWSER] …". Drop the tag; the full line is in the tooltip.
    private var friendlyStatus: String {
        let line = store.statusLine
        guard line.hasPrefix("["), let end = line.firstIndex(of: "]") else { return line }
        return line[line.index(after: end)...].trimmingCharacters(in: .whitespaces)
    }
}

/// Initials in a gray circle, like Contacts / Messages.
private struct Avatar: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.48)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }

    private var initials: String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

// MARK: - Chat

/// Thread + composer. Files can be dropped onto this whole pane.
private struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var pickingFile = false
    @State private var dropTargeted = false

    var body: some View {
        Group {
            if let peer = store.selectedPeer {
                thread(for: peer)
            } else {
                ContentUnavailableView {
                    Label("No Conversation Selected", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Pick a Mac in the sidebar. BlueComms talks over the local radio only — no internet.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func thread(for peer: NearbyPeer) -> some View {
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .background(Color.accentColor.opacity(0.06))
                        .overlay(Label("Drop to Send", systemImage: "arrow.down.doc").font(.title3))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
            .navigationTitle(peer.displayName)
            .navigationSubtitle(headerStatus(for: peer))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if store.isConnectedToSelection {
                        Button { store.disconnect() } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                        .help("Close the secure session")
                    } else {
                        Button { store.connectToSelection() } label: {
                            Label("Connect", systemImage: "link")
                        }
                        .help(peer.isOnline ? "Open a secure session" : "This Mac is not nearby right now")
                        .disabled(store.phase == .connecting || !peer.isOnline)
                    }
                }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    urls.forEach { store.sendFile(url: $0) }
                }
            }
    }

    private func headerStatus(for peer: NearbyPeer) -> String {
        if store.isConnectedToSelection {
            return peer.isOnline ? "Secure session" : "Secure session · signal lost"
        }
        if store.phase == .connecting { return "Connecting…" }
        if peer.isOnline { return "Nearby · not connected" }
        return "Last seen \(peer.lastSeen.formatted(.relative(presentation: .named)))"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.selectedMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .overlay {
                if store.selectedMessages.isEmpty {
                    ContentUnavailableView {
                        Label("No Messages", systemImage: "message")
                    } description: {
                        Text(store.isConnectedToSelection
                             ? "Say hi, or drop a photo or file here."
                             : "Messages you type now are queued and sent when you connect.")
                    }
                }
            }
            .onChange(of: store.selectedMessages.count) {
                if let last = store.selectedMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var canSend: Bool {
        !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button { pickingFile = true } label: {
                Image(systemName: "paperclip")
            }
            .help("Attach a file")
            Button { store.sendScreenshot() } label: {
                Image(systemName: "camera.viewfinder")
            }
            .help("Send a screenshot of your screen")

            TextField(store.isConnectedToSelection ? "Message" : "Message (queued until connected)",
                      text: $store.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor))
                )
                .onSubmit(store.sendDraft)

            Button(action: store.sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)
            .help("Send (⌘↩)")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// Finder / Photos drop. Must hop to main because loadObject is off-thread.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { store.sendFile(url: url) }
            }
        }
        return accepted
    }
}

// MARK: - Bubbles

/// One chat row: a text bubble or a file card with a progress bar.
private struct MessageBubble: View {
    let message: ChatMessage

    private var bubbleFill: Color {
        message.isLocal ? .accentColor : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    var body: some View {
        HStack {
            if message.isLocal { Spacer(minLength: 80) }
            VStack(alignment: message.isLocal ? .trailing : .leading, spacing: 3) {
                if message.kind == .file {
                    fileCard
                } else {
                    Text(message.text)
                        .textSelection(.enabled)
                        .foregroundStyle(message.isLocal ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(bubbleFill, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                caption
            }
            if !message.isLocal { Spacer(minLength: 80) }
        }
    }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: fileIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.fileName ?? message.text)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(byteCount)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if message.fileState == .complete, message.filePath != nil {
                    Button("Open", action: openFile)
                        .controlSize(.small)
                }
            }
            if message.fileState == .transferring || (message.fileState == .queued && message.progress > 0 && message.progress < 1) {
                ProgressView(value: message.progress)
                    .controlSize(.small)
                Text("\(byteCount(of: UInt64(Double(message.fileSize ?? 0) * message.progress))) of \(byteCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 240, maxWidth: 320, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }

    private var fileIcon: String {
        let ext = (message.fileName as NSString?)?.pathExtension.lowercased() ?? ""
        if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff"].contains(ext) { return "photo" }
        if ["mov", "mp4", "m4v", "avi", "mkv"].contains(ext) { return "film" }
        return "doc.fill"
    }

    private var byteCount: String {
        byteCount(of: message.fileSize ?? 0)
    }

    private func byteCount(of value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    @ViewBuilder
    private var caption: some View {
        let time = message.sentAt.formatted(date: .omitted, time: .shortened)
        Group {
            switch (message.kind == .file ? message.fileState : nil, message.delivery) {
            case (.failed?, _):
                Label("\(time) · Not delivered", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            case (.cancelled?, _):
                Text("\(time) · Cancelled")
            case (.queued?, _), (nil, .queued):
                Label("\(time) · Waiting to send", systemImage: "clock")
            case (.transferring?, _):
                Text("\(time) · Sending…")
            case (.complete?, _):
                Text(message.isLocal ? "\(time) · Delivered" : "\(time) · Saved to Downloads")
            default:
                Text(time)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func openFile() {
        guard let path = message.filePath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
