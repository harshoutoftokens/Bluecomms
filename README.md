# BlueComms

Nearby Mac chat and files over Bonjour + AWDL. No internet. Wi-Fi just needs to be on.

## Run with a friend

On **each** Mac, after this fix is on `main`:

```bash
cd Bluecomms
git pull
cd BlueCommsCLI
swift run BlueCommsApp
```

1. Wi-Fi on (same network not required).
2. Allow **Local Network** for Terminal.
3. Click the other Mac → **Connect** → type, Attach, Screenshot, or drop a file.

Incoming files: `~/Downloads/BlueComms`.

Terminal instead:

```bash
cd Bluecomms/BlueCommsCLI
swift run BlueCommsCLI
```

Then `list`, `connect 0`, type, `quit`.

Needs macOS 14+ and Swift 6.1.

## iPhone and iPad

The iOS app talks to the Mac app and CLI over the same Bonjour + AWDL radio, with the same encryption. It needs the full Xcode app (16 or newer), not just the Command Line Tools.

1. Open `iOS/BlueComms.xcodeproj` in Xcode.
2. Select the **BlueComms** target → **Signing & Capabilities** → choose your Team. If Xcode says the bundle ID is taken, change `com.bluecomms.ios` to something unique.
3. Plug in your iPhone (iOS 17+), pick it as the run destination, and press ⌘R.
4. Allow **Local Network** when asked. Set your name under the gear icon.

Incoming files: Files app → On My iPhone → BlueComms.

iOS pauses apps in the background, so BlueComms only finds and receives messages while it is open. Anything sent while it is closed waits in the sender's queue until you reconnect.

If AirDrop also cannot see the other Mac, fix AirDrop first (same radio). Quit Tailscale and try with the firewall off.

## Tests

```bash
cd BlueCommsCLI
swift run BlueCommsSelfTest
```
