# Networking Deep Dive: How BlueComms Communicates

> **Document Type:** Low-Level Networking Architecture  
> **Repository Path:** [BlueCommsCore/NetworkManager.swift](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift) & [BlueCommsCore/PeerConnection.swift](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

---

## 1. End-to-End Architectural Layering

Every byte exchanged in BlueComms moves through a strictly defined hierarchy of layers:

```
+-----------------------------------------------------------------------------------------+
|                                    APPLICATION LAYER                                    |
|                     SwiftUI Views / CLI Command Parser (main.swift)                     |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
|                                STATE & ORCHESTRATION                                    |
|                     ChatStore.swift / NetworkManager.swift                              |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
|                                APPLICATION PROTOCOL                                     |
|               WireType (0x01 Handshake, 0x02 Chat, 0x03 FileMessage)                    |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
|                              CRYPTOGRAPHIC ENCRYPTION                                   |
|                CryptoSession.swift: AES-GCM-256 (Sealed Box + 12-byte Nonce)            |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
|                                   FRAMING LAYER                                         |
|                   FrameCodec.swift: 4-Byte Big-Endian UInt32 Length                     |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
|                              APPLE NETWORK.FRAMEWORK                                    |
|                        NWConnection / NWListener / NWBrowser                            |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
|                                DISCOVERY & TRANSPORT                                    |
|              Bonjour (DNS-SD) / TCP Stream / AWDL (includePeerToPeer)                   |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
|                                PHYSICAL LAYER (PHY)                                     |
|                     802.11 Wi-Fi Radio (Ad-hoc P2P or Local Subnet)                     |
+-----------------------------------------------------------------------------------------+
```

---

## 2. Apple Networking Components Explained in Detail

### 1. `NWParameters.includePeerToPeer = true`
Located in [NetworkManager.swift:L539-L543](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L539-L543):

```swift
private static func makeParameters() -> NWParameters {
    let params = NWParameters.tcp
    params.includePeerToPeer = true
    return params
}
```

#### What does `includePeerToPeer` actually do?
1. **Enables AWDL (Apple Wireless Direct Link):** By default, standard TCP sockets only bind to active infrastructure interfaces (`en0` connected to a Wi-Fi Access Point, or `en1` Ethernet). If you are not connected to a Wi-Fi router, standard sockets fail immediately. Setting `includePeerToPeer = true` instructs the Darwin kernel and `mDNSResponder` to activate Apple's proprietary AWDL interface (`awdl0`).
2. **Ad-Hoc Radio Synchronization:** The Wi-Fi chip periodically switches channels to listen on an Apple-reserved frequency for peer beacons. When two devices with `includePeerToPeer = true` discover each other, they schedule shared transmission windows without needing an Access Point.

#### What does it NOT guarantee?
- **It does NOT guarantee offline operation if Wi-Fi is powered off:** If the user toggles Wi-Fi OFF in Control Center, the Wi-Fi physical radio is powered down. AWDL cannot operate.
- **It does NOT work across non-Apple devices:** AWDL is a proprietary Apple protocol. Android and Windows Wi-Fi drivers do not implement the AWDL MAC frame specification.
- **It does NOT bypass the Local Network Privacy prompt:** On macOS 14+ and iOS 14+, the OS will still block peer discovery until the user grants permission.

---

### 2. Service Advertising: `NWListener`
Located in [NetworkManager.swift:L242-L271](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L242-L271):

#### Purpose:
`NWListener` listens for incoming TCP connections and registers this device's presence with `mDNSResponder` (the system DNS Service Discovery daemon).

#### Initialization & Configuration:
```swift
let newListener = try NWListener(using: params)
var txt = NWTXTRecord()
txt["id"] = identity.id.uuidString
txt["proto"] = String(HandshakePayload.protoVersion)
txt["name"] = identity.displayName
newListener.service = NWListener.Service(
    name: identity.bonjourName,
    type: "_bluecomms._tcp",
    domain: "local.",
    txtRecord: txt
)
```

#### Key Mechanics:
1. **Dynamic Port Binding:** `NWListener(using: params)` automatically requests an ephemeral, unused TCP port from the kernel.
2. **DNS-SD Registration:** Setting `newListener.service` instructs Bonjour to broadcast a DNS `PTR` record for `_bluecomms._tcp.local.`, an `SRV` record resolving the dynamic port, and a `TXT` record containing the device metadata.
3. **The `newConnectionHandler` Callback:** When a remote peer connects, this handler fires on the `bluecomms.network` dispatch queue, yielding an inbound `NWConnection` instance.

---

### 3. Service Discovery: `NWBrowser`
Located in [NetworkManager.swift:L274-L293](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L274-L293):

#### Purpose:
`NWBrowser` scans the local network and AWDL channels for advertised `_bluecomms._tcp` services and receives real-time updates when devices appear or disappear.

#### Initialization & TXT Query:
```swift
let newBrowser = NWBrowser(
    for: .bonjourWithTXTRecord(type: "_bluecomms._tcp", domain: "local."),
    using: params
)
```

#### Why `.bonjourWithTXTRecord` is Critical:
Using the standard `.bonjour(type:domain:)` descriptor causes Network.framework to optimize away the DNS-SD TXT record query to save battery, returning empty metadata (`result.metadata == nil`). Because BlueComms relies on the TXT `id` key to uniquely identify peers across name changes, `.bonjourWithTXTRecord` is mandatory.

#### The `browseResultsChangedHandler`:
Whenever a device enters or leaves the radio range, this callback receives a `Set<NWBrowser.Result>`.
Each `NWBrowser.Result` contains:
- `endpoint`: An `NWEndpoint.service(name:type:domain:interface:)` representing the target.
- `metadata`: The parsed `NWTXTRecord` containing `id`, `proto`, and `name`.

---

### 4. Connection Lifecycle: `NWConnection`
Managed in [PeerConnection.swift](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift):

#### State Machine Progression:
```
+-------+      +-----------+      +---------+
| setup | ---> | preparing | ---> |  ready  | ---> Active Communication
+-------+      +-----------+      +---------+
                     |                 |
                     v                 v
               +-----------+     +-----------+
               |  waiting  |     |  failed   |
               +-----------+     +-----------+
                                       |
                                       v
                                 +-----------+
                                 | cancelled |
                                 +-----------+
```

1. **`.setup`:** The object is instantiated but not yet active.
2. **`.preparing`:** The network stack resolves DNS-SD records, sets up AWDL radio channel scheduling, and initiates the TCP 3-way handshake (`SYN` $\rightarrow$ `SYN-ACK` $\rightarrow$ `ACK`).
3. **`.waiting`:** Temporary network unavailability (e.g. Wi-Fi interface down).
4. **`.ready`:** The TCP socket is fully connected. The application can now send and receive raw bytes.
5. **`.failed` / `.cancelled`:** The link was closed by a network error, timeout, or explicit `.cancel()`.

---

## 3. The `isComplete: false` Rule in `NWConnection.send()`

Located in [PeerConnection.swift:L266](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift#L266):

```swift
connection.send(
    content: framed,
    contentContext: .defaultMessage,
    isComplete: false,
    completion: .contentProcessed { ... }
)
```

### Why this is critical:
In Apple's `Network.framework`, `isComplete` defaults to `true`. On a TCP stream:
- Setting `isComplete: true` sends a **TCP FIN** packet immediately after the data.
- This signals to the remote peer that the sending side has shut down its stream.
- In early prototypes, sending a single chat message closed the entire socket!
- **BlueComms Rule:** `isComplete` **must always remain `false`** for all regular frames to keep the bidirectional TCP socket alive.

---

## 4. The Receive Loop Architecture

Located in [PeerConnection.swift:L130-L164](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift#L130-L164):

```swift
private func receiveLoop() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] content, _, isComplete, error in
        guard let self, !self.closed else { return }

        if let content, !content.isEmpty {
            do {
                let frames = try self.decoder.append(content)
                for frame in frames {
                    try self.handleFrame(frame)
                }
            } catch {
                self.cancel()
                return
            }
        }

        if isComplete || error != nil {
            self.cancel()
            return
        }

        self.receiveLoop() // Re-arm the receive callback for the next chunk
    }
}
```

### Architectural Principles:
1. **Explicit Re-arming:** `NWConnection.receive` is a **one-shot callback**. After processing a chunk of data, the code must explicitly call `receiveLoop()` again to listen for future bytes.
2. **Buffer Management via `FrameDecoder`:** `content` may contain half a frame, one frame, or five frames. `self.decoder.append(content)` parses only complete frames and preserves leftover bytes in an internal buffer.
3. **Single Loop Invariant:** `receiveLoop()` is invoked exactly once when the connection state transitions to `.ready`. Calling it multiple times would cause race conditions and corrupted frame decoding.
