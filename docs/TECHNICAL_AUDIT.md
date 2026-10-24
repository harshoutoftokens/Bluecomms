# Comprehensive Technical Audit & Risk Report

> **Document Type:** System Audit, Code Health & Risk Assessment  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

This technical audit provides an objective evaluation of the BlueComms repository as it exists today, detailing architectural strengths, fragility points, technical debt, security boundaries, and prioritized future engineering recommendations.

---

## 1. Executive Summary

- **Repository Structure:** Single Swift Package (`BlueCommsCLI`) with 4 targets:
  1. `BlueCommsCore` (Library: framing, crypto, AWDL/Bonjour networking, file streaming, identity)
  2. `BlueCommsCLI` (Executable: Terminal chat client)
  3. `BlueCommsApp` (Executable: SwiftUI macOS GUI)
  4. `BlueCommsSelfTest` (Executable: In-process test runner with 32 unit/integration tests)
- **Primary Networking Technology:** Apple `Network.framework` (`NWListener`, `NWBrowser`, `NWConnection`) over Bonjour service `_bluecomms._tcp` in domain `local.` with `includePeerToPeer = true` (Apple Wireless Direct Link / AWDL).
- **Primary Cryptographic Technology:** Apple `CryptoKit` Curve25519 (X25519) key agreement, HKDF-SHA256 directional key derivation, and AES-GCM-256 authenticated encryption with Trust-On-First-Use (TOFU) key pinning.

---

## 2. Strengths (What Is Technically Solid)

1. **Robust Binary Framing:** [FrameCodec.swift](../BlueCommsCLI/Sources/BlueCommsCore/FrameCodec.swift) uses a 4-byte big-endian length prefix with a dedicated [FrameDecoder](../BlueCommsCLI/Sources/BlueCommsCore/FrameCodec.swift#L44-L72) accumulator, correctly eliminating TCP stream coalescing and fragmentation bugs.
2. **Deterministic Cryptographic Handshake:** [CryptoSession.swift](../BlueCommsCLI/Sources/BlueCommsCore/CryptoSession.swift) performs a zero-round-trip key agreement by lexicographically comparing public keys, establishing unique directional encryption keys (`lowToHigh` and `highToLow`) with no negotiation overhead.
3. **Memory-Constrained File Streaming:** [FileTransfer.swift](../BlueCommsCLI/Sources/BlueCommsCore/FileTransfer.swift) streams files up to 8 GB in 256 KB slices using a sliding window of 8 in-flight chunks and verifies full-file SHA-256 integrity before finalizing downloads, keeping RAM usage flat under ~10 MB.
4. **Thread-Safe Queue Isolation:** [NetworkManager.swift](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift) protects all socket and session mutations on a dedicated serial `DispatchQueue` and uses `DispatchSpecificKey` to prevent recursive re-entrancy deadlocks.
5. **Path Traversal Protection:** Remote filenames are strictly sanitized before writing to `~/Downloads/BlueComms/`, preventing malicious overwrite of local system files.
6. **32 Automated Self-Tests:** [BlueCommsSelfTest](../BlueCommsCLI/Sources/BlueCommsSelfTest/main.swift) provides 100% passing automated test coverage across framing, crypto, TOFU, file messages, and in-process discovery/transfer.

---

## 3. Weaknesses & Fragility Points

1. **Tight Coupling to Network.framework:** `NetworkManager` directly imports and instantiates Apple `Network` APIs rather than conforming to an abstract transport protocol. This makes cross-platform porting to Android or Windows impossible without refactoring.
2. **Static Identity ECDH (No Ephemeral Forward Secrecy):** `CryptoSession` performs key agreement directly with the long-term identity keys stored in `~/.bluecomms/identity`. If a device's private key is ever compromised, past recorded sessions could theoretically be decrypted.
3. **Unauthenticated Bonjour Broadcasts:** Bonjour service discovery broadcasts unencrypted device names and UUIDs. While chat payloads are encrypted, an eavesdropper can see that BlueComms is active and map nearby devices.
4. **1-to-1 Star Topology for Multi-Peer:** `NetworkManager` maintains individual 1-to-1 sockets per peer. There is no true group broadcast or decentralized group key management (MLS).

---

## 4. Known Technical Debt & Dangerous Assumptions

| Component | Debt / Assumption | Risk / Bug Potential |
| :--- | :--- | :--- |
| **`NetworkManager.swift`** | Assumes `DiscoveredPeer` always has a valid UUID in TXT `id`. | Older or third-party Bonjour services on `_bluecomms._tcp` without TXT records are silently dropped. |
| **`PeerConnection.swift`** | Assumes `FileTransfer.accept` always starts from offset 0 (`resumeFrom: 0`). | File resuming after an interrupted session restarts from byte 0 instead of resuming mid-transfer. |
| **`IdentityStore.swift`** | `localComputerName()` calls macOS `SCDynamicStoreCopyComputerName`. | Non-portable to iOS/Linux; requires conditional compilation fallbacks. |
| **`ScreenGrab.swift`** | Relies on AppKit / CoreGraphics `CGDisplayCreateImage`. | Fails on headless environments or systems without Screen Recording permission. |
| **`ChatStore.swift`** | Synchronously rewrites entire `conversations.bin` archive on every sent/received message. | With thousands of messages, writing the entire JSON blob to disk on every message will introduce I/O latency. |

---

## 5. Security & Threat Audit

- **Encryption on the Wire:** **AES-GCM-256 (Strong)**.
- **Key Exchange:** **Curve25519 ECDH + HKDF-SHA256 (Strong)**.
- **Data Integrity:** **16-byte GCM tags + SHA-256 file checksums (Strong)**.
- **Trust Model:** **Trust-On-First-Use / TOFU (Moderate - vulnerable to first-contact MITM)**.
- **Forward Secrecy:** **Not implemented (Static ECDH keys)**.
- **Path Traversal:** **Protected (Sanitized file paths)**.

---

## 6. Prioritized Engineering Recommendations

### **P0 — Critical Architectural Foundations (Understand / Fix First)**
- **Ephemeral Forward Secrecy:** Generate an ephemeral Curve25519 keypair per session and sign it with the long-term identity key to ensure past sessions cannot be decrypted if long-term keys leak.
- **Transport Abstraction Layer:** Define `TransportListener`, `TransportBrowser`, and `TransportSession` protocols to decouple `NetworkManager` from Apple `Network.framework`.

### **P1 — Important Platform & Operational Features**
- **iOS Target & Background Entitlements:** Create an Xcode iOS application target and implement background push/VoIP lifecycle handling.
- **Incremental Database Persistence:** Replace single-file `conversations.bin` JSON serialization with SQLite / GRDB to support large chat histories without disk I/O bottlenecks.
- **File Transfer Resumption:** Update `FileTransfer.swift` to track verified chunk offsets so interrupted file transfers resume where they left off.

### **P2 — Future Multi-Device & Group Features**
- **Decentralized Group Messaging:** Implement group key management or tree-based ratchets so group messages are not duplicated across $N$ individual sockets.
- **Multi-Radio BLE/AWDL Coexistence:** Use BLE for low-power peer presence beacons and dynamically spin up AWDL Wi-Fi only when high-bandwidth transfers occur.

### **P3 — Experimental & Research Directions**
- **Multi-Hop Mesh Routing:** Design a store-and-forward delay-tolerant overlay protocol with hop limits (TTL) and cryptographic packet routing.
- **Cross-Platform Android/Windows Transports:** Implement Wi-Fi Direct (Android) and Wi-Fi P2P (Windows) transport adapters.
