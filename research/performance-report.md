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

### Rounded corners
- SF composes any layer with a corner radius on the GPU. So it is a real cost, but not the main one: blur is.
- Framework `config_supportsRoundedCornersOnWindows=false`:
  - app open: SF client-composited frames 1325 -> 676, missed frames 1142 -> 564;
  - the display-timeline jank did not improve (7.3% -> 8.6%, noise).
- The toggle lets you trade the look for less GPU work. It defaults to on.

### Tried and rejected (measured)
| Change | Result |
|---|---|
| `config_wallpaperMaxScale=1` (no wallpaper zoom) | recents-open unchanged (9.0% / 21.7%), reverted |
| `debug.sf.predict_hwc_composition_strategy=1` | icon-open worse (5.8% / 11.3%) |
| `debug.sf.luma_sampling=0` | neutral to worse (recents display 24.8%) |
| Rounded corners off (framework flag + task radius) | no display-timeline gain |

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

(to be filled in: the Dolby fixes, the Pixel Launcher no-blur overlay toggle, shade blur toggle, measurements.)

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
