# Runtime Flow & State Transitions

> **Document Type:** Execution Flow Diagrams & Sequence Specifications  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

---

## 1. Flow A: Application Startup

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as BlueCommsMacApp
    participant Store as ChatStore (@MainActor)
    participant Archive as MessageArchive
    participant StoreDisk as IdentityStore (~/.bluecomms)
    participant Net as NetworkManager (Queue)
    participant Bonjour as Apple mDNSResponder / AWDL

    User->>App: Launch App
    App->>Store: init()
    Store->>StoreDisk: loadOrCreate()
    StoreDisk-->>Store: Return DeviceIdentity (UUID, Keys, Name)
    Store->>Archive: load()
    Archive-->>Store: Return ConversationSnapshot
    App->>Store: ContentView.onAppear -> store.start()
    Store->>Net: start()
    Net->>Net: startListener()
    Net->>Bonjour: NWListener.start(service: "_bluecomms._tcp")
    Net->>Net: startBrowser()
    Net->>Bonjour: NWBrowser.start(for: .bonjourWithTXTRecord)
```

- **Initiating Component:** `BlueCommsMacApp.init()` and `ContentView.onAppear`.
- **Function Calls:** `IdentityStore.loadOrCreate()`, `MessageArchive.load()`, `NetworkManager.start()`, `startListener()`, `startBrowser()`.
- **State Transition:** `didStart` becomes `true`; `statusLine` changes to `"Starting local radio..."`.
- **UI Update:** SwiftUI window renders with sidebar displaying local device name, short ID, and key fingerprint.

---

## 2. Flow B: Device Discovery

```mermaid
sequenceDiagram
    autonumber
    participant PeerRadio as Remote Mac Radio
    participant Bonjour as mDNSResponder / AWDL
    participant Browser as NWBrowser
    participant Net as NetworkManager (Queue)
    participant Store as ChatStore (@MainActor)
    participant UI as SidebarView (SwiftUI)

    PeerRadio->>Bonjour: Broadcasts _bluecomms._tcp + TXT (id, name, proto)
    Bonjour->>Browser: browseResultsChangedHandler(results)
    Browser->>Net: applyBrowseResults(results)
    Net->>Net: Filter out self UUID, parse DiscoveredPeer
    Net->>Store: onPeersUpdated([DiscoveredPeer]) -> MainActor
    Store->>Store: mergePresence(discovered)
    Store->>UI: Update @Published peers
    UI-->>UI: Renders PeerRow with green dot (isOnline = true)
```

- **Initiating Component:** Remote peer's `NWListener` beacon over AWDL/Wi-Fi.
- **Function Calls:** `NWBrowser.browseResultsChangedHandler`, `NetworkManager.applyBrowseResults()`, `ChatStore.mergePresence()`.
- **State Transition:** Peer added to `ChatStore.peers` with `isOnline: true`.
- **UI Update:** Peer appears in sidebar with green online dot.

---

## 3. Flow C: Device Connection & Cryptographic Handshake

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant UI as ChatView (SwiftUI)
    participant Store as ChatStore (@MainActor)
    participant Net as NetworkManager (Queue)
    participant PeerConn as PeerConnection
    participant Crypto as CryptoSession
    participant Remote as Remote Mac

    User->>UI: Clicks "Connect"
    UI->>Store: connectToSelection()
    Store->>Net: connectToPeer(id: peer.id)
    Net->>PeerConn: init(connection, identity)
    Net->>PeerConn: start()
    PeerConn->>Remote: TCP SYN -> SYN/ACK (AWDL link established)
    Remote-->>PeerConn: NWConnection.State = .ready
    PeerConn->>Remote: Send Handshake Frame (0x01 + proto + UUID + Public Key)
    Remote->>PeerConn: Send Handshake Frame (0x01 + proto + Remote UUID + Remote Key)
    PeerConn->>Crypto: establish(peerPublicKey)
    Crypto-->>PeerConn: Derive sendKey & receiveKey (HKDF)
    PeerConn->>Net: onReadyForChat(peerUUID)
    Net->>Store: onSecureSession(peerUUID) -> MainActor
    Store->>Store: markSession(open: true), phase = .ready
    Store->>Store: flushOutbound(peerID) (send queued messages)
    Store->>UI: Update statusLine = "Secure session with [Name]"
```

- **Initiating Component:** User clicking "Connect" in `ChatView`.
- **Function Calls:** `ChatStore.connectToSelection()`, `NetworkManager.connect(to:)`, `PeerConnection.sendHandshake()`, `CryptoSession.establish()`, `ChatStore.flushOutbound()`.
- **State Transition:** `ChatStore.phase` $\rightarrow$ `.connecting` $\rightarrow$ `.ready`; `isSessionOpen` $\rightarrow$ `true`.
- **UI Update:** "Connect" button changes to "Disconnect", sidebar displays blue **LIVE** badge.

---

## 4. Flow D: Sending a Message (Text & Queued)

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant UI as Composer (SwiftUI)
    participant Store as ChatStore (@MainActor)
    participant Archive as MessageArchive
    participant Net as NetworkManager (Queue)
    participant PeerConn as PeerConnection
    participant Crypto as CryptoSession
    participant Remote as Remote Mac

    User->>UI: Types "hello", presses Send
    UI->>Store: sendDraft()
    Store->>Store: append(ChatMessage(delivery: isLive ? .sent : .queued))
    Store->>Archive: save(ConversationSnapshot)
    alt Session is LIVE (.ready)
        Store->>Net: send(message: "hello", to: peerID)
        Net->>PeerConn: send(message: "hello")
        PeerConn->>Crypto: seal(UTF-8 bytes)
        Crypto-->>PeerConn: Sealed Blob (Nonce + Ciphertext + Tag)
        PeerConn->>Remote: NWConnection.send(Framed Ciphertext Frame 0x02, isComplete: false)
    else Session is OFFLINE / DISCONNECTED
        Store->>Store: Message stays in conversations with delivery = .queued
        Store->>UI: statusLine = "Queued. It will send when this peer is back."
    end
```

---

## 5. Flow E: Receiving a Message

```mermaid
sequenceDiagram
    autonumber
    participant Remote as Remote Mac
    participant Socket as NWConnection (Queue)
    participant Decoder as FrameDecoder
    participant PeerConn as PeerConnection
    participant Crypto as CryptoSession
    participant Net as NetworkManager
    participant Store as ChatStore (@MainActor)
    participant Archive as MessageArchive
    participant UI as MessageBubble (SwiftUI)

    Remote->>Socket: Sends 38 bytes (Framed Ciphertext)
    Socket->>PeerConn: receive callback fires
    PeerConn->>Decoder: append(bytes)
    Decoder-->>PeerConn: Yields complete 34-byte frame
    PeerConn->>Crypto: open(sealedBlob)
    Crypto-->>PeerConn: Returns plaintext UTF-8 Data ("hello")
    PeerConn->>Net: onMessageReceived("hello")
    Net->>Store: onMessageFromPeer(peerUUID, "hello") -> MainActor
    Store->>Store: append(ChatMessage(isLocal: false))
    Store->>Archive: save(ConversationSnapshot)
    Store->>UI: Update @Published conversations
    UI-->>UI: Renders gray incoming chat bubble
```

---

## 6. Flow F: Connection Failure & Backoff Recovery

```mermaid
sequenceDiagram
    autonumber
    participant Socket as NWConnection
    participant PeerConn as PeerConnection
    participant Net as NetworkManager (Queue)
    participant Store as ChatStore (@MainActor)
    participant UI as SwiftUI

    Socket->>PeerConn: stateUpdateHandler(.failed(POSIXError.ECONNRESET))
    PeerConn->>Net: onStateChange(.failed)
    Net->>Net: removeSession(connectionID)
    Net->>Store: onPeerDisconnected(peerUUID) -> MainActor
    Store->>Store: markSession(open: false), phase = .idle
    Store->>UI: statusLine = "Disconnected"
    Note over Net: If NWListener or NWBrowser fails:
    Net->>Net: scheduleRestart(reason)
    Net->>Net: queue.asyncAfter(delay = min(2^attempt, 30s)) -> startStacks()
```

---

## 7. Flow G: Device Disappearing (Walk Away)

```mermaid
sequenceDiagram
    autonumber
    participant Remote as Remote Mac (Leaves Range)
    participant Bonjour as mDNSResponder / AWDL
    participant Browser as NWBrowser
    participant Net as NetworkManager (Queue)
    participant Store as ChatStore (@MainActor)
    participant UI as SidebarView (SwiftUI)

    Remote--xBonjour: Beacons cease
    Bonjour->>Browser: browseResultsChangedHandler(emptySet)
    Browser->>Net: applyBrowseResults(results)
    Net->>Net: Calculate gone = previous.subtracting(next)
    Net->>Net: lastSeenAt[peerID] = Date()
    Net->>Store: onPeersUpdated(snapshot) -> MainActor
    Store->>Store: mergePresence(discovered) -> isOnline = false
    Store->>UI: Update @Published peers
    UI-->>UI: Green dot turns gray, displays "last seen [X mins ago]"
```

---

## 8. Flow H: App Termination

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as BlueCommsMacApp
    participant Store as ChatStore (@MainActor)
    participant Net as NetworkManager (Queue)
    participant PeerConn as PeerConnection
    participant Socket as NWConnection / NWListener / NWBrowser

    User->>App: Cmd+Q / Quit
    App->>Store: NotificationCenter(willTerminateNotification) -> store.stop()
    Store->>Net: stop()
    Net->>Net: stopLocked()
    Net->>PeerConn: cancel()
    PeerConn->>Socket: connection.cancel()
    Net->>Socket: listener.cancel(), browser.cancel()
    Socket-->>Socket: All sockets closed & ports released
```

---

## 9. Flow I: Multiple Simultaneous Devices

- `NetworkManager` maintains a dictionary `sessions: [String: PeerConnection]` keyed by peer device UUID.
- If Mac A connects to Mac B and Mac C simultaneously:
  - Both connections operate on independent `NWConnection` sockets.
  - Encryption sessions maintain separate symmetric keys and sequence counters.
  - `ChatStore.conversations` maintains independent message threads per peer UUID.

---

## 10. Flow J: Reconnection & Queue Delivery

When a disconnected peer reappears and reconnects:
1. `ChatStore` executes Flow C (Handshake).
2. When `onSecureSession` triggers, `ChatStore.flushOutbound(for: peerID)` scans `conversations[peerID]`.
3. Any `ChatMessage` with `delivery == .queued` is automatically encrypted and sent via `manager.send()`.
4. Its delivery state is updated to `.sent`, saved to disk, and rendered with the updated caption.
