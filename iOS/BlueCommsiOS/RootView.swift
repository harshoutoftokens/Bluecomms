//
//  RootView.swift
//
//  Why this file exists:
//    Top-level navigation. NavigationSplitView collapses to a push stack on
//    iPhone (list → chat, like Messages) and shows two columns on iPad.
//    No networking here — views only read/write ChatStore.
//

import BlueCommsChat
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ChatStore

    var body: some View {
        NavigationSplitView {
            PeerListView()
        } detail: {
            if let peer = store.selectedPeer {
                ConversationView(peer: peer)
                    .id(peer.id)
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Pick someone nearby. BlueComms talks over the local radio only — no internet.")
                )
            }
        }
    }
}
