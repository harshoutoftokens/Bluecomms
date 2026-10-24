# Security, Cryptography & Threat Model Audit

> **Document Type:** Security Architecture & Threat Model Audit  
> **Repository Path:** [BlueCommsCore/CryptoSession.swift](../BlueCommsCLI/Sources/BlueCommsCore/CryptoSession.swift) & [BlueCommsCore/IdentityStore.swift](../BlueCommsCLI/Sources/BlueCommsCore/IdentityStore.swift)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

---

## 1. Separation: Platform Security vs. BlueComms Security

To accurately evaluate security, we must distinguish between what Apple's OS provides and what BlueComms actually implements:

```
+-----------------------------------------------------------------------------------------+
| SECURITY PROVIDED BY APPLE PLATFORM                                                     |
|   • Local Network Privacy: Requires user consent before apps can scan mDNS.             |
|   • Process Isolation: Darwin App Sandbox isolates memory from other apps.              |
|   • Hardware Crypto: ARMv8-A / AES-NI acceleration for AES-GCM and SHA-256.             |
|   • (NOT PROVIDED: Apple does NOT encrypt raw TCP streams or authenticate Bonjour peers)|
+-----------------------------------------------------------------------------------------+
                                             │
                                             ▼
+-----------------------------------------------------------------------------------------+
| SECURITY IMPLEMENTED BY BLUECOMMS                                                       |
|   • Authenticated Encryption: AES-GCM-256 on all chat text, control frames, and files.  |
|   • Key Agreement: X25519 (Curve25519) producing unique directional session keys.       |
|   • Integrity Verification: 16-byte Poly1305 / GCM tags + SHA-256 file checksums.       |
|   • Key Pinning / TOFU: ~/.bluecomms/known-peers.json rejects changed peer public keys. |
|   • Encrypted Local Storage: ~/.bluecomms/conversations.bin encrypted with AES-GCM.     |
+-----------------------------------------------------------------------------------------+
```

---

## 2. Threat Model & Attack Vector Analysis

| Threat / Attack Vector | Vulnerable in BlueComms? | Technical Analysis & Current Mitigations |
| :--- | :---: | :--- |
| **Passive RF Eavesdropping (Sniffing)** | **NO (Protected)** | All chat and file payloads are encrypted with AES-GCM-256. A passive Wi-Fi packet capture (Wireshark) only sees raw ciphertext. |
| **Active In-Flight Tampering / Bit-Flips** | **NO (Protected)** | AES-GCM's 16-byte authentication tag guarantees detection; tampered packets fail decryption and are dropped immediately. |
| **Replay Attacks (Captured Frames Re-sent)** | **NO (Protected)** | Monotonically increasing 64-bit counter nonce in AES-GCM ensures every frame has a unique nonce. |
| **First-Connection Man-in-the-Middle (MITM)** | **PARTIAL RISK (TOFU)** | On the *first ever* connection to a new peer, BlueComms trusts their public key. Mitigated by visual out-of-band fingerprint verification. |
| **Long-Term Key Compromise (Forward Secrecy)** | **YES (Vulnerable)** | `CryptoSession` performs ECDH directly on long-term identity keys rather than generating ephemeral session keys per connection. |
| **Metadata / Traffic Analysis** | **YES (Vulnerable)** | Bonjour broadcasts unencrypted device names, short IDs, and MAC addresses. Anyone within Wi-Fi range can see that BlueComms is active. |
| **Unauthenticated Discovery / Spam Connection**| **PARTIAL RISK** | Anyone nearby can discover the `_bluecomms._tcp` listener and open a TCP socket. However, they cannot send chat until the crypto handshake completes. |
| **Path Traversal File Write Attack** | **NO (Protected)** | `FileTransfer.sanitizeFileName()` strips `/` and `:` separators, restricting all incoming files to `~/Downloads/BlueComms/`. |

---

## 3. Cryptographic Primitives & Key Derivation

### 1. Key Agreement
- **Algorithm:** Curve25519 ECDH via `CryptoKit.Curve25519.KeyAgreement`.
- **Shared Secret:** $\text{Secret} = \text{X25519}(\text{Private}_{\text{local}}, \text{Public}_{\text{peer}})$.

### 2. Key Derivation Function (HKDF)
In [CryptoSession.swift:L139-L146](../BlueCommsCLI/Sources/BlueCommsCore/CryptoSession.swift#L139-L146):
- **Hash Function:** SHA-256.
- **Salt:** `"bluecomms-v1"`.
- **Directional Keys Derived:**
  $$\text{Key}_{\text{l2h}} = \text{HKDF-Expand}(\text{Secret}, \text{info: "bluecomms-v1-l2h"}, 32\text{ bytes})$$
  $$\text{Key}_{\text{h2l}} = \text{HKDF-Expand}(\text{Secret}, \text{info: "bluecomms-v1-h2l"}, 32\text{ bytes})$$
- By comparing `localPublic.lexicographicallyPrecedes(peerPublic)`, both peers deterministically assign their `sendKey` and `receiveKey` without extra negotiation rounds.

### 3. File Transfer Path Sanitization
In [FileTransfer.swift:L177-L182](../BlueCommsCLI/Sources/BlueCommsCore/FileTransfer.swift#L177-L182):
```swift
public func sanitizeFileName(_ raw: String) -> String {
    let trimmed = raw.replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "file" : trimmed
}
```
Prevents malicious peers from sending filenames like `../../../../.zshrc` to overwrite sensitive user configuration files.
