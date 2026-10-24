# BlueComms: Under the Hood

> **Document Type:** Developer Deep Dive  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

---

## 1. What Problem Does BlueComms Solve?

Modern messaging apps (iMessage, WhatsApp, Slack, Signal) are **infrastructure-dependent**. When you send a message to someone sitting three feet away from you:
1. Your device connects to a Wi-Fi Access Point or Cellular Base Station.
2. The packet travels across your ISP, through underwater cables or fiber backbones, to a data center.
3. A cloud server processes, authenticates, and routes the message.
4. The packet travels all the way back across the internet to your neighbor's device.

If the power goes out, if the internet router is down, or if you are on an airplane, in the woods, or in a disaster zone, **traditional apps stop working entirely**.

**BlueComms** provides direct, device-to-device communication without any internet, cloud servers, cell towers, or shared Wi-Fi routers. As long as two Macs have their Wi-Fi hardware switched on, they can discover each other, establish an encrypted peer-to-peer link, chat, and stream gigabyte-sized files.

---

## 2. Real-Life Level: What Happens Step by Step?

Let’s trace a real-world scenario: **Mac A (Alice)** wants to send the message `"hello"` to **Mac B (Bob)**.

```
+-------------------------------------------------------------------------------+
| REAL-LIFE STEP-BY-STEP FLOW                                                   |
|                                                                               |
| 1. Alice & Bob turn on their Macs with Wi-Fi enabled (no Wi-Fi router needed) |
| 2. Both open BlueComms. Each Mac generates or loads its cryptographic ID.     |
| 3. Mac A announces: "I am Alice (_bluecomms._tcp on local.)" over the air.    |
| 4. Mac B's radio hears Alice's announcement and adds "Alice" to its sidebar.  |
| 5. Bob clicks "Connect" next to Alice's name.                                 |
| 6. Mac B establishes a direct peer-to-peer radio link (AWDL/Wi-Fi) to Mac A. |
| 7. Both devices exchange public encryption keys and perform a handshake.      |
| 8. Both verify: "Alice is Alice" and derive matching session encryption keys. |
| 9. Alice types "hello" and presses Send.                                      |
| 10. Mac A encrypts "hello" into secret bytes and transmits them over the air. |
| 11. Mac B receives the bytes, decrypts them, and displays "hello" in the UI.  |
+-------------------------------------------------------------------------------+
```

### What Physically Happens?
- **No Access Point Required:** The two Macs communicate over **Apple Wireless Direct Link (AWDL)**—the same proprietary, ad-hoc 802.11 Wi-Fi mesh technology that powers AirDrop and AirPlay.
- **Discovery Signals:** The Wi-Fi chips periodically synchronize active time windows to broadcast and listen for Bonjour (mDNS / DNS-SD) service announcements.
- **Physical Link:** Once Mac B chooses to connect, an ad-hoc 802.11 link is scheduled directly between the two Wi-Fi MAC addresses. No third device routes the traffic.

---

## 3. Computer / Networking Level: The Technical Reality

Now let’s translate that real-life story into the exact networking and operating system concepts implemented in this repository.

```
+---------------------------------------------------------------------------------------+
| BLUECOMMS PROTOCOL & NETWORKING STACK                                                 |
+---------------------------------------------------------------------------------------+
| Application UI        | SwiftUI (ContentView.swift) & Terminal (main.swift)          |
+-----------------------+---------------------------------------------------------------+
| Presentation / State  | ChatStore.swift (@MainActor, ObservableObject)                |
+-----------------------+---------------------------------------------------------------+
| Domain & Orchestration| NetworkManager.swift (Serial DispatchQueue, Session Registry) |
+-----------------------+---------------------------------------------------------------+
| Session & Wire Logic  | PeerConnection.swift (State Machine, Queuing, Transfers)      |
+-----------------------+---------------------------------------------------------------+
| Security Layer        | CryptoSession.swift (X25519 Key Exchange, HKDF, AES-GCM-256)  |
+-----------------------+---------------------------------------------------------------+
| Framing Layer         | FrameCodec.swift (4-Byte Big-Endian Length Prefix)            |
+-----------------------+---------------------------------------------------------------+
| Apple Transport Stack | Apple Network.framework (NWListener, NWBrowser, NWConnection) |
+-----------------------+---------------------------------------------------------------+
| Discovery / Link      | DNS-SD / Bonjour (_bluecomms._tcp) + AWDL (includePeerToPeer) |
+-----------------------+---------------------------------------------------------------+
| Physical Hardware     | 802.11 Wi-Fi Chip (Peer-to-Peer Ad-Hoc Mode)                 |
+-----------------------+---------------------------------------------------------------+
```

### Layer 1: Identity & Persistent Keys
Before any network activity begins, the application needs a cryptographic identity.
- [IdentityStore.swift](../BlueCommsCLI/Sources/BlueCommsCore/IdentityStore.swift) inspects `~/.bluecomms/`.
- If missing, it generates:
  1. A random `UUID` (`device-id`).
  2. A Curve25519 private key (`identity`) using Apple's `CryptoKit`.
- Permissions are strictly set to POSIX `0700` (directory) and `0600` (files) so no other local user can read the private key.

### Layer 2: Service Advertising & Discovery (Bonjour / DNS-SD)
To let peers find each other:
- **The Listener ([NetworkManager.swift:L242-L271](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L242-L271)):** Configures an `NWListener` with `NWParameters.tcp` and `includePeerToPeer = true`. It advertises the Bonjour service type `_bluecomms._tcp` in domain `local.`.
- **The TXT Record:** BlueComms attaches a DNS-SD TXT record containing:
  - `id`: The device UUID string.
  - `proto`: The protocol version (`"1"`).
  - `name`: The machine display name (retrieved from `SCDynamicStoreCopyComputerName`).
- **The Browser ([NetworkManager.swift:L274-L293](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L274-L293)):** Starts an `NWBrowser` using `.bonjourWithTXTRecord(type: "_bluecomms._tcp", domain: "local.")`.
- **Filtering:** When the browser receives `NWBrowser.Result` objects, it parses the TXT record, ignores its own UUID, and notifies the UI with a list of [DiscoveredPeer](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift#L25-L33) instances.

### Layer 3: Connection Establishment & Transport Link
When user Bob clicks "Connect" to Alice:
- [NetworkManager.swift](../BlueCommsCLI/Sources/BlueCommsCore/NetworkManager.swift) creates an `NWConnection(to: peer.endpoint, using: parameters)`.
- Because `parameters.includePeerToPeer` is `true`, Network.framework instructs macOS to bring up an AWDL virtual link if the devices are not on a shared Wi-Fi network.
- `NWConnection.stateUpdateHandler` transitions through `.setup` $\rightarrow$ `.preparing` $\rightarrow$ `.ready`.

### Layer 4: Cryptographic Handshake (Zero-Round-Trip Key Exchange)
TCP alone is unencrypted. Anyone nearby listening with a Wi-Fi packet capture card could inspect the traffic.
- When `NWConnection.State` becomes `.ready`, [PeerConnection.swift](../BlueCommsCLI/Sources/BlueCommsCore/PeerConnection.swift) immediately transmits a **Handshake Frame** (`WireType.handshake = 0x01`):
  $$\text{Payload} = [\text{proto: 1 byte}] + [\text{peerID: 16 bytes}] + [\text{X25519 Public Key: 32 bytes}]$$
- When received, both sides perform an **ECDH** (Elliptic-Curve Diffie-Hellman) shared secret agreement:
  $$\text{SharedSecret} = \text{X25519}(\text{LocalPrivateKey}, \text{RemotePublicKey})$$
- Using **HKDF-SHA256** with salt `"bluecomms-v1"`, both derive two distinct 256-bit AES symmetric keys:
  1. `lowToHigh` (`info: "bluecomms-v1-l2h"`)
  2. `highToLow` (`info: "bluecomms-v1-h2l"`)
- By comparing `localPublicKey.lexicographicallyPrecedes(remotePublicKey)`, both devices agree on which key encrypts outbound traffic and which key decrypts inbound traffic without needing a third negotiation message.
- **Trust On First Use (TOFU):** [IdentityStore.swift](../BlueCommsCLI/Sources/BlueCommsCore/IdentityStore.swift) checks `~/.bluecomms/known-peers.json`. If a peer with the same UUID presents a different public key, the connection is instantly aborted with `CryptoError.tofuMismatch`.

### Layer 5: Message Framing (Stream vs. Packet)
TCP is a byte-stream protocol, not a message protocol. If you call `send("hello")` and `send("world")`, TCP might deliver them as one 10-byte chunk, or as five 2-byte chunks.
- [FrameCodec.swift](../BlueCommsCLI/Sources/BlueCommsCore/FrameCodec.swift) prefixes every frame with a **4-byte big-endian UInt32 length**:
  $$\text{Wire Blob} = [\text{Length (4 bytes)}] + [\text{WireType (1 byte)}] + [\text{Encrypted Body}]$$
- [FrameCodec.swift](../BlueCommsCLI/Sources/BlueCommsCore/FrameCodec.swift#L44-L72) buffers incoming TCP fragments until a complete frame is assembled before passing it up the stack.

### Layer 6: Payload Encryption & Delivery
For text chat:
- Plaintext UTF-8 bytes are encrypted using **AES-GCM-256** with an incrementing 64-bit counter as a 12-byte nonce (padded with 4 zero bytes).
- The sealed payload contains `[12-byte Nonce] + [Ciphertext] + [16-byte GCM Tag]`.
- On the receiver, `CryptoSession.open()` verifies the tag, decrypts the ciphertext, and converts UTF-8 bytes back into a Swift `String`.
- [ChatStore.swift](../BlueCommsCLI/Sources/BlueCommsApp/ChatStore.swift) appends the message to `conversations`, updates SwiftUI on the `@MainActor`, and saves the encrypted thread to disk using [MessageArchive.swift](../BlueCommsCLI/Sources/BlueCommsCore/MessageArchive.swift).

---

## 4. Summary of Key Concepts in Simple vs. Technical Terms

| Concept | Simple Real-Life Analogy | Exact Technical Definition in BlueComms |
| :--- | :--- | :--- |
| **Bonjour / DNS-SD** | Announcing your name in a crowded room so friends can find you. | Multicast DNS (`mDNSResponder`) service discovery broadcasting `_bluecomms._tcp` over `local.`. |
| **AWDL** | A direct private radio walkie-talkie channel between two Apple devices. | Apple Wireless Direct Link: 802.11 peer-to-peer Wi-Fi interface enabling ad-hoc connections without a base station. |
| **NWListener** | A mailbox waiting to receive incoming envelopes. | Network.framework object binding to a dynamic port and handling incoming TCP connection requests. |
| **NWBrowser** | Looking around the room with binoculars for people wearing "BlueComms" badges. | Network.framework object querying mDNS for services matching `_bluecomms._tcp` and retrieving TXT records. |
| **NWConnection** | An open, private telephone wire between two people. | Bidirectional TCP stream abstraction managing socket lifecycle, queues, and link parameters. |
| **Framing** | Putting each letter in an envelope with the exact page count written on the outside. | 4-byte big-endian length prefix prepended to payloads so stream fragmentation does not corrupt messages. |
| **X25519 Handshake** | Alice and Bob mixing paint colors in public to create a secret private color nobody else can deduce. | Elliptic-Curve Diffie-Hellman Key Agreement over Curve25519 producing a 32-byte shared secret. |
| **AES-GCM-256** | A tamper-evident, unbreakable steel lockbox. | Authenticated encryption algorithm providing confidentiality and cryptographic integrity verification. |
| **TOFU** | Memorizing your friend's face on day 1 so an imposter cannot pretend to be them later. | Trust On First Use: Persisting peer public keys in `known-peers.json` and rejecting unexpected key rotations. |
