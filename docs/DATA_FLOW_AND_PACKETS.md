# Data Flow, Packets & Wire Format

> **Document Type:** Byte-Level & Protocol Specification  
> **Repository Path:** [BlueCommsCore/FrameCodec.swift](../BlueCommsCLI/Sources/BlueCommsCore/FrameCodec.swift) & [BlueCommsCore/CryptoSession.swift](../BlueCommsCLI/Sources/BlueCommsCore/CryptoSession.swift)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

---

## 1. Step-by-Step Lifecycle: Tracing `"hello"`

Let us trace exactly what happens to the string `"hello"` from the moment a user presses Enter in the UI to the moment it renders on the remote peer's screen.

```
+-----------------------------------------------------------------------------------------------+
| SENDER LIFECYCLE (MAC A)                                                                      |
+-----------------------------------------------------------------------------------------------+
1. User presses 'Send' in SwiftUI ContentView.swift.
2. ChatStore.sendDraft() grabs draft String = "hello".
3. String converted to UTF-8 Swift Data: Data("hello".utf8) (5 bytes: 0x68 0x65 0x6C 0x6C 0x6F).
4. PeerConnection.sendCiphertext() invokes CryptoSession.seal(plaintext):
   a. Generates 12-byte Nonce from sendCounter (UInt64 big-endian padded):
      [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]
   b. AES-GCM-256 encrypts 5 bytes into 5 bytes of ciphertext using sendKey.
   c. Generates 16-byte Poly1305 / GCM authentication tag.
   d. Sealed Blob = [12-byte Nonce] + [5-byte Ciphertext] + [16-byte Tag] (Total: 33 bytes).
5. PeerConnection.sendFrame(type: .ciphertext, body: sealedBlob):
   a. Wire Payload = [WireType.ciphertext (0x02)] + [33-byte Sealed Blob] (Total: 34 bytes).
   b. FrameCodec.encode(payload) calculates 4-byte big-endian length = 34 (0x00000022).
   c. Final Wire Buffer = [0x00, 0x00, 0x00, 0x22] + [0x02] + [Sealed Blob] (Total: 38 bytes).
6. NWConnection.send(content: 38 bytes, isComplete: false) pushes buffer to Darwin kernel.
7. Kernel segments data into TCP Segment -> IP Packet -> 802.11 AWDL Wi-Fi Frame.
8. Physical Wi-Fi radio transmits 802.11 RF signal across the air.
+-----------------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------------+
| RECEIVER LIFECYCLE (MAC B)                                                                    |
+-----------------------------------------------------------------------------------------------+
9. Physical Wi-Fi radio receives 802.11 RF signal, decodes MAC frame.
10. Kernel reassembles IP packet -> TCP stream buffer.
11. NWConnection.receive callback fires on 'bluecomms.network' DispatchQueue with chunk Data.
12. FrameDecoder.append(chunk):
    a. Reads first 4 bytes: 0x00000022 (Length = 34).
    b. Waits until buffer contains 4 + 34 = 38 bytes.
    c. Slices payload (34 bytes), removes 38 bytes from internal buffer.
13. PeerConnection.handleFrame(payload):
    a. Inspects byte 0: 0x02 -> WireType.ciphertext.
    b. Drops byte 0, passes 33-byte body to CryptoSession.open().
14. CryptoSession.open(blob):
    a. Slices 12-byte Nonce, 16-byte Tag, 5-byte Ciphertext.
    b. AES-GCM-256 decrypts and verifies tag against receiveKey.
    c. Returns 5-byte plaintext Data.
15. PeerConnection converts Data to UTF-8 String -> "hello".
16. Callback onMessageFromPeer(peerUUID, "hello") dispatches to MainActor.
17. ChatStore appends ChatMessage to conversations dictionary.
18. MessageArchive encrypts conversation snapshot to ~/.bluecomms/conversations.bin.
19. SwiftUI observes @Published conversations change and renders chat bubble on screen.
+-----------------------------------------------------------------------------------------------+
```

---

## 2. Core Concepts: Distinguishing Network Entities

To avoid architectural confusion, we must clearly define what each networking term means:

```
+----------------------------------------------------------------------------------------+
| Application Message  | High-level Swift domain object (ChatMessage: text, id, sender)  |
+----------------------+-----------------------------------------------------------------+
| Plaintext Bytes      | Swift Data containing raw UTF-8 string bytes                    |
+----------------------+-----------------------------------------------------------------+
| Ciphertext Body      | Encrypted bytes: Nonce (12B) + Ciphertext + GCM Tag (16B)       |
+----------------------+-----------------------------------------------------------------+
| Wire Frame           | Framed unit: Length Prefix (4B) + WireType (1B) + Body          |
+----------------------+-----------------------------------------------------------------+
| TCP Segment          | Transport-layer chunk (with TCP headers: ports, SEQ, ACK flags) |
+----------------------+-----------------------------------------------------------------+
| IP Packet            | Network-layer datagram (with IP headers: src/dst IP addresses)  |
+----------------------+-----------------------------------------------------------------+
| 802.11 Frame         | Link-layer Wi-Fi frame (with MAC headers, preamble, CRC)        |
+----------------------+-----------------------------------------------------------------+
```

---

## 3. The Fallacy: "One `send()` Equals One `receive()`"

A common bug in network programming is assuming that if the sender calls:
```swift
connection.send(content: data1)
connection.send(content: data2)
```
The receiver will experience two separate callback invocations:
```swift
// WRONG ASSUMPTION:
connection.receive { data in /* data1 */ }
connection.receive { data in /* data2 */ }
```

### Why this assumption is false for TCP:
1. **Stream Coalescing (Nagle's Algorithm & Kernel Buffers):** The OS kernel may hold `data1` in a socket buffer and combine it with `data2`, sending both inside a single TCP segment. The receiver gets `data1 + data2` in one `receive()` call.
2. **Fragmentation (MTU Slicing):** If `data1` is 200 KB, it exceeds the Maximum Transmission Unit (MTU ~1500 bytes on Ethernet, ~2000 bytes on AWDL). The network splits it into dozens of IP packets. The receiver might get 1400 bytes in chunk 1, 1400 bytes in chunk 2, etc.

### How BlueComms Solves This:
The [FrameDecoder](../BlueCommsCLI/Sources/BlueCommsCore/FrameCodec.swift#L44-L72) class maintains a persistent `buffer: Data`.

```swift
public func append(_ data: Data) throws -> [Data] {
    buffer.append(data)
    var frames: [Data] = []

    while buffer.count >= FrameCodec.headerSize {
        let length = FrameCodec.readUInt32BE(buffer)
        guard length <= UInt32(FrameCodec.maxPayloadSize) else {
            buffer.removeAll(keepingCapacity: false)
            throw FrameError.declaredLengthTooLarge(length)
        }
        let total = FrameCodec.headerSize + Int(length)
        guard buffer.count >= total else { break } // Wait for more TCP bytes
        frames.append(buffer.subdata(in: FrameCodec.headerSize..<total))
        buffer.removeSubrange(0..<total)
    }

    return frames
}
```

---

## 4. Binary Wire Format Specifications

### A. Handshake Frame (`WireType.handshake = 0x01`)
Total wire payload size: **49 bytes** ($4\text{ header} + 1\text{ type} + 1\text{ proto} + 16\text{ UUID} + 32\text{ Key} = 54\text{ total bytes}$).

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      Frame Length (49)                        | (Big-Endian UInt32)
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| WireType (0x01)| ProtoVer (0x01)|                             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+                               +
|                                                               |
|                   Sender Device UUID (16 bytes)               |
|                                                               |
|                               +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                               |                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+                               +
|                                                               |
|                 X25519 Public Key (32 bytes)                  |
|                                                               |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

---

### B. Chat Frame (`WireType.ciphertext = 0x02`)
$$\text{Wire Size} = 4\text{ bytes (Length)} + 1\text{ byte (0x02)} + 12\text{ bytes (Nonce)} + N\text{ bytes (Ciphertext)} + 16\text{ bytes (GCM Tag)}$$

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Frame Length (29 + N)                      | (Big-Endian UInt32)
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| WireType (0x02)|             AES-GCM Nonce (12 bytes)          |
+-+-+-+-+-+-+-+-+                                               +
|                                                               |
|                               +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                               |                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+                               +
|                   Encrypted UTF-8 Chat Text (N bytes)         |
|                              ...                              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
|                   AES-GCM Auth Tag (16 bytes)                 |
|                                                               |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

---

### C. File Control & Chunk Frames (`WireType.file = 0x03`)
Each `FileMessage` is serialized, AES-GCM sealed, and wrapped in a `WireType.file` frame.

#### Opcodes:
- `0x01: offer(id: UUID, size: UInt64, name: String)`
- `0x02: accept(id: UUID, resumeFrom: UInt64)`
- `0x03: reject(id: UUID)`
- `0x04: chunk(id: UUID, offset: UInt64, data: Data)`
- `0x05: ack(id: UUID, receivedUpTo: UInt64)`
- `0x06: complete(id: UUID, sha256: Data)`
- `0x07: cancel(id: UUID)`
