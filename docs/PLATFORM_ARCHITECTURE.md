# Platform Architecture & Portability Matrix

> **Document Type:** Cross-Platform Portability & System Constraints  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

---

## 1. Codebase Portability Classification

Every file in the repository is classified into four distinct portability tiers:

```
+-----------------------------------------------------------------------------------------+
| TIER 1: PLATFORM-INDEPENDENT CORE (Pure Swift / Standard Cryptography)                  |
|   • FrameCodec.swift     (Pure binary length-prefix encoding & decoding)                |
|   • ChatMessage.swift    (Codable domain models & serialization)                        |
|   • FileTransfer.swift   (Wire opcodes, sliding-window math, SHA-256 chunk logic)       |
+-----------------------------------------------------------------------------------------+
                                             │
+-----------------------------------------------------------------------------------------+
| TIER 2: APPLE ECOSYSTEM PORTABLE (macOS, iOS, iPadOS, watchOS, visionOS)                |
|   • CryptoSession.swift  (Apple CryptoKit: Curve25519, HKDF-SHA256, AES-GCM)            |
|   • MessageArchive.swift (Encrypted local storage via CryptoKit + Foundation)           |
|   • NetworkManager.swift (Apple Network.framework: NWListener, NWBrowser, NWConnection) |
|   • PeerConnection.swift (Apple Network.framework: TCP lifecycle + AWDL)                |
+-----------------------------------------------------------------------------------------+
                                             │
+-----------------------------------------------------------------------------------------+
| TIER 3: MACOS-SPECIFIC IMPLEMENTATIONS                                                  |
|   • IdentityStore.swift  (localComputerName() uses SCDynamicStoreCopyComputerName)      |
|   • ScreenGrab.swift     (AppKit, CoreGraphics CGDisplayCreateImage)                    |
|   • ContentView.swift    (NSWorkspace.shared.open, AppKit file drops)                   |
|   • BlueCommsApp.swift   (NSApp.setActivationPolicy, WindowGroup layout)                |
+-----------------------------------------------------------------------------------------+
                                             │
+-----------------------------------------------------------------------------------------+
| TIER 4: NON-PORTABLE PROTOCOL PREREQUISITES                                             |
|   • AWDL Radio Protocol  (Apple proprietary 802.11 peer-to-peer MAC driver)             |
|   • Package.swift        (macOS linker flags: -sectcreate __TEXT __info_plist)          |
+-----------------------------------------------------------------------------------------+
```

---

## 2. Portability Across Targets

| File / Component | Pure Swift / Linux | iOS / iPadOS | Android (NDK/Kotlin) | Windows (.NET/C++) | Reason / Dependency |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **`FrameCodec.swift`** | **100%** | **100%** | **100%** | **100%** | Pure algorithmic byte-level framing; zero OS dependencies. |
| **`ChatMessage.swift`** | **100%** | **100%** | **100%** | **100%** | Standard `Foundation.Codable` struct. |
| **`FileTransfer.swift`** | **100%** | **100%** | **100%** | **100%** | Protocol definitions, opcodes, and chunk serialization. |
| **`CryptoSession.swift`** | **Yes** (via Swift-Crypto) | **100%** | **Via libsodium/OpenSSL** | **Via BCrypt/OpenSSL** | Relies on `CryptoKit`. On Linux, `swift-crypto` drops in cleanly. |
| **`IdentityStore.swift`** | **Partial** | **95%** | **Rewrite needed** | **Rewrite needed** | POSIX file permissions work on Linux; `SCDynamicStore` requires fallback. |
| **`NetworkManager.swift`**| **No** | **100%** | **0% (Rewrite)** | **0% (Rewrite)** | Hardcoded to Apple `Network.framework` (`NWListener`, `NWBrowser`). |
| **`PeerConnection.swift`** | **No** | **100%** | **0% (Rewrite)** | **0% (Rewrite)** | Hardcoded to Apple `NWConnection`. |
| **`ScreenGrab.swift`** | **No** | **0%** | **0%** | **0%** | Relies on macOS `CoreGraphics` display capture APIs. |

---

## 3. The Cross-Platform Architectural Dilemma

### Scenario A: Mac $\longleftrightarrow$ iPhone (Apple Ecosystem)
Both devices use Apple's native network stack.

```
       Mac (macOS 14+)                          iPhone (iOS 17+)
+----------------------------+            +----------------------------+
| BlueComms Mac App (SwiftUI)|            | BlueComms iOS App (SwiftUI)|
+----------------------------+            +----------------------------+
              │                                         │
              ▼                                         ▼
+----------------------------+            +----------------------------+
|      BlueCommsCore         |            |      BlueCommsCore         |
| (NetworkManager, Crypto)   |            | (NetworkManager, Crypto)   |
+----------------------------+            +----------------------------+
              │                                         │
              ▼                                         ▼
+----------------------------+            +----------------------------+
| Apple Network.framework    |            | Apple Network.framework    |
+----------------------------+            +----------------------------+
              │                                         │
              ▼                                         ▼
+----------------------------+            +----------------------------+
| Apple AWDL / Bonjour Radio | <========> | Apple AWDL / Bonjour Radio |
+----------------------------+            +----------------------------+
```

- **Outcome:** **Flawless interoperability.** Both share the exact same `BlueCommsCore` code, Bonjour service type `_bluecomms._tcp`, and AWDL radio channels.

---

### Scenario B: Mac $\longleftrightarrow$ Android / Windows (Cross-Platform)
Android and Windows **do not have AWDL** and **do not have Network.framework**.

```
       Mac (macOS 14+)                              Android / Windows
+----------------------------+            +------------------------------------+
| BlueComms Mac App (SwiftUI)|            | BlueComms Android App (Compose/C++)|
+----------------------------+            +------------------------------------+
              │                                         │
              ▼                                         ▼
+----------------------------+            +------------------------------------+
|      BlueCommsCore         |            |     BlueComms Core (Abstract)      |
| (Hardcoded Network.fw)     |            | (FrameCodec, ChatMessage, Crypto)  |
+----------------------------+            +------------------------------------+
              │                                         │
              ▼                                         ▼
+----------------------------+            +------------------------------------+
| Apple Network.framework    |            | Android Wi-Fi Direct / Windows P2P |
+----------------------------+            +------------------------------------+
              │                                         │
              ▼                                         ▼
+----------------------------+            +------------------------------------+
|   AWDL Radio (Proprietary) |    XXXX    | Standard Wi-Fi Direct (Incompatible)|
+----------------------------+            +------------------------------------+
```

### Why the Current Architecture Fails Cross-Platform:
1. **Lack of Transport Abstraction:** `NetworkManager` is not a protocol interface; it is a concrete class directly importing `Network`.
2. **Physical Radio Layer Incompatibility:** AWDL frames cannot be decoded by Android Wi-Fi chips in ad-hoc mode. For a Mac to communicate with an Android device offline, both must either:
   - Connect to the same Wi-Fi router/AP, or
   - One device must host a standard Wi-Fi SoftAP (Hotspot) which the other joins.
