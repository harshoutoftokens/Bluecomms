# Failure Modes & Resilience Analysis

> **Document Type:** Error Handling & Failure Matrix  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

---

## 1. Comprehensive Failure Modes Matrix

| Failure Mode | User Symptom | Root Cause | Code Detection Point | Handled Correctly? |
| :--- | :--- | :--- | :--- | :---: |
| **Local Network Permission Denied** | "No peers yet" in sidebar permanently. | User clicked "Don't Allow" on system prompt. | `NWListener` / `NWBrowser` state transitions to `.waiting(POSIXError.EPERM)`. | **Yes** (Logs advisory to check System Settings). |
| **Wi-Fi Radio Switched Off** | Sidebar clears; cannot connect. | User toggled Wi-Fi off in Control Center. | `NWBrowser.browseResultsChangedHandler` receives empty set; sockets reset. | **Yes** (Peers marked offline with last-seen timestamps). |
| **Handshake Timeout (10s)** | Connect button spins for 10s then returns to Idle. | Peer socket opened but remote device hung before sending public key. | `scheduleHandshakeTimeout()` DispatchWorkItem fires in `PeerConnection.swift`. | **Yes** (Connection cancelled, pending map cleaned). |
| **TOFU Key Mismatch (MITM / Key Reset)** | Connection immediately drops with security log. | Peer UUID has a different public key than stored in `known-peers.json`. | `IdentityStore.verifyOrRemember()` throws `CryptoError.tofuMismatch`. | **Yes** (Connection severed immediately to prevent MITM). |
| **Stream Drop Mid-Message** | Message remains in outbox or fails to deliver. | Peer walked out of radio range or closed laptop lid during TCP send. | `NWConnection.receive` returns `isComplete: true` or POSIX error (`ECONNRESET`). | **Yes** (Socket cleaned up, session removed, reconnect allowed). |
| **Stream Drop Mid-File Transfer** | Progress bar stops, status shows "Transfer failed". | Connection severed while transferring a large file. | `FileHandle` throws or socket closes; `failIncoming()` / `failOutgoing()` fires. | **Yes** (Temporary `.part` file deleted on receiver; sender resets). |
| **File Checksum Corruption** | Progress hits 100% then displays "Checksum failed". | Bit flip or corrupted chunk received over the wire. | Receiver compares `SHA256(receivedBytes)` to sender's `digest` in `complete` frame. | **Yes** (Corrupted file deleted; never moved to Downloads). |
| **Directory Write Permission Error** | Status shows "Could not create inbox file". | `~/Downloads/BlueComms` not writable. | `FileManager.createDirectory` throws in `acceptIncoming()`. | **Yes** (Sends `reject` frame to peer with error log). |
| **Oversized Frame Attack (>512 KB)** | Connection instantly dropped. | Malicious peer transmitted a length prefix claiming $>512\text{ KB}$. | `FrameDecoder.append()` detects `length > maxPayloadSize` and throws. | **Yes** (Buffer purged, socket closed to prevent memory exhaustion). |
| **Malformed / Invalid UTF-8 Text** | Nothing appears in remote thread; log warning. | Received bytes cannot be decoded into a valid Swift `String`. | `String(data: plaintext, encoding: .utf8)` returns `nil`. | **Yes** (Logs `Dropped a message that was not valid UTF-8`). |
| **Simultaneous Bidirectional Connect** | Both Macs connect smoothly without duplicate threads. | Both users clicked "Connect" at the same time. | Whichever handshake completes second cancels the duplicate older session in `onReadyForChat`. | **Yes** (Deduplicated cleanly). |
| **Listener / Browser Crash** | Radio recovers automatically after a few seconds. | Underlying Darwin networking daemon restarted. | `scheduleRestart()` initiates exponential backoff restart (1s, 2s, 4s... max 30s). | **Yes** (Automatic self-healing). |
| **App Backgrounding (macOS App Nap)** | Discovery pauses if Mac sleeps. | macOS puts background apps into App Nap. | Socket transitions to `.waiting` or `.cancelled` on wake. | **Partial** (Recovers on wake; iOS backgrounding needs VoIP/Push). |

---

## 2. In-Depth Failure Case Studies

### 1. The Corrupted File Transfer Defense
Located in [PeerConnection.swift:L429-L448](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift#L429-L448):

```swift
private func finishIncoming(id: UUID, digest: Data) {
    guard let transfer = incoming.removeValue(forKey: id) else { return }
    try? transfer.handle.close()
    let actual = Data(transfer.hasher.finalize())
    guard actual == digest, transfer.received == transfer.size else {
        try? FileManager.default.removeItem(at: transfer.partURL)
        publishFile(id: id, ..., state: .failed, error: "Checksum failed")
        return
    }
    // Only atomically move to ~/Downloads/BlueComms after hash verification
    try? FileManager.default.moveItem(at: transfer.partURL, to: transfer.finalURL)
}
```

#### Why this is secure:
At no point is an unverified or corrupted file exposed in `~/Downloads/BlueComms`. Incomplete files remain hidden as `.[UUID].part` until the cryptographic SHA-256 digest is 100% matched against the sender's finalized hash.

---

### 2. Exponential Backoff on Radio Crashes
Located in [NetworkManager.swift:L483-L500](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L483-L500):

```swift
private func scheduleRestart(reason: String) {
    guard !isStopping, !restartScheduled else { return }
    restartScheduled = true
    listener?.cancel()
    browser?.cancel()
    
    let delay = min(pow(2.0, Double(restartAttempt)), 30)
    restartAttempt += 1
    queue.asyncAfter(deadline: .now() + delay) { [weak self] in
        self?.startStacks()
    }
}
```

#### Why this is resilient:
If the Wi-Fi interface is cycling or the operating system is under heavy load, BlueComms does not enter a tight loop spinning the CPU. It backs off exponentially ($1\text{s} \rightarrow 2\text{s} \rightarrow 4\text{s} \rightarrow 8\text{s} \rightarrow 16\text{s} \rightarrow 30\text{s}$), relieving system pressure until the radio stabilizes.
