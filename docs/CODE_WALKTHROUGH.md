# Code Walkthrough: Component & Lifecycle Guide

> **Document Type:** Line-Level Engineering Architecture  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

---

## 1. Complete System Lifecycle Walkthrough

Below is the chronological lifecycle of BlueComms from process launch to teardown, detailing thread hops, state mutations, and error boundaries.

```
[1. App Launch] ──> [2. Identity Loaded] ──> [3. Listener & Browser Start]
                                                      │
                                                      ▼
[6. Handshake (ECDH)] <── [5. TCP Handshake] <── [4. Bonjour Browse Result]
         │
         ▼
[7. TOFU Verification] ──> [8. Secure Session Ready] ──> [9. Bidirectional Transfer]
                                                                  │
                                                                  ▼
                                                      [10. Disconnect / Teardown]
```

---

## 2. Deep Dive by Component

---

### `IdentityStore.swift` & `DeviceIdentity`
[Sources/BlueCommsCore/IdentityStore.swift](../BlueCommsCLI/Sources/BlueCommsCore/IdentityStore.swift)

#### Key Responsibilities:
- Loads or creates long-term device UUID and Curve25519 private key in `~/.bluecomms/`.
- Obtains the machine's display name using `SCDynamicStoreCopyComputerName` (instant, non-blocking).
- Maintains `known-peers.json` for Trust-On-First-Use (TOFU) key pinning.

#### Critical Functions:
- `loadOrCreate() -> DeviceIdentity`: Ensures directory exists with POSIX permissions `0700`. Reads `device-id` and `identity` files with POSIX permissions `0600`.
- `verifyOrRemember(peerID:publicKey:)`: Checks if `peerID` exists in `known-peers.json`. If matched, returns `.matched`. If new, stores key and returns `.firstSeen`. If mismatched, throws `CryptoError.tofuMismatch`.

---

### `NetworkManager.swift`
[Sources/BlueCommsCore/NetworkManager.swift](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift)

#### Concurrency & State Ownership:
- **Queue:** Operates entirely on an internal serial `DispatchQueue(label: "bluecomms.network")`.
- **State Owned:**
  - `listener: NWListener?`
  - `browser: NWBrowser?`
  - `sessions: [String: PeerConnection]` (key is peer UUID string)
  - `pending: [UUID: PeerConnection]` (key is connection object UUID)
  - `discoveredByID: [String: DiscoveredPeer]`

#### Critical Methods:

#### 1. `startListener()` ([L242-L271](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L242-L271))
- **Why:** Binds an ephemeral TCP port and publishes `_bluecomms._tcp.local.` via Bonjour.
- **TXT Record Population:** Injects `id` (device UUID), `proto` (`1`), and `name` into the `NWTXTRecord`.
- **`newConnectionHandler`:** When an inbound connection arrives, it logs the endpoint and passes the raw `NWConnection` to `attach(connection)`.

#### 2. `startBrowser()` ([L274-L293](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L274-L293))
- **Why:** Scans for other BlueComms devices over local Wi-Fi and AWDL.
- **Browse Result Handling (`applyBrowseResults`):**
  - Converts each `NWBrowser.Result` into a `DiscoveredPeer`.
  - Filters out our own device UUID.
  - Updates `lastSeenAt` timestamps for devices that left radio range.
  - Dispatches `onPeersUpdated` to the main queue.

#### 3. `connect(to peer: DiscoveredPeer)` ([L361-L370](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L361-L370))
- **Why:** Initiates outbound TCP to `peer.endpoint` using parameters with `includePeerToPeer = true`.
- **Passing to `attach`:** Instantiates a `PeerConnection` and stores it in `pending[connectionID]`.

#### 4. `attach(_ connection: NWConnection)` ([L373-L448](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L373-L448))
- Hooks `onHandshake`, `onReadyForChat`, `onMessageReceived`, `onFileTransfer`, and `onStateChange`.
- **Race Condition Resolution:** When `onReadyForChat` fires, if an existing session exists for the same peer UUID, the older session is cancelled and replaced by the newly authenticated connection.

---

### `PeerConnection.swift`
[Sources/BlueCommsCore/PeerConnection.swift](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift)

#### State Owned:
- `connection: NWConnection`
- `crypto: CryptoSession`
- `decoder: FrameDecoder`
- `outboundQueue: [String]` (buffers up to 32 messages while handshake completes)
- `outgoing: [UUID: OutgoingTransfer]`
- `incoming: [UUID: IncomingTransfer]`

#### Critical Methods:

#### 1. `start()` ([L64-L82](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift#L64-L82))
- Sets `connection.stateUpdateHandler`.
- When state reaches `.ready`:
  1. Calls `sendHandshake()` to transmit our public key.
  2. Spawns `receiveLoop()` exactly once.
- Schedules a **10-second handshake timeout** via `DispatchWorkItem` to prevent zombie connections.

#### 2. `receiveLoop()` ([L130-L164](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift#L130-L164))
- Calls `connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144)`.
- Passes chunk to `decoder.append()`.
- Iterates over all decoded frames and routes to:
  - `handleHandshake()` for `WireType.handshake` (`0x01`).
  - `handleCiphertext()` for `WireType.ciphertext` (`0x02`).
  - `handleFileBlob()` for `WireType.file` (`0x03`).
- Re-arms `receiveLoop()` recursively unless connection is closed or encountered an error.

#### 3. `sendFrame(type: WireType, body: Data)` ([L260-L274](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift#L260-L274))
- Encodes frame with 4-byte big-endian length prefix.
- Invokes `connection.send(content: framed, isComplete: false)`.

---

### `CryptoSession.swift`
[Sources/BlueCommsCore/CryptoSession.swift](../BlueCommsCLI/Sources/BlueCommsCore/CryptoSession.swift)

#### Key State & Operations:
- `localPrivateKey: Curve25519.KeyAgreement.PrivateKey`
- `sendKey: SymmetricKey?`
- `receiveKey: SymmetricKey?`
- `sendCounter: UInt64`
- `establish(peerPublicKey: Data)`: Computes X25519 ECDH shared secret. Derives `lowToHigh` and `highToLow` keys via HKDF-SHA256. Assigns send/receive keys based on public key lexicographical comparison.
- `seal(plaintext: Data) -> Data`: Nonce generated from `sendCounter` (12 bytes). AES-GCM encryption. Returns `[Nonce] + [Ciphertext] + [Tag]`.
- `open(blob: Data) -> Data`: Validates length $\ge 28$ bytes. Slices Nonce (12B), Tag (16B), Ciphertext. Authenticates and decrypts.

---

### `FrameCodec.swift`
[Sources/BlueCommsCore/FrameCodec.swift](../BlueCommsCLI/Sources/BlueCommsCore/FrameCodec.swift)

#### Constants:
- `headerSize = 4` (UInt32 Big-Endian)
- `maxPayloadSize = 524_288` (512 KB)

#### Mechanics:
- `encode(payload: Data)`: Throws `FrameError.payloadTooLarge` if payload exceeds 512 KB. Returns `[4-byte BE length] + payload`.
- `FrameDecoder.append(data: Data)`: Appends incoming bytes to internal `buffer`. Loops while `buffer.count >= 4`. Extracts complete frames and trims `buffer`.

---

### `ChatStore.swift` & `ContentView.swift`
[Sources/BlueCommsApp/ChatStore.swift](../BlueCommsCLI/Sources/BlueCommsApp/ChatStore.swift) & [Sources/BlueCommsApp/ContentView.swift](../BlueCommsCLI/Sources/BlueCommsApp/ContentView.swift)

#### State Owned by `@MainActor ChatStore`:
- `@Published var peers: [NearbyPeer]`
- `@Published var conversations: [String: [ChatMessage]]`
- `@Published var selectedPeerID: String?`
- `@Published var draft: String`
- `@Published var phase: ConnectionPhase`
- `@Published var statusLine: String`

#### Reactive UI Binding:
- SwiftUI views observe `ChatStore` via `@EnvironmentObject`.
- Any background callback from `NetworkManager` hops to `@MainActor` via `Task { @MainActor in ... }` before modifying published state, ensuring thread-safe UI rendering.
