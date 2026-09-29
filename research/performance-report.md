# dizi (Redmi Pad Pro) performance report: LineageOS 23.2 and Evolution X

Work of 2026-09-28/29.
- Device: SM7435 (Adreno 710), 2560x1600 at 120 Hz, landscape.
- Tests: in-tree tools, warm runs, 10-20 cycles each (see "Method").
- Janky % is the share of frames that missed their deadline. There are two views:
  - hwui: the launcher's own frames.
  - display: SurfaceFlinger's display frame timeline, which includes composition.

## Summary

| Path | Before | After | Change |
|---|---|---|---|
| App drawer open/close (launcher) | 6.57%, p90 18 ms, p99 40 ms | **2.56%**, p90 8 ms, p99 16 ms | Launcher3 all-apps/overview blur flags off (toggle) |
| App open from a home icon (launcher) | 3.2-3.5% | **1.0-1.2%** | Launcher "blur behind apps" off (toggle) |
| App open from a home icon (display) | 8.0-8.5% | **4.7%** | Same |
| Recents -> app (display) | 20.9-23.7% | 20.3-20.9% | Same; the remaining jank is composition (see below) |
| Quick settings pulldown | 4.35%, p90 15 ms | **3.34%**, p90 9 ms | Shade blur off (toggle) |
| Boot (flash reboot to boot_completed) | 112 s (lineage-5..7) | **43 s** (33 s from kernel) | Dolby Vision Codec2 VINTF fix |
| Launcher crash on swipe home (flags off) | every swipe | none | Launcher3 fix |

EvoX: see "Evolution X" (to be filled in).

## Why the launcher and shade jank: SurfaceFlinger GPU composition

The perfetto traces, including the SF layer trace with per-layer composition types, all point the same way:
- the launcher itself is rarely late (app deadline misses are about 0);
- SurfaceFlinger misses its GPU deadline.

A layer is composed by the GPU (CLIENT) instead of the display engine (DEVICE) when it:
- has a background blur behind it (the blur needs the layers below as a texture);
- has rounded corners (SF forces client composition for any corner radius);
- is scaled, like the wallpaper zoom and the task leashes in transitions;
- sits above one of those in the same contiguous stack.

One GPU-composited frame at 2560x1600 costs about 3 ms of drawLayers plus a 3.9 ms fence wait inside the 6.9 ms
present. At 120 Hz that already exceeds the 8.3 ms frame budget. The GPU runs at 940 MHz throughout the transition
(the power HAL's interaction hint), so clock speed is not the limit.

The launcher's apparent 400-600 ms main-thread stalls are frames nested in one coroutine. They wait in postAndWait on
RenderThread, which waits in dequeueBuffer (about 8 ms average) for SurfaceFlinger to release a buffer. That is the
same bottleneck.

## Changes (LineageOS 23.2)

### Blur, now user toggles
- **Trebuchet: Home settings > Visual effects.** The blurs default to off (the measured wins); the corners default to on.
  - Blur behind the app drawer: the `all_apps_blur` flag path.
  - Blur behind recents: `enable_overview_background_wallpaper_blur`.
  - Blur while opening apps: the depth blur in all other launcher states, the swipe-home reveal and predictive back.
  - Rounded corners in animations.
- The aconfig flags are READ_ONLY (compile-time), so the toggles wrap the flag getters
  (`com.android.launcher3.util.VisualEffects`). A change restarts the launcher when you leave settings.
- **Notification shade blur** (XiaomiParts > Display > Blur effects): `persist.sysui.disableBlur`, then a SystemUI restart.

### Toggle results (lineage-9, same session, warm)
| Setting | App drawer | Icon -> app (launcher / display) | Recents -> app display |
|---|---|---|---|
| Defaults: blur off, corners on | 2.25%, p90 7 ms | 0.66% / 3.69% | 23.5% |
| All blur on, corners on (upstream look) | 6.64%, p90 18 ms | 0.66% / 3.28% | 22.9% |
| Blur off, corners off | 2.30%, p90 7 ms | 0.80% / 3.42% | 22.6% |

- With the upstream flags on, Trebuchet's enhanced transitions do not blur behind a launching app.
- The expensive "behind apps" blur is the legacy (flag-off) depth blur. It is off by default, so a drawer-blur-off
  setup does not bring it back.

### Rounded corners
- SF composes any layer with a corner radius on the GPU. So it is a real cost, but not the main one: blur is.
- Framework `config_supportsRoundedCornersOnWindows=false`:
  - app open: SF client-composited frames 1325 -> 676, missed frames 1142 -> 564;
  - the display-timeline jank did not improve (7.3% -> 8.6%, noise).
- The toggle lets you trade the look for less GPU work. It defaults to on.

### SurfaceFlinger: framebuffer buffers (kept)
`ro.surface_flinger.max_frame_buffer_acquired_buffers=3` (the stock HyperOS value; the port had the default of 2):
- Recents -> app display timeline, same test: **22.2-23.5% -> 18.1%** (lineage-10 vs lineage-9). Launcher 8.6-9.5% -> 7.9%.
- Icon-open, drawer and QS were unchanged.
- Cost: one more 2560x1600 client-target buffer (about 16 MB).

### Tried and rejected (measured)
| Change | Result |
|---|---|
| `config_wallpaperMaxScale=1` (no wallpaper zoom) | recents-open unchanged (9.0% / 21.7%), reverted |
| `debug.sf.predict_hwc_composition_strategy=1` | icon-open worse (5.8% / 11.3%) |
| `debug.sf.luma_sampling=0` | neutral to worse (recents display 24.8%) |
| Rounded corners off (the Trebuchet toggle: framework flag, task radius 0 and every window-animation radius) | no gain: recents 22.6% vs 22.9-23.5%, icon-open 0.80% vs 0.66% |
| `debug.sf.disable_client_composition_cache=1` (stock value) | no gain: recents 23.4%, QS 4.18% |
| `debug.sf.latch_unsignaled=1` (stock value) | no gain: recents 22.95% vs 22.19% reference, QS 4.37% vs 4.46% |

### Correctness and boot fixes found along the way
- **Boot hang (80 s lost per boot):** after hardware/dolby's crashing Dolby Vision codec2 service was disabled, the stock
  `c2_manifest_vendor_parrot.xml` still declared `IComponentStore/dolby`. Every Codec2 client blocks in getService for a
  declared instance:
  1. mediaserver's codec list blocks,
  2. then cameraserver's HEIC init,
  3. then system_server's DisplayContent (CameraStateMonitor);
  4. the watchdog kills system_server after 65 s.
  Fixed with an extract-files fixup: boot 112 s -> 43 s.
- **Dolby Vision `dolbycodec2`:** it crashed at every boot (null RefBase in listComponents). Its codecs were stripped from
  media_codecs, so the service is now off.
- **Launcher3:** `ScalingWorkspaceRevealAnim` read an integer resource as a dimen on the flag-off path, which crashed
  the launcher on every swipe home. Fixed upstream-style.
- **Dock:** the browser slot was empty on the first boot. Jelly is now named in the default layout (overlay).

### Boot time now
- boot_completed 32 s after `adb reboot`; the boot animation ends at 21.8 s.
- The largest remaining item: system_server waits 6.9 s for the sensors HAL (the QTI SSC sub-HAL enumerating over the
  ADSP). Stock uses the same sub-HAL.

## Evolution X

Build-46 (bka, 2026-09-29), with the Lineage findings applied:
- **Dolby Vision codec2 off, and its VINTF instance dropped:** the same crash-at-every-boot and the same boot-hang trap as
  on Lineage. EvoX boots with one system_server start and no tombstones. The ruan vendor tree got the same manifest fix,
  because ruan inherits dizi's device.mk.
- **XiaomiParts > Display > Blur effects: notification shade blur** (`persist.sysui.disableBlur`, applied live).
- **No launcher blur switch on EvoX.** The Pixel Launcher's blur measured nearly free (table below).
  - A runtime switch would need Parts to talk to OverlayManager. Parts runs in the vendor `devicesettings_app` domain, and
    the platform neverallow (domain.te: vendor apps may only use stable services) forbids finding `overlay_service`.
  - The measurements used `cmd overlay` on a test overlay.
- `ro.surface_flinger.max_frame_buffer_acquired_buffers=3` (stock) is queued for the next EvoX build.

| Path (EvoX, Pixel Launcher) | Blur on | Blur off |
|---|---|---|
| App drawer (launcher) | 1.37% | 0.81% |
| Icon -> app (Play Store; launcher / display) | 3.51% / 4.58% | 3.83% / 5.49% (noise) |
| Recents -> app (Settings/Chrome; launcher / display) | 5.76% / 11.73% | 5.73% / 11.05% |
| QS pulldown (shade blur) | 4.04%, p90 16 ms | **2.43%**, p90 11 ms |

- The Pixel Launcher's blur is cheap, like Trebuchet's with the upstream flags on. The shade blur costs the same on both ROMs.
- **Cross-ROM caveat:** the recents-open test alternates Settings with the default browser: Chrome on EvoX, Jelly on
  Lineage. Jelly's own frames are slow, so Lineage looked worse.
  - With the same apps (`RECENTS_TARGETS="Settings Calculator"`), EvoX is 8.16% / 17.12%, close to Lineage.
  - **Trebuchet and the Pixel Launcher are on par for recents.**
- App sweep: 19 apps, 0 crashes, 0 tombstones, 0 ANRs.
- **Build-47:** adds `max_frame_buffer_acquired_buffers=3`.
  - Recents -> app (Settings/Clock; launcher / display): 6.2-12.5% / 9.5-11.4%. QS 5.15%.
  - Lineage-11 on the same test: 7.9-8.0% / 17.3-18.2%.
  - Run-to-run noise on recents is large here (one 85-frame run at 12.5%). The EvoX/Lineage recents gap is not settled.
- **Parts shade switch (build-49 / lineage-13):** it needs no SystemUI restart, because BlurUtils reads the property on
  every blur. Android 16 also ignores a force-stop of the persistent SystemUI.

## Android 17 (Evolution X `cnb`), first build

- **Tree:** `/build/alex/dizi/evox-cnb`: repo `cnb`, `--reference` to the bka tree. The whole sync took minutes.
  - Local manifest: kernel headers, hardware_xiaomi `cnb-no-dolby`, hardware_dolby `cnb-aospa`, GameBar, all on `cnb`.
- **Device tree:** branch `cnb-dizi` = bka-dizi plus garnet's cnb commits:
  - FCM level 7;
  - power-libperfmgr namespaces;
  - legacy libion;
  - Parts DefaultDialerManager fix;
  - 64-bit only (core_64_bit_only, no TARGET_2ND_*).
  The eSIM and kernel-clang commits don't apply.
- **Build fixes:** one, `vendor_poweroffalarm_app` no longer exists in the Android 17 QTI vendor policy (dontaudit.te).
  - cnb-1 (clean): 1 h 29 min to that failure; cnb-3 finished in 13 min.
  - The 32-bit vendor blobs didn't block the 64-bit-only build.
- **First flash (cnb-3):** Evolution X 17.0, `CP2A.260605.016`.
  - boot_completed 54 s after the flash;
  - SELinux enforcing;
  - one system_server start;
  - no tombstones;
  - display, Wi-Fi and adb root work.
- **validate.sh:** 17 PASS, 0 FAIL. **App sweep:** 17 apps, 0 crashes, 0 tombstones, 0 ANRs.
- **Jank on 17 (Pixel Launcher, cnb-3):**
  | Test | Result |
  |---|---|
  | QS pulldown | **13.4-16.1%, p90 32-34 ms**, even pinned at 120 Hz |
  | QS with the shade blur off | **3.70%, p90 14 ms** |
  | App drawer | 6.11% (p90 23 ms) on the first run after boot; **2.94% (p90 11 ms) warm** (cnb-4, no blur: the drawer layer trace shows radius 0; only the rotated wallpaper is GPU-composed, as on 16) |
  | Recents -> app (Settings/Clock) | 8.55% / 15.72% |
  - Android 17's shade blur is several times more expensive than 16's on this GPU.
  - cnb-4 therefore ships `persist.sysui.disableBlur=true` as the default; the Blur effects switch turns it back on.
  - It also adds `max_frame_buffer_acquired_buffers=3`.
- The display idles at 60 Hz on 17 (`frameRateCategoryRate normal=60, high=90`) and goes to 120 Hz on interaction.
  The mapping in SurfaceFlinger is the same as 16's.

## Method

Tools are in `tools/`:
- `ui-jank.sh [ONLY=]`: settings, launcher and browser flings, plus the QS pulldown; hwui gfxinfo and SF timestats.
- `recents-open-jank.sh`: home -> overview -> tap a card -> home.
- `app-open-jank.sh`: home icon -> app -> home.
- `ab-quick.sh`: one line with the recents and icon-open numbers.
- `recents-open-trace.sh` / `launcher-fling-trace.sh` with `CFG=tools/perfetto/{deep,layers}.pbtxt`: perfetto, including
  the SF layer trace.
- Live A/B used `cmd overlay fabricate` (bool and integer only; dimens are rejected) and `setprop`.
  - Fabricated overlays do not survive a framework restart (`stop; start`) or a reboot.
  - Always discard the first run after a restart.
- Noise between identical runs is about ±1 point on display-timeline %, and more on runs straight after a restart.
