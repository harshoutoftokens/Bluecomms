# Concurrency, Threading & Asynchronous Architecture

> **Document Type:** Concurrency & Thread Synchronization Deep Dive  
> **Repository Path:** [BlueCommsCore/NetworkManager.swift](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift) & [BlueCommsApp/ChatStore.swift](../BlueCommsCLI/Sources/BlueCommsApp/ChatStore.swift)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

---

## 1. Why Networking Cannot Be Synchronous

In classical, naive programming tutorials, networking is often demonstrated as linear synchronous code:
```swift
// NAIVE SYNCHRONOUS CODE (WILL FREEZE APPS AND CRASH):
let socket = connect("192.168.1.5", 8080) // Blocks thread for 2-5 seconds
socket.send("hello")                      // Blocks until buffer flushes
let response = socket.receive()           // Blocks indefinitely waiting for bytes
```

### Why this is impossible in production P2P applications:
1. **The Radio is Asynchronous:** Bringing up an ad-hoc AWDL radio link involves RF channel negotiation, beacon alignment, and cryptographic handshakes taking hundreds of milliseconds to seconds.
2. **Main Thread Deadlock:** If synchronous network calls run on the main UI thread, macOS beachballs, the UI freezes, and the OS watchdog terminates the process.
3. **Unsolicited Inbound Events:** Incoming connections, peer walk-aways, and incoming messages arrive at random, non-deterministic intervals.

---

## 2. Concurrency Architecture in BlueComms

BlueComms employs a **two-tier concurrency model**:
1. **UI & State Tier:** Swift Concurrency `@MainActor` in `ChatStore.swift`.
2. **Networking Tier:** Dedicated Serial Grand Central Dispatch queue (`DispatchQueue(label: "bluecomms.network")`) in `NetworkManager.swift` and `PeerConnection.swift`.

```
+-----------------------------------------------------------------------------------------+
| MAIN THREAD / @MainActor                                                                |
|   • ChatStore.swift (State Machine, @Published properties, UI Binding)                  |
|   • ContentView.swift & SwiftUI View Hierarchy                                          |
+-----------------------------------------------------------------------------------------+
                     ▲                                             │
                     │ Task { @MainActor in ... }                  │ manager.send() / connect()
                     │ (Dispatches UI updates)                     │ (Hops to queue)
                     │                                             ▼
+-----------------------------------------------------------------------------------------+
| SERIAL DISPATCH QUEUE: "bluecomms.network"                                              |
|   • NetworkManager.swift (Registry mutation, Listener/Browser lifecycle)               |
|   • PeerConnection.swift (Frame decoding, CryptoSession, Outbound queuing)             |
|   • Network.framework callbacks (stateUpdateHandler, receive callback)                  |
+-----------------------------------------------------------------------------------------+
```

---

## 3. Queue Synchronization & Deadlock Prevention

In [NetworkManager.swift:L41-L42](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L41-L42) and [L546-L560](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L546-L560), BlueComms prevents queue re-entrancy deadlocks using `DispatchSpecificKey`:

```swift
private let queueKey = DispatchSpecificKey<UInt8>()

// In init():
queue.setSpecific(key: queueKey, value: 1)

// Helper methods:
private func onQueueAsync(_ body: @escaping @Sendable () -> Void) {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
        body() // Already on network queue; execute immediately
    } else {
        queue.async(execute: body) // Off queue; hop asynchronously
    }
}

private func onQueueSync<T>(_ body: () -> T) -> T {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
        return body() // Avoid recursive queue.sync deadlock
    }
    return queue.sync(execute: body)
}
```

### What this achieves:
- **Thread Safety:** Every mutation of `sessions`, `pending`, `discoveredByID`, and `lastSeenAt` occurs strictly on the serial `bluecomms.network` queue.
- **Deadlock Immunity:** If a method already running on the network queue calls another helper that requests queue isolation, `DispatchQueue.getSpecific` detects it and executes inline, preventing thread lockups.

---

## 4. Race Condition Defenses

### 1. Simultaneous Inbound & Outbound Connections
If Alice clicks "Connect" to Bob at the exact same microsecond Bob clicks "Connect" to Alice, two distinct `NWConnection` sockets are opened.
- **How Handled ([NetworkManager.swift:L391-L397](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L391-L397)):** Both connections live in `pending` until their cryptographic handshakes finish. Whichever handshake finishes first registers in `sessions[key]`. When the second handshake completes, it gracefully cancels the duplicate older session.

### 2. Typing While Disconnected (Outbox Queue)
If the user types a message while the connection is still in `.preparing` or offline:
- **How Handled ([PeerConnection.swift:L85-L96](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift#L85-L96)):** Messages are buffered in `outboundQueue: [String]` (capped at 32 items).
- When the handshake completes and `isReadyForMessages` becomes `true`, `flushOutboundQueue()` automatically encrypts and transmits the backlog in order.
