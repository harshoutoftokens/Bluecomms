# Code to Concept Cross-Reference Map

> **Document Type:** Symbol-to-Concept Traceability Matrix  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

This document maps every major Swift type, class, function, and configuration in the BlueComms codebase to its corresponding networking and architectural concept.

---

## 1. Traceability Matrix

| Code Symbol / File | Architectural Concept | Implementation Details in BlueComms |
| :--- | :--- | :--- |
| **`NWListener`** ([NetworkManager.swift:L46](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L46)) | **Service Advertising & Inbound Socket Binding** | Binds dynamic TCP port, registers `_bluecomms._tcp.local.` with `mDNSResponder`, and accepts connections. |
| **`NWBrowser`** ([NetworkManager.swift:L47](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L47)) | **Service Discovery (DNS-SD Scanner)** | Queries local mDNS for `_bluecomms._tcp`, extracts TXT record metadata (`id`, `proto`, `name`). |
| **`includePeerToPeer = true`** ([NetworkManager.swift:L541](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L541)) | **Apple Wireless Direct Link (AWDL)** | Enables Apple ad-hoc 802.11 peer-to-peer Wi-Fi interface (AirDrop-class radio) without an internet router. |
| **`DiscoveredPeer`** ([NetworkManager.swift:L25](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L25)) | **Service Endpoint Descriptor** | Encapsulates remote device UUID, human-readable display name, and `NWEndpoint` for connection routing. |
| **`PeerConnection`** ([PeerConnection.swift:L22](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift#L22)) | **Session Controller & FSM** | Manages `NWConnection` state transitions, handshake timers, receive loops, outbound queuing, and file transfers. |
| **`CryptoSession`** ([CryptoSession.swift:L68](../BlueCommsCLI/Sources/BlueCommsCore/CryptoSession.swift#L68)) | **Authenticated Cryptographic Session** | Implements X25519 ECDH key agreement, HKDF-SHA256 directional key derivation, and AES-GCM-256 authenticated encryption. |
| **`HandshakePayload`** ([CryptoSession.swift:L36](../BlueCommsCLI/Sources/BlueCommsCore/CryptoSession.swift#L36)) | **Zero-Round-Trip Handshake Frame** | 49-byte fixed payload: `[1B proto] + [16B device UUID] + [32B Curve25519 public key]`. |
| **`FrameCodec`** ([FrameCodec.swift:L20](../BlueCommsCLI/Sources/BlueCommsCore/FrameCodec.swift#L20)) | **Stream Framing (Length Prefix)** | Encodes 4-byte big-endian UInt32 length prefix before payloads to delineate stream boundaries (max 512 KB). |
| **`FrameDecoder`** ([FrameCodec.swift:L44](../BlueCommsCLI/Sources/BlueCommsCore/FrameCodec.swift#L44)) | **Stream Reassembly Buffer** | Accumulates incoming TCP fragments, extracts complete frames, and retains leftover partial bytes. |
| **`WireType`** ([CryptoSession.swift:L20](../BlueCommsCLI/Sources/BlueCommsCore/CryptoSession.swift#L20)) | **Wire Protocol Multiplexer** | 1-byte opcode distinguishing: `0x01` (Handshake), `0x02` (Chat Text), `0x03` (File Transfer). |
| **`FileMessage`** ([FileTransfer.swift:L78](../BlueCommsCLI/Sources/BlueCommsCore/FileTransfer.swift#L78)) | **Chunked File Transfer Protocol** | Opcodes for `offer`, `accept`, `chunk` (256 KB), `ack`, `complete` (SHA-256), `reject`, `cancel`. |
| **`IdentityStore`** ([IdentityStore.swift:L70](../BlueCommsCLI/Sources/BlueCommsCore/IdentityStore.swift#L70)) | **Identity & Key Pinning (TOFU)** | Stores long-term UUID, private key in `~/.bluecomms/`, and pins peer public keys in `known-peers.json`. |
| **`MessageArchive`** ([MessageArchive.swift:L16](../BlueCommsCLI/Sources/BlueCommsCore/MessageArchive.swift#L16)) | **Encrypted Local Persistence** | Encrypts conversation history using AES-GCM-256 to `~/.bluecomms/conversations.bin`. |
| **`ChatStore`** ([ChatStore.swift:L26](../BlueCommsCLI/Sources/BlueCommsApp/ChatStore.swift#L26)) | **Application State Store** | `@MainActor ObservableObject` managing SwiftUI state, thread selection, draft composer, and presence. |
| **`isComplete: false`** ([PeerConnection.swift:L266](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift#L266)) | **TCP FIN Suppression** | Keeps bidirectional TCP socket open after sending a frame; prevents kernel from closing stream. |
| **`sanitizeFileName`** ([FileTransfer.swift:L177](../BlueCommsCLI/Sources/BlueCommsCore/FileTransfer.swift#L177)) | **Path Traversal Defense** | Strips `/` and `:` from remote filenames to confine file writes strictly to `~/Downloads/BlueComms/`. |
| **`-sectcreate __TEXT __info_plist`** ([Package.swift:L38](../BlueCommsCLI/Package.swift#L38)) | **Mach-O Entitlement Embedding** | Injects `Info.plist` into standalone CLI executables so macOS grants Local Network & Bonjour permissions. |
