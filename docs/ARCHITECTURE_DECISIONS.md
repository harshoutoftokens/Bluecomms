# Architecture Decision Records (ADRs)

> **Document Type:** Architectural & Engineering Analysis  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

This document explains the technical "WHY" behind every major architectural decision in BlueComms. It analyzes the chosen technologies against realistic alternatives, detailing trade-offs, constraints, and long-term cross-platform implications.

---

## 1. Primary Networking Stack: Apple Network.framework (with AWDL)

### 1. What did we choose?
`Network.framework` (`NWListener`, `NWBrowser`, `NWConnection`) with `NWParameters.tcp` and `includePeerToPeer = true` over Bonjour service `_bluecomms._tcp`.

### 2. What problem does it solve?
Provides reliable, high-throughput, low-latency device-to-device communication without requiring internet access or a shared local Wi-Fi router.

### 3. Why did we choose it?
- **Modern Apple Standard:** Replaced deprecated BSD sockets and legacy CoreOS APIs in macOS 10.14+ / iOS 12+.
- **AWDL Integration:** Setting `includePeerToPeer = true` seamlessly triggers Apple Wireless Direct Link (the 802.11 peer-to-peer Wi-Fi radio layer used by AirDrop).
- **High Throughput:** Because it establishes a direct Wi-Fi physical link, throughput easily reaches tens to hundreds of megabits per second, making gigabyte file transfers practical.
- **Unified Event-Driven API:** Integrates cleanly with Grand Central Dispatch (`DispatchQueue`) and Swift concurrency.

### 4. What alternatives existed?
1. **Multipeer Connectivity (`MultipeerConnectivity.framework`)**
2. **CoreBluetooth (Bluetooth Low Energy / BLE GATT)**
3. **Raw BSD Sockets (`sys/socket.h`, `CFSocket`, POSIX)**
4. **UDP Datagrams via Network.framework (`NWParameters.udp`)**
5. **WebSockets (`URLSessionWebSocketTask` or Network.framework WebSocket)**
6. **Wi-Fi Direct (Standard Wi-Fi P2P)**
7. **Google Nearby Connections**

### 5. Why didn't we choose those alternatives?

#### A. Why not Multipeer Connectivity?
- **Opaque Black Box:** `MultipeerConnectivity` bundles discovery, session establishment, encryption, and framing into a single monolithic framework (`MCSession`, `MCNearbyServiceAdvertiser`). When a connection fails or drops, debugging is virtually impossible because Apple provides almost zero diagnostics or control over the underlying socket or radio state.
- **Arbitrary 8-Peer Limit:** `MCSession` is hardcoded to a maximum of 8 connected peers.
- **High Failure Rate:** Widely known in the Apple developer community for unexplainable connection dropouts, slow discovery hangs, and inability to recover cleanly without restarting Bluetooth/Wi-Fi.
- **Proprietary Protocol:** Completely locked to Apple platforms with zero path to cross-platform compatibility.

#### B. Why isn't BLE (CoreBluetooth) automatically the best solution for offline comms?
- **Extreme Bandwidth Bottleneck:** BLE throughput in practice is limited to ~2 KB/s to 10 KB/s (under ideal BLE 5.0 conditions with 2M PHY, ~50 KB/s max). While fine for small text packets, sending a 100 MB video or a 500 MB photo over BLE would take hours.
- **GATT Packet Size Limits:** Bluetooth MTU sizes require aggressive application-level chunking (typically 20 to 512 bytes per packet).
- **Complex State Machine:** Managing Centrals, Peripherals, Services, Characteristics, RSSI thresholds, and connection intervals introduces substantial complexity without solving the file transfer problem.

#### C. Why not Raw BSD Sockets?
- **No Native AWDL Control:** Raw POSIX `socket()` calls cannot easily instruct macOS to negotiate peer-to-peer 802.11 link schedules over AWDL without private system daemons.
- **Local Network Privacy Hurdles:** macOS 14+ and iOS 14+ require integration with system network authorization prompts which `Network.framework` handles natively.
- **Manual Thread/Select Management:** Requires complex C-level `kqueue` or `poll` event loops.

#### D. Why not UDP?
- **Lack of Reliability & Ordering:** UDP does not guarantee delivery or packet ordering. BlueComms would have had to implement an entire TCP stack in user space (sequence numbers, ACKs, retransmissions, sliding windows, congestion control).
- **File Transfer Overhead:** File streaming requires guaranteed, ordered bytes. TCP solves this out of the box.

### 6. What trade-offs did we accept?
- **Apple Platform Lock-in for AWDL:** `includePeerToPeer` relies on Apple's proprietary AWDL driver and daemon. Android and Windows cannot join an AWDL peer-to-peer session.
- **Connection Setup Latency:** Bringing up an AWDL radio link between two sleeping or separate Macs can take 1–3 seconds before the first TCP handshake byte is exchanged.

### 7. What limitations does our choice have?
- **Point-to-Point Topology:** `NWConnection` is a direct 1-to-1 socket. It does not perform multi-hop routing, mesh forwarding, or broadcast flooding.
- **Radio Range:** Communication is limited to direct Wi-Fi radio range (~30–100 feet depending on physical obstacles).

### 8. Under what circumstances would another choice become better?
- If BlueComms must run on **microcontrollers or low-power IoT devices**, BLE would be required.
- If BlueComms must support **Android/Windows peer-to-peer without an AP**, Wi-Fi Direct or WebRTC data channels with custom discovery would become necessary.

### 9. Is this decision specific to macOS/iOS or portable?
- **Apple Specific:** `Network.framework` and AWDL are exclusive to macOS, iOS, iPadOS, watchOS, and tvOS.

### 10. Will this decision cause problems when BlueComms becomes cross-platform?
- **Yes.** To support Android or Windows, BlueComms must abstract the transport layer behind a protocol (e.g., `TransportAdapter`) and implement platform-native transports (Wi-Fi Direct on Android, Wi-Fi P2P on Windows).

---

## 2. Encryption & Key Agreement: Curve25519 (X25519) + AES-GCM-256 + TOFU

### 1. What did we choose?
Custom application-layer cryptographic session ([CryptoSession.swift](../BlueCommsCLI/Sources/BlueCommsCore/CryptoSession.swift)) using:
- **Key Agreement:** Curve25519 (X25519) via `CryptoKit.Curve25519.KeyAgreement`.
- **Key Derivation:** HKDF-SHA256 with `"bluecomms-v1"` salt and directional info tags (`"bluecomms-v1-l2h"` and `"bluecomms-v1-h2l"`).
- **Authenticated Encryption:** AES-GCM with 256-bit keys and a 64-bit monotonically incrementing counter nonce.
- **Identity & Trust:** Trust-On-First-Use (TOFU) persisted in `~/.bluecomms/known-peers.json`.

### 2. What problem does it solve?
Protects all communications (text and files) against eavesdropping, tampering, and man-in-the-middle attacks over the unencrypted local radio/LAN.

### 3. Why did we choose it?
- **Zero Round-Trip Negotiation:** By exchanging public keys in the initial handshake and sorting them lexicographically, both sides independently compute identical directional symmetric keys without extra round-trip handshakes.
- **High Performance:** AES-GCM uses hardware acceleration (AES-NI / ARM Crypto instructions) on modern Apple Silicon and Intel CPUs, running at gigabytes per second.
- **Tamper Evidence:** AES-GCM's 16-byte authentication tag guarantees that if even a single bit of ciphertext is modified in transit, decryption fails completely.

### 4. What alternatives existed?
1. **Standard TLS 1.3 (via `NWParameters.tls`)**
2. **Noise Protocol Framework (e.g., Noise_IK or Noise_XX)**
3. **Signal Protocol (Double Ratchet)**
4. **Unencrypted Plaintext**

### 5. Why didn't we choose those alternatives?
- **Why not TLS 1.3?** Standard TLS requires a Public Key Infrastructure (PKI) with Certificate Authorities (CAs) or self-signed X.509 certificate chains. In a fully offline, ad-hoc, peer-to-peer environment with no internet, managing CA root trust or validating domain names in certificates adds massive complexity without adding security over raw public-key pinning.
- **Why not Signal Double Ratchet?** The Double Ratchet provides forward secrecy per-message for asynchronous messaging. In BlueComms' current direct synchronous session model, a static-per-session ECDH key is simpler and sufficient for real-time streams. (Ratchet can be added in future iterations for asynchronous store-and-forward).

### 6. What trade-offs did we accept?
- **TOFU Vulnerability on Initial Discovery:** The very first time you connect to a new peer, you trust their public key without a centralized certificate authority. If an attacker is actively MITM-ing the radio on the exact first connection, they could intercept it (mitigated by out-of-band fingerprint verification).

### 7. What limitations does our choice have?
- **Ephemeral Session Keys vs. Static Identities:** Currently, `DeviceIdentity` uses its long-term identity key directly for ECDH key agreement instead of generating ephemeral keys per session. This means if a device's long-term private key were ever compromised, past recorded sessions from that key could theoretically be decrypted (no ephemeral Forward Secrecy).

---

## 3. Message Framing: 4-Byte Big-Endian Length Prefix

### 1. What did we choose?
A custom binary framing codec ([FrameCodec.swift](../BlueCommsCLI/Sources/BlueCommsCore/FrameCodec.swift)):
$$\text{Header (4 bytes UInt32 BE)} + \text{Payload (up to 512 KB)}$$

### 2. What problem does it solve?
Solves the fundamental **TCP stream delimitation problem**. TCP is an unstructured stream of bytes; it has no concept of "messages". Without framing, messages merge together or fragment unpredictably.

### 3. Why did we choose it?
- **Deterministic & Fast:** Reading a 4-byte integer tells the decoder exactly how many bytes to buffer before yielding a complete payload.
- **Zero Parsing Ambiguity:** Unlike delimiter-based framing (e.g., `\n` or `\0`), binary length prefixing allows arbitrary binary data (encrypted ciphertexts, raw file chunks) without byte-stuffing or escaping.
- **Safety Cap (512 KB):** Prevents malicious peers from sending a length header claiming $4\text{ GB}$, which would cause the receiver to allocate massive memory and crash (DoS protection).

### 4. What alternatives existed?
1. **Delimiter-based framing (e.g. newline `\n` or null byte `\0`)**
2. **WebSocket Framing (RFC 6455)**
3. **Protocol Buffers / gRPC**
4. **Assuming `send()` equals `receive()`**

### 5. Why didn't we choose those alternatives?
- **Delimiter:** Incompatible with arbitrary binary ciphertexts (which can contain random `\n` bytes) without base64 encoding (which adds a 33% bandwidth penalty).
- **WebSocket:** Adds unnecessary masking, opcode headers, and framing complexity for a direct binary stream.
- **Assuming `send() == receive()`:** Catastrophic bug in early network prototypes; TCP will inevitably coalesce or split packets at MTU boundaries.

---

## 4. File Streaming Architecture: Chunked Window Protocol

### 1. What did we choose?
A custom chunked streaming protocol ([FileTransfer.swift](../BlueCommsCLI/Sources/BlueCommsCore/FileTransfer.swift)):
- **Chunk Size:** 256 KB.
- **Sliding Window:** 8 chunks in flight ($2\text{ MB}$ window).
- **Control Flow:** `offer` $\rightarrow$ `accept` $\rightarrow$ `chunk` $\rightarrow$ `ack` $\rightarrow$ `complete` (with full file SHA-256 validation).
- **Storage:** Direct disk-to-network streaming via `FileHandle` without loading entire files into RAM.

### 2. What problem does it solve?
Allows transferring files up to 8 GB on memory-constrained devices without memory spikes or app crashes.

### 3. Why did we choose it?
- **Constant Memory Footprint:** Reading and writing 256 KB slices ensures RAM usage stays under ~10 MB even when sending a 4 GB 4K video.
- **Pipelined Throughput:** The 8-chunk window keeps the AWDL Wi-Fi pipeline saturated without waiting for an ACK on every single 256 KB slice.
- **End-to-End Integrity:** Receiver calculates a running SHA-256 hash as chunks are written to a `.part` file, verifying it against the sender's final digest before moving the file to `~/Downloads/BlueComms`.

---

## 5. Mesh & Routing: Why Doesn't TCP Automatically Solve Mesh Networking?

A common misconception in offline networking is: *"If we have offline peer-to-peer TCP, don't we automatically have a mesh network?"*

### The Engineering Reality:
**No.** TCP is strictly a **point-to-point, single-hop connection** between two endpoints.

```
       Direct TCP Link
Mac A <================> Mac B (In Radio Range)

Mac A . . . . . . . . . . . . . . . . . . . . . Mac C (OUT OF RADIO RANGE)
                                                 
       Direct TCP Link          Direct TCP Link
Mac A <================> Mac B <================> Mac C (Mesh Relay Required)
```

1. **Physical Radio Boundaries:** If Mac A is 50 feet from Mac B, and Mac B is 50 feet from Mac C, Mac A cannot physically reach Mac C.
2. **TCP Cannot Hop:** Mac A's TCP connection to Mac B terminates at Mac B's kernel. Mac B's OS does not automatically inspect Mac A's encrypted payload, determine it is intended for Mac C, and route it across its separate TCP connection to Mac C.
3. **What Mesh Actually Requires:**
   - **Network-Layer Routing:** A protocol (e.g., AODV, BATMAN, or custom overlay) to maintain a topology routing table of multi-hop paths.
   - **Addressing & Identity:** Addressing messages by destination device UUID, not IP/port endpoint.
   - **Hop Limits (TTL):** To prevent packets from looping endlessly across cycles.
   - **Store-and-Forward:** Storing messages in local storage if the next hop is temporarily offline.
   - **End-to-End vs. Hop-by-Hop Encryption:** Mac B (the relay) must not be able to read or tamper with Mac A's message to Mac C.

BlueComms currently implements **direct 1-to-1 peer-to-peer connections**, not a multi-hop mesh.

---

## 6. Comprehensive Technology Comparison Matrix

| Technology | Bandwidth | Range | Multi-Hop Mesh? | Offline / No AP? | Cross-Platform? | BlueComms Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Network.framework (AWDL)** | High (50–300 Mbps) | Medium (~30m) | No (Point-to-Point) | **Yes** (AirDrop radio) | **Apple Only** | **Active Core** |
| **Multipeer Connectivity** | Medium (10–50 Mbps) | Medium (~30m) | Partial (Unreliable) | **Yes** | **Apple Only** | **Rejected** (Unstable) |
| **CoreBluetooth (BLE)** | Very Low (2–100 Kbps) | Short (~15m) | No | **Yes** | Yes | **Future / Secondary** |
| **Bluetooth Mesh** | Extremely Low (<5 Kbps)| Short (Relayed) | **Yes** (Flooding) | **Yes** | Yes (Complex) | **Not Suitable for Files** |
| **Wi-Fi Direct** | High (50–300 Mbps) | Medium (~30m) | No (P2P Group) | **Yes** | Android/Windows | **Future Cross-Platform** |
| **Raw BSD Sockets** | High | N/A | No | Requires AP or IP | Yes | **Rejected** (No AWDL) |
