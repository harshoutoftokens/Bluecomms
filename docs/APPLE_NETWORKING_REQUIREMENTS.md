# Apple Networking Requirements & Local Network Privacy

> **Document Type:** Apple OS Privacy, Entitlements & Security Guide  
> **Repository Path:** [BlueCommsCLI/Package.swift](../BlueCommsCLI/Package.swift) & [Info.plist Files](../BlueCommsCLI/Sources/BlueCommsApp/Info.plist)  
> **Status:** Grounded in active codebase as of macOS 14+ / Swift 6.1

---

## 1. The Critical Distinction: Code Correctness vs. OS Permission

In modern Apple operating systems (macOS 14+ Sonoma/Sequoia and iOS 14+), there is a fundamental barrier between application code and the physical network:

$$\text{Code Correctness} \neq \text{OS Permission to Transmit}$$

You can write 100% bug-free Swift networking code using `NWBrowser` and `NWListener`. The compiler will build it without errors. However, at runtime, if the application has not complied with Apple's **Local Network Privacy Architecture**, the operating system's kernel and `mDNSResponder` will silently discard all multicast discovery packets and block socket connections. The browser will remain permanently empty, and the listener will enter the `.waiting` state indefinitely.

---

## 2. Required Info.plist Keys in BlueComms

Both [BlueCommsApp/Info.plist](../BlueCommsCLI/Sources/BlueCommsApp/Info.plist) and [BlueCommsCLI/Info.plist](../BlueCommsCLI/Sources/BlueCommsCLI/Info.plist) declare:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>BlueComms discovers nearby peers over the local network and AWDL so you can chat without the internet.</string>

<key>NSBonjourServices</key>
<array>
    <string>_bluecomms._tcp</string>
</array>
```

### 1. `NSLocalNetworkUsageDescription` (String)
- **Why Apple Requires It:** Introduced to prevent untrusted apps and ad SDKs from silently scanning users' local home networks (smart TVs, printers, security cameras) to fingerprint user locations and devices.
- **What It Does:** Displays the user-facing explanation modal when the app first attempts to browse or listen on the local network: *"BlueComms would like to find and connect to devices on your local network."*
- **What Happens If Missing:** In iOS, the app immediately crashes on launch when initiating a network call. In macOS, network operations silently fail without presenting a prompt.

### 2. `NSBonjourServices` (Array of Strings)
- **Why Apple Requires It:** Limits the scope of Bonjour queries. An app cannot perform a wildcard browse (`_services._dns-sd._udp`) to discover all devices on a network; it must explicitly declare every service type it intends to interact with.
- **What It Does:** Whitelists `_bluecomms._tcp` for discovery and advertising by `mDNSResponder`.
- **What Happens If Missing:** `NWBrowser` will return zero browse results, even if peers are advertising 2 inches away.

---

## 3. Command-Line Binaries vs. App Bundles (`-sectcreate`)

When building via Xcode, the IDE automatically bundles `Info.plist` into the app's `.app/Contents/` directory. However, when compiling a command-line tool via Swift Package Manager (`swift run BlueCommsApp` or `swift run BlueCommsCLI`), there is **no app bundle directory**.

### How BlueComms Solves This in `Package.swift`:
Located in [BlueCommsCLI/Package.swift:L36-L56](../BlueCommsCLI/Package.swift#L36-L56):

```swift
linkerSettings: [
    .unsafeFlags([
        "-Xlinker", "-sectcreate",
        "-Xlinker", "__TEXT",
        "-Xlinker", "__info_plist",
        "-Xlinker", infoPlistPath,
    ])
]
```

### What this linker flag does:
It instructs the Mach-O linker (`ld64`) to embed the raw XML `Info.plist` directly into the binary's `__TEXT` segment under the `__info_plist` section. When macOS launches the standalone executable, the Darwin kernel inspects this embedded Mach-O section and recognizes the executable's Local Network and Bonjour entitlements.

---

## 4. Summary of System Requirements

| Requirement | Target | Impact If Missing |
| :--- | :--- | :--- |
| **`NSLocalNetworkUsageDescription`** | iOS / macOS | Privacy prompt never triggers; network calls fail silently. |
| **`NSBonjourServices`** | iOS / macOS | `NWBrowser` returns empty results; cannot discover `_bluecomms._tcp`. |
| **Mach-O `__info_plist` Linking** | SwiftPM Executables | Standalone CLI/App binaries fail local network authorization. |
| **App Sandbox Entitlements** | App Store Builds | Requires `com.apple.security.network.client` and `com.apple.security.network.server`. |
| **Screen Recording Permission** | Screenshot Tool | `CGDisplayCreateImage` returns `nil` on macOS 10.15+. |
