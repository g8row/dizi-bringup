# Evolution X 11.11 (Android 16) – Redmi Pad Pro (dizi) – first unofficial release

This is the first build of this ROM for dizi. It's based on the HyperOS OS3.0.303.0 (EEA) firmware
and runs a kernel built from source.

## Highlights

- **Performance work specific to this tablet:**
  - **Landscape was composed entirely by the GPU.** The display engine rejected the rotated, zoomed
    wallpaper and fell back to GPU composition for every layer of every frame. It's now composed by
    the display hardware, as on stock: Settings scrolling went from 0.7% to 0.1% janky frames.
  - **About half of all boots left the panel at 60 Hz** while Android scheduled frames for 120 Hz,
    so every animation stuttered. This is fixed in the kernel display driver: it detects the
    bootloader's 60 Hz handover and reprograms the panel timing.
  - **Recents / overview:** 23% → 3% janky frames. The wallpaper zoom and blur behind the cards is
    off; stock HyperOS doesn't have it either.
  - **Commit stall:** a CAF "speculative fence" setting made every frame wait an extra vsync. It's off.
  - **GPU boosts** for touch and for blur rendering, and **ADPF** performance-hint sessions (apps and
    games can request CPU headroom per frame).
- **Redmi Smart Pen:**
  - automatic Bluetooth pairing, pressure, hover and palm rejection;
  - a settings page with configurable button actions: Home, Back, Recents, Screenshot, Play/pause,
    New note, or any app.
- **Kernel from source:** LineageOS `android_kernel_xiaomi_sm7435` (5.10.269) with the stock
  modules, which are symbol-compatible. The display driver is built from Xiaomi's released source.
- **SELinux enforcing**, with no denials during normal use.
- **Widevine L1**, and hardware video decode up to 4K (H.264, HEVC, VP9).
- **Tablet features:** split screen and desktop windowing, large-screen launcher and taskbar.
- **Double-tap to wake** (Settings → Display → Tap to wake, off by default), using the stock touch
  controller's wakeup gesture.
- **USB works right after boot:** the USB controller sometimes misses the cable at boot; this is now
  recovered automatically, so MTP and adb no longer need a replug.

## Known issues and untested features

See INSTALL.md. In short:
- The blur in quick settings and the app drawer costs a few frames.
- The first camera launch after boot sometimes takes no photo.
- Not yet verified: recovery OTA sideload, and some wired and Bluetooth audio paths.

## Credits

- **Evolution X, LineageOS and AOSP**, and the LineageOS garnet (Redmi Note 13 Pro 5G) maintainers,
  whose device tree this port started from.
- **Xiaomi** for the `ruan-u-oss` kernel and display-driver source releases.
