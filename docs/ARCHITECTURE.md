# Architecture & System Design Analysis

> **Document Type:** System Architecture & Scalability Assessment  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

---

## 1. The Actual Architectural Pattern Present in BlueComms

Rather than imposing theoretical buzzwords ("Clean Architecture", "Hexagonal Architecture", or "Pure VIPER"), an empirical inspection of the code reveals that BlueComms currently follows an **Actor-Isolated Store / Orchestrator Pattern with Direct Hardware Coupling**.

```
+-----------------------------------------------------------------------------------------+
| PRESENTATION LAYER (macOS App & Terminal CLI)                                           |
|   • ContentView.swift, SidebarView, ChatView, MessageBubble (SwiftUI declarative views) |
|   • BlueCommsCLI/main.swift (Terminal loop + CLI verb parser)                           |
+-----------------------------------------------------------------------------------------+
                                      │ (Observes / Calls)
                                      ▼
+-----------------------------------------------------------------------------------------+
| APPLICATION STATE LAYER (@MainActor ObservableObject)                                   |
|   • ChatStore.swift                                                                     |
|     - Central state machine for UI, drafts, thread selection, presence, and status      |
|     - Bridges background network callbacks to UI thread via Task { @MainActor }         |
+-----------------------------------------------------------------------------------------+
                    │                                             │
                    ▼ (Persists)                                  ▼ (Orchestrates)
+----------------------------------------+   +--------------------------------------------+
| PERSISTENCE LAYER                      |   | DOMAIN & NETWORKING COORDINATOR            |
|   • MessageArchive.swift (AES-GCM bin) |   |   • NetworkManager.swift (Serial Queue)    |
|   • IdentityStore.swift (TOFU + Keys)  |   |     - Bonjour listener/browser lifecycle   |
+----------------------------------------+   |     - Active session registry & routing    |
                                             +--------------------------------------------+
                                                                  │ (Owns)
                                                                  ▼
                                             +--------------------------------------------+
                                             | SESSION & WIRE LAYER                       |
                                             |   • PeerConnection.swift (Per-peer TCP)    |
                                             |   • CryptoSession.swift (X25519 / AES-GCM) |
                                             |   • FrameCodec.swift (4-byte length prefix)|
                                             |   • FileTransfer.swift (Chunk/Window FSM)  |
                                             +--------------------------------------------+
                                                                  │ (Direct Dependency)
                                                                  ▼
                                             +--------------------------------------------+
                                             | HARDWARE / PLATFORM INFRASTRUCTURE         |
                                             |   • Apple Network.framework (AWDL, TCP)    |
                                             |   • Apple CryptoKit (Curve25519, AES)      |
                                             |   • macOS SystemConfiguration (SCDynamic)  |
                                             +--------------------------------------------+
```

---

## 2. Layer Analysis & Dependency Directions

### 1. Presentation Layer
- **Components:** `ContentView.swift`, `SidebarView`, `ChatView`, `MessageBubble`, `BlueCommsCLI/main.swift`.
- **Dependency Direction:** Depends strictly downwards on `ChatStore` (for App) or `NetworkManager` (for CLI).
- **Separation of Concerns:** High. The UI views contain zero networking logic, zero socket calls, and zero cryptographic operations.

### 2. Application State Layer (`ChatStore`)
- **Components:** `ChatStore.swift`.
- **Role:** Owns UI state, selected conversation, presence list, outbox queue flushing, and background-to-foreground thread synchronization.
- **Coupling:** Strongly coupled to `NetworkManager` and `MessageArchive`.

### 3. Domain & Networking Coordinator (`NetworkManager`)
- **Components:** `NetworkManager.swift`.
- **Role:** Serializes all networking mutations on a private `DispatchQueue`. Manages the discovery of peers, dynamic port binding, inbound connection dispatching, and session lifetime.
- **Coupling:** Directly coupled to Apple's `NWListener`, `NWBrowser`, and `NWParameters`.

### 4. Wire & Protocol Layer (`PeerConnection`, `CryptoSession`, `FrameCodec`, `FileTransfer`)
- **Components:** `PeerConnection.swift`, `CryptoSession.swift`, `FrameCodec.swift`, `FileTransfer.swift`.
- **Role:** Handles length-prefixed framing, cryptographic handshakes, stream reassembly, sliding-window chunk transfers, and SHA-256 validation.
- **Coupling:** `CryptoSession` and `FrameCodec` are clean, decoupled value types that depend only on `CryptoKit` and `Foundation`. However, `PeerConnection` is directly tied to `NWConnection`.

---

## 3. Scalability Evaluation: Can This Architecture Scale?

Let us evaluate how well the current architecture accommodates future expansion across several dimensions:

### 1. Multi-Platform Support (iOS, iPadOS)
- **Status:** **Ready with minimal friction.**
- **Why:** iOS fully supports `Network.framework`, `CryptoKit`, `SwiftUI`, and `AWDL` (`includePeerToPeer`).
- **Required Changes:** Update `Info.plist` with iOS local network permission strings and replace AppKit-specific helpers (`NSWorkspace.open`, `CGDisplayCreateImage`) with UIKit equivalents.

### 2. Non-Apple Platforms (Android, Windows, Linux)
- **Status:** **Requires significant architectural refactoring.**
- **Why:**
  1. `NetworkManager` and `PeerConnection` are hardcoded to Apple's `Network.framework` APIs (`NWListener`, `NWBrowser`, `NWConnection`).
  2. `AWDL` is an Apple-proprietary radio protocol unavailable on Android/Windows.
  3. `localComputerName()` relies on macOS `SystemConfiguration.framework`.
- **What is Needed:** Introduce a transport abstraction protocol (e.g. `TransportListener`, `TransportBrowser`, `TransportStream`) so Android can plug in Wi-Fi Direct and Windows can plug in Wi-Fi P2P.

### 3. Multiple Transports (BLE + Wi-Fi Coexistence)
- **Status:** **Moderately difficult under current design.**
- **Why:** Currently, `NetworkManager` assumes one transport (TCP over Bonjour/AWDL). If BLE is added, `NetworkManager` would need to manage multiple transport paths per peer, dynamic link switching, and MTU-aware payload routing.

### 4. Group Messaging (Broadcast / Multicast)
- **Status:** **Partially supported via star topology; not true broadcast.**
- **Why:** Because `NetworkManager` manages multiple 1-to-1 `PeerConnection` sessions, sending a group message currently requires looping over all active sessions and encrypting/sending the message $N$ times. True group messaging with decentralized ratchet trees (MLS) is not yet present.

### 5. Future Mesh Routing (Multi-Hop)
- **Status:** **Major architectural extension required.**
- **Why:**
  1. `PeerConnection` delivers incoming messages directly to `ChatStore` assuming the immediate sender is the ultimate destination.
  2. To support multi-hop mesh, an intermediate **Routing / Forwarding Engine** must sit between `FrameDecoder` and `CryptoSession` to inspect a packet's destination UUID and forward it to another peer if it is not addressed to the local machine.
