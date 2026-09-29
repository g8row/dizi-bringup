# Plain LineageOS 23.2 on dizi (lineage-2, 2026-09-28)

A test of the dizi device tree on stock LineageOS 23.2 (same Android 16 QPR base as EvoX bka), mainly to
compare Trebuchet (Launcher3 Quickstep built from source) with the Pixel Launcher prebuilt.

## Tree and build

- Source: `/build/alex/dizi/lineage`, repo `lineage-23.2` with `--reference` to evox.
  - hardware/xiaomi, hardware/dolby, GameBar and the kernel headers are pinned to the evox commits
    (`.repo/local_manifests/dizi.xml`).
  - device/xiaomi/{dizi,dizi-kernel}, vendor/xiaomi/dizi and vendor/dizi-bench are `cp -a` copies.
    The device tree is on branch lineage-23.2.
- Build reuse:
  - `out-dizi` is a `cp -a` of evox's.
  - `tools/match-mtimes.py evox lineage` gives blob-identical files evox's mtimes: it matched 1.64M files,
    and 2.8k differ (frameworks/base 1250, Settings 310, lineage-sdk 192, recovery 176, ...).
  - The first build ran 83k ninja actions in 71 min; the second (after a sepolicy fix) ran 15k in 19 min.
- Device tree changes:
  - `sepolicy/private/compat/202404/202404.ignore.cil` for devicesettings_app and settingslib_prop.
    Lineage's system/sepolicy runs the treble compat tests, which EvoX's fork doesn't.
- Platform patches:
  - build/make, frameworks/native and vendor/lineage apply as-is.
  - system/core isn't needed: Lineage has no is_upgrade resource-cache wipe.
- `TREE=lineage tools/build.sh <id> bacon superimage`; `TREE=lineage tools/deploy.sh <id> --wipe`.
  The build is test-keys, so moving from the EvoX release needs a wipe.

## Boot

- Booted first time (43 s to boot_completed), SELinux enforcing.
- USB adb came up without a replug.
- The user confirmed that camera, audio, screen and the launcher work.
- Tombstones:
  - hardware/dolby `dolbycodec2` (Codec2 `default2`) crashes in `BnHwComponentStore::_hidl_listComponents`
    (null RefBase).
  - mediaserver then aborted once: `Codec2 service "default2" does not have IConfigurable`.
  - EvoX ships the same services (same out/ contents), so this is likely shared. The note in a17-cnb.md
    saying dolbycodec2 isn't shipped is stale.
- AVC denials: about 15 triples, mostly system_app -> HAL binder calls and adbroot; nothing blocking.

## Jank (landscape, warm runs, same scripts as EvoX)

`tools/apps.sh` now resolves the launcher, browser, clock and gallery apps, so the scripts run on both ROMs.

| Test | EvoX (research/performance.md) | Lineage (Trebuchet, Jelly) |
|---|---|---|
| Settings fling | 0.09-0.18% | **0.05%**, p99 7 ms |
| Browser fling | Chrome (layer timeline) | Jelly 0.00%, p99 7 ms |
| Launcher home fling | 1.6-2.1% | **6.10%**, p90 18 / p99 44 ms, 88 slow issue draw |
| QS pulldown | ~4.7-5.6% | **4.00%**, p99 32 ms |
| Recents (enter, fling cards, home) | 2.99% (after the landscape blur fix; 24% before) | 4.02%, p50 11 ms |
| Recents -> app, launcher hwui | 6.7-9.2% | 8.79% (7.04% in a 20-cycle run) |
| Recents -> app, display timeline | 13.0-14.8% | **20.7%** (17.7% in a 20-cycle run) |

- Trebuchet is AOT-compiled (`speed`, prebuilt dexpreopt), so JIT on the first boot is not a factor.
- LauncherOverlayDizi targets com.google.android.apps.nexuslauncher, so it doesn't apply here. Launcher3 has no
  600dp landscape blur (max_depth_blur_radius_enhanced is 30dp in values/ only), so nothing is lost.
- In recents-open, an unnamed layer (`none`, probably the transition leash or the blur/dim surface) is 33-48% janky.
  The Jelly layer is janky 53% of its 122 frames while it opens.
- Logs: logs/lineage-2/ (logs-235016, ui-jank-*, recents-*).

## lineage-3 .. lineage-8 (2026-09-29)

- **GApps:** MindTheGapps (vendor/gapps, baklava) is built in (lineage-3). Sideloading it failed because
  system/product/system_ext are erofs, which is read-only. ext4 plus reserved headroom would allow sideloading; the
  user chose erofs with built-in GApps. The Google Setup Wizard, Play Store and GMS work.
- **Launcher3 blur flags off** (device release config map, lineage-4): `all_apps_blur` and
  `enable_overview_background_wallpaper_blur` are READ_ONLY ENABLED in bp3a/bp4a.
  - Live A/B first, with `disable_window_blurs` 0/1: the all-apps fling went from 6.57% to 2.24% janky.
  - The build with the flags off: **2.56%, p90 8 ms, p99 16 ms**, with system blur still on.
  - The flags-off path exposed an upstream crash: ScalingWorkspaceRevealAnim read `R.integer.max_depth_blur_radius`
    with getDimensionPixelSize. It crashed the launcher on every swipe-home. Fixed in Launcher3 9149aaa1e4 (lineage-6);
    the patch is in patches/packages/apps/Launcher3.
- **Dolby Vision codec2 (dolbycodec2) off** (lineage-5): it crashed with a null RefBase in listComponents on every boot.
- **Boot hang after that change** (lineage-5..7 booted in 112 s):
  - The stock `c2_manifest_vendor_parrot.xml` still declared `IComponentStore/dolby`.
  - Codec2 clients call getService on every declared store and block on the one that never registers.
  - mediaserver's codec list blocked, then cameraserver's HEIC init (CameraProviderManager -> HeicEncoderInfoManager ->
    getCodecList), then system_server's main thread (CameraStateMonitor in DisplayContent init). After 65 s the
    watchdog killed system_server.
  - The instance was dropped by an extract-files fixup (lineage-8). **Boot is 43 s including the flash reboot**, with
    boot_complete at 33 s.
- **Bench adb root after a wipe:** a system_ext rc writes /data/adbroot/enabled on WITH_ADB_INSECURE builds.
- **Still open:** vendor.qti.media.c2 (media.hwcodec) and vendor.dolby.media.c2 each crashed once at boot, with the same
  null-RefBase signature in the HIDL IComponentStore stub. Both restart, and all c2.qti codecs are registered.
- **config_wallpaperMaxScale=1** (lineage-7) made no difference to recents-open (launcher 9.0%, display 21.7%), so it
  was reverted.

### Recents -> app on Trebuchet (lineage-5..7 traces)

- About 70% of display frames are janky entering overview (START_RECENTS_TRANSITION); TO_FRONT is almost all janky.
  Nearly all of it is SF GPU deadline or SF stuffing; app deadline misses are 0.
- The GPU clock is not the limit: 940 MHz for the whole overview transition (power hint), 295 MHz only when idle.
- SF per frame: present 6.9 ms, which includes a 3.9 ms fence wait (waitForever); composeSurfaces 3.2 ms; drawLayers 2.8 ms.
- The layer trace (android.surfaceflinger.layers, tools/perfetto/layers.pbtxt) shows what is CLIENT (GPU):
  - task leashes scaled with corner radius (170 px in leash space);
  - the scaled wallpaper wrapper;
  - the launcher above them.
  Taskbar, status bar and screen decor stay on the DPU.
- Launcher main-thread "stalls" of 400-600 ms are the overview animation running frames nested in one coroutine
  (as EvoX's traces showed). Inside, draw waits in postAndWait (1.7 s over 6 cycles) on RenderThread, and RenderThread
  waits in dequeueBuffer (7.9 ms average). Everything goes back to SF GPU composition throughput.
- App open from a home icon: launcher 2.9%, display 7.3%, but SF missed 51% of frames and client-composited 59%.
- QS pulldown on lineage-6: 4.45%, p90 16 ms (EvoX 4.8-5.1%).

## Next

- Perfetto traces of the home-page fling and of Recents -> app on Trebuchet: find what "slow issue draw commands"
  and the `none` layer are. Launcher3 is source here, so fixes can go in directly.
