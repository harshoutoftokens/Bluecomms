//
//  ConversationView.swift
//
//  Why this file exists:
//    One thread: bubbles, the composer, and Connect / Disconnect in the
//    navigation bar. Photos and Files go through Outbox first (see Outbox.swift)
//    because iOS revokes access to picked files once the picker returns.
//

import BlueCommsChat
import BlueCommsCore
import PhotosUI
import QuickLook
import SwiftUI
import UIKit

struct ConversationView: View {
    @EnvironmentObject private var store: ChatStore
    let peer: NearbyPeer

    @State private var pickingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pickingFiles = false
    /// Non-nil shows Quick Look for a received or sent file.
    @State private var previewURL: URL?
    @FocusState private var composerFocused: Bool

    var body: some View {
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { titleView }
                ToolbarItem(placement: .topBarTrailing) { connectButton }
            }
            .photosPicker(isPresented: $pickingPhotos, selection: $photoItems, matching: .any(of: [.images, .videos]))
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await sendPhotos(items) }
            }
            .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls { send(copyOf: url) }
            }
            .quickLookPreview($previewURL)
    }

    // MARK: Navigation bar

    private var titleView: some View {
        VStack(spacing: 0) {
            Text(peer.displayName)
                .font(.headline)
                .lineLimit(1)
            Text(status)
                .font(.caption)
                .foregroundStyle(store.isConnectedToSelection ? .green : .secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        if store.isConnectedToSelection {
            return peer.isOnline ? "Secure session" : "Secure session · signal lost"
        }
        if store.phase == .connecting { return "Connecting…" }
        if peer.isOnline { return "Nearby" }
        return "Last seen \(peer.lastSeen.formatted(.relative(presentation: .named)))"
    }

    @ViewBuilder
    private var connectButton: some View {
        if store.isConnectedToSelection {
            Button("Disconnect", role: .destructive) { store.disconnect() }
        } else if store.phase == .connecting {
            ProgressView()
        } else {
            Button("Connect") { store.connectToSelection() }
                .fontWeight(.semibold)
                .disabled(!peer.isOnline)
        }
    }

    // MARK: Thread

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.selectedMessages) { message in
                        MessageBubble(message: message) { previewURL = $0 }
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if store.selectedMessages.isEmpty {
                    ContentUnavailableView {
                        Label("No Messages", systemImage: "message")
                    } description: {
                        Text(store.isConnectedToSelection
                             ? "Say hi, or send a photo."
                             : "Messages you write now are queued and sent when you connect.")
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

    // MARK: Composer

    private var canSend: Bool {
        !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button { pickingPhotos = true } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                Button { pickingFiles = true } label: {
                    Label("Files", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(.secondarySystemFill), in: Circle())
            }
            .accessibilityLabel("Attach")

            HStack(alignment: .bottom, spacing: 4) {
                TextField(store.isConnectedToSelection ? "Message" : "Message (queued)",
                          text: $store.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .padding(.vertical, 7)
                    .padding(.leading, 12)
                if canSend {
                    Button(action: store.sendDraft) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                    }
                    .padding(3)
                    .accessibilityLabel("Send")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(minHeight: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(.separator))
            )
            .animation(.snappy(duration: 0.15), value: canSend)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Sending files

    private func sendPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                if let picked = try await item.loadTransferable(type: PickedMedia.self) {
                    store.sendFile(url: picked.url)
                }
            } catch {
                store.statusLine = "Could not load that photo: \(error.localizedDescription)"
            }
        }
    }

    private func send(copyOf url: URL) {
        do {
            store.sendFile(url: try Outbox.copy(url))
        } catch {
            store.statusLine = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
