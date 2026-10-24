# Proof & Verification Audit: What Has Actually Been Proven?

> **Document Type:** Verification & Empirical Proof Audit  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

This document provides a strict, evidence-grounded assessment of which features in BlueComms are mathematically or empirically proven, which are partially tested, and which remain unproven or unimplemented.

---

## 1. Classification Definitions

- **PROVEN:** Verified by automated unit/integration tests in the repository (`BlueCommsSelfTest`) or confirmed operational across physical machines with reproducible evidence.
- **PARTIALLY PROVEN:** Working in single-process loopback simulations or local subnet environments, but possessing known constraints or unverified edge cases in production.
- **NOT YET PROVEN:** Supported theoretically by the underlying operating system APIs, but not yet tested or verified across physical target devices in this repository.
- **UNKNOWN / UNIMPLEMENTED:** Not present in the codebase; theoretical future concept only.

---

## 2. Comprehensive Capability Matrix

| Feature / Capability | Classification | Empirical Evidence in Repository | Notes & Caveats |
| :--- | :---: | :--- | :--- |
| **Binary Framing & Reassembly** | **PROVEN** | `testFrameRoundTrip`, `testTwoFramesInOneChunk`, `testSplitPayloadAcrossChunks` | Verified across partial, split, and coalesced chunks. |
| **X25519 + AES-GCM Crypto** | **PROVEN** | `testHandshakeRoundTrip`, `testMultipleMessagesDecrypt`, `testFramedCiphertextRoundTrip` | Verified bidirectional encryption, key agreement, and tag validation. |
| **Trust-On-First-Use (TOFU)** | **PROVEN** | `testTOFURemembersThenMatches`, `testTOFUMismatch` | Verified key pinning and mismatch rejection in `IdentityStore`. |
| **Encrypted Disk History** | **PROVEN** | `testArchiveRoundTrip`, `testArchiveWrongKey` | Verified AES-GCM persistence of conversation threads. |
| **Chunked File Streaming** | **PROVEN** | `testFileStreamReassembles`, `testFileOfferRoundTrip` | Verified 256 KB chunking, sliding window, and SHA-256 integrity. |
| **In-Process Discovery & Transfer** | **PROVEN** | `testTwoPeersSendFile` (32nd test case in `BlueCommsSelfTest`) | Two distinct `NetworkManager` instances discover and transfer files over dynamic ports. |
| **Mac $\longleftrightarrow$ Mac Local Wi-Fi** | **PROVEN** | Manual testing, screenshots in `docs/screenshots/` | Confirmed working across Macs connected to a shared local Wi-Fi AP. |
| **Mac $\longleftrightarrow$ Mac Offline AWDL** | **PARTIALLY PROVEN** | `includePeerToPeer = true` enabled; screenshots and video in `docs/screenshots/` | Requires AirDrop-compatible hardware; sensitive to local RF interference and VPNs. |
| **Simultaneous Multi-Peer Chat** | **PARTIALLY PROVEN** | `NetworkManager.sessions` dictionary supports $N$ connections; UI displays sidebar list | Verified in code architecture; stress tested up to small peer counts. |
| **Mac $\longleftrightarrow$ iPhone Chat** | **NOT YET PROVEN** | No iOS target or Xcode iOS build scheme in current `Package.swift` | Network stack is identical, but needs iOS bundle target and testing on real iOS hardware. |
| **iPhone $\longleftrightarrow$ iPhone Chat** | **NOT YET PROVEN** | No iOS app target implemented | Architecturally supported by `Network.framework`, but untested in this repo. |
| **iOS Background Operation** | **NOT YET PROVEN** | No Background Modes entitlements or VoIP push handlers | iOS aggressively suspends background sockets after ~30 seconds. |
| **Android Interoperability** | **UNKNOWN** | **0% implemented** in repository | AWDL is Apple-only; requires separate Wi-Fi Direct transport. |
| **Windows Interoperability** | **UNKNOWN** | **0% implemented** in repository | AWDL is Apple-only; requires separate Wi-Fi P2P transport. |
| **Multi-Hop Mesh Routing** | **UNKNOWN** | **0% implemented** in repository | Code is strictly point-to-point (1-to-1 direct sockets). |
| **Decentralized Group Chat (MLS)** | **UNKNOWN** | **0% implemented** in repository | Group chat currently uses $N$ individual 1-to-1 encrypted sockets. |

---

## 3. Summary of Automated Test Coverage

The repository includes a dedicated test runner ([BlueCommsSelfTest/main.swift](../BlueCommsCLI/Sources/BlueCommsSelfTest/main.swift)) executing **32 automated test cases**:

```
[32 / 32 Passed]
ok   frame round trip
ok   two frames in one chunk
ok   split header then payload
ok   split payload across chunks
ok   empty payload
ok   max frame size accepted
ok   encode rejects oversized payload
ok   decode rejects oversized declared length
ok   trailing partial frame stays buffered
ok   crypto handshake round trip
ok   multiple messages decrypt
ok   same key rejected
ok   invalid public key rejected
ok   seal before establish fails
ok   handshake payload round trip
ok   handshake rejects unsupported protocol
ok   fingerprint is stable
ok   identity load is stable
ok   tofu remembers then matches
ok   tofu mismatch
ok   computer name is non-empty
ok   bonjour name respects byte limit
ok   framed ciphertext round trip
ok   archive round trip
ok   archive empty load
ok   archive rejects wrong key
ok   file offer round trip
ok   file chunk round trip
ok   file name sanitizes slashes
ok   file offer rejects huge size
ok   file stream reassembles with matching hash
ok   two local peers discover and send a file
```
