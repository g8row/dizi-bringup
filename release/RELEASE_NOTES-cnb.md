# Evolution X 12.2 (Android 17) – Redmi Pad Pro (dizi) – first unofficial release

The first Android 17 build of this ROM for dizi. It is based on Evolution X `cnb` and the HyperOS
OS3.0.303.0 (EEA) firmware, and runs a kernel built from source. It carries over everything from the
Android 16 releases (pen, double-tap to wake, the 120 Hz and landscape composition fixes, SELinux
enforcing) and adds the following.

## New in this release

- **Android 17** (Evolution X 12.2, `CP2A.260605.016`). The device tree is 64-bit only, at FCM level 7.
- **Smoother Recents and animations.**
  - Apps and the compositor now get two 120 Hz frames of work time instead of about one and a half.
  - Opening an app from Recents is 30-40% less janky.
  - The cost is about 3-4 ms more touch-to-display latency.
- **Apps render with Vulkan** (HWUI). The launcher's own frames in Recents drop from about 6.6% to 4.8%
  janky. An app sweep found no crashes.
- **Notification shade blur is off by default.** On Android 17 it is much more expensive on this GPU:
  pulling down quick settings is 13-16% janky with it and about 2-4% without.
  - To turn it back on: **Settings > Display > Blur effects**.
- **Faster, reliable boot.** A codec manifest entry for a disabled Dolby Vision service made media services
  hang and the system restart during boot. That's fixed, and boot takes about 30 s.
- **Frame buffers match stock HyperOS** (`max_frame_buffer_acquired_buffers=3`).

## Install

See INSTALL.md in the fastboot package.
- **Coming from Android 16 builds, a different ROM, or HyperOS:** this is a clean install. Format data in
  recovery.
- **Never relock the bootloader.**

## Known issues

- **First release on Android 17.** Everything in our hardware checklist passes (Wi-Fi, BT, audio, cameras,
  sensors, charging, pen, display modes), but Android 17 is new upstream, so please report anything odd with
  `collect-logs`.
- **A "Select USB mode" chooser can appear after boot** when a cable is connected. Close it, or pick a mode.
- **Recents still drops some frames while zooming into an app.** Rounded, scaled app windows have to be
  composed by the GPU. Details are in the performance report in the dizi-bringup repository.
