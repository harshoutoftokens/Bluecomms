# Developer Knowledge Check: Self-Test

> **Document Type:** Developer Self-Assessment & Knowledge Verification  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

After reading the BlueComms engineering documentation, you should be able to answer every question in this self-test. The questions are ordered by difficulty from beginner to advanced.

---

## Part 1: Beginner Questions (Core Concepts)

1. What fundamental real-world problem does BlueComms solve?
2. Does BlueComms require an active internet connection, cellular service, or a shared Wi-Fi router?
3. What is the role of Bonjour (mDNS / DNS-SD) in BlueComms?
4. What is Apple's `Network.framework`, and which legacy API did it replace?
5. What does `NWListener` do in this codebase?
6. What does `NWBrowser` do in this codebase?
7. What does `NWConnection` represent?
8. What is the service type string advertised and browsed by BlueComms?
9. What service domain does BlueComms use, and why is `nil` avoided?
10. Where does BlueComms persist a device’s identity, cryptographic keys, and chat history on macOS?
11. What algorithm is used to encrypt chat history in `~/.bluecomms/conversations.bin`?
12. Why is `SCDynamicStoreCopyComputerName` used instead of `Host.current().localizedName`?
13. What is the default directory where received files are saved on disk?

---

## Part 2: Intermediate Questions (Protocols, Framing & Wire Formats)

14. Why is a Swift `String` not the same thing as a stream of bytes over a network socket?
15. Why is the assumption `"one send() call equals one receive() callback"` false when using TCP?
16. How does `FrameCodec` solve the TCP stream fragmentation problem?
17. What is the exact binary header prepended to every frame in BlueComms?
18. What is the maximum allowed payload size per frame, and why does this cap exist?
19. What are the three `WireType` opcodes defined in `CryptoSession.swift`, and what does each represent?
20. What is contained in the 49-byte `HandshakePayload` sent when a connection first opens?
21. What elliptic curve algorithm is used for peer-to-peer key agreement in `CryptoSession`?
22. How do two devices derive identical symmetric keys using HKDF-SHA256 without extra round-trip negotiations?
23. What security model does `IdentityStore` implement when verifying peer public keys?
24. What happens if a peer with a known UUID presents a different public key upon reconnecting?
25. Why must `isComplete: false` always be passed when calling `NWConnection.send()`?
26. How does `PeerConnection.receiveLoop()` ensure it does not miss incoming TCP data?
27. What chunk size and sliding window size are used for file transfers in `FileTransfer.swift`?
28. How does the receiver verify that a downloaded file was not corrupted in transit?
29. How does `FileTransfer.sanitizeFileName` prevent path traversal attacks?

---

## 3. Advanced Questions (Architecture, Concurrency & Systems)

30. What does `NWParameters.includePeerToPeer = true` actually instruct macOS to do?
31. What is AWDL (Apple Wireless Direct Link), and how does it relate to AirDrop?
32. Why is BlueComms unencrypted at the transport level (raw TCP) but encrypted at the application level?
33. Why isn't standard TLS 1.3 with certificate validation used in BlueComms?
34. On which thread / queue does `NetworkManager` execute its operations, and how does it prevent deadlocks?
35. How does `ChatStore` bridge background networking callbacks onto the main UI thread?
36. What happens if two Macs click "Connect" to each other at the exact same millisecond? How is the race condition resolved?
37. What happens if a user types and sends a message while the remote peer is offline?
38. Why does `Package.swift` contain `-sectcreate __TEXT __info_plist` linker flags?
39. What is the difference between "code correctness" and "OS network authorization" on macOS 14+ / iOS 14+?
40. Why doesn't having direct peer-to-peer TCP automatically create a mesh network?
41. What is the difference between direct peer-to-peer, multi-device chat, relay communication, store-and-forward, and a mesh?
42. Why is Bluetooth Low Energy (BLE) not suitable as the primary transport for gigabyte file transfers?
43. What architectural refactoring would be required to make BlueComms run on Android and Windows?
44. Does BlueComms currently provide ephemeral Forward Secrecy? Why or why not?
45. How does `NetworkManager` handle crashes or unexpected closures of the listener or browser?
