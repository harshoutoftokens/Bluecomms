# BlueComms Engineering & Architecture Documentation

> **Welcome to the BlueComms Developer Deep Dive.**  
> This directory contains a comprehensive technical audit, architectural blueprint, and developer learning guide for the BlueComms codebase.

---

## 1. Executive Overview

### What is BlueComms?
**BlueComms** is an offline, peer-to-peer messaging and file transfer application for macOS. It enables nearby devices to discover each other, establish direct encrypted connections, chat, and stream gigabyte-sized files **without internet access, cellular networks, or shared Wi-Fi routers**.

### How Does It Work Today?
1. **Radio Layer:** Utilizes Apple Wireless Direct Link (AWDL)—the same ad-hoc 802.11 Wi-Fi radio protocol that powers Apple AirDrop.
2. **Discovery:** Advertises and scans for the Bonjour service `_bluecomms._tcp` in domain `local.` using DNS-SD TXT records.
3. **Transport:** Establishes direct bidirectional TCP connections using Apple’s modern `Network.framework` (`NWListener`, `NWBrowser`, `NWConnection`).
4. **Security:** Implements application-layer authenticated encryption using Curve25519 (X25519) key agreement, HKDF-SHA256 directional key derivation, and AES-GCM-256 with Trust-On-First-Use (TOFU) key pinning.
5. **Framing & Streaming:** Employs a 4-byte big-endian length prefix to eliminate TCP stream fragmentation, streaming files in 256 KB chunks with a sliding window of 8 in-flight chunks and full SHA-256 checksum verification.

---

## 2. Documentation Sitemap & Recommended Reading Order

To master the codebase from first principles to low-level byte manipulation, read the documentation in this exact order:

```
 1. docs/README.md ───────────────────────► [You Are Here: Entry Point]
 2. docs/BLUECOMMS_UNDER_THE_HOOD.md ─────► Real-Life vs. Network-Level Deep Dive
 3. docs/ARCHITECTURE.md ─────────────────► Layering, Coupling & Scalability
 4. docs/ARCHITECTURE_DECISIONS.md ───────► The "WHY" Behind Every Tech Choice & Alternative
 5. docs/NETWORKING_DEEP_DIVE.md ─────────► Network.framework, AWDL, Bonjour & Sockets
 6. docs/DATA_FLOW_AND_PACKETS.md ────────► Wire Formats, Framing & Packet Lifecycles
 7. docs/RUNTIME_FLOW.md ─────────────────► Sequence Diagrams for All 10 System Flows
 8. docs/CODE_WALKTHROUGH.md ─────────────► Component & State Ownership Walkthrough
 9. docs/CONCURRENCY.md ──────────────────► Threads, Queues, Deadlock Prevention & Races
10. docs/DEBUGGING_GUIDE.md ──────────────► Diagnostic CLI Tools & Decision Trees
11. docs/FAILURE_MODES.md ────────────────► Error Matrix, Recovery & Failure Scenarios
12. docs/PLATFORM_ARCHITECTURE.md ────────► macOS vs iOS vs Android vs Windows Portability
13. docs/FUTURE_NETWORKING.md ────────────► Evolving from Point-to-Point to Multi-Hop Mesh
14. docs/SECURITY.md ─────────────────────► Threat Model, Crypto Primitives & MITM Analysis
15. docs/GLOSSARY.md ─────────────────────► Plain English & Technical Networking Definitions
16. docs/REBUILD_FROM_SCRATCH.md ────────► 15-Step Blueprint: Building BlueComms Yourself
17. docs/DEVELOPER_KNOWLEDGE_CHECK.md ────► 45 Self-Test Questions (Beginner to Advanced)
18. docs/TECHNICAL_AUDIT.md ─────────────► Final Audit, Risks & Prioritized P0-P3 Roadmap
19. docs/CODE_TO_CONCEPT_MAP.md ──────────► Code Symbol Traceability Reference
```

---

## 3. Quick Reference: Core Components & Source Files

| Source File | Role & Architectural Scope |
| :--- | :--- |
| **[Package.swift](../BlueCommsCLI/Package.swift)** | SwiftPM manifest linking Info.plist into binaries via Mach-O `-sectcreate` flags. |
| **[NetworkManager.swift](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift)** | Central networking coordinator managing Bonjour discovery, dynamic ports, and active sessions on a serial queue. |
| **[PeerConnection.swift](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift)** | Owns a single `NWConnection` TCP session, orchestrates the crypto handshake, receive loops, and file transfers. |
| **[CryptoSession.swift](../BlueCommsCLI/Sources/BlueCommsCore/CryptoSession.swift)** | X25519 ECDH key agreement, HKDF key derivation, and AES-GCM-256 authenticated encryption. |
| **[FrameCodec.swift](../BlueCommsCLI/Sources/BlueCommsCore/FrameCodec.swift)** | 4-byte big-endian binary framing and stream reassembly buffer (`FrameDecoder`). |
| **[FileTransfer.swift](../BlueCommsCLI/Sources/BlueCommsCore/FileTransfer.swift)** | Chunked sliding-window file streaming protocol, opcodes, and SHA-256 integrity hashing. |
| **[IdentityStore.swift](../BlueCommsCLI/Sources/BlueCommsCore/IdentityStore.swift)** | Persistent device UUID, private key storage in `~/.bluecomms/`, and TOFU key pinning. |
| **[MessageArchive.swift](../BlueCommsCLI/Sources/BlueCommsCore/MessageArchive.swift)** | Encrypted local conversation history stored in `~/.bluecomms/conversations.bin`. |
| **[ChatStore.swift](../BlueCommsCLI/Sources/BlueCommsApp/ChatStore.swift)** | `@MainActor ObservableObject` driving SwiftUI state, thread selection, drafts, and presence. |
| **[ContentView.swift](../BlueCommsCLI/Sources/BlueCommsApp/ContentView.swift)** | Declarative SwiftUI user interface for the macOS desktop application. |
| **[BlueCommsSelfTest/main.swift](../BlueCommsCLI/Sources/BlueCommsSelfTest/main.swift)** | 32 automated in-process unit and integration tests. |
