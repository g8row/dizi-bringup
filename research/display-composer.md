# dizi EvoX: display composer (QTI SDM/HWC) mismatch analysis

Written 2026-09-27, read-only analysis (no device access, nothing under `evox/` modified).
Paths are relative to `/build/alex/dizi`. Scratch artefacts (disassembly, probes, downloaded
garnet/"ingot" blobs) are in `/tmp/sdmcmp`.

Runtime evidence used: `logs/build-16/audio-shorts.txt` (21 367 SDM lines, the ApplyScale
spam) and `logs/build-16/ui-jank-181545/` (SF timestats, 2540 frames, 1962 client-composited).

---

## TL;DR

* The scaler lives in **stock blobs only**: `ScalarConfig*`, `ResourceImpl::ConfigurePipeScaleData`
  are in `vendor/lib64/libsdmextension.so`; `lib_scale_get_pipe_settings` is exported by
  `vendor/lib64/libqseed3.so`, which libsdmextension dlopens. Both are byte-identical to dizi
  stock in our out dir. The source tree has no scaler code at all.
* **The binary interface between the source core and the stock extension checks out as compatible.**
  Everything below matches between source `libsdmcore` (LineageOS `lineage-23.2-caf-sm8450`,
  CLO tag `DISPLAY.LA.2.0.r1-13200-WAIPIO.0`) and the dizi blobs:
  - the `ExtensionInterface`, `ResourceInterface` and `StrategyInterface` vtables, slot by slot;
  - the sizes of `HWResourceInfo` (0x268), `HWLayerConfig` (0x1ec8), `Layer` (0x1830),
    `LayerBuffer` (0xbd8), `HWPipeInfo` (0x300), `HWScaleData` (0x1dc) and
    `HWRotatorSession` (0x1860). These were built from the source headers and match the
    strides the blobs use;
  - the `HWResourceInfo` field offsets that `ScalarConfigQseed3::Init` reads
    (`pipe_qseed3_version` @0x194, `inline_rot_info` @0x1a0);
  - the `DisplayBuiltIn`/`DisplayBase`/`CoreImpl`/`HWDeviceDRM` vtables (stock libsdmcore
    against source libsdmcore: 145/111/19/66 slots, identical order).
  Switching to the sm8550/sm8650 display branches would **break** this ABI, because
  `ExtensionInterface` gains `DumpCodeCoverage`/`CreateCwbManagerExtn` there. Don't do it.
* Garnet (same SoC, official LineageOS) runs this same source HAL with SDM blobs taken from
  "ingot" (`UKQ1.240227.165`). The ingot `libsdmextension`/`libqseed3` have **the same exports
  and the same code** as dizi's, down to the same qseed-version lookup table and the same
  lib_scale init tag `0x0104000e`. Swapping in the garnet/ingot blobs therefore will
  almost certainly **not** fix this. Garnet is a phone, so it rarely takes the
  rotate-90 + downscale path that a tablet in landscape takes all the time.
* The failure is data-dependent: only a **90°-rotated + downscaled NV12-UBWC video layer on
  the inline rotator** fails. It's layer 0: `1600x1200 Y_CBCR_420_VENUS_UBWC`, rot 90 →
  dst 1050x1400, `lib_scale_get_pipe_settings status = 2`, `Inline Rotator ... ds ratio = 0.0`.
  The input comes from the source core, not the Xiaomi core HyperOS ships with. The only
  remaining difference in the stack is the core itself: Xiaomi's `libsdmcore` has Xiaomi
  patches and an older QTI tag than 13200.
* **dpi 24.95 is a Xiaomi units quirk, now proven.** The DT gives the panel size in 0.1 mm
  (`qcom,mdss-pan-physical-width-dimension = <0x65d>` = 1629, height `<0xa2e>` = 2606,
  i.e. 162.9 x 260.6 mm, a 12.1" panel). Stock `libsdmcore`
  `HWDeviceDRM::PopulateDisplayAttributes` divides `mmWidth/mmHeight` by 10.0
  (`fmov v1.2s,#10.0; fdiv` @0xaa408). The source doesn't, so 1600*25.4/1629 = 24.95.
  Stock reports `xDpi=249.478 yDpi=249.516` (`recon/dumpsys/display.txt`).
* The high `clientCompositionFrames` in the **UI fling** test is probably *not* this scaler
  bug: that run had no video layer. Check the rotator/blur/props listed in section 4 first.

**Recommended fix (ranked):** (1) hybrid: ship **stock `libsdmcore.so`** (+ its new dependency
`vendor.xiaomi.hardware.displayfeature@1.0.so`, optionally stock `libsdedrm.so`) under the
source composer. This is a verified drop-in and it also fixes the dpi. (2) If the spam
persists or the hybrid can't be packaged cleanly, use the full stock composer stack
(file list in 4b). (3) Use props as a mitigation or diagnostic. (4) Patch the source for dpi
only.

---

## 1. Who implements ScalarConfig / lib_scale, and do the interfaces match?

| Item | Finding |
|---|---|
| `ScalarConfig`, `ScalarConfigQseed3::*`, `ResourceImpl::ConfigurePipeScaleData` | only in `stock/dump/vendor/lib64/libsdmextension.so` (blob, sha1 34eec1fa, same file in `out/.../vendor/lib64`) |
| `lib_scale_init/_get_pipe_settings/_get_version/...` | exported by `libqseed3.so` (blob, sha1 93bc80ea), dlopened by `ScalarConfigQseed3::Init` (`DynLib::Open/Sym`) |
| Source tree | `hardware/qcom-caf/sm8450/display` has no ScalarConfig/lib_scale code. Scaling is entirely inside the extension blob, fed from core structs (`HWResourceInfo`, `HWLayersInfo`, `HWLayerConfig`, `HWPipeInfo`, `HWRotatorSession`, `LayerBuffer`) |
| libsdmextension imports | only from `libsdmutils` (`Debug::*`, `RectUtils`, formats), `libdisplaydebug`, `libdisplayqos`, `libdisplayskuutils`, `libsdm-color`, `libtestutils`, `libtinyxml2_1`. All resolve against our build (symbol diff: our libsdmutils only drops `__cfi_check` and some libc++ template instances) |
| `EXTENSION_VERSION_TAG` | 2.0 in sm8450, sm8550 and sm8650 alike, so it's not a useful discriminator |
| ExtensionInterface vtable | stock exports exactly the 10 methods of the sm8450 header, same signatures. sm8550/8650 add `DumpCodeCoverage`, `Create/DestroyCwbManagerExtn`, and 8650 changes the `CreateCapabilitiesExtn` args, so they are **incompatible** |
| ResourceImpl vtable (31 slots) and StrategyImpl vtable | identical order to sm8450 `resource_interface.h` / `strategy_interface.h` (decoded from `.rela.dyn`) |
| Struct sizes (probe compiled against the sm8450 headers with the AOSP clang/libc++/bionic, `/tmp/sdmcmp/probe`) | HWResourceInfo 0x268, HWLayerConfig 0x1ec8, Layer 0x1830, LayerBuffer 0xbd8, HWPipeInfo 0x300, HWScaleData 0x1dc, HWRotatorSession 0x1860, HWDisplayAttributes 0x44. The same immediates appear as strides in the blob code (e.g. 0x1ec8 x111 in libsdmextension; 0x44 in stock `PopulateDisplayAttributes`) |
| qseed / inrot enums | kernel reports `scaler_step_ver` 0x3001 (`qcom,sde-qseed-scalar-version`), which the source maps to `kQseed3litev7` (=5). The blob's table maps 0..5 to lib versions {1,2,2,3,4,5}, identical in dizi and ingot. The inline rotator is `true_inline_rot_rev` 0x201, which maps to `kInlineRotationV2`, with `in_rot_maxheight` 1200 (parrot catalog) |

So I found no ABI break. What fails is the scaler computation for one layer class. Excerpt
from the failing input (`logs/build-16/audio-shorts.txt:63-90`, identical every frame):

```
DumpPipeInputParams: Optimization Mode: 0 ContentType: 1 ModuleType[0]: 1 ... InputFlags: 0x468 Chroma_Site: 5
surf[W x H]: [1600 x 1200] roi_in:[0 0 1600 1200] roi_out_width_left: 1050 roi_out_width_right: 0 roi_out_dst_height: 1400
Mixer ROI[X Y W H]: [0 0 0 0] LayerMixer WxH 0x0
Left: Src[w x h]:[1600 x 1200] format = Y_CBCR_420_VENUS_UBWC ...  dst_roi 550,580 - 1600,1980
Inline Rotator o/p format = Y_CBCR_420_VENUS_UBWC ds ratio = 0.000000 Rotation = 90.000000
lib_scale_get_pipe_settings failed: status = 2  ->  ApplyScale failed for hw layer idx = 0
```

This is a portrait (Shorts) video buffered as 1600x1200 with a 90° transform, downscaled
about 1.14x. `ds ratio = 0` means the inline-rotation pre-downscaler was not engaged.
Each failure makes the strategy drop that layer to GPU, and SDM logs about 14 lines per
retry, which gives the ~475 lines/s.

## 2. Which QTI display release is each side?

| Side | Evidence | Release |
|---|---|---|
| dizi stock (OS3.0.303 EEA) | `ro.vendor.build.fingerprint=.../dizi:12/SKQ1.231214.001/...`, `ro.board.first_api_level=31`, vendor security patch 2026-02-01. No CLO tag strings in any display blob. The composer DT_NEEDED list and vintf manifest (composer 2.4, QtiComposer 3.1, display.config AIDL **V5**, mapper/allocator 4.0 HIDL, demura 2.0) are **identical** to our source build's | QTI display.lnx.8.0-family (taro/parrot, "WAIPIO" branch), **Xiaomi-patched**: `libsdmcore` imports `vendor.xiaomi.hardware.displayfeature@1.0` (`IDisplayFeatureGet`, `CoreInterface::HandleDisplayRequest/SetHDRStatus`), has the /10 mm quirk, and its `init.qti.display_boot.sh` differs (`enable_spec_fence 0`, no `disable_non_wfd_vds`). Older than tag 13200: it lacks the "panel ids" payload and the "stc color mode" code present in source |
| `hardware/qcom-caf/sm8450/display` | LineageOS/android_hardware_qcom_display `lineage-23.2-caf-sm8450`, local HEAD 222878b (2026-08-03, depth-1 clone). GitHub history: `Merge tag 'DISPLAY.LA.2.0.r1-13200-WAIPIO.0'` (2026-07-09), earlier merges from `display.lnx.8.0(.r4-rel)` including "config: Update blending space of parrot" and "Add Parrot SOCID" | QTI display.lnx.8.0 / DISPLAY.LA.2.0.r1-13200-WAIPIO.0: the same family as stock, newer tag |
| sm8450-6.6 / sm8750 (display-core/hal/intf split), sm8550, sm8650 | present locally. The extension ABI differs (see above) | not usable with dizi blobs |

**Other SM7435/SM7475 trees** (`trees/ref`, GitHub):
* LineageOS **garnet** (SM7435): stock composer until 2024-04-16 (`e9819a6057 "Move to OSS
  display HAL"`), then "Kang display blobs from eqs", then "from ingot UKQ1.231121.127", now
  ingot UKQ1.240227.165. Before OSS it needed `libutils-v32` for the stock composer
  (`849b0bc416`, abort `incStrongRequireStrong() ... isn't already owned`). The EvoX garnet
  tree is identical.
* **efeisot_dizi**: full stock display HAL (composer, allocator, mapper, displayfeature
  service, `vendor.qti.hardware.display.config-V*-ndk` from stock).
* **ksn2_ruan / noble6_ruan** (Redmi Pad Pro 5G, same display blobs; ruan libsdmcore sha1
  e7ab3287 == dizi): list the stock composer in proprietary-files but also build the source
  one, so they are not a clean reference.
* Our dizi tree: section headers in `proprietary-files.txt` still say "from ingot-user 14", but
  the files are dizi stock (hashes match `stock/dump`). They are unpinned, so extract took
  dizi's.

## 3. dpi = 24.95

* DT (`recon/running.dts:19647/19655`, both panel nodes):
  `qcom,mdss-pan-physical-width-dimension = <0x65d>` (1629) and
  `qcom,mdss-pan-physical-height-dimension = <0xa2e>` (2606). Xiaomi uses 0.1 mm units.
* The kernel passes these straight through as DRM connector `mmWidth/mmHeight`.
* Source `hw_device_drm.cpp:786`: `x_dpi = hdisplay*25.4/mm_width` = 1600*25.4/1629 = **24.95**.
* Stock `libsdmcore` `HWDeviceDRM::PopulateDisplayAttributes`: `ldr d0,[x20,#0x4e0]`
  (mmWidth,mmHeight pair), `ucvtf`, `fmov v1.2s,#10.0`, `fdiv`, giving 162.9 x 260.6 mm and
  **249.48 x 249.52** dpi, which matches stock `dumpsys display`.
* Not a build.prop issue: `ro.sf.lcd_density=320` (logical density) is the same in both. The
  impact is `DisplayMetrics.xdpi/ydpi` (physical-size-aware apps, stylus/ruler, and
  SF/DisplayManager dpi reporting), not UI scale.
* Fix options: use stock libsdmcore (4a), or patch the source (4d).

## 4. Fixes, ranked

### (a) Recommended: hybrid, stock `libsdmcore.so` under the source composer

Why: the whole core ABI matches (vtables, struct sizes, all imports of stock libsdmcore
resolve against our libsdmutils/libdrmutils/libsdedrm/libdisplaydebug; checked with nm).
This restores the Xiaomi core that the dizi `libsdmextension`/`libqseed3` were validated with
on HyperOS, and it fixes dpi. You keep the source composer, gralloc and mapper, which are
modern and built against A16 libs.

Files (blobs, pin with sha1 from `stock/dump`):
```
vendor/lib64/libsdmcore.so                                  # sha1 e7ab3287f2d6cced574040af0184161ce1992ef4
vendor/lib64/vendor.xiaomi.hardware.displayfeature@1.0.so   # new DT_NEEDED of stock libsdmcore
# optional, test separately: vendor/lib64/libsdedrm.so (stock DRM property parser)
```
Stock libsdmcore NEEDED: libhidltransport, libhidlbase,
vendor.xiaomi.hardware.displayfeature@1.0, liblog, libcutils, libutils, libdisplaydebug,
libsdmutils, libdrm, libdrmutils, libsdedrm, libbinder. All of these exist in our vendor
except the displayfeature interface lib. Without the displayfeature *service* it just logs
"Query DisplayFeature service returned null" (Xiaomi code path; harmless).

Packaging problem: a source module `libsdmcore` (namespace `hardware/qcom-caf/sm8450`) is
pulled in by `vendor.qti.hardware.display.composer-service`, so a blob with the same install
path collides. Options:
1. Add `overrides: ["libsdmcore"]` to the generated prebuilt (set in `setup-makefiles.py`
   via a custom module or `lib_fixups`). Verify that out/.../vendor/lib64/libsdmcore.so is
   the blob (sha1 e7ab3287).
2. Or also take the stock composer binary (below, 4b), which removes the source
   composer→libsdmcore edge.
3. For a quick on-device A/B test without a rebuild (userdebug, adb root, permissive):
   `adb disable-verity && adb reboot`, then `adb root && adb remount`, then
   `adb push stock/.../libsdmcore.so stock/.../vendor.xiaomi.hardware.displayfeature@1.0.so /vendor/lib64/`
   and `adb shell setprop ctl.restart vendor.qti.hardware.display.composer`
   (restarts SF via `onrestart`). Revert with `adb enable-verity`.
   Alternative without remount: copy /vendor/lib64 to /data/local/tmp, add the files, and
   `mount --bind` it over /vendor/lib64 before restarting the composer.

Risk: A12-era Xiaomi code on A16 `libutils` can abort with `incStrongRequireStrong` (garnet
hit this with the stock composer). If the composer crashes with that message, add a
blob_fixup `replace_needed('libutils.so','libutils-v32.so')` and install
`prebuilts/vndk/v32/arm64/arch-arm64-armv8-a/shared/vndk-sp/libutils.so` as
`vendor/lib64/libutils-v32.so` (this is what garnet did, commit 849b0bc416).

### (b) Full stock composer stack (most faithful; what efeisot_dizi does)

Blobs to add to `proprietary-files.txt` (all present in `stock/dump/vendor`; closure checked,
0 unresolved symbols against our out):
```
vendor/bin/hw/vendor.qti.hardware.display.composer-service
vendor/etc/init/vendor.qti.hardware.display.composer-service.rc   # or keep ours (identical except writepid vs task_profiles)
vendor/etc/vintf/manifest/vendor.qti.hardware.display.composer-service.xml  # identical to ours
vendor/lib64/libsdmcore.so
vendor/lib64/libsdmutils.so
vendor/lib64/libsdedrm.so
vendor/lib64/libdrmutils.so
vendor/lib64/libqdutils.so
vendor/lib64/libqservice.so
vendor/lib64/libhistogram.so
vendor/lib64/libgpu_tonemapper.so
vendor/lib64/libdisplaydebug.so
vendor/lib64/libdisplayconfig.qti.so
vendor/lib64/vendor.xiaomi.hardware.displayfeature@1.0.so
# optional Xiaomi display features (DC dimming, eyecare, pen VRR hooks):
vendor/bin/hw/vendor.xiaomi.hardware.displayfeature@1.0-service (+ .rc, vintf xml, libdisplayfeature*.so, libMiDispDevManager.so)
```
Fixups (extract-files.py, same pattern as the existing entry at line 163):
```
'vendor/bin/hw/vendor.qti.hardware.display.composer-service':
    replace_needed('vendor.qti.hardware.display.config-V5-ndk_platform.so','vendor.qti.hardware.display.config-V5-ndk.so')
    replace_needed('android.hardware.common-V2-ndk_platform.so','android.hardware.common-V2-ndk.so')
    # if it aborts in incStrongRequireStrong: replace_needed('libutils.so','libutils-v32.so') (+ ship libutils-v32)
```
device.mk: remove `vendor.qti.hardware.display.composer-service` from PRODUCT_PACKAGES.
Keep the source `android.hardware.graphics.mapper@4.0-impl-qti-display`,
`vendor.qti.hardware.display.allocator-service`, gralloc libs, `libqdMetaData`,
`libgralloctypes` and the interface `.so`s (composer@3.x, display.config, color, postproc,
mapper/allocator HIDL), because stock composer imports resolve against them. Also keep
`init.qti.display_boot.*` and `snapdragon_color_libs_config.xml`. Check that no other
installed source module still pulls in source `libsdmcore/libsdmutils/libqdutils/libqservice/libdrmutils`
(duplicate install errors will tell you). If one does, move that one to blob as well or add
`overrides`. BoardConfig: nothing to change for the display itself; the
`vendor.qti.hardware.display.config` V5 manifest stays the same.

### (c) Props: mitigation and diagnostics (settable live)

Test loop (userdebug, `adb root`):
```
adb shell setprop <prop> <val>
adb shell setprop ctl.restart vendor.qti.hardware.display.composer   # onrestart restarts surfaceflinger (+ system_server)
```
Most SDM props are read at composer or extension init, so a restart is needed.

First, read what is actually set now:
`adb shell 'getprop | grep -E "vendor\.display\.(enable_rotator_ui|disable_inline|disable_rotator|disable_pre_down|disable_scaler|comp_mask|enable_spec_fence|supports_background_blur)"'`.
Stock HyperOS has `enable_rotator_ui=1`, `enable_spec_fence=0`, `disable_offline_rotator=1`,
`disable_scaler=0`, `comp_mask=0`, `supports_background_blur=1`.

| Prop | Read by | Effect / use |
|---|---|---|
| `vendor.display.disable_pre_downscaler=1` | libsdmextension (inrot v2 pre-downscaler) | Changes how rotate+downscale is split between the inline rotator and QSEED. **First thing to try for the status=2 video layer** |
| `vendor.display.disable_rotator_downscale=1` | `Debug::IsRotatorDownScaleDisabled` (libsdmutils, imported by the extension) | Stops downscale in the rotator path. Second try |
| `vendor.display.disable_inline_rotator=1` | `Debug::GetPropertyDisableInlineMode` | No inline rotation at all. The spam stops, but rotated layers go to GPU (offline rotator is disabled on parrot). This is a diagnostic: if the spam stops, it confirms the rotator path |
| `vendor.display.enable_rotator_ui=1` | `Debug::IsRotatorEnabledForUi` | Lets **UI** layers use the inline rotator. In landscape, every UI layer is rotated 90° relative to the portrait-native panel. If this is 0, all of them are GPU-composited. `init.qti.display_boot.sh` sets it for parrot soc_ids 537/583/613/631/633/634/638/663; make sure it is 1 on our build. **Prime suspect for the fling-test clientCompositionFrames if the tablet was in landscape** |
| `vendor.display.disable_inline_rotator_ui=1` | extension | Opposite of the above; for A/B only |
| `vendor.display.enable_spec_fence=0` | core | Stock value (Xiaomi overrides QTI's 1). The source script sets 1. Candidate for missed frames |
| `vendor.display.disable_scaler=1` | `Debug::IsScalarDisabled` | Disables MDP scaling entirely, so every scaled layer goes to GPU. Diagnostic only |
| `settings put global disable_window_blurs 1` (runtime) | SF | Blur forces client composition (`ro.surface_flinger.supports_background_blur=1` on both stock and ours). The ui-jank capture is full of `NotificationShade#…` layers, so measure with blur off |
| `debug.sf.*` (need an SF restart) | SF | Stock: `disable_client_composition_cache=1`, `enable_gl_backpressure=1`, `disable_backpressure=1`, `set_idle_timer_ms=50000`, phase offsets. Ours: garnet durations, `latch_unsignaled=0` (keep; garnet chose it for jank). Secondary |

### (d) Source patch for dpi only (if staying fully on source)

Carry it by forking `LineageOS/android_hardware_qcom_display` (branch
`lineage-23.2-caf-sm8450`) in `.repo/local_manifests/dizi.xml` (remove-project + project), or
as a patch applied by `tools/build.sh`. In `sdm/libs/core/drm/hw_device_drm.cpp`,
`PopulateDisplayAttributes`, before the dpi computation (about line 780):
```cpp
  // Xiaomi DSI panels report physical size in 0.1 mm (dizi: 1629 x 2606 -> 162.9 x 260.6 mm);
  // stock Xiaomi libsdmcore divides by 10 unconditionally.
  if (mm_width > 1000 || mm_height > 1000) {
    mm_width /= 10;
    mm_height /= 10;
  }
```
(Alternative: edit the dtbo panel nodes, but the kernel/dtbo are stock prebuilts; not recommended.)

### Not recommended
* Switching to sm8550/sm8650/sm8750/sm8450-6.6 display: extension ABI mismatch (see 1).
* Garnet/ingot SDM blobs: same code as dizi's, so no expected gain, and you lose Xiaomi panel tuning.

## 5. Verification on device

```
# SDM log rate (lines per 10 s while the failing content plays, e.g. YouTube Shorts)
adb logcat -c; sleep 10; adb logcat -d -s SDM:* | wc -l        # now ~4750; target ~0
adb logcat -d -s SDM:* | grep -c 'lib_scale_get_pipe_settings failed'

# SF timestats around a 60 s fling/scroll run
adb shell dumpsys SurfaceFlinger --timestats -disable -clear -enable
#   ... run test ...
adb shell dumpsys SurfaceFlinger --timestats -dump | grep -E 'totalFrames|missedFrames|clientCompositionFrames' | head -3
#   baseline build-16: 2540 / 1574 / 1962

# per-layer composition (look for CLIENT vs DEVICE, and the rotated/video layer)
adb shell dumpsys SurfaceFlinger | grep -iE 'composition|Layer .*\(|DEVICE|CLIENT' | head -80

# dpi
adb shell dumpsys display | grep -m1 -o 'xDpi=[0-9.]*, yDpi=[0-9.]*'   # target ~249.48 / 249.52

# Hybrid/stock-core sanity: composer did not crash-loop, Xiaomi core loaded
adb shell 'logcat -d | grep -E "DisplayFeature|incStrongRequireStrong|composer.*(crash|died)"'
adb shell 'cat /proc/$(pidof vendor.qti.hardware.display.composer-service)/maps | grep -E "libsdmcore|displayfeature"'
```
Test in both orientations. Portrait avoids the inline rotator entirely, so compare
landscape clientComposition before and after `enable_rotator_ui` / hybrid.

---

## 6. Hybrid implementation (2026-09-27, ready for build-23)

**What changed**

* `trees/staging` commit `00963a5` "dizi: Ship stock libsdmcore under the source display composer":
  * `proprietary-files.txt`: new section `# Display (stock SDM core)` with
    `vendor/lib/libsdmcore.so` and `vendor/lib64/libsdmcore.so`. These are unpinned like the rest
    and need no fixups, so the shipped files are byte-identical to stock.
  * `gen-blobs.py`: the same entries as the EXTRA group `'Display (stock SDM core)'`, so a
    regeneration keeps them. The staging copy was also resynced with `tools/gen-blobs.py`,
    which had drifted (telephony/modem SKIP_ENTRIES, and the Batterysecret/Speaker/Media
    groups). The current proprietary-files.txt regenerates identically except for one
    hand-edited section header.
  * `device.mk` and `extract-files.py`: unchanged. extract-utils puts `libsdmcore` in
    `dizi-vendor.mk` PRODUCT_PACKAGES on its own.
* `evox/vendor/xiaomi/dizi`: regenerated. There is a new `cc_prebuilt_library_shared { name: "libsdmcore", prefer: true }`
  (arm + arm64) and `libsdmcore` in PRODUCT_PACKAGES.

**Why this packaging works**

* The source `libsdmcore` (`hardware/qcom-caf/sm8450/display/sdm/libs/core/Android.bp`)
  is only installed as a dependency. The single module that links it is
  `vendor.qti.hardware.display.composer-service` (`composer/Android.bp`); `display-product.mk`
  is not included anywhere. No other built vendor ELF has it in DT_NEEDED.
* `vendor/xiaomi/dizi` is its own soong namespace that imports `hardware/qcom-caf/sm8450`. So a
  same-named `prefer: true` prebuilt pairs with the source module, and Soong replaces the
  composer's dependency with it and hides the source module from Make. The result is no
  duplicate-module error and no install-path clash. The composer now links against the stock
  .so at build time. extract-utils has no `OVERRIDES` support for libraries (apps only), and
  none was needed.
* The prebuilt must cover both arches. PRODUCT_PACKAGES installs every arch of a name, so with
  lib64 only, the 32-bit *source* libsdmcore and its 32-bit deps got installed into vendor/lib
  (first check build). With both arches in the prebuilt, vendor/lib gets the stock 32-bit core,
  as on stock. The 32-bit libsdmutils/libsdedrm/libdrmutils/libdisplaydebug/libdrm/displayfeature
  now in vendor/lib are its deps, and stock has them too.
* `vendor.xiaomi.hardware.displayfeature@1.0.so` is **not** a blob. It is the vendor variant of
  the `hidl_interface` in `hardware/xiaomi/interfaces/xiaomi/hardware/displayfeature/1.0`,
  pulled in through the prebuilt's `shared_libs`, the same way `libmlipay` gets `mlipay@1.0`.
  Stock libsdmcore imports exactly one symbol from it, `IDisplayFeature::tryGetService(std::string const&, bool)`,
  and the source-built lib exports it. The .hal has the same 8 methods as the stock blob.
  It is only a client library: nothing registers a service, so no VINTF manifest entry or
  hwservice_contexts entry is needed. Stock checks `init.svc.vendor.displayfeature-hal-1-0`
  and otherwise logs "Query DisplayFeature service returned null". If it does query
  hwservicemanager, the worst case is an avc `hwservice_manager find` denial on
  `default_hwservice` for hal_graphics_composer_default. That is harmless; add a `dontaudit`
  if it gets noisy. We do not ship the displayfeature service or libdisplayfeature*.so.
* Stock `libsdedrm.so` is still **not** shipped (the optional item). Stock core runs against
  the source libsdedrm; every C++ import resolves.

**How it was verified** (after build-22 exited; `logs/sdm-hybrid-check.log`, `m vendorimage` exit=0)

* sha256 of `out/.../vendor/lib64/libsdmcore.so` = stock `4ad547c1…43dcc`, and
  `vendor/lib/libsdmcore.so` = stock `5cacf818…2a898`. The source core is no longer built
  or installed for either arch.
* Composer imports from libsdmcore (`CoreInterface::CreateCore/DestroyCore`, `DynLib::Open/Sym/~DynLib`)
  are all exported by stock (llvm-nm). The composer also links against the prebuilt without error.
* Stock libsdmcore undefined symbols, 64- and 32-bit: every C++ symbol resolves against the
  freshly built vendor libhidltransport/libhidlbase/libutils/libcutils/liblog/libbinder/libc++/
  libdisplaydebug/libsdmutils/libdrm/libdrmutils/libsdedrm/displayfeature@1.0. The remainder
  is libc/libm/libdl.
* `tools/check-needed.py out/target/product/dizi`: the same 6 pre-existing unresolved
  entries (DSP rfsa skel libs only), none display-related.

**Risks / what to watch on device** (see also section 5)

* A12-era Xiaomi code on A16 libutils: if the composer aborts with `incStrongRequireStrong`,
  apply the libutils-v32 fallback from 4a.
* The dpi should now read ~249.5. If something relied on 24.95 (nothing should), it changes.
* If the ApplyScale spam persists with the stock core, the scaler issue is not core-side.
  Continue with props (4c) or the full stock stack (4b).

**Rollback**

Revert `00963a5` in trees/staging (or drop the two `libsdmcore.so` lines from
proprietary-files.txt and the EXTRA group from gen-blobs.py), fast-forward
evox/device/xiaomi/dizi, then rerun extract-files.py, or revert the vendor/xiaomi/dizi regen
commit. The source libsdmcore then gets installed again automatically as the composer's
dependency. For an on-device A/B without rebuilding, push source/stock libsdmcore.so as
described in 4a option 3.
