# Technical & Networking Glossary

> **Document Type:** Reference Dictionary & Core Terminology  
> **Repository Path:** [BlueCommsCLI/Sources](../BlueCommsCLI/Sources)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

This glossary defines the networking, cryptographic, and Apple system terms essential for understanding BlueComms.

---

### **A**
- **AES-GCM (Galois/Counter Mode):** An authenticated symmetric encryption algorithm providing confidentiality (secrecy) and integrity (tamper detection) in a single pass.
- **AWDL (Apple Wireless Direct Link):** Apple's proprietary peer-to-peer Wi-Fi protocol enabling high-speed ad-hoc communication (AirDrop, AirPlay) without an internet router or shared Access Point.

### **B**
- **BLE (Bluetooth Low Energy):** A low-power wireless personal area network standard suited for small sensor data and discovery beacons, but poorly suited for large file transfers due to low throughput (~2–50 KB/s).
- **Bonjour:** Apple’s implementation of zero-configuration networking (ZeroConf) based on multicast DNS (mDNS) and DNS Service Discovery (DNS-SD).
- **Byte:** 8 binary bits ($0\text{ to }255$). The fundamental unit of digital network data.

### **C**
- **Curve25519 (X25519):** A high-speed, state-of-the-art elliptic curve used for Diffie-Hellman Key Agreement (ECDH).
- **Ciphertext:** Encrypted data that is unreadable without the corresponding cryptographic key.

### **D**
- **Data (Swift Data):** A byte buffer wrapper in Swift’s `Foundation` framework representing raw binary memory.
- **DNS-SD (DNS Service Discovery):** A standard allowing devices to broadcast and discover named service types (e.g., `_bluecomms._tcp`) and metadata over local networks.

### **E**
- **Endpoint (`NWEndpoint`):** In `Network.framework`, a descriptor representing a target host, IP address, or Bonjour service instance.

### **F**
- **Frame / Framing:** The technique of establishing boundaries on a continuous byte stream (such as TCP) by prepending length headers or delimiters so messages can be uniquely parsed.

### **G**
- **GATT (Generic Attribute Profile):** The hierarchical data organization standard for BLE defining Services and Characteristics.

### **H**
- **HKDF (HMAC-based Key Derivation Function):** A cryptographic standard (RFC 5869) that expands a master shared secret into distinct symmetric keys using salt and info context strings.

### **M**
- **MAC Address:** A unique hardware identifier assigned to a network interface controller (NIC).
- **Mesh Network:** A decentralized network topology where nodes dynamically relay packets across multiple hops to reach destinations outside direct radio range.

### **N**
- **Network.framework:** Apple’s modern, event-driven networking stack introduced in macOS 10.14 and iOS 12 to replace legacy BSD sockets.
- **NWBrowser:** Apple API that scans for Bonjour service advertisements on local interfaces and AWDL.
- **NWConnection:** Apple API managing a bidirectional network transport connection (TCP or UDP).
- **NWListener:** Apple API that binds to a port and accepts incoming connections.
- **NWParameters:** Apple API defining protocol options (TCP/UDP, TLS, peer-to-peer flags).

### **P**
- **Packet:** A discrete unit of data routed at the Network Layer (IP) containing headers and payload.
- **Peer-to-Peer (P2P):** A distributed network architecture where participants share equal privilege and communicate directly without a central server.

### **S**
- **Segment (TCP Segment):** A chunk of stream data encapsulated with TCP headers (sequence numbers, ports, flags) at the Transport Layer.
- **Socket:** A software endpoint for sending or receiving data across a network interface.

### **T**
- **TCP (Transmission Control Protocol):** A connection-oriented, reliable transport protocol providing ordered, error-checked delivery of a continuous stream of bytes.
- **TOFU (Trust On First Use):** A security model where a client trusts a public key on the initial encounter and permanently rejects future keys that mismatch.
- **TTL (Time To Live):** A counter in packet headers decremented at each hop to prevent routing loops from circulating forever.
- **TXT Record:** A DNS-SD key-value metadata container attached to Bonjour service announcements.

### **U**
- **UDP (User Datagram Protocol):** A lightweight, connectionless transport protocol with no delivery, ordering, or duplicate protection guarantees.
- **UTF-8:** A variable-width character encoding mapping Unicode text into 1 to 4 bytes.
