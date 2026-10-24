# Engineering Blueprint: Rebuilding BlueComms from Scratch

> **Document Type:** Step-by-Step Architectural Blueprint & Engineering Thought Process  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

If this codebase were erased and you had to rebuild the networking subsystem from scratch, this document details the exact sequence of engineering decisions and implementation steps you should follow.

---

## 1. The 15 Engineering Stages

```
1. Define Requirements & Constraints ──> 2. Choose Transport (TCP vs UDP vs BLE)
                                                   │
                                                   ▼
4. Define Service & Metadata (TXT) <── 3. Select Discovery (Bonjour vs BLE vs mDNS)
         │
         ▼
5. Design Connection & Session Model ──> 6. Design Message & Framing Protocol
                                                   │
                                                   ▼
8. Implement State Machine & Concurrency <── 7. Design Security & Handshake (ECDH)
         │
         ▼
9. Implement Error Handling & Timeouts ──> 10. Configure Apple Privacy & Entitlements
                                                   │
                                                   ▼
12. Build Connection & Handshake <── 11. Build Listener & Browser
         │
         ▼
13. Build Framing & Stream Transfers ──> 14. Write Automated Integration Tests ──> 15. Wire UI
```

---

## 2. Step-by-Step Engineering Execution

### Step 1: Define Requirements & Constraints
- **Why First:** You cannot select protocols without knowing data constraints.
- **Decision:** Must support text chat AND large files (photos/videos up to multiple gigabytes) without internet access. This immediately eliminates BLE as the primary transport because BLE throughput is too low for gigabyte transfers.

### Step 2: Choose Transport Protocol
- **Why:** Must decide between TCP, UDP, or raw frames.
- **Decision:** Choose **TCP** via `Network.framework`. TCP provides in-order byte streams, retransmissions, and congestion control out of the box, saving you from writing an entire reliable transport layer over UDP.

### Step 3: Select Discovery Mechanism
- **Why:** How do devices know who is nearby?
- **Decision:** Choose **Bonjour (DNS-SD)** with `includePeerToPeer = true`. This leverages Apple's AWDL radio layer, allowing Macs to discover each other over ad-hoc Wi-Fi without needing a shared Wi-Fi router.

### Step 4: Define Service Name & TXT Metadata
- **Why:** Bonjour instance names (e.g. `"John's MacBook"`) can change at any time and collide.
- **Decision:** Advertise service type `_bluecomms._tcp` in domain `local.`. Attach a DNS-SD TXT record with:
  - `id`: A permanent device UUID string.
  - `proto`: Protocol version (`"1"`).
  - `name`: Human-readable computer name.

### Step 5: Define Connection Architecture
- **Why:** How many sockets exist between two devices?
- **Decision:** Maintain **one bidirectional TCP connection per peer UUID**. Store pending connections in a temporary map until their handshake succeeds, then promote them to the active `sessions` table.

### Step 6: Design Message Framing
- **Why:** TCP is a continuous byte stream; two `send()` calls can arrive coalesced into a single `receive()` chunk.
- **Decision:** Prepend a **4-byte big-endian UInt32 length prefix** before every payload:
  $$\text{Frame} = [\text{UInt32 BE Length}] + [\text{WireType}] + [\text{Payload}]$$
  Set a hard cap of 512 KB per frame to prevent buffer overflow/DoS attacks.

### Step 7: Design Encryption & Key Agreement
- **Why:** AWDL and local Wi-Fi packets are unencrypted over the air.
- **Decision:**
  1. Generate a persistent **Curve25519** keypair in `~/.bluecomms/`.
  2. Exchange public keys in frame `0x01` on connection start.
  3. Compute an X25519 shared secret and derive directional 256-bit AES keys via HKDF-SHA256.
  4. Encrypt all subsequent frames using **AES-GCM-256** with an incrementing 64-bit counter nonce.
  5. Enforce **Trust-On-First-Use (TOFU)** in `known-peers.json`.

### Step 8: Define Threading & Concurrency
- **Why:** Sockets, crypto, and file I/O must never block the main UI thread.
- **Decision:** Put all networking state, sockets, and session registries on a dedicated serial `DispatchQueue("bluecomms.network")`. Isolate UI state inside a `@MainActor ObservableObject` (`ChatStore`).

### Step 9: Define Error Handling & Timeouts
- **Why:** Sockets can hang or stall silently if a peer walks out of range.
- **Decision:**
  - Schedule a **10-second handshake timeout** on new connections.
  - Implement **exponential backoff** ($1\text{s} \rightarrow 30\text{s}$) when restarting failed listeners or browsers.

### Step 10: Configure Platform Privacy & Entitlements
- **Why:** macOS 14+ and iOS 14+ block local discovery without user permission.
- **Decision:** Declare `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_bluecomms._tcp`) in `Info.plist`. In `Package.swift`, pass `-sectcreate __TEXT __info_plist` linker flags so standalone executables embed these keys.

### Step 11: Implement Discovery (`NetworkManager`)
- **Code:** Build `startListener()` and `startBrowser()` using `.bonjourWithTXTRecord`. Filter out your own device UUID from browse results.

### Step 12: Implement Connection & Handshake (`PeerConnection`)
- **Code:** Listen for `NWConnection.State == .ready`. Immediately transmit `HandshakePayload`. Remember to set `isComplete: false` on `send()` to prevent closing the stream.

### Step 13: Implement File Streaming (`FileTransfer`)
- **Code:** Build a chunked streaming FSM: `offer` $\rightarrow$ `accept` $\rightarrow$ `256 KB chunk` $\rightarrow$ `ack` $\rightarrow$ `complete`. Use a sliding window of 8 chunks in flight and verify the end-to-end SHA-256 digest before moving to `~/Downloads/BlueComms`.

### Step 14: Write Automated Self-Tests
- **Code:** Build an in-process test suite (`BlueCommsSelfTest`) verifying:
  - Framing round-trips across split/coalesced buffers.
  - Handshake and directional key derivation.
  - TOFU key mismatch rejection.
  - File chunk streaming and checksum validation.

### Step 15: Wire Reactive UI
- **Code:** Bind SwiftUI views to `ChatStore` `@Published` properties. Connect the Send button to `manager.send()` and the Attach button to `manager.sendFile()`.
